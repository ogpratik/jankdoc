import 'package:meta/meta.dart';
import 'diagnosis.dart';
import 'telemetry_batch.dart';

/// A declarative Rule — not an imperative Dart function.
///
/// Rules are Dart constants. Adding a rule requires no recompilation
/// of the analysis engine. The rule engine loads all [Rule] instances
/// from [RuleProvider] at daemon startup and evaluates them in order.
@immutable
final class Rule {
  const Rule({
    required this.id,
    required this.patternId,
    required this.confidence,
    required this.severity,
    required this.condition,
    this.priority = 0,
  });

  /// Unique rule identifier. Matches the KB Entry ID.
  final String id;

  /// KB Entry ID this rule references for the canned Diagnosis.
  final String patternId;

  /// Confidence score assigned to Diagnoses produced by this rule [0.85, 1.0].
  final double confidence;

  final Severity severity;

  /// The root Condition tree. Evaluated against a TelemetryBatch.
  final Condition condition;

  /// Higher priority rules are evaluated first. Default 0.
  /// Use to ensure specific rules run before general fallback rules.
  final int priority;

  /// Returns true if this rule matches the given batch.
  bool matches(TelemetryBatch batch) => condition.evaluate(batch);
}

/// Base class for all composable Conditions.
///
/// Conditions form a tree: leaf conditions check specific signals,
/// combinator conditions (And, Or, Not) compose them.
sealed class Condition {
  const Condition();

  /// Returns true if this condition is satisfied by the given batch.
  bool evaluate(TelemetryBatch batch);
}

// ─────────────────────────────────────────────────────────────────────────────
// Combinator conditions
// ─────────────────────────────────────────────────────────────────────────────

/// All child conditions must be satisfied.
final class And extends Condition {
  const And(this.conditions);
  final List<Condition> conditions;

  @override
  bool evaluate(TelemetryBatch batch) =>
      conditions.every((c) => c.evaluate(batch));
}

/// At least one child condition must be satisfied.
final class Or extends Condition {
  const Or(this.conditions);
  final List<Condition> conditions;

  @override
  bool evaluate(TelemetryBatch batch) =>
      conditions.any((c) => c.evaluate(batch));
}

/// The child condition must NOT be satisfied.
final class Not extends Condition {
  const Not(this.condition);
  final Condition condition;

  @override
  bool evaluate(TelemetryBatch batch) => !condition.evaluate(batch);
}

// ─────────────────────────────────────────────────────────────────────────────
// Thread conditions
// ─────────────────────────────────────────────────────────────────────────────

/// True when the worst JankFrame's UI thread exceeds [thresholdMs].
final class UiThreadMs extends Condition {
  const UiThreadMs({required this.greaterThan});
  final double greaterThan;

  @override
  bool evaluate(TelemetryBatch batch) =>
      batch.worstFrame.uiThreadMs > greaterThan;
}

/// True when the worst JankFrame's raster thread exceeds [thresholdMs].
final class RasterThreadMs extends Condition {
  const RasterThreadMs({required this.greaterThan});
  final double greaterThan;

  @override
  bool evaluate(TelemetryBatch batch) =>
      batch.worstFrame.rasterThreadMs > greaterThan;
}

/// True when the raster thread is the dominant bottleneck
/// (raster ≥ ui * [factor]).
final class RasterDominant extends Condition {
  const RasterDominant({this.factor = 1.5});
  final double factor;

  @override
  bool evaluate(TelemetryBatch batch) {
    final frame = batch.worstFrame;
    return frame.rasterThreadMs >= frame.uiThreadMs * factor;
  }
}

/// True when the UI thread is the dominant bottleneck.
final class UiDominant extends Condition {
  const UiDominant({this.factor = 1.5});
  final double factor;

  @override
  bool evaluate(TelemetryBatch batch) {
    final frame = batch.worstFrame;
    return frame.uiThreadMs >= frame.rasterThreadMs * factor;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget / stack conditions
// ─────────────────────────────────────────────────────────────────────────────

/// True when [widgetType] appears in any frame's rebuild counts.
final class WidgetType extends Condition {
  const WidgetType(this.widgetType);
  final String widgetType;

  @override
  bool evaluate(TelemetryBatch batch) =>
      batch.rebuiltWidgets.contains(widgetType);
}

/// True when any of [widgetTypes] appear in the rebuild counts.
final class AnyWidgetType extends Condition {
  const AnyWidgetType(this.widgetTypes);
  final List<String> widgetTypes;

  @override
  bool evaluate(TelemetryBatch batch) =>
      batch.rebuiltWidgets.any(widgetTypes.contains);
}

/// True when any UI stack frame across jank frames contains [functionPattern].
final class StackContains extends Condition {
  const StackContains(this.functionPattern);
  final String functionPattern;

  @override
  bool evaluate(TelemetryBatch batch) => batch.jankFrames
      .expand((f) => f.uiStack)
      .any((s) => s.function.contains(functionPattern));
}

/// True when the rebuild count for [widgetType] exceeds [fps] * [factor].
final class RebuildStorm extends Condition {
  const RebuildStorm({required this.widgetType, this.factor = 1.5});
  final String widgetType;

  /// Multiplier on the target FPS. Default 1.5 = 90 rebuilds/sec at 60fps.
  final double factor;

  @override
  bool evaluate(TelemetryBatch batch) {
    final count = batch.jankFrames
        .expand((f) => f.rebuildCounts.entries)
        .where((e) => e.key.contains(widgetType))
        .fold(0, (sum, e) => sum + e.value);
    final threshold =
        (batch.worstFrame.targetFps * factor).round();
    return count > threshold;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Platform / device conditions
// ─────────────────────────────────────────────────────────────────────────────

/// True when the device is running with Impeller enabled.
final class ImpellerEnabled extends Condition {
  const ImpellerEnabled();

  @override
  bool evaluate(TelemetryBatch batch) => batch.deviceInfo.impellerEnabled;
}

/// True when the target platform matches.
final class Platform extends Condition {
  const Platform(this.platform);
  final TargetPlatform platform;

  @override
  bool evaluate(TelemetryBatch batch) => batch.deviceInfo.platform == platform;
}

/// True when the GPU name contains [pattern] (case-insensitive).
final class GpuContains extends Condition {
  const GpuContains(this.pattern);
  final String pattern;

  @override
  bool evaluate(TelemetryBatch batch) =>
      batch.deviceInfo.gpuName
          ?.toLowerCase()
          .contains(pattern.toLowerCase()) ??
      false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Memory / GC conditions
// ─────────────────────────────────────────────────────────────────────────────

/// True when GC events occurred during this batch window.
final class GcPressure extends Condition {
  const GcPressure({this.minCount = 1});
  final int minCount;

  @override
  bool evaluate(TelemetryBatch batch) => batch.gcCount >= minCount;
}

/// True when heap usage exceeds [thresholdMb].
final class HeapUsageMb extends Condition {
  const HeapUsageMb({required this.greaterThan});
  final double greaterThan;

  @override
  bool evaluate(TelemetryBatch batch) =>
      (batch.heapUsageMb ?? 0) > greaterThan;
}
