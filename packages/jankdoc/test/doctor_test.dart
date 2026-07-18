import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jankdoc/src/doctor.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaReachableCheck', () {
    test('ok when /api/tags returns 200', () async {
      final check = OllamaReachableCheck(
        client: _StubClient(status: 200, body: '{"models":[]}'),
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.detail, contains('reachable'));
      expect(result.fixHint, isNull);
    });

    test('fail with install hint when Ollama unreachable', () async {
      final check = OllamaReachableCheck(client: _ThrowingClient());
      final result = await check.run();
      expect(result.status, DoctorStatus.fail);
      expect(result.fixHint, contains('ollama.com'));
      expect(result.fixHint, contains('ollama serve'));
    });

    test('fail with serve hint when Ollama returns non-200', () async {
      final check = OllamaReachableCheck(
        client: _StubClient(status: 500, body: 'err'),
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.fail);
      expect(result.fixHint, contains('ollama serve'));
    });
  });

  group('OllamaModelCheck', () {
    test('ok when the model tag is present in /api/tags', () async {
      final body = jsonEncode({
        'models': [
          {'name': 'qwen2.5-coder:7b'},
          {'name': 'nomic-embed-text:latest'},
        ],
      });
      final check = OllamaModelCheck(
        modelId: 'qwen2.5-coder:7b',
        client: _StubClient(status: 200, body: body),
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
    });

    test('ok when the family prefix matches (nomic-embed-text:latest)', () async {
      final body = jsonEncode({
        'models': [
          {'name': 'nomic-embed-text:latest'},
        ],
      });
      final check = OllamaModelCheck(
        modelId: 'nomic-embed-text',
        client: _StubClient(status: 200, body: body),
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
    });

    test('fail with pull hint when model missing', () async {
      final body = jsonEncode({
        'models': [
          {'name': 'llama3:8b'},
        ],
      });
      final check = OllamaModelCheck(
        modelId: 'qwen2.5-coder:7b',
        client: _StubClient(status: 200, body: body),
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.fail);
      expect(result.fixHint, contains('ollama pull qwen2.5-coder:7b'));
    });
  });

  group('DaemonPortCheck', () {
    test('ok when port is available (bind succeeds)', () async {
      final port = await _pickFreePort();
      final check = DaemonPortCheck(port: port, client: _ThrowingClient());
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.detail, contains('available'));
    });

    test('ok when JankDoc daemon already running on the port', () async {
      final port = await _pickFreePort();
      // Simulate a running daemon by binding + serving /health.
      final server = await HttpServer.bind('127.0.0.1', port);
      unawaited(server.forEach((req) {
        req.response.write('{"status":"ok"}');
        req.response.close();
      }));

      final check = DaemonPortCheck(port: port);
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.detail, contains('JankDoc daemon already running'));

      await server.close(force: true);
    });
  });

  group('KbBundleCacheCheck', () {
    test('warn when cache directory does not exist', () async {
      final tempDir = Directory.systemTemp.createTempSync('jankdoc_no_cache_');
      final check = KbBundleCacheCheck(homeOverride: tempDir.path);
      final result = await check.run();
      expect(result.status, DoctorStatus.warn);
      expect(result.detail, contains('no cache directory'));
      tempDir.deleteSync(recursive: true);
    });

    test('warn when cache directory is empty', () async {
      final tempDir = Directory.systemTemp.createTempSync('jankdoc_empty_');
      Directory('${tempDir.path}/.jankdoc/kb-cache').createSync(recursive: true);
      final check = KbBundleCacheCheck(homeOverride: tempDir.path);
      final result = await check.run();
      expect(result.status, DoctorStatus.warn);
      expect(result.detail, contains('cache dir empty'));
      tempDir.deleteSync(recursive: true);
    });

    test('ok when at least one .jankdoc-kb file is present', () async {
      final tempDir = Directory.systemTemp.createTempSync('jankdoc_ok_');
      final cacheDir = Directory('${tempDir.path}/.jankdoc/kb-cache')
        ..createSync(recursive: true);
      File('${cacheDir.path}/jankdoc-kb-1.0.0.jankdoc-kb')
          .writeAsStringSync('gzip placeholder');
      final check = KbBundleCacheCheck(homeOverride: tempDir.path);
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.detail, contains('1 bundle'));
      tempDir.deleteSync(recursive: true);
    });
  });

  group('MacosEntitlementsCheck', () {
    test('ok when not running on macOS (skips)', () async {
      final check = MacosEntitlementsCheck(isMacosOverride: false);
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.detail, contains('not applicable'));
    });

    test('ok when the project has no macos/ directory (workspace root)',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('jankdoc_noent_');
      final check = MacosEntitlementsCheck(
        projectDirOverride: tempDir.path,
        isMacosOverride: true,
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.detail, contains('no macos/ directory'));
      tempDir.deleteSync(recursive: true);
    });

    test('fail with actionable XML fix when entitlement is missing',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('jankdoc_missing_');
      final runnerDir = Directory('${tempDir.path}/macos/Runner')
        ..createSync(recursive: true);
      File('${runnerDir.path}/DebugProfile.entitlements').writeAsStringSync(
        '<?xml version="1.0"?>\n<plist>\n<dict>\n'
        '  <key>com.apple.security.app-sandbox</key>\n  <true/>\n'
        '</dict></plist>',
      );
      final check = MacosEntitlementsCheck(
        projectDirOverride: tempDir.path,
        isMacosOverride: true,
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.fail);
      expect(result.fixHint, isNotNull);
      expect(
        result.fixHint,
        contains('<key>com.apple.security.network.client</key>'),
      );
      expect(result.fixHint, contains('<true/>'));
      tempDir.deleteSync(recursive: true);
    });

    test('ok when entitlement is present', () async {
      final tempDir = Directory.systemTemp.createTempSync('jankdoc_ok_ent_');
      final runnerDir = Directory('${tempDir.path}/macos/Runner')
        ..createSync(recursive: true);
      File('${runnerDir.path}/DebugProfile.entitlements').writeAsStringSync(
        '<?xml version="1.0"?>\n<plist>\n<dict>\n'
        '  <key>com.apple.security.app-sandbox</key>\n  <true/>\n'
        '  <key>com.apple.security.network.client</key>\n  <true/>\n'
        '</dict></plist>',
      );
      final check = MacosEntitlementsCheck(
        projectDirOverride: tempDir.path,
        isMacosOverride: true,
      );
      final result = await check.run();
      expect(result.status, DoctorStatus.ok);
      expect(result.detail, contains('network.client'));
      tempDir.deleteSync(recursive: true);
    });
  });

  group('Doctor.report', () {
    test('exit code is 1 when any check fails', () {
      final results = [
        const DoctorCheckResult(
          name: 'A',
          status: DoctorStatus.ok,
          detail: 'x',
        ),
        const DoctorCheckResult(
          name: 'B',
          status: DoctorStatus.fail,
          detail: 'y',
          fixHint: 'do z',
        ),
      ];
      expect(Doctor.exitCode(results), 1);
    });

    test('exit code is 0 when only warns and oks present', () {
      final results = [
        const DoctorCheckResult(
          name: 'A',
          status: DoctorStatus.ok,
          detail: 'x',
        ),
        const DoctorCheckResult(
          name: 'B',
          status: DoctorStatus.warn,
          detail: 'y',
          fixHint: 'consider z',
        ),
      ];
      expect(Doctor.exitCode(results), 0);
    });

    test('report includes fix hints for non-ok checks', () {
      final buffer = StringBuffer();
      Doctor.report(
        [
          const DoctorCheckResult(
            name: 'Ollama',
            status: DoctorStatus.fail,
            detail: 'not reachable',
            fixHint: 'Install: https://ollama.com',
          ),
        ],
        sink: buffer,
      );
      final out = buffer.toString();
      expect(out, contains('✗ Ollama'));
      expect(out, contains('→ Install: https://ollama.com'));
      expect(out, contains('1 failing'));
    });

    test('report says all-passed when everything is ok', () {
      final buffer = StringBuffer();
      Doctor.report(
        [
          const DoctorCheckResult(
            name: 'A',
            status: DoctorStatus.ok,
            detail: 'ok',
          ),
        ],
        sink: buffer,
      );
      expect(buffer.toString(), contains('All checks passed'));
    });
  });
}

Future<int> _pickFreePort() async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  final port = server.port;
  await server.close();
  return port;
}

final class _StubClient extends http.BaseClient {
  _StubClient({required this.status, required this.body});
  final int status;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        status,
        request: request,
      );
}

final class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const SocketException('connection refused'));
}
