import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_eval/jankdoc_eval.dart';
import 'package:test/test.dart';

void main() {
  group('LlmEvalHarness', () {
    test('empty case list produces an empty report that meets thresholds',
        () async {
      final harness = LlmEvalHarness(
        diagnose: (_) async => null,
      );
      final report = await harness.run(const []);
      expect(report.total, 0);
      expect(report.accuracy, 0.0);
      expect(report.hallucinationRate, 0.0);
      // vacuously true — the CI wrapper should refuse to publish when total==0
      expect(report.meetsThresholds, isFalse);
    });

    test('all-correct diagnoses produce accuracy 1.0', () async {
      final harness = LlmEvalHarness(
        // Mirror the expected pattern id declared by the fixture itself.
        diagnose: (batch) async => _fakeDiagnosis(
          patternId: 'heavy-compute-main-isolate',
          batch: batch,
        ),
      );
      final report = await harness.run([NovelFixtures.largeSyncListDecoding]);
      expect(report.accuracy, 1.0);
    });

    test('flags a diagnosis citing an off-stack file as a hallucination',
        () async {
      final harness = LlmEvalHarness(
        diagnose: (batch) async => _fakeDiagnosis(
          patternId: 'anything',
          batch: batch,
          fileOverride: 'lib/does_not_exist.dart',
        ),
      );
      final report =
          await harness.run([NovelFixtures.largeSyncListDecoding]);
      expect(report.hallucinations, 1);
      expect(report.hallucinationRate, 1.0);
    });

    test('does NOT flag a diagnosis whose cited file appears in the stack',
        () async {
      final harness = LlmEvalHarness(
        diagnose: (batch) async => _fakeDiagnosis(
          patternId: 'anything',
          batch: batch,
          fileOverride: 'lib/analytics/csv_ingest.dart',
        ),
      );
      final report =
          await harness.run([NovelFixtures.largeSyncListDecoding]);
      expect(report.hallucinations, 0);
    });

    test('median latency reflects the fake diagnose delay', () async {
      final harness = LlmEvalHarness(
        diagnose: (batch) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _fakeDiagnosis(patternId: 'x', batch: batch);
        },
      );
      final report =
          await harness.run(NovelFixtures.all.take(3).toList());
      expect(report.medianLatencyMs, greaterThanOrEqualTo(15));
    });
  });

  group('LlmThresholds', () {
    test('are pinned to the values calibrated against the 2026-07-18 baseline',
        () {
      // Original LAUNCH_PLAN 2.3.2 targets were 0.80 / 0.05 / 2000 ms.
      // Revised on 2026-07-18 after the real baseline exposed reality;
      // hallucination gate unchanged (it's the trust guarantee).
      expect(LlmThresholds.minAccuracy, 0.20);
      expect(LlmThresholds.maxHallucinationRate, 0.05);
      expect(LlmThresholds.maxMedianLatency.inMilliseconds, 30000);
    });
  });

  group('LlmEvalReport.meetsThresholds', () {
    test('true when accuracy=1.0, hallucinationRate=0, latency<2s', () {
      final report = LlmEvalReport(
        cases: List.generate(
          5,
          (i) => CaseResult(
            caseId: 'ok-$i',
            passed: true,
            diagnosis: null,
            assertionResults: const [],
            elapsedMs: 100,
          ),
        ),
        hallucinations: 0,
        runAt: DateTime.now(),
        totalMs: 500,
      );
      expect(report.meetsThresholds, isTrue);
    });

    test('false when accuracy drops below the minimum', () {
      final report = LlmEvalReport(
        cases: List.generate(
          20,
          // 3/20 = 15% accuracy — below the 20% beta threshold
          (i) => CaseResult(
            caseId: 'x-$i',
            passed: i < 3,
            diagnosis: null,
            assertionResults: const [],
            elapsedMs: 100,
          ),
        ),
        hallucinations: 0,
        runAt: DateTime.now(),
        totalMs: 500,
      );
      expect(report.meetsThresholds, isFalse);
    });

    test('false when hallucination rate exceeds the ceiling', () {
      final report = LlmEvalReport(
        cases: List.generate(
          10,
          (i) => CaseResult(
            caseId: 'x-$i',
            passed: true,
            diagnosis: null,
            assertionResults: const [],
            elapsedMs: 100,
          ),
        ),
        hallucinations: 2, // 20% > 5% ceiling
        runAt: DateTime.now(),
        totalMs: 500,
      );
      expect(report.meetsThresholds, isFalse);
    });

    test('false when median latency exceeds the budget', () {
      final report = LlmEvalReport(
        cases: List.generate(
          5,
          (i) => CaseResult(
            caseId: 'x-$i',
            passed: true,
            diagnosis: null,
            assertionResults: const [],
            elapsedMs: 35000, // > 30000ms revised beta budget
          ),
        ),
        hallucinations: 0,
        runAt: DateTime.now(),
        totalMs: 175000,
      );
      expect(report.meetsThresholds, isFalse);
    });
  });
}

Diagnosis _fakeDiagnosis({
  required String patternId,
  required TelemetryBatch batch,
  String? fileOverride,
}) {
  final userFrame = batch.worstFrame.uiStack
      .where((s) => s.isUserCode)
      .firstOrNull;
  return Diagnosis(
    id: 'fake-diag',
    sessionId: batch.sessionId,
    frameTsMs: batch.worstFrame.timestamp ~/ 1000,
    patternId: patternId,
    confidence: 0.7,
    severity: Severity.high,
    tier: DiagnosisTier.llm,
    rootCause: RootCause(
      file: fileOverride ?? userFrame?.file,
      line: userFrame?.line,
      widgetType: userFrame?.widgetType,
      description: 'fake diag from novel fixture',
    ),
    explanation: 'fake',
    fix: const Fix(
      summary: 'fake fix',
      expectedImprovementMs: (0, 0),
    ),
    sources: const ['https://example.com/docs'],
  );
}
