import 'package:jankdoc/src/analysis/output_validator.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:test/test.dart';

void main() {
  final validator = OutputValidator();

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Diagnosis makeDiagnosis({
    DiagnosisTier tier = DiagnosisTier.llm,
    String? file,
    double confidence = 0.9,
    String explanation = 'Some explanation',
  }) =>
      Diagnosis(
        id: 'test-id',
        sessionId: 'test-session',
        frameTsMs: 1000,
        patternId: 'test-pattern',
        confidence: confidence,
        severity: Severity.high,
        tier: tier,
        rootCause: RootCause(
          file: file,
          description: 'Test root cause',
        ),
        explanation: explanation,
        fix: const Fix(
          summary: 'Fix it',
          expectedImprovementMs: (4.0, 8.0),
        ),
        sources: const [],
      );

  TelemetryBatch makeBatch({List<StackFrame> uiStack = const []}) {
    final frame = JankFrame(
      timestamp: 1_000_000,
      uiThreadMs: 25.0,
      rasterThreadMs: 8.0,
      totalMs: 33.0,
      targetFps: 60,
      uiStack: uiStack,
      rasterStack: const [],
    );
    return TelemetryBatch(
      sessionId: 'test-session',
      projectFingerprint: 'test000000000000',
      windowStartMs: 0,
      windowEndMs: 500,
      jankFrames: [frame],
      analysisMode: AnalysisMode.deep,
      deviceInfo: const DeviceInfo(
        platform: TargetPlatform.android,
        osVersion: '14',
        flutterVersion: '3.29.0',
        dartVersion: '3.6.0',
        impellerEnabled: false,
      ),
    );
  }

  const knownFrame = StackFrame(
    file: 'lib/home_screen.dart',
    line: 42,
    column: 0,
    function: 'build',
    packageName: 'my_app',
  );

  // ── Tests ────────────────────────────────────────────────────────────────────

  group('OutputValidator.validate', () {
    // 1. Rule-tier diagnosis passes through unchanged.
    test('passes rule-tier diagnosis through unchanged', () {
      final diagnosis = makeDiagnosis(
        tier: DiagnosisTier.rule,
        file: 'lib/ghost_file.dart',
        confidence: 0.95,
      );
      final batch = makeBatch();
      final result = validator.validate(diagnosis, batch);

      expect(result, same(diagnosis),
          reason: 'Rule-tier diagnoses must not be modified');
    });

    // 2. LLM diagnosis with null file passes through unchanged.
    test('passes LLM diagnosis with null rootCause.file through unchanged', () {
      final diagnosis = makeDiagnosis(
        confidence: 0.8,
      );
      final batch = makeBatch();
      final result = validator.validate(diagnosis, batch);

      expect(result, same(diagnosis),
          reason: 'A null file means no attribution to verify');
    });

    // 3. LLM diagnosis with file present in uiStack passes through unchanged.
    test('passes LLM diagnosis through when cited file is in uiStack', () {
      final diagnosis = makeDiagnosis(
        file: 'lib/home_screen.dart',
      );
      final batch = makeBatch(uiStack: [knownFrame]);
      final result = validator.validate(diagnosis, batch);

      expect(result.confidence, 0.9,
          reason: 'Confidence must not be reduced when file is verified');
      expect(result.explanation, 'Some explanation',
          reason: 'Explanation must not be modified when file is verified');
    });

    // 4. LLM diagnosis with file NOT in any stack → confidence capped at 0.5,
    //    warning appended to explanation.
    test(
        'caps confidence at 0.5 and appends warning when cited file is not in '
        'any stack frame', () {
      final diagnosis = makeDiagnosis(
        file: 'lib/ghost_file.dart',
      );
      // uiStack has a different file — ghost_file.dart never appears
      final batch = makeBatch(uiStack: [knownFrame]);
      final result = validator.validate(diagnosis, batch);

      expect(result.confidence, 0.5,
          reason: 'Confidence must be capped at 0.5 for unverified file');
      expect(result.explanation, contains('lib/ghost_file.dart'),
          reason: 'Warning must name the unverified file');
      expect(result.explanation, contains('not found in'),
          reason: 'Warning must state that the file was not found');
      expect(result.explanation, startsWith('Some explanation'),
          reason: 'Original explanation must be preserved at the start');
    });

    // 5. LLM diagnosis with confidence already below 0.5 — clamp(0.0, 0.5)
    //    leaves it unchanged (does not raise it to 0.5).
    test(
        'does not raise confidence when it is already below 0.5 and file is '
        'not in stack', () {
      final diagnosis = makeDiagnosis(
        file: 'lib/ghost_file.dart',
        confidence: 0.3,
      );
      final batch = makeBatch(uiStack: [knownFrame]);
      final result = validator.validate(diagnosis, batch);

      // clamp(0.0, 0.5) on 0.3 leaves 0.3 — the cap does not raise confidence
      expect(result.confidence, closeTo(0.3, 1e-9),
          reason: 'Confidence below 0.5 must not be raised by the clamp');
      // The warning is still appended regardless of original confidence
      expect(result.explanation, contains('lib/ghost_file.dart'));
    });
  });
}
