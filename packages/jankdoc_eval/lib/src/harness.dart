import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_rules/jankdoc_rules.dart';

import 'eval_case.dart';
import 'eval_result.dart';

/// Runs an eval suite against the rule engine only (no LLM required).
///
/// The [EvalHarness] is the entry point for both interactive runs and CI.
/// It exercises [RuleEngine] against a set of [EvalCase]s and produces an
/// [EvalReport].  The LLM path is covered by a separate integration harness
/// (`LlmEvalHarness`) that requires a running Ollama instance.
final class EvalHarness {
  EvalHarness({
    RuleProvider? ruleProvider,
  }) : _ruleEngine = RuleEngine(ruleProvider ?? BuiltInRuleProvider());

  final RuleEngine _ruleEngine;

  /// Run all [cases] and return an [EvalReport].
  ///
  /// Cases run sequentially to ensure deterministic ordering. Each case is
  /// independently timed.
  Future<EvalReport> run(List<EvalCase> cases) async {
    final startTime = DateTime.now();
    final results = <CaseResult>[];

    for (final c in cases) {
      results.add(await _runCase(c));
    }

    final totalMs = DateTime.now()
        .difference(startTime)
        .inMilliseconds;

    return EvalReport(
      cases: results,
      runAt: startTime,
      totalMs: totalMs,
    );
  }

  Future<CaseResult> _runCase(EvalCase c) async {
    final sw = Stopwatch()..start();
    Diagnosis? diagnosis;
    String? error;

    try {
      final match = _ruleEngine.evaluate(c.batch);
      if (match != null) {
        diagnosis = _matchToDiagnosis(match, c.batch);
      }
    } catch (e) {
      error = e.toString();
    }

    sw.stop();

    final assertionResults = c.assertions
        .map((a) => AssertionResult(
              assertion: a,
              passed: diagnosis != null ? a.check(diagnosis) : false,
            ))
        .toList();

    final passed =
        error == null && assertionResults.every((ar) => ar.passed);

    return CaseResult(
      caseId: c.id,
      passed: passed,
      diagnosis: diagnosis,
      assertionResults: assertionResults,
      elapsedMs: sw.elapsedMilliseconds,
      error: error,
    );
  }

  /// Converts a [RuleMatch] to a minimal [Diagnosis] for assertion checks.
  ///
  /// The harness doesn't need a full pipeline — it only needs enough of
  /// [Diagnosis] to run assertions (patternId, severity, confidence, tier,
  /// fix.summary). Full pipeline tests live in integration tests.
  static Diagnosis _matchToDiagnosis(RuleMatch match, TelemetryBatch batch) {
    final rule = match.rule;
    final frame = batch.worstFrame;
    final userFrame = frame.uiStack
        .where((s) => s.isUserCode)
        .firstOrNull;

    return Diagnosis(
      id: 'eval-${rule.id}',
      sessionId: batch.sessionId,
      frameTsMs: frame.timestamp ~/ 1000,
      patternId: rule.patternId,
      confidence: rule.confidence,
      severity: rule.severity,
      tier: DiagnosisTier.rule,
      rootCause: RootCause(
        file: userFrame?.file,
        line: userFrame?.line,
        widgetType: userFrame?.widgetType,
        description: 'Matched rule: ${rule.id}',
      ),
      explanation: 'Rule-tier match for ${rule.patternId}.',
      fix: const Fix(
        summary: 'See rule documentation.',
        expectedImprovementMs: (0, 0),
      ),
      sources: const [],
    );
  }
}

/// Retrieval quality report for the vector store.
///
/// Run against a set of known query → expected-entry-id pairs to
/// measure whether the KB retrieval correctly surfaces relevant entries.
final class RetrievalQualityReport {
  const RetrievalQualityReport({
    required this.queries,
    required this.hits,
    required this.misses,
    required this.avgTopRank,
    required this.mrr,
  });

  final int queries;
  final int hits; // expected entry in top-5
  final int misses;
  final double avgTopRank; // average rank of first relevant hit (1-based)

  /// Mean Reciprocal Rank.
  final double mrr;

  double get hitRate => queries == 0 ? 0.0 : hits / queries;

  String toSummary() => [
        '── Retrieval Quality ──',
        'Queries:     $queries',
        'Hit@5 rate:  ${(hitRate * 100).toStringAsFixed(1)}%',
        'MRR:         ${mrr.toStringAsFixed(3)}',
        'Avg top rank: ${avgTopRank.toStringAsFixed(1)}',
      ].join('\n');
}
