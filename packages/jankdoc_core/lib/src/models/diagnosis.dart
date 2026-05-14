import 'package:meta/meta.dart';

/// The structured output JankDoc produces for one analysis request.
///
/// The unit of value the user sees. Every field is explicit — confidence
/// is never hidden, file attribution is never fabricated.
@immutable
final class Diagnosis {
  const Diagnosis({
    required this.id,
    required this.sessionId,
    required this.frameTsMs,
    required this.patternId,
    required this.confidence,
    required this.severity,
    required this.tier,
    required this.rootCause,
    required this.explanation,
    required this.fix,
    required this.sources,
    this.recurrenceCount = 0,
    this.createdAt,
  });

  /// Unique diagnosis identifier (UUID v4).
  final String id;

  final String sessionId;

  /// Timestamp of the triggering JankFrame in milliseconds.
  final int frameTsMs;

  /// KB Entry ID that matched (e.g. 'excessive-rebuild-animated-builder').
  final String patternId;

  /// Confidence in the root cause attribution [0.0, 1.0].
  /// Rule-tier: always ≥0.85. LLM-tier: capped at 0.5 if file not in stack.
  final double confidence;

  final Severity severity;

  /// Which diagnostic tier produced this diagnosis.
  final DiagnosisTier tier;

  final RootCause rootCause;

  /// Plain-English explanation of the root cause.
  final String explanation;

  /// Concrete code-level fix with before/after snippet.
  final Fix fix;

  /// Primary source URLs (docs.flutter.dev, GitHub issues) for verification.
  final List<String> sources;

  /// How many times this pattern has been seen in this project across sessions.
  final int recurrenceCount;

  final DateTime? createdAt;

  /// Whether the root cause was confidently attributed to a specific file/line.
  bool get hasFileAttribution =>
      rootCause.file != null && confidence > 0.5;

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'frame_ts_ms': frameTsMs,
        'pattern_id': patternId,
        'confidence': confidence,
        'severity': severity.name,
        'tier': tier.name,
        'root_cause': rootCause.toJson(),
        'explanation': explanation,
        'fix': fix.toJson(),
        'sources': sources,
        'recurrence_count': recurrenceCount,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
        id: json['id'] as String,
        sessionId: json['session_id'] as String,
        frameTsMs: json['frame_ts_ms'] as int,
        patternId: json['pattern_id'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        severity: Severity.values.byName(json['severity'] as String),
        tier: DiagnosisTier.values.byName(json['tier'] as String),
        rootCause: RootCause.fromJson(json['root_cause'] as Map<String, dynamic>),
        explanation: json['explanation'] as String,
        fix: Fix.fromJson(json['fix'] as Map<String, dynamic>),
        sources: List<String>.from(json['sources'] as List),
        recurrenceCount: (json['recurrence_count'] as int?) ?? 0,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
      );

  Diagnosis copyWith({
    int? recurrenceCount,
    double? confidence,
    String? explanation,
  }) =>
      Diagnosis(
        id: id,
        sessionId: sessionId,
        frameTsMs: frameTsMs,
        patternId: patternId,
        confidence: confidence ?? this.confidence,
        severity: severity,
        tier: tier,
        rootCause: rootCause,
        explanation: explanation ?? this.explanation,
        fix: fix,
        sources: sources,
        recurrenceCount: recurrenceCount ?? this.recurrenceCount,
        createdAt: createdAt,
      );
}

@immutable
final class RootCause {
  const RootCause({
    this.file,
    this.line,
    this.column,
    this.widgetType,
    required this.description,
  });

  /// Source file path (relative to project root), or null if uncertain.
  final String? file;

  final int? line;
  final int? column;

  /// Flutter widget type implicated in the root cause, if applicable.
  final String? widgetType;

  /// Short technical description of the root cause.
  final String description;

  Map<String, dynamic> toJson() => {
        if (file != null) 'file': file,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
        if (widgetType != null) 'widget_type': widgetType,
        'description': description,
      };

  factory RootCause.fromJson(Map<String, dynamic> json) => RootCause(
        file: json['file'] as String?,
        line: json['line'] as int?,
        column: json['column'] as int?,
        widgetType: json['widget_type'] as String?,
        description: json['description'] as String,
      );
}

@immutable
final class Fix {
  const Fix({
    required this.summary,
    required this.expectedImprovementMs,
    this.codeBefore,
    this.codeAfter,
    this.dartFixCommand,
  });

  /// One-sentence description of the fix.
  final String summary;

  /// Expected frame time reduction in milliseconds (e.g. 4.0–8.0).
  final (double min, double max) expectedImprovementMs;

  /// Code snippet before the fix (optional, not always available).
  final String? codeBefore;

  /// Code snippet after the fix.
  final String? codeAfter;

  /// `dart fix` command if a machine-applicable fix exists.
  final String? dartFixCommand;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'expected_improvement_ms': {
          'min': expectedImprovementMs.$1,
          'max': expectedImprovementMs.$2,
        },
        if (codeBefore != null) 'code_before': codeBefore,
        if (codeAfter != null) 'code_after': codeAfter,
        if (dartFixCommand != null) 'dart_fix_command': dartFixCommand,
      };

  factory Fix.fromJson(Map<String, dynamic> json) {
    final improvement =
        json['expected_improvement_ms'] as Map<String, dynamic>;
    return Fix(
      summary: json['summary'] as String,
      expectedImprovementMs: (
        (improvement['min'] as num).toDouble(),
        (improvement['max'] as num).toDouble(),
      ),
      codeBefore: json['code_before'] as String?,
      codeAfter: json['code_after'] as String?,
      dartFixCommand: json['dart_fix_command'] as String?,
    );
  }
}

enum Severity { low, medium, high, critical }

enum DiagnosisTier {
  /// Produced by the Rule Pre-filter. Confidence ≥0.85. No LLM invoked.
  rule,

  /// Produced by the LLM Tier. Confidence may be lower.
  llm,
}
