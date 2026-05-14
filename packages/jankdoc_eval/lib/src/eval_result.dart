import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:meta/meta.dart';

import 'eval_case.dart';

/// Outcome of running a single [EvalCase].
@immutable
final class CaseResult {
  const CaseResult({
    required this.caseId,
    required this.passed,
    required this.diagnosis,
    required this.assertionResults,
    required this.elapsedMs,
    this.error,
  });

  final String caseId;
  final bool passed;
  final Diagnosis? diagnosis;
  final List<AssertionResult> assertionResults;
  final int elapsedMs;

  /// Non-null if the pipeline threw during evaluation.
  final String? error;
}

@immutable
final class AssertionResult {
  const AssertionResult({
    required this.assertion,
    required this.passed,
  });

  final DiagnosisAssertion assertion;
  final bool passed;
}

/// Aggregated results for the full eval suite.
@immutable
final class EvalReport {
  const EvalReport({
    required this.cases,
    required this.runAt,
    required this.totalMs,
  });

  final List<CaseResult> cases;
  final DateTime runAt;
  final int totalMs;

  int get total => cases.length;
  int get passed => cases.where((c) => c.passed).length;
  int get failed => total - passed;

  /// Pass-rate in [0.0, 1.0].
  double get passRate => total == 0 ? 0.0 : passed / total;

  int get avgLatencyMs {
    if (cases.isEmpty) return 0;
    return cases.fold(0, (s, c) => s + c.elapsedMs) ~/ cases.length;
  }

  int get ruleTierHits =>
      cases
          .where((c) =>
              c.passed &&
              c.diagnosis?.tier == DiagnosisTier.rule)
          .length;

  int get llmTierHits =>
      cases
          .where((c) =>
              c.passed &&
              c.diagnosis?.tier == DiagnosisTier.llm)
          .length;

  String toSummary() {
    final pct = (passRate * 100).toStringAsFixed(1);
    return [
      '══════════════════════════════════════════',
      ' JankDoc Eval Report — ${runAt.toIso8601String().substring(0, 19)}',
      '══════════════════════════════════════════',
      ' Total:   $total',
      ' Passed:  $passed  ($pct%)',
      ' Failed:  $failed',
      ' Rule-tier hits: $ruleTierHits',
      ' LLM-tier hits:  $llmTierHits',
      ' Avg latency:    ${avgLatencyMs}ms',
      ' Total runtime:  ${totalMs}ms',
      '──────────────────────────────────────────',
      if (failed > 0) ...[
        ' FAILURES:',
        for (final c in cases.where((c) => !c.passed)) ...[
          '  ✗ ${c.caseId}${c.error != null ? " — ${c.error}" : ""}',
          for (final ar in c.assertionResults.where((a) => !a.passed))
            '      ✗ ${ar.assertion.description}',
        ],
        '──────────────────────────────────────────',
      ],
    ].join('\n');
  }
}
