import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jankdoc/src/analysis/diagnosis_pipeline.dart';
import 'package:jankdoc/src/analysis/ollama_provider.dart';
import 'package:jankdoc/src/analysis/output_validator.dart';
import 'package:jankdoc/src/analysis/vector_store_impl.dart';
import 'package:jankdoc/src/session/session_repository.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_eval/jankdoc_eval.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

// ── Minimal MockClient ────────────────────────────────────────────────────────

typedef _ResponseFactory = http.Response Function(http.Request request);

/// A drop-in [http.Client] replacement that delegates to [_handler].
final class _MockClient extends http.BaseClient {
  _MockClient(this._handler);
  final _ResponseFactory _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    final response = _handler(req);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

/// Returns a client where every request fails with 503 (Ollama down).
http.Client unavailableClient() => _MockClient((_) => http.Response('', 503));

/// Returns a client where:
///   - GET  /api/tags        → 200 (Ollama up)
///   - POST /api/embeddings  → 200 with a 3-d unit vector
///   - everything else       → 404
http.Client availableClient() => _MockClient((req) {
      if (req.url.path.endsWith('/api/tags')) {
        return http.Response('{"models":[]}', 200);
      }
      if (req.url.path.endsWith('/api/embeddings')) {
        return http.Response(
          jsonEncode({'embedding': [1.0, 0.0, 0.0]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 404);
    });

// ── No-match RuleProvider ─────────────────────────────────────────────────────

/// A [RuleProvider] that always returns an empty rule list.
///
/// Used to force the pipeline into the LLM tier regardless of batch content.
final class _NoMatchRuleProvider implements RuleProvider {
  @override
  List<Rule> get rules => const [];

  @override
  Rule? findById(String id) => null;
}

/// Returns a [RuleEngine] that never matches any rule.
RuleEngine noMatchEngine() => RuleEngine(_NoMatchRuleProvider());

// ── Helpers ───────────────────────────────────────────────────────────────────

const _uuid = Uuid();

/// Insert a session row matching [batch] so FK JOINs in
/// countRecurrences resolve correctly.
Future<void> seedSession(SessionRepository repo, TelemetryBatch batch) =>
    repo.saveSession(Session(
      id: batch.sessionId,
      projectFingerprint: batch.projectFingerprint,
      flutterVersion: batch.deviceInfo.flutterVersion,
      dartVersion: batch.deviceInfo.dartVersion,
      deviceInfo: batch.deviceInfo,
      startedAt: DateTime.now(),
    ));

/// Return a copy of [evalCase].batch with unique sessionId + projectFingerprint
/// so each test run gets its own DB rows and tests don't interfere.
TelemetryBatch isolatedBatch(EvalCase evalCase) {
  final base = evalCase.batch;
  return TelemetryBatch(
    sessionId: _uuid.v4(),
    projectFingerprint: _uuid.v4().replaceAll('-', '').substring(0, 16),
    windowStartMs: base.windowStartMs,
    windowEndMs: base.windowEndMs,
    jankFrames: base.jankFrames,
    analysisMode: base.analysisMode,
    deviceInfo: base.deviceInfo,
    gcCount: base.gcCount,
  );
}

DiagnosisPipeline buildPipeline({
  required http.Client client,
  required SessionRepository repo,
  InMemoryVectorStore? vectorStore,
  RuleEngine? ruleEngine,
}) =>
    DiagnosisPipeline(
      ruleEngine: ruleEngine ?? RuleEngine(BuiltInRuleProvider()),
      llmProvider: OllamaProvider(
        baseUrl: 'http://127.0.0.1:11434',
        modelId: 'phi3',
        client: client,
      ),
      vectorStore: vectorStore ?? InMemoryVectorStore(),
      validator: OutputValidator(),
      sessionRepo: repo,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late SessionRepository repo;

  setUp(() {
    // Opens (or re-uses) ~/.jankdoc/sessions.db.
    // Each test uses unique IDs to avoid row collisions.
    repo = SessionRepository();
  });

  tearDown(() => repo.dispose());

  group('DiagnosisPipeline', () {
    // 1. Rule match → diagnosis yielded and saveDiagnosis called.
    test('yields a diagnosis on a rule match and persists it', () async {
      final batch = isolatedBatch(EvalFixtures.animatedBuilderRebuildStorm);
      await seedSession(repo, batch);

      final pipeline = buildPipeline(
        client: unavailableClient(), // LLM path never reached
        repo: repo,
      );

      final results = await pipeline.process(batch).toList();

      expect(results, hasLength(1),
          reason: 'Exactly one diagnosis must be yielded on a rule match');

      // countRecurrences queries diagnoses JOIN sessions; returns >= 1 only if
      // saveDiagnosis wrote the row (and the session exists for the JOIN).
      final count = await repo.countRecurrences(
        projectFingerprint: batch.projectFingerprint,
        patternId: results.first.patternId,
      );
      expect(count, greaterThanOrEqualTo(1),
          reason: 'saveDiagnosis must have persisted the row');
    });

    // 2. No rule match + LLM unavailable → empty stream.
    test('yields nothing when no rule matches and LLM is unavailable', () async {
      final batch = isolatedBatch(EvalFixtures.unknownJankNoMatch);
      await seedSession(repo, batch);

      // noMatchEngine() ensures the rule tier is skipped so the test reaches
      // the LLM availability check and stops there.
      final pipeline = buildPipeline(
        client: unavailableClient(),
        repo: repo,
        ruleEngine: noMatchEngine(),
      );

      final results = await pipeline.process(batch).toList();
      expect(results, isEmpty,
          reason: 'Silent degradation: no output when LLM is down');
    });

    // 3. No rule match + LLM available + empty vector store → empty stream.
    test('yields nothing when LLM is available but vector store is empty',
        () async {
      final batch = isolatedBatch(EvalFixtures.unknownJankNoMatch);
      await seedSession(repo, batch);

      // noMatchEngine() forces the LLM path. availableClient returns a valid
      // embedding; the empty vector store causes query() to return [],
      // ending the pipeline before any LLM call.
      final pipeline = buildPipeline(
        client: availableClient(),
        repo: repo,
        ruleEngine: noMatchEngine(),
        vectorStore: InMemoryVectorStore(), // empty — no KB loaded
      );

      final results = await pipeline.process(batch).toList();
      expect(results, isEmpty,
          reason: 'Empty RAG results must produce no diagnosis');
    });

    // 4. Rule match → diagnosis tier is DiagnosisTier.rule.
    test('rule match produces a rule-tier diagnosis', () async {
      final batch = isolatedBatch(EvalFixtures.animatedBuilderRebuildStorm);
      await seedSession(repo, batch);

      final pipeline = buildPipeline(
        client: unavailableClient(),
        repo: repo,
      );

      final results = await pipeline.process(batch).toList();
      expect(results.first.tier, DiagnosisTier.rule,
          reason: 'Rule pre-filter output must carry tier=rule');
    });

    // 5. Rule match → patternId matches the rule's declared patternId.
    test('rule match produces correct patternId', () async {
      final batch = isolatedBatch(EvalFixtures.animatedBuilderRebuildStorm);
      await seedSession(repo, batch);

      final pipeline = buildPipeline(
        client: unavailableClient(),
        repo: repo,
      );

      final results = await pipeline.process(batch).toList();
      expect(results.first.patternId, 'animated-builder-rebuild-storm',
          reason: 'patternId must match the rule that fired');
    });
  });
}
