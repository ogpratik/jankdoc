import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jankdoc/src/startup_banner.dart';
import 'package:test/test.dart';

void main() {
  group('StartupBanner', () {
    test('renders 5 status lines when /info reports full state', () async {
      final captured = StringBuffer();
      final banner = StartupBanner(
        port: 9101,
        client: _StubClient(_kFullInfo),
        quiet: false,
        sink: _BufferSink(captured),
      );

      await banner.render();

      final lines = captured.toString().trim().split('\n');
      expect(lines.length, 5);
      expect(lines[0], contains('daemon http://127.0.0.1:9101'));
      expect(lines[1], contains('LLM tier: enabled'));
      expect(lines[2], contains('KB: 1.2.3'));
      expect(lines[3], contains('Rules: 42 built-in'));
      expect(lines[4], contains('ready — open Flutter DevTools'));
    });

    test('LLM disabled line includes install hint when Ollama unreachable',
        () async {
      final captured = StringBuffer();
      final infoBody = Map<String, dynamic>.from(_kFullInfo)
        ..['llm_available'] = false;
      final banner = StartupBanner(
        port: 9101,
        client: _StubClient(infoBody),
        quiet: false,
        sink: _BufferSink(captured),
      );

      await banner.render();

      final llmLine =
          captured.toString().split('\n').firstWhere((l) => l.contains('LLM tier'));
      expect(llmLine, contains('disabled'));
      expect(llmLine, contains('https://ollama.com'));
      expect(llmLine, contains('ollama pull qwen2.5-coder:7b'));
    });

    test('seeder fallback KB emits a warning line', () async {
      final captured = StringBuffer();
      final infoBody = Map<String, dynamic>.from(_kFullInfo)
        ..['kb_source'] = 'seeder'
        ..['kb_version'] = null;
      final banner = StartupBanner(
        port: 9101,
        client: _StubClient(infoBody),
        quiet: false,
        sink: _BufferSink(captured),
      );

      await banner.render();

      final kbLine = captured
          .toString()
          .split('\n')
          .firstWhere((l) => l.contains('KB:'));
      expect(kbLine, contains('seeder fallback'));
      expect(kbLine, contains('26 entries'));
    });

    test('quiet: true prints nothing', () async {
      final captured = StringBuffer();
      final banner = StartupBanner(
        port: 9101,
        client: _StubClient(_kFullInfo),
        quiet: true,
        sink: _BufferSink(captured),
      );

      await banner.render();

      expect(captured.toString(), isEmpty);
    });

    test('daemon /info failure degrades to two-line warning', () async {
      final captured = StringBuffer();
      final banner = StartupBanner(
        port: 9101,
        client: _StubClient(null, statusCode: 500),
        quiet: false,
        sink: _BufferSink(captured),
      );

      await banner.render();

      final lines = captured.toString().trim().split('\n');
      expect(lines.length, 2);
      expect(lines[0], contains('daemon http://127.0.0.1:9101'));
      expect(lines[1], contains('/info unavailable'));
    });
  });
}

const _kFullInfo = <String, dynamic>{
  'version': '1.0.0',
  'model': 'qwen2.5-coder:7b',
  'embed_model': 'nomic-embed-text',
  'ollama_url': 'http://127.0.0.1:11434',
  'llm_available': true,
  'kb_source': 'bundle',
  'kb_version': '1.2.3',
  'kb_entries': 26,
  'rules': 42,
};

/// Minimal `http.Client` that returns a canned JSON body on every call.
final class _StubClient extends http.BaseClient {
  _StubClient(this._info, {this.statusCode = 200});

  final Map<String, dynamic>? _info;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = _info == null ? '' : jsonEncode(_info);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
    );
  }
}

/// Sink that appends every write to a [StringBuffer] — lets us assert on
/// stdout contents without touching the real terminal.
final class _BufferSink implements StringSink {
  _BufferSink(this._buffer);
  final StringBuffer _buffer;

  @override
  void write(Object? o) => _buffer.write(o);

  @override
  void writeln([Object? o = '']) => _buffer.writeln(o);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
}
