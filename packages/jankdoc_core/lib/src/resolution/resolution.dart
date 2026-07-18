import 'package:meta/meta.dart';

/// The structured output describing *how* to fix a diagnosed antipattern.
///
/// A Resolution is produced by the Analysis Daemon alongside a Diagnosis.
/// For Rule Pre-filter diagnoses, the Resolution is read directly from the KB Entry.
/// For LLM-tier diagnoses, the LLM generates a Resolution and the Output Validator
/// cross-checks the cited file paths against the real stack frames.
@immutable
final class Resolution {
  const Resolution({
    required this.diagnosisId,
    required this.patternId,
    required this.kind,
    required this.summary,
    required this.codeExample,
    required this.filePaths,
    this.measuredDelta,
  });

  factory Resolution.fromJson(Map<String, dynamic> json) => Resolution(
        diagnosisId: json['diagnosis_id'] as String,
        patternId: json['pattern_id'] as String,
        kind: ResolutionKind.values.byName(json['kind'] as String),
        summary: json['summary'] as String,
        codeExample: json['code_example'] as String,
        filePaths: (json['file_paths'] as List).cast<String>(),
        measuredDelta: json['measured_delta'] != null
            ? FrameTimingDelta.fromJson(
                json['measured_delta'] as Map<String, dynamic>,
              )
            : null,
      );

  /// The Diagnosis this Resolution belongs to.
  final String diagnosisId;

  /// The KB Entry ID that defines this resolution.
  final String patternId;

  final ResolutionKind kind;

  /// One-sentence human-readable description of the fix.
  final String summary;

  /// The concrete code change to make. For rule-tier diagnoses this comes
  /// verbatim from the KB Entry; for LLM-tier diagnoses it is generated.
  final String codeExample;

  /// File paths that will need to change. Validated against real stack frames
  /// by the Output Validator for LLM-tier diagnoses.
  final List<String> filePaths;

  /// Measured before/after frame timing from the eval harness.
  /// Null for diagnoses produced outside the eval harness.
  final FrameTimingDelta? measuredDelta;

  Map<String, dynamic> toJson() => {
        'diagnosis_id': diagnosisId,
        'pattern_id': patternId,
        'kind': kind.name,
        'summary': summary,
        'code_example': codeExample,
        'file_paths': filePaths,
        if (measuredDelta != null) 'measured_delta': measuredDelta!.toJson(),
      };
}

/// The category of code change required to resolve a diagnosed antipattern.
///
/// Used by the DevTools Extension UI to render fix suggestions with
/// context-appropriate guidance and to group recurring resolutions.
enum ResolutionKind {
  /// Move expensive computation out of a widget's build() method into a
  /// field, initState(), or a provider — preventing redundant recalculation.
  moveOutsideBuild,

  /// Extract a subtree into a separate StatelessWidget or const widget so
  /// Flutter can skip its rebuild when its inputs have not changed.
  extractWidget,

  /// Wrap a subtree in RepaintBoundary to isolate its raster layer from
  /// its neighbours, reducing raster overdraw on animation.
  addRepaintBoundary,

  /// Replace a broad rebuild trigger (setState, provider watch) with a
  /// fine-grained ValueListenableBuilder or ValueNotifier listener.
  useValueListenableBuilder,

  /// Cache the result of a pure computation using a field, `late final`,
  /// or a memoisation wrapper so it is not recomputed on every build.
  memoize,

  /// Reduce the number of compositing layers — remove redundant Opacity,
  /// ShaderMask, or BackdropFilter widgets that force layer promotion.
  reduceLayerCount,

  /// Offload CPU-bound work (JSON decoding, image processing) to a
  /// background Dart isolate via `compute()` or `Isolate.run()`.
  useIsolate,

  /// Add or update an SkSL shader warm-up file to eliminate first-frame
  /// shader compilation stutter.
  addShaderWarmup,

  /// Set `itemExtent`, `prototypeItem`, or switch to a `SliverFixedExtentList`
  /// to let Flutter skip layout calculations on uniform list items.
  fixListExtent,

  /// Supply `cacheWidth`/`cacheHeight` to Image or use `ResizeImage` to
  /// decode images at display resolution rather than their native size.
  fixImageCacheSize,

  /// A platform-specific fix that does not map cleanly to a single Dart
  /// code change — e.g. Impeller flag, Android GPU driver configuration.
  platformSpecific,

  /// A fix that does not fit any of the above categories. The codeExample
  /// field carries the full explanation.
  other,
}

/// Before/after frame timing measured by the eval harness for a given Resolution.
///
/// Used by the stable CI gate to enforce fix effectiveness ≥ 0.65
/// (frame-time reduction ≥ 20%).
@immutable
final class FrameTimingDelta {
  const FrameTimingDelta({
    required this.beforeMs,
    required this.afterMs,
  }) : assert(beforeMs > 0, 'beforeMs must be positive');

  factory FrameTimingDelta.fromJson(Map<String, dynamic> json) =>
      FrameTimingDelta(
        beforeMs: (json['before_ms'] as num).toDouble(),
        afterMs: (json['after_ms'] as num).toDouble(),
      );

  /// Median frame time before the fix was applied (ms).
  final double beforeMs;

  /// Median frame time after the fix was applied (ms).
  final double afterMs;

  /// Frame-time reduction as a percentage (0–100).
  double get reductionPercent =>
      ((beforeMs - afterMs) / beforeMs * 100).clamp(0.0, 100.0);

  /// True when the fix meets the stable CI gate threshold (≥ 20% reduction).
  bool get meetsStableThreshold => reductionPercent >= 20.0;

  /// Fix effectiveness score [0.0, 1.0] used in CI gate comparisons.
  double get effectivenessScore => (reductionPercent / 100).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'before_ms': beforeMs,
        'after_ms': afterMs,
      };
}
