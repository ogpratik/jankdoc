import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_extension/src/services/daemon_client.dart';

void main() {
  group('DaemonClient', () {
    // ── isAlive ───────────────────────────────────────────────────────────────

    group('isAlive()', () {
      test('returns true when /health responds 200', () async {
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response('ok', 200)),
        );
        expect(await client.isAlive(), isTrue);
        client.dispose();
      });

      test('returns false when /health responds 503', () async {
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response('down', 503)),
        );
        expect(await client.isAlive(), isFalse);
        client.dispose();
      });

      test('returns false when the request throws', () async {
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => throw Exception('connection refused')),
        );
        expect(await client.isAlive(), isFalse);
        client.dispose();
      });
    });

    // ── fetchInfo ─────────────────────────────────────────────────────────────

    group('fetchInfo()', () {
      test('parses DaemonInfo from JSON response', () async {
        final body = jsonEncode({
          'version': '1.2.3',
          'model': 'qwen2.5-coder:7b',
          'ollama_url': 'http://127.0.0.1:11434',
        });
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response(body, 200)),
        );
        final info = await client.fetchInfo();
        expect(info.version, '1.2.3');
        expect(info.modelId, 'qwen2.5-coder:7b');
        expect(info.ollamaUrl, 'http://127.0.0.1:11434');
        client.dispose();
      });

      test('uses fallback "?" values for missing JSON keys', () async {
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response('{}', 200)),
        );
        final info = await client.fetchInfo();
        expect(info.version, '?');
        expect(info.modelId, '?');
        expect(info.ollamaUrl, '?');
        client.dispose();
      });

      test('throws StateError on 4xx response', () async {
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response('not found', 404)),
        );
        expect(() => client.fetchInfo(), throwsStateError);
        client.dispose();
      });
    });

    // ── fetchSessions ─────────────────────────────────────────────────────────

    group('fetchSessions()', () {
      test('returns empty list when sessions array is empty', () async {
        final body = jsonEncode({'sessions': <dynamic>[]});
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response(body, 200)),
        );
        final sessions = await client.fetchSessions();
        expect(sessions, isEmpty);
        client.dispose();
      });
    });

    // ── fetchSession ──────────────────────────────────────────────────────────

    group('fetchSession()', () {
      test('returns null on 404', () async {
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response('', 404)),
        );
        expect(await client.fetchSession('non-existent'), isNull);
        client.dispose();
      });

      test('throws StateError on 500', () async {
        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          MockClient((_) async => http.Response('server error', 500)),
        );
        expect(() => client.fetchSession('some-id'), throwsStateError);
        client.dispose();
      });
    });

    // ── diagnosisStream ───────────────────────────────────────────────────────

    group('diagnosisStream()', () {
      test('emits Diagnosis objects from valid SSE events', () async {
        final diagnosis =
            _fakeDiagnosis('diag-1', DiagnosisTier.rule, Severity.high);
        final ssePayload = 'data: ${jsonEncode(diagnosis.toJson())}\n\n';

        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          _StreamingMockClient((_) async => http.StreamedResponse(
                Stream.fromIterable([utf8.encode(ssePayload)]),
                200,
              )),
        );

        final result = await client.diagnosisStream().first;
        expect(result.id, 'diag-1');
        expect(result.tier, DiagnosisTier.rule);
        expect(result.severity, Severity.high);
        client.dispose();
      });

      test('skips SSE lines that do not start with "data: "', () async {
        final diagnosis =
            _fakeDiagnosis('diag-2', DiagnosisTier.llm, Severity.medium);
        // Comment + event lines before the real data frame
        final ssePayload =
            ': heartbeat\n'
            'event: diagnosis\n'
            'data: ${jsonEncode(diagnosis.toJson())}\n\n';

        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          _StreamingMockClient((_) async => http.StreamedResponse(
                Stream.fromIterable([utf8.encode(ssePayload)]),
                200,
              )),
        );

        final result = await client.diagnosisStream().first;
        expect(result.id, 'diag-2');
        client.dispose();
      });

      test('skips malformed JSON frames without throwing', () async {
        final good =
            _fakeDiagnosis('diag-ok', DiagnosisTier.rule, Severity.low);
        final ssePayload =
            'data: {not valid json!!!\n\n'
            'data: ${jsonEncode(good.toJson())}\n\n';

        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          _StreamingMockClient((_) async => http.StreamedResponse(
                Stream.fromIterable([utf8.encode(ssePayload)]),
                200,
              )),
        );

        // Bad frame skipped; good frame emitted.
        final result = await client.diagnosisStream().first;
        expect(result.id, 'diag-ok');
        client.dispose();
      });

      test('skips [DONE] sentinel frame', () async {
        final good =
            _fakeDiagnosis('diag-final', DiagnosisTier.rule, Severity.low);
        final ssePayload =
            'data: [DONE]\n\n'
            'data: ${jsonEncode(good.toJson())}\n\n';

        final client = DaemonClient.forTesting(
          'http://localhost:9101',
          _StreamingMockClient((_) async => http.StreamedResponse(
                Stream.fromIterable([utf8.encode(ssePayload)]),
                200,
              )),
        );

        final result = await client.diagnosisStream().first;
        expect(result.id, 'diag-final');
        client.dispose();
      });
    });

    // ── DaemonInfo factory ────────────────────────────────────────────────────

    group('DaemonInfo.fromJson()', () {
      test('parses all fields correctly', () {
        final info = DaemonInfo.fromJson({
          'version': '2.0.0',
          'model': 'llama3.2',
          'ollama_url': 'http://localhost:11434',
        });
        expect(info.version, '2.0.0');
        expect(info.modelId, 'llama3.2');
        expect(info.ollamaUrl, 'http://localhost:11434');
      });

      test('tolerates null values by using "?" fallback', () {
        final info = DaemonInfo.fromJson(<String, dynamic>{});
        expect(info.version, '?');
        expect(info.modelId, '?');
        expect(info.ollamaUrl, '?');
      });
    });
  });
}

// ── Streaming mock helper ─────────────────────────────────────────────────────

/// A minimal [http.BaseClient] that routes every request through [_send].
///
/// Use this instead of [MockClient] when the code under test calls
/// [http.Client.send] and expects a [http.StreamedResponse] (e.g. SSE streams).
/// [MockClient] only accepts a handler that returns [http.Response], which is
/// not assignable to [http.StreamedResponse].
final class _StreamingMockClient extends http.BaseClient {
  _StreamingMockClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
}

// ── Test fixture helpers ──────────────────────────────────────────────────────

Diagnosis _fakeDiagnosis(
  String id,
  DiagnosisTier tier,
  Severity severity,
) =>
    Diagnosis(
      id: id,
      sessionId: 'session-abc',
      frameTsMs: 1_000_000,
      patternId: 'test-pattern',
      confidence: 0.9,
      severity: severity,
      tier: tier,
      rootCause: const RootCause(
        description: 'Test root cause',
        file: 'lib/main.dart',
        line: 42,
      ),
      explanation: 'Test explanation.',
      fix: const Fix(
        summary: 'Test fix',
        expectedImprovementMs: (2.0, 6.0),
      ),
      sources: const ['https://docs.flutter.dev'],
    );
