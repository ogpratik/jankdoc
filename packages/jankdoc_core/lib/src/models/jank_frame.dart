import 'package:meta/meta.dart';

/// A single rendered frame that exceeded the device's frame budget.
///
/// The atomic unit of telemetry that triggers JankDoc analysis.
/// Budget: >16ms at 60fps, >8ms at 120fps.
@immutable
final class JankFrame {
  const JankFrame({
    required this.timestamp,
    required this.uiThreadMs,
    required this.rasterThreadMs,
    required this.totalMs,
    required this.targetFps,
    required this.uiStack,
    required this.rasterStack,
    this.rebuildCounts = const {},
    this.layoutPhaseMs,
    this.paintPhaseMs,
  });

  /// Microseconds since VM start (from vm.TimelineEvents).
  final int timestamp;

  /// UI thread duration in milliseconds.
  final double uiThreadMs;

  /// Raster thread duration in milliseconds.
  final double rasterThreadMs;

  /// Total frame duration in milliseconds.
  final double totalMs;

  /// Target refresh rate (60 or 120).
  final int targetFps;

  /// Stack frames from the UI thread at peak activity.
  final List<StackFrame> uiStack;

  /// Stack frames from the raster thread at peak activity.
  final List<StackFrame> rasterStack;

  /// Widget type → rebuild count (debug mode only, from trackRebuildDirtyWidgets).
  final Map<String, int> rebuildCounts;

  /// Layout phase duration in milliseconds (from debugProfileLayoutsEnabled).
  final double? layoutPhaseMs;

  /// Paint phase duration in milliseconds.
  final double? paintPhaseMs;

  /// The per-frame budget in milliseconds at the target refresh rate.
  double get budgetMs => 1000 / targetFps;

  /// How far over budget this frame was, in milliseconds.
  double get overBudgetMs => totalMs - budgetMs;

  /// Which thread is the bottleneck.
  ThreadBottleneck get bottleneck {
    if (uiThreadMs >= rasterThreadMs * 1.5) return ThreadBottleneck.ui;
    if (rasterThreadMs >= uiThreadMs * 1.5) return ThreadBottleneck.raster;
    return ThreadBottleneck.both;
  }

  /// Whether this frame has rebuild data (only available in Deep Analysis Mode).
  bool get hasRebuildData => rebuildCounts.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'ui_thread_ms': uiThreadMs,
        'raster_thread_ms': rasterThreadMs,
        'total_ms': totalMs,
        'target_fps': targetFps,
        'ui_stack': uiStack.map((f) => f.toJson()).toList(),
        'raster_stack': rasterStack.map((f) => f.toJson()).toList(),
        'rebuild_counts': rebuildCounts,
        if (layoutPhaseMs != null) 'layout_phase_ms': layoutPhaseMs,
        if (paintPhaseMs != null) 'paint_phase_ms': paintPhaseMs,
      };

  factory JankFrame.fromJson(Map<String, dynamic> json) => JankFrame(
        timestamp: json['timestamp'] as int,
        uiThreadMs: (json['ui_thread_ms'] as num).toDouble(),
        rasterThreadMs: (json['raster_thread_ms'] as num).toDouble(),
        totalMs: (json['total_ms'] as num).toDouble(),
        targetFps: json['target_fps'] as int,
        uiStack: (json['ui_stack'] as List)
            .map((e) => StackFrame.fromJson(e as Map<String, dynamic>))
            .toList(),
        rasterStack: (json['raster_stack'] as List)
            .map((e) => StackFrame.fromJson(e as Map<String, dynamic>))
            .toList(),
        rebuildCounts: Map<String, int>.from(
          (json['rebuild_counts'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ),
        ),
        layoutPhaseMs: (json['layout_phase_ms'] as num?)?.toDouble(),
        paintPhaseMs: (json['paint_phase_ms'] as num?)?.toDouble(),
      );
}

/// A single stack frame captured from the VM.
@immutable
final class StackFrame {
  const StackFrame({
    required this.file,
    required this.line,
    required this.column,
    required this.function,
    this.packageName,
    this.widgetType,
  });

  final String file;
  final int line;
  final int column;
  final String function;

  /// Resolved package name (e.g. 'my_app', 'flutter', 'riverpod').
  final String? packageName;

  /// Widget type if the frame corresponds to a widget's build method.
  final String? widgetType;

  /// Whether this frame is in user code (not framework or packages).
  bool get isUserCode =>
      packageName != null &&
      packageName != 'flutter' &&
      !packageName!.startsWith('flutter_') &&
      packageName != 'dart' &&
      !packageName!.startsWith('dart:');

  Map<String, dynamic> toJson() => {
        'file': file,
        'line': line,
        'column': column,
        'function': function,
        if (packageName != null) 'package_name': packageName,
        if (widgetType != null) 'widget_type': widgetType,
      };

  factory StackFrame.fromJson(Map<String, dynamic> json) => StackFrame(
        file: json['file'] as String,
        line: json['line'] as int,
        column: json['column'] as int,
        function: json['function'] as String,
        packageName: json['package_name'] as String?,
        widgetType: json['widget_type'] as String?,
      );
}

enum ThreadBottleneck { ui, raster, both }
