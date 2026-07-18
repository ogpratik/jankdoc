/// JankDoc evaluation harness — pure Dart, no device required.
///
/// Run with: `dart test packages/jankdoc_eval`
///
/// Exports:
///   - [EvalCase] / [DiagnosisAssertion] — build test cases
///   - [EvalHarness] — run cases and collect results
///   - [EvalReport] / [CaseResult] — structured outcomes
///   - [EvalFixtures] — canonical rule-tier fixtures
///   - [NovelFixtures] — 5 cases that no built-in rule matches (LLM tier only)
///   - [LlmEvalHarness] / [LlmEvalReport] / [LlmThresholds] — LLM-tier
///     baseline gating (accuracy, hallucination, latency)
///   - [RetrievalQualityReport] — vector-store retrieval metrics
library jankdoc_eval;

export 'src/eval_case.dart';
export 'src/eval_result.dart';
export 'src/fixtures.dart';
export 'src/harness.dart';
export 'src/llm_harness.dart';
export 'src/novel_fixtures.dart';
