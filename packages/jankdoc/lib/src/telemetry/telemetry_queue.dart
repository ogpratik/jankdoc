import 'dart:async';

import 'package:jankdoc_core/jankdoc_core.dart';

/// A broadcast stream of [TelemetryBatch] objects received from the
/// Flutter app via POST /telemetry/batch.
///
/// The [DiagnosisPipeline] subscribes to [batches] and processes each one.
final class TelemetryQueue {
  final _controller = StreamController<TelemetryBatch>.broadcast();

  /// Add a batch to the queue. Called by the daemon's HTTP handler.
  void add(TelemetryBatch batch) => _controller.add(batch);

  /// Stream of incoming telemetry batches.
  Stream<TelemetryBatch> get batches => _controller.stream;

  Future<void> dispose() => _controller.close();
}
