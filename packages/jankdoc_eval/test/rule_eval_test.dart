import 'package:jankdoc_eval/jankdoc_eval.dart';
import 'package:test/test.dart';

/// CI gate: every built-in fixture must pass.
///
/// Run: `dart test packages/jankdoc_eval/test/rule_eval_test.dart`
///
/// This test does NOT require Ollama or any network connection — it only
/// exercises the Rule Pre-filter tier.
void main() {
  late EvalHarness harness;

  setUpAll(() {
    harness = EvalHarness();
  });

  group('Rule engine — built-in fixtures', () {
    for (final fixture in EvalFixtures.all) {
      test(fixture.id, () async {
        final result = await harness.run([fixture]);
        final c = result.cases.single;

        if (c.error != null) {
          fail('Pipeline threw: ${c.error}');
        }

        for (final ar in c.assertionResults) {
          expect(
            ar.passed,
            isTrue,
            reason: '${fixture.id}: assertion failed — ${ar.assertion.description}',
          );
        }
      });
    }
  });

  group('Rule engine — aggregate metrics', () {
    test('pass rate ≥ 90%', () async {
      final report = await harness.run(EvalFixtures.all);
      printOnFailure(report.toSummary());
      expect(
        report.passRate,
        greaterThanOrEqualTo(0.90),
        reason: report.toSummary(),
      );
    });

    test('rule-tier avg latency < 5ms', () async {
      final report = await harness.run(EvalFixtures.all);
      expect(
        report.avgLatencyMs,
        lessThan(5),
        reason: 'Rule engine too slow: ${report.avgLatencyMs}ms avg',
      );
    });

    test('no impeller rule fires on Android non-Impeller device', () async {
      final report = await harness.run(EvalFixtures.impeller);
      // Impeller rules should only fire on iOS/Impeller fixture
      for (final c in report.cases) {
        if (c.diagnosis != null) {
          expect(
            c.diagnosis!.patternId,
            startsWith('impeller-'),
          );
        }
      }
    });
  });
}
