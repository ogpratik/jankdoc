import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:meta/meta.dart';

/// A single labelled test case for the diagnostic pipeline.
///
/// Each case bundles a synthetic [TelemetryBatch] (built from a [JankFrame])
/// with the expected [DiagnosisAssertion]s that must be satisfied.
@immutable
final class EvalCase {
  const EvalCase({
    required this.id,
    required this.description,
    required this.batch,
    required this.assertions,
    this.tags = const [],
  });

  /// Unique case identifier, e.g. 'animated-builder-rebuild-storm-001'.
  final String id;

  /// Human-readable description of what the case tests.
  final String description;

  /// The synthetic telemetry to feed into the pipeline.
  final TelemetryBatch batch;

  /// All assertions that must pass for the case to be GREEN.
  final List<DiagnosisAssertion> assertions;

  /// Optional tags for grouping (e.g. ['impeller', 'ios']).
  final List<String> tags;
}

/// Predicate that a [Diagnosis] must satisfy.
abstract interface class DiagnosisAssertion {
  /// Human-readable description of the assertion.
  String get description;

  /// Returns true if [diagnosis] satisfies the assertion.
  bool check(Diagnosis diagnosis);
}

// ── Built-in assertions ───────────────────────────────────────────────────────

/// Asserts the diagnosis matches a specific [patternId].
final class PatternIdAssertion implements DiagnosisAssertion {
  const PatternIdAssertion(this.expectedPatternId);
  final String expectedPatternId;

  @override
  String get description => 'patternId == "$expectedPatternId"';

  @override
  bool check(Diagnosis diagnosis) =>
      diagnosis.patternId == expectedPatternId;
}

/// Asserts the diagnosis severity is at least [minSeverity].
final class MinSeverityAssertion implements DiagnosisAssertion {
  const MinSeverityAssertion(this.minSeverity);
  final Severity minSeverity;

  @override
  String get description =>
      'severity >= ${minSeverity.name}';

  @override
  bool check(Diagnosis diagnosis) =>
      diagnosis.severity.index >= minSeverity.index;
}

/// Asserts the diagnosis confidence is at least [minConfidence].
final class MinConfidenceAssertion implements DiagnosisAssertion {
  const MinConfidenceAssertion(this.minConfidence);
  final double minConfidence;

  @override
  String get description =>
      'confidence >= ${(minConfidence * 100).toStringAsFixed(0)}%';

  @override
  bool check(Diagnosis diagnosis) =>
      diagnosis.confidence >= minConfidence;
}

/// Asserts the diagnosis came from the rule tier (no LLM invoked).
final class RuleTierAssertion implements DiagnosisAssertion {
  const RuleTierAssertion();

  @override
  String get description => 'tier == rule';

  @override
  bool check(Diagnosis diagnosis) =>
      diagnosis.tier == DiagnosisTier.rule;
}

/// Asserts that the cited file path contains [substring].
final class FileContainsAssertion implements DiagnosisAssertion {
  const FileContainsAssertion(this.substring);
  final String substring;

  @override
  String get description => 'rootCause.file contains "$substring"';

  @override
  bool check(Diagnosis diagnosis) =>
      diagnosis.rootCause.file?.contains(substring) ?? false;
}

/// Asserts the fix summary contains [keyword].
final class FixMentionsAssertion implements DiagnosisAssertion {
  const FixMentionsAssertion(this.keyword);
  final String keyword;

  @override
  String get description =>
      'fix.summary contains "$keyword" (case-insensitive)';

  @override
  bool check(Diagnosis diagnosis) =>
      diagnosis.fix.summary.toLowerCase().contains(keyword.toLowerCase());
}

/// Asserts the diagnosis has at least one source URL.
final class HasSourcesAssertion implements DiagnosisAssertion {
  const HasSourcesAssertion();

  @override
  String get description => 'sources.isNotEmpty';

  @override
  bool check(Diagnosis diagnosis) => diagnosis.sources.isNotEmpty;
}
