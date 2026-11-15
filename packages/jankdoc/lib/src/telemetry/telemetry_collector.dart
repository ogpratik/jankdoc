import 'dart:async' show unawaited;
// FramePhase and FrameTiming are dart:ui types (not package:flutter).
import 'dart:ui' show FramePhase;

// Hide flutter's StackFrame so jankdoc_core.StackFrame (telemetry model) stays in scope.
import 'package:flutter/foundation.dart' hide StackFrame;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show BuildOwner, WidgetsBinding;
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:uuid/uuid.dart';

import 'batch_sender.dart';
import 'device_info_resolver.dart';
import 'layer_census.dart';
import 'rebuild_tracker.dart';
import 'vm_service_client.dart';

/// Collects frame timing, rebuild counts, and stack traces from the running
/// Flutter app and forwards them to the JankDoc Analysis Daemon.
///
/// ## Data pipeline
///
/// ```
/// SchedulerBinding.addTimingsCallback
///         ↓ FrameTiming (every frame)
/// _onFrameTimings() — filters over-budget frames
///         ↓ (async, non-blocking)
/// VmServiceClient.getCpuStackFrames()  ← only on jank frames
/// RebuildTracker.flushCounts()
///         ↓
/// BatchSender.addFrame()
///         ↓ (every 500ms)
/// POST http://127.0.0.1:9101/telemetry/batch
/// ```
///
/// ## Threading model
///
/// [SchedulerBinding.addTimingsCallback] fires on the UI thread after every
/// frame. The callback is kept short: filtering + scheduling async work.
/// The VM Service call and HTTP POST run on Dart's async event loop and
/// never block the UI thread.
///
/// ## Mode behaviour
///
/// | Mode     | Frame timing | Rebuild counts | Stack frames |
/// |----------|-------------|----------------|--------------|
/// | Debug    | ✓           | ✓              | ✓            |
/// | Profile  | ✓ (better)  | ✗              | ✓            |
/// | Release  | (no-op — TelemetryCollector is never created in release mode) |
final class TelemetryCollector {
  TelemetryCollector._({
    required VmServiceClient? vmClient,
    required RebuildTracker rebuildTracker,
    required BatchSender sender,
    required double targetFps,
  })  : _vmClient = vmClient,
        _rebuildTracker = rebuildTracker,
        _sender = sender,
        _targetFps = targetFps,
        _budgetMs = 1000.0 / targetFps;

  static const _uuid = Uuid();

  final VmServiceClient? _vmClient;
  final RebuildTracker _rebuildTracker;
  final BatchSender _sender;
  final double _targetFps;
  final double _budgetMs;

  bool _started = false;

  // CPU-sample capture is expensive: the VM serves getCpuSamples on this
  // isolate's thread and the reply holds the whole function table, so
  // capturing on every jank frame stalls the UI and manufactures more jank.
  // One capture at a time, at most once per cooldown, UI-bound frames only.
  static const _captureCooldown = Duration(seconds: 2);
  bool _captureInFlight = false;
  DateTime _lastCapture = DateTime.fromMillisecondsSinceEpoch(0);

  // setState scheduled from a post-frame callback on consecutive frames is
  // the setState-in-build loop (build → addPostFrameCallback → setState →
  // build …); calling setState directly in build asserts, so this is how the
  // pattern shows up in practice. The loop re-renders every frame forever,
  // so it is reported even when each frame fits the budget.
  static const _loopFrames = 3;
  static const _loopReportInterval = Duration(seconds: 5);
  BuildOwner? _buildOwner;
  VoidCallback? _previousOnBuildScheduled;
  Duration? _lastPostFrameBuild;
  int _postFrameBuildStreak = 0;
  List<StackFrame>? _loopStack;
  DateTime _lastLoopReport = DateTime.fromMillisecondsSinceEpoch(0);

  // Render-tree census of saveLayer-forcing widgets for raster-bound frames.
  static const _censusCooldown = Duration(seconds: 1);
  DateTime _lastCensus = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Creates and starts a [TelemetryCollector] connected to the daemon at
  /// [daemonPort].
  ///
  /// Steps:
  ///   1. Connect to the VM Service (best-effort — null on failure).
  ///   2. Resolve [DeviceInfo] from the current runtime.
  ///   3. Wire up [RebuildTracker] and [BatchSender].
  ///   4. Call [start] to register the frame timing callback.
  static Future<TelemetryCollector> create(int daemonPort) async {
    final sessionId = _uuid.v4();

    // Connect to VM Service — non-fatal if unavailable
    final vmClient = await VmServiceClient.connect();

    // Resolve device info (uses VM Service if available)
    final deviceInfo = await DeviceInfoResolver.resolve(
      vmService: vmClient?.service,
      mainIsolateId: vmClient?.mainIsolateId,
    );

    final rebuildTracker = RebuildTracker();
    final sender = BatchSender(
      daemonPort: daemonPort,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
    );

    final fps = DeviceInfoResolver.displayRefreshRate();

    final collector = TelemetryCollector._(
      vmClient: vmClient,
      rebuildTracker: rebuildTracker,
      sender: sender,
      targetFps: fps,
    );

    collector.start();
    return collector;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void start() {
    if (_started) return;
    _started = true;
    _rebuildTracker.start();
    _sender.start();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    final owner = WidgetsBinding.instance.buildOwner;
    if (owner != null) {
      _buildOwner = owner;
      _previousOnBuildScheduled = owner.onBuildScheduled;
      owner.onBuildScheduled = _onBuildScheduled;
    }
    _log(
        'Telemetry collector started (target: ${_targetFps.toStringAsFixed(0)}fps, '
        'budget: ${_budgetMs.toStringAsFixed(1)}ms)');
  }

  Future<void> dispose() async {
    if (!_started) return;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    if (_buildOwner case final owner?) {
      owner.onBuildScheduled = _previousOnBuildScheduled;
      _buildOwner = null;
    }
    _rebuildTracker.stop();
    await _sender.flush();
    _sender.dispose();
    _vmClient?.dispose();
    _started = false;
    _log('Telemetry collector stopped.');
  }

  // ── Frame timing callback ──────────────────────────────────────────────────

  /// Called by [SchedulerBinding] after every rendered frame.
  ///
  /// Kept fast: O(n) over the frame list (usually 1 frame), async work
  /// is scheduled without awaiting.
  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final uiMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = uiMs + rasterMs;

      final loopStack = _takeLoopStack();
      if (totalMs <= _budgetMs && loopStack == null) continue; // within budget

      // Capture rebuild counts immediately (synchronous — UI thread data),
      // plus the layer census when the raster thread is the bottleneck.
      final rebuildCounts = {
        ..._rebuildTracker.flushCounts(),
        if (rasterMs > uiMs) ..._takeCensus(),
      };

      // Schedule stack capture + sender asynchronously — non-blocking.
      // unawaited is intentional: we must not stall the frame timing callback.
      unawaited(_captureAndQueue(
        timing: timing,
        uiMs: uiMs,
        rasterMs: rasterMs,
        totalMs: totalMs,
        rebuildCounts: rebuildCounts,
        loopStack: loopStack,
      ));
    }
  }

  /// Wraps [BuildOwner.onBuildScheduled], which fires for the first widget
  /// marked dirty after each build.
  void _onBuildScheduled() {
    _previousOnBuildScheduled?.call();
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.postFrameCallbacks) {
      _postFrameBuildStreak = 0;
      return;
    }
    final frame = scheduler.currentFrameTimeStamp;
    final last = _lastPostFrameBuild;
    final consecutive = last != null &&
        frame > last &&
        frame - last < const Duration(milliseconds: 100);
    _postFrameBuildStreak = consecutive ? _postFrameBuildStreak + 1 : 1;
    _lastPostFrameBuild = frame;
    if (_postFrameBuildStreak >= _loopFrames && _loopStack == null) {
      _loopStack = _parseStackTrace(StackTrace.current);
    }
  }

  Map<String, int> _takeCensus() {
    final now = DateTime.now();
    if (now.difference(_lastCensus) < _censusCooldown) return const {};
    _lastCensus = now;
    return LayerCensus.take();
  }

  /// Returns the setState-loop stack at most once per report interval.
  List<StackFrame>? _takeLoopStack() {
    final stack = _loopStack;
    if (stack == null) return null;
    _loopStack = null;
    if (_postFrameBuildStreak < _loopFrames) return null; // loop ended
    final now = DateTime.now();
    if (now.difference(_lastLoopReport) < _loopReportInterval) return null;
    _lastLoopReport = now;
    return stack;
  }

  static final _traceLine =
      RegExp(r'^#\d+\s+(.+?) \((.+?):(\d+)(?::(\d+))?\)$');

  /// Parses a VM [StackTrace], dropping JankDoc's own frames.
  static List<StackFrame> _parseStackTrace(StackTrace trace) => [
        for (final line in trace.toString().split('\n'))
          if (_traceLine.firstMatch(line.trim()) case final m?)
            if (!m[2]!.startsWith('package:jankdoc/'))
              StackFrame(
                file: m[2]!,
                line: int.parse(m[3]!),
                column: int.tryParse(m[4] ?? '') ?? 0,
                function: m[1]!,
                packageName: _packageOf(m[2]!),
              ),
      ].take(12).toList();

  static String? _packageOf(String uri) {
    if (uri.startsWith('package:')) {
      final slash = uri.indexOf('/');
      return slash > 8 ? uri.substring(8, slash) : null;
    }
    if (uri.startsWith('dart:')) return 'dart';
    return null;
  }

  /// Async continuation: captures CPU samples then queues the frame.
  ///
  /// Runs on the Dart event loop (not the UI thread) so VM Service I/O is safe.
  Future<void> _captureAndQueue({
    required FrameTiming timing,
    required double uiMs,
    required double rasterMs,
    required double totalMs,
    required Map<String, int> rebuildCounts,
    List<StackFrame>? loopStack,
  }) async {
    var uiStack = <StackFrame>[...?loopStack];

    final vmClient = _vmClient;
    if (vmClient != null &&
        uiMs >= rasterMs &&
        !_captureInFlight &&
        DateTime.now().difference(_lastCapture) >= _captureCooldown) {
      _captureInFlight = true;
      try {
        final startUs = timing.timestampInMicroseconds(FramePhase.buildStart);
        final endUs = timing.timestampInMicroseconds(FramePhase.rasterFinish);
        uiStack = [
          ...uiStack,
          ...await vmClient.getCpuStackFrames(startUs, endUs)
        ];
      } finally {
        _captureInFlight = false;
        _lastCapture = DateTime.now();
      }
    }

    final frame = JankFrame(
      timestamp: timing.timestampInMicroseconds(FramePhase.buildStart),
      uiThreadMs: uiMs,
      rasterThreadMs: rasterMs,
      totalMs: totalMs,
      targetFps: _targetFps.round(),
      uiStack: uiStack,
      rasterStack: const [], // Raster stack not accessible from Dart side
      rebuildCounts: rebuildCounts,
      layoutPhaseMs: _layoutPhaseMs(timing),
      paintPhaseMs: _paintPhaseMs(timing),
    );

    _sender.addFrame(frame);
  }

  // ── Frame phase helpers ────────────────────────────────────────────────────

  /// Extracts layout duration from timeline phases if available.
  ///
  /// `buildFinish - buildStart` = full build phase (layout + paint combined).
  /// Flutter doesn't expose separate layout/paint timestamps via [FrameTiming],
  /// so we approximate by splitting build time in half. Accurate breakdown
  /// requires timeline events which add overhead we want to avoid.
  static double? _layoutPhaseMs(FrameTiming timing) {
    try {
      final buildUs = timing.buildDuration.inMicroseconds;
      return buildUs / 2000.0; // rough: half of build = layout
    } catch (_) {
      return null;
    }
  }

  static double? _paintPhaseMs(FrameTiming timing) {
    try {
      final buildUs = timing.buildDuration.inMicroseconds;
      return buildUs / 2000.0; // rough: half of build = paint
    } catch (_) {
      return null;
    }
  }

  // ── Logging ────────────────────────────────────────────────────────────────

  static void _log(String msg) {
    assert(() {
      debugPrint('[JankDoc] $msg');
      return true;
    }());
  }
}
