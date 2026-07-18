import 'package:meta/meta.dart';
import 'jank_frame.dart';

/// A 500ms window of VM Service events containing at least one JankFrame.
///
/// Only batches with at least one JankFrame are forwarded to the Analysis Daemon.
/// All other batches are discarded at the collector level (~95% volume reduction).
@immutable
final class TelemetryBatch {
  const TelemetryBatch({
    required this.sessionId,
    required this.projectFingerprint,
    required this.windowStartMs,
    required this.windowEndMs,
    required this.jankFrames,
    required this.analysisMode,
    required this.deviceInfo,
    this.cpuUsagePercent,
    this.heapUsageMb,
    this.gcCount = 0,
  });

  final String sessionId;

  /// Stable 16-hex-char hash of the project root directory path.
  ///
  /// Computed client-side (FNV-1a of `Directory.current.path`) so the actual
  /// path is never transmitted to the daemon.
  /// Used by the daemon to correlate sessions from the same project and
  /// produce accurate cross-session recurrence counts.
  final String projectFingerprint;

  /// Window start time in milliseconds since epoch.
  final int windowStartMs;

  /// Window end time in milliseconds since epoch.
  final int windowEndMs;

  /// All frames in this window that exceeded the frame budget.
  final List<JankFrame> jankFrames;

  /// Whether the app is running in debug or profile mode.
  final AnalysisMode analysisMode;

  /// Device and runtime information.
  final DeviceInfo deviceInfo;

  /// Average CPU usage percentage during this window.
  final double? cpuUsagePercent;

  /// Heap usage in MB at the end of this window.
  final double? heapUsageMb;

  /// Number of GC events during this window.
  final int gcCount;

  int get windowDurationMs => windowEndMs - windowStartMs;

  /// The most severe jank frame (highest totalMs).
  JankFrame get worstFrame =>
      jankFrames.reduce((a, b) => a.totalMs > b.totalMs ? a : b);

  /// All unique files appearing in UI stack frames across all jank frames.
  Set<String> get involvedFiles => jankFrames
      .expand((f) => f.uiStack)
      .where((s) => s.isUserCode)
      .map((s) => s.file)
      .toSet();

  /// All unique widget types appearing in rebuild data.
  Set<String> get rebuiltWidgets =>
      jankFrames.expand((f) => f.rebuildCounts.keys).toSet();

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'project_fingerprint': projectFingerprint,
        'window_start_ms': windowStartMs,
        'window_end_ms': windowEndMs,
        'jank_frames': jankFrames.map((f) => f.toJson()).toList(),
        'analysis_mode': analysisMode.name,
        'device_info': deviceInfo.toJson(),
        if (cpuUsagePercent != null) 'cpu_usage_percent': cpuUsagePercent,
        if (heapUsageMb != null) 'heap_usage_mb': heapUsageMb,
        'gc_count': gcCount,
      };

  factory TelemetryBatch.fromJson(Map<String, dynamic> json) => TelemetryBatch(
        sessionId: json['session_id'] as String,
        // Backward-compat: default to empty string if field absent
        // (batches sent by an older client before this field was added).
        projectFingerprint: json['project_fingerprint'] as String? ?? '',
        windowStartMs: json['window_start_ms'] as int,
        windowEndMs: json['window_end_ms'] as int,
        jankFrames: (json['jank_frames'] as List)
            .map((e) => JankFrame.fromJson(e as Map<String, dynamic>))
            .toList(),
        analysisMode:
            AnalysisMode.values.byName(json['analysis_mode'] as String),
        deviceInfo:
            DeviceInfo.fromJson(json['device_info'] as Map<String, dynamic>),
        cpuUsagePercent: (json['cpu_usage_percent'] as num?)?.toDouble(),
        heapUsageMb: (json['heap_usage_mb'] as num?)?.toDouble(),
        gcCount: (json['gc_count'] as int?) ?? 0,
      );
}

enum AnalysisMode {
  /// Debug mode — has rebuild counts, lower frame timing fidelity.
  deep,

  /// Profile mode — accurate frame timing, no rebuild counts.
  timing,
}

@immutable
final class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    required this.osVersion,
    required this.flutterVersion,
    required this.dartVersion,
    required this.impellerEnabled,
    this.gpuName,
    this.physicalMemoryMb,
    this.cpuCores,
  });

  final TargetPlatform platform;
  final String osVersion;
  final String flutterVersion;
  final String dartVersion;
  final bool impellerEnabled;
  final String? gpuName;
  final int? physicalMemoryMb;
  final int? cpuCores;

  Map<String, dynamic> toJson() => {
        'platform': platform.name,
        'os_version': osVersion,
        'flutter_version': flutterVersion,
        'dart_version': dartVersion,
        'impeller_enabled': impellerEnabled,
        if (gpuName != null) 'gpu_name': gpuName,
        if (physicalMemoryMb != null) 'physical_memory_mb': physicalMemoryMb,
        if (cpuCores != null) 'cpu_cores': cpuCores,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        platform: TargetPlatform.values.byName(json['platform'] as String),
        osVersion: json['os_version'] as String,
        flutterVersion: json['flutter_version'] as String,
        dartVersion: json['dart_version'] as String,
        impellerEnabled: json['impeller_enabled'] as bool,
        gpuName: json['gpu_name'] as String?,
        physicalMemoryMb: json['physical_memory_mb'] as int?,
        cpuCores: json['cpu_cores'] as int?,
      );
}

enum TargetPlatform { android, ios, macos, windows, linux, fuchsia }
