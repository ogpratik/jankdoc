import 'package:meta/meta.dart';

import '../models/diagnosis.dart';
import 'kb_category.dart';
import 'kb_channel.dart';
import 'kb_version.dart';

/// A single antipattern document in the Knowledge Base.
///
/// Each KbEntry contributes:
/// - One or more Rules to the Rule Pre-filter (declared in the jankdoc-kb YAML).
/// - One or more pre-computed embedding vectors to the Vector Store.
///
/// Every KbEntry must cite a primary source and have a corresponding eval
/// test app before it can be merged into the candidate or stable channel.
@immutable
final class KbEntry {
  const KbEntry({
    required this.id,
    required this.category,
    required this.channel,
    required this.severity,
    required this.title,
    required this.description,
    required this.flutterVersionRange,
    required this.detectionSignals,
    required this.sources,
    required this.fixGuidance,
    required this.expectedImprovement,
    required this.introducedIn,
    this.deprecated = false,
    this.deprecationReason,
    this.supersededBy,
  }) : assert(
          !deprecated || deprecationReason != null,
          'deprecated entries must provide a deprecationReason',
        );

  factory KbEntry.fromJson(Map<String, dynamic> json) => KbEntry(
        id: json['id'] as String,
        category: KbCategory.values.byName(json['category'] as String),
        channel: KbChannel.values.byName(json['channel'] as String),
        severity: Severity.values.byName(json['severity'] as String),
        title: json['title'] as String,
        description: json['description'] as String,
        flutterVersionRange: json['flutter_version_range'] as String,
        detectionSignals: DetectionSignals.fromJson(
          json['detection_signals'] as Map<String, dynamic>,
        ),
        sources: (json['sources'] as List).cast<String>(),
        fixGuidance: json['fix_guidance'] as String,
        expectedImprovement: ExpectedImprovement.fromJson(
          json['expected_improvement'] as Map<String, dynamic>,
        ),
        introducedIn: KbVersion.parse(json['introduced_in'] as String),
        deprecated: (json['deprecated'] as bool?) ?? false,
        deprecationReason: json['deprecation_reason'] as String?,
        supersededBy: json['superseded_by'] as String?,
      );

  /// Stable, URL-safe identifier (e.g. "animated-builder-rebuild-storm").
  /// Must be unique across the public KB. Local entries may reuse a public
  /// id to override the public entry.
  final String id;

  final KbCategory category;
  final KbChannel channel;
  final Severity severity;

  /// Short human-readable name shown in the UI (e.g. "AnimatedBuilder rebuild storm").
  final String title;

  /// One or two paragraph explanation of the antipattern for a Flutter developer.
  final String description;

  /// pub_semver constraint string for Flutter versions this entry applies to.
  /// Examples: ">=3.0.0", ">=3.27.0 <4.0.0", "any".
  final String flutterVersionRange;

  /// The signals the Rule Pre-filter and LLM Tier use to detect this pattern.
  final DetectionSignals detectionSignals;

  /// One or more primary source URLs. Every public entry must have at least one.
  /// Accepted sources: flutter.dev, flutter/flutter GitHub issues, peer-reviewed benchmarks.
  final List<String> sources;

  /// Human-readable fix guidance shown in the Diagnosis explanation.
  final String fixGuidance;

  final ExpectedImprovement expectedImprovement;

  /// The KB version in which this entry was introduced.
  final KbVersion introducedIn;

  /// True when this entry has been marked deprecated. Deprecated entries are
  /// excluded from all channel bundles but retained in the jankdoc-kb repo.
  final bool deprecated;
  final String? deprecationReason;

  /// ID of the entry that replaces this one, if deprecated.
  final String? supersededBy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'channel': channel.name,
        'severity': severity.name,
        'title': title,
        'description': description,
        'flutter_version_range': flutterVersionRange,
        'detection_signals': detectionSignals.toJson(),
        'sources': sources,
        'fix_guidance': fixGuidance,
        'expected_improvement': expectedImprovement.toJson(),
        'introduced_in': introducedIn.toString(),
        'deprecated': deprecated,
        if (deprecationReason != null) 'deprecation_reason': deprecationReason,
        if (supersededBy != null) 'superseded_by': supersededBy,
      };
}

/// The observable signals used by the Rule Pre-filter and the LLM Tier
/// to detect this antipattern in a TelemetryBatch.
///
/// The Rule Pre-filter uses [widgetTypes], [stackPatterns], thread thresholds,
/// and [requiresImpeller] for fast deterministic matching.
/// The Vector Store uses [embedChunks] for semantic RAG retrieval.
@immutable
final class DetectionSignals {
  const DetectionSignals({
    this.widgetTypes = const [],
    this.stackPatterns = const [],
    this.minUiThreadMs,
    this.minRasterThreadMs,
    this.requiresImpeller,
    this.minRebuildCount,
    this.embedChunks = const [],
  });

  factory DetectionSignals.fromJson(Map<String, dynamic> json) =>
      DetectionSignals(
        widgetTypes: (json['widget_types'] as List?)?.cast<String>() ?? [],
        stackPatterns: (json['stack_patterns'] as List?)?.cast<String>() ?? [],
        minUiThreadMs: (json['min_ui_thread_ms'] as num?)?.toDouble(),
        minRasterThreadMs: (json['min_raster_thread_ms'] as num?)?.toDouble(),
        requiresImpeller: json['requires_impeller'] as bool?,
        minRebuildCount: json['min_rebuild_count'] as int?,
        embedChunks: (json['embed_chunks'] as List?)?.cast<String>() ?? [],
      );

  /// Widget class names that must appear in rebuild counts or UI stack frames.
  final List<String> widgetTypes;

  /// Dart symbol or file fragments that must appear in UI or raster stack frames.
  final List<String> stackPatterns;

  /// Minimum UI thread frame time to consider this pattern (ms).
  final double? minUiThreadMs;

  /// Minimum raster thread frame time to consider this pattern (ms).
  final double? minRasterThreadMs;

  /// If non-null, Impeller must be enabled (true) or disabled (false).
  final bool? requiresImpeller;

  /// Minimum rebuild count for any widget within the frame budget window.
  final int? minRebuildCount;

  /// Pre-written text chunks for embedding. Each chunk is embedded independently
  /// and stored in the KB Bundle's EmbeddingManifest. At retrieval time, the
  /// daemon queries by cosine similarity against the batch's telemetry summary.
  final List<String> embedChunks;

  Map<String, dynamic> toJson() => {
        'widget_types': widgetTypes,
        'stack_patterns': stackPatterns,
        if (minUiThreadMs != null) 'min_ui_thread_ms': minUiThreadMs,
        if (minRasterThreadMs != null)
          'min_raster_thread_ms': minRasterThreadMs,
        if (requiresImpeller != null) 'requires_impeller': requiresImpeller,
        if (minRebuildCount != null) 'min_rebuild_count': minRebuildCount,
        'embed_chunks': embedChunks,
      };
}

/// The expected frame-time improvement when the fix is applied.
///
/// Candidate entries use author estimates; stable entries use measured values
/// from the eval harness (FrameTimingDelta). The stable CI gate enforces
/// that fix effectiveness ≥ 0.65 (≥ 20% frame-time reduction).
@immutable
final class ExpectedImprovement {
  const ExpectedImprovement({
    required this.minReductionPercent,
    required this.maxReductionPercent,
    required this.description,
  })  : assert(
          minReductionPercent >= 0 && minReductionPercent <= 100,
          'minReductionPercent must be in [0, 100]',
        ),
        assert(
          maxReductionPercent >= minReductionPercent,
          'maxReductionPercent must be >= minReductionPercent',
        );

  factory ExpectedImprovement.fromJson(Map<String, dynamic> json) =>
      ExpectedImprovement(
        minReductionPercent: (json['min_reduction_percent'] as num).toDouble(),
        maxReductionPercent: (json['max_reduction_percent'] as num).toDouble(),
        description: json['description'] as String,
      );

  /// Lower bound of expected frame-time reduction (percentage, 0–100).
  final double minReductionPercent;

  /// Upper bound of expected frame-time reduction (percentage, 0–100).
  final double maxReductionPercent;

  /// Human-readable description shown in the Diagnosis UI.
  final String description;

  Map<String, dynamic> toJson() => {
        'min_reduction_percent': minReductionPercent,
        'max_reduction_percent': maxReductionPercent,
        'description': description,
      };
}
