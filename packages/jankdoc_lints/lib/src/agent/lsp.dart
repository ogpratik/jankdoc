// Minimal Language Server Protocol client plumbing: base-protocol framing
// (`Content-Length` headers) and request/response correlation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Splits an LSP byte stream into JSON messages.
///
/// Each message is a header block (one or more `Name: value` lines, e.g.
/// `Content-Length` and `Content-Type`, header names case-insensitive) ended
/// by an empty line, then exactly `Content-Length` bytes of UTF-8 JSON.
/// Chunks may split a message anywhere, or carry several messages.
class LspFramer {
  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// Feeds [chunk] and returns every message it completes.
  List<Map<String, Object?>> add(List<int> chunk) {
    _buffer
      ..add(_pending)
      ..add(chunk);
    var bytes = _buffer.takeBytes();
    final messages = <Map<String, Object?>>[];
    while (true) {
      final headerEnd = _indexOfBlankLine(bytes);
      if (headerEnd < 0) break;
      final headers = ascii.decode(
        bytes.sublist(0, headerEnd),
        allowInvalid: true,
      );
      int? length;
      for (final line in headers.split('\r\n')) {
        final colon = line.indexOf(':');
        if (colon < 0) continue;
        if (line.substring(0, colon).trim().toLowerCase() == 'content-length') {
          length = int.tryParse(line.substring(colon + 1).trim());
        }
      }
      if (length == null) {
        throw FormatException('LSP message without Content-Length', headers);
      }
      final bodyStart = headerEnd + 4;
      if (bytes.length < bodyStart + length) break;
      messages.add(
        jsonDecode(utf8.decode(bytes.sublist(bodyStart, bodyStart + length)))
            as Map<String, Object?>,
      );
      bytes = Uint8List.sublistView(bytes, bodyStart + length);
    }
    _pending = Uint8List.fromList(bytes);
    return messages;
  }

  static int _indexOfBlankLine(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}

/// Encodes [message] with LSP base-protocol framing.
List<int> lspEncode(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
  return [...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
}

/// A JSON-RPC connection to a language server process.
class LspConnection {
  LspConnection(this._process) {
    _process.stdout.listen(
      (chunk) {
        for (final m in _framer.add(chunk)) {
          _dispatch(m);
        }
      },
      onDone: () {
        for (final c in _pending.values) {
          c.completeError(StateError('language server exited'));
        }
        _pending.clear();
        _notifications.close();
      },
    );
  }

  final Process _process;
  final _framer = LspFramer();
  final _pending = <int, Completer<Object?>>{};
  final _notifications = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );
  var _nextId = 0;

  /// Server → client notifications (`method` + `params`).
  Stream<Map<String, Object?>> get notifications => _notifications.stream;

  Future<int> get exitCode => _process.exitCode;

  Future<Object?> request(String method, Object? params) {
    final id = ++_nextId;
    final completer = _pending[id] = Completer<Object?>();
    _send({'id': id, 'method': method, 'params': params});
    return completer.future;
  }

  void notify(String method, Object? params) =>
      _send({'method': method, 'params': params});

  void _send(Map<String, Object?> message) {
    try {
      _process.stdin.add(lspEncode(message));
    } on StateError {
      // stdin already closed: the server is gone; requests fail via onDone.
    }
  }

  void _dispatch(Map<String, Object?> m) {
    final id = m['id'];
    final method = m['method'] as String?;
    if (method == null) {
      // A response to one of our requests.
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = m['error'];
      if (error != null) {
        completer.completeError(LspError(error as Map<String, Object?>));
      } else {
        completer.complete(m['result']);
      }
    } else if (id != null) {
      // A request from the server. Answer so it never blocks on us:
      // `workspace/configuration` wants one (null = default) per item.
      final params = m['params'];
      final items = params is Map ? params['items'] : null;
      _send({
        'id': id,
        'result': method == 'workspace/configuration' && items is List
            ? List<Object?>.filled(items.length, null)
            : null,
      });
    } else {
      _notifications.add(m);
    }
  }

  void kill() => _process.kill();
}

class LspError implements Exception {
  LspError(this.error);
  final Map<String, Object?> error;
  @override
  String toString() => 'LSP error ${error['code']}: ${error['message']}';
}
