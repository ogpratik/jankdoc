// Lets short-lived `jankdoc_check --hook` runs reuse a running jankdoc_mcp
// server's warm analysis instead of starting `dart analyze` (~3 s) per edit.
//
// The MCP server listens on a random loopback port and records it, with a
// random token, in `<project>/.dart_tool/jankdoc_lints/mcp_endpoint.json`.
// The hook looks for that file in the edited file's ancestors.
//
// No `package:analyzer` imports: the hook imports this and must start fast.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'findings.dart';

const _endpointFile = '.dart_tool/jankdoc_lints/mcp_endpoint.json';

class HookEndpoint {
  HookEndpoint._(this._server, this._file);

  final HttpServer _server;
  final File _file;

  /// Serves checks of files under [root] with [check].
  static Future<HookEndpoint> serve(
    String root,
    Future<List<Finding>> Function(String path) check,
  ) async {
    final random = Random.secure();
    final token = base64Url.encode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      try {
        if (request.method != 'POST' ||
            request.uri.path != '/check' ||
            request.headers.value('x-jankdoc-token') != token) {
          response.statusCode = HttpStatus.forbidden;
          return;
        }
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        final raw = body['path'];
        final path = raw is String
            ? File(raw).absolute.uri.normalizePath().toFilePath()
            : null;
        if (path == null ||
            !path.startsWith('$root/') ||
            !path.endsWith('.dart') ||
            !File(path).existsSync()) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        final findings = await check(path);
        response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'findings': [for (final f in findings) f.toJson()],
            }),
          );
      } on Object catch (e) {
        response
          ..statusCode = HttpStatus.internalServerError
          ..write('$e');
      } finally {
        await response.close();
      }
    });
    final file = File('$root/$_endpointFile');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'port': server.port, 'token': token, 'pid': pid}),
    );
    return HookEndpoint._(server, file);
  }

  Future<void> close() async {
    try {
      // Only remove the file if it is still ours (another server may have
      // replaced it).
      final json = jsonDecode(_file.readAsStringSync()) as Map;
      if (json['port'] == _server.port) _file.deleteSync();
    } on Object {
      // Already gone.
    }
    await _server.close(force: true);
  }
}

/// Findings for [file] from a running jankdoc_mcp server for one of its
/// enclosing projects, or null if none answers.
Future<List<Finding>?> checkViaRunningServer(String file) async {
  for (Directory? d = File(file).absolute.parent; d != null; d = d.parent) {
    final endpoint = File('${d.path}/$_endpointFile');
    if (endpoint.existsSync()) {
      final result = await _ask(endpoint, file);
      if (result != null) return result;
    }
    if (d.parent.path == d.path) break;
  }
  return null;
}

Future<List<Finding>?> _ask(File endpoint, String file) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 500);
  try {
    final info = jsonDecode(endpoint.readAsStringSync()) as Map;
    final request = await client.post(
      InternetAddress.loopbackIPv4.address,
      info['port'] as int,
      '/check',
    );
    request.headers
      ..set('x-jankdoc-token', info['token'] as String)
      ..contentType = ContentType.json;
    request.write(jsonEncode({'path': file}));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) return null;
    return [
      for (final f in (jsonDecode(body) as Map)['findings'] as List)
        Finding.fromJson((f as Map).cast<String, Object?>()),
    ];
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}
