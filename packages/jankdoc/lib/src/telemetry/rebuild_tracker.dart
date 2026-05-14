import 'package:flutter/widgets.dart';

/// Tracks widget rebuild counts during the current frame window.
///
/// In **debug mode**: hooks into [debugOnRebuildDirtyWidget], a framework
/// callback invoked inside `BuildOwner.buildScope` every time a dirty widget
/// is rebuilt. Counting is cumulative until [flushCounts] is called.
///
/// In **profile / release mode**: the [debugOnRebuildDirtyWidget] hook is
/// inside an `assert()`, so it never runs. [flushCounts] returns an empty map.
/// This is expected — profile mode gives more accurate frame timing at the
/// cost of debug-only introspection.
final class RebuildTracker {
  final Map<String, int> _counts = {};

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;

    // The assignment is inside an assert so it is dead code in profile/release.
    assert(() {
      debugOnRebuildDirtyWidget = _onRebuild;
      return true;
    }());
  }

  void stop() {
    assert(() {
      // Only clear if we were the ones who set it (guard against other users
      // of debugOnRebuildDirtyWidget in the same process, e.g. Flutter Inspector).
      if (debugOnRebuildDirtyWidget == _onRebuild) {
        debugOnRebuildDirtyWidget = null;
      }
      return true;
    }());
    _counts.clear();
    _started = false;
  }

  /// Returns a snapshot of rebuild counts since the last call to [flushCounts]
  /// and resets the internal counter.
  ///
  /// Thread-safety: called on the UI thread only, so no lock needed.
  Map<String, int> flushCounts() {
    if (_counts.isEmpty) return const {};
    final snapshot = Map<String, int>.from(_counts);
    _counts.clear();
    return snapshot;
  }

  void _onRebuild(Element element, bool builtOnce) {
    // Use widget.runtimeType.toString() for a stable key.
    // This matches how DevTools and the LLM prompts reference widget types.
    final widgetType = element.widget.runtimeType.toString();
    _counts[widgetType] = (_counts[widgetType] ?? 0) + 1;
  }
}
