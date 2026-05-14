import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

/// Accumulates [JankFrame]s from the frame timing callback and POSTs them
/// to the Analysis Daemon as [TelemetryBatch]es.
///
/// Batching strategy:
///   - Frames are buffered for up to [_windowMs] milliseconds (500ms).
///   - On flush, all pending frames become a single batch.
///   - Batches with no jank frames are silently dropped.
///   - HTTP errors are swallowed — the collector degrades gracefully if
///     the daemon is temporarily unavailable.
final class BatchSender {
  BatchSender({
    required this.daemonPort,
    required this.sessionId,
    required this.deviceInfo,
  }) : _client = HttpClient();

  final int daemonPort;
  final String sessionId;
  final DeviceInfo deviceInfo;
  final HttpClient _client;

  static const _windowMs = 500;

  final List<JankFrame> _pending = [];
  Timer? _timer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void start() {
    _timer ??= Timer.periodic(
      const Duration(milliseconds: _windowMs),
      (_) => _flush(),
    );
  }

  /// Adds a jank frame to the pending buffer.
  void addFrame(JankFrame frame) => _pending.add(frame);

  /// Flush remaining frames immediately and cancel the timer.
  /// Called on [TelemetryCollector.dispose].
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await _flush();
  }

  void dispose() {
    _timer?.cancel();
    _client.close(force: true);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _flush() async {
    if (_pending.isEmpty) return;

    final frames = List<JankFrame>.from(_pending);
    _pending.clear();

    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = TelemetryBatch(
      sessionId: sessionId,
      windowStartMs: now - _windowMs,
      windowEndMs: now,
      jankFrames: frames,
      analysisMode: kDebugMode ? AnalysisMode.deep : AnalysisMode.timing,
      deviceInfo: deviceInfo,
    );

    await _post(batch);
  }

  Future<void> _post(TelemetryBatch batch) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$daemonPort/telemetry/batch');
      final request = await _client
          .postUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(batch.toJson()));
      final response = await request.close();
      // Drain response body to free the socket
      await response.drain<void>();
    } on TimeoutException {
      // Daemon slow — drop batch, log only in debug
      assert(() {
        debugPrint('[JankDoc] Batch POST timed out — daemon busy?');
        return true;
      }());
    } catch (_) {
      // Daemon unreachable — drop batch silently
    }
  }
}
