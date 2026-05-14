/// JankDoc — A Flutter DevTools extension that diagnoses jank at the code level.
///
/// ## Usage
///
/// ```yaml
/// # pubspec.yaml
/// dev_dependencies:
///   jankdoc: ^1.0.0
/// ```
///
/// ```dart
/// // lib/main.dart
/// import 'package:jankdoc/jankdoc.dart';
///
/// void main() async {
///   await JankDoc.attach();
///   runApp(const MyApp());
/// }
/// ```
///
/// Then open Flutter DevTools → JankDoc tab.
///
/// ## What happens at each call site
///
/// | Mode    | Daemon | Telemetry | DevTools UI |
/// |---------|--------|-----------|-------------|
/// | Debug   | ✓ auto | ✓ full    | ✓           |
/// | Profile | ✓ auto | ✓ timing  | ✓           |
/// | Release | ✗ no-op | ✗        | N/A         |
///
/// The release-mode guard is a `const bool.fromEnvironment` compile-time
/// constant — the entire [JankDoc] class is tree-shaken from release APKs.
library jankdoc;

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/daemon_launcher.dart';
import 'src/telemetry/telemetry_collector.dart';

export 'src/daemon_launcher.dart';

/// The main JankDoc entry point.
abstract final class JankDoc {
  JankDoc._();

  static final _launcher = DaemonLauncher();
  static bool _attached = false;
  static TelemetryCollector? _collector;

  /// Attach JankDoc to the current Flutter app.
  ///
  /// Call this **before** [runApp] in your `main()`:
  ///
  /// ```dart
  /// void main() async {
  ///   await JankDoc.attach();
  ///   runApp(const MyApp());
  /// }
  /// ```
  ///
  /// ### What it does
  ///
  /// 1. Starts (or reuses) the Analysis Daemon on port 9101.
  /// 2. Registers the `ext.jankdoc.daemonUrl` VM Service extension so the
  ///    DevTools extension can discover the daemon's address.
  /// 3. Starts the [TelemetryCollector]:
  ///    - Hooks [SchedulerBinding.addTimingsCallback] for frame timing.
  ///    - In debug mode: tracks widget rebuild counts.
  ///    - Connects to the VM Service to capture CPU stack frames on jank.
  ///    - POSTs [TelemetryBatch]es to the daemon every 500ms.
  ///
  /// ### Guarantees
  ///
  /// - **Idempotent**: safe to call multiple times (hot-restart safe).
  /// - **Release no-op**: compiles away entirely in release mode.
  /// - **Non-fatal**: if the daemon can't start, JankDoc logs a message and
  ///   returns — your app keeps running normally.
  static Future<void> attach() async {
    // ── Release guard ──────────────────────────────────────────────────────
    // const bool.fromEnvironment is evaluated at compile time; the entire
    // body is tree-shaken in release builds.
    if (const bool.fromEnvironment('dart.vm.product')) return;

    if (_attached) return;
    _attached = true;

    // Ensure the Flutter binding is initialized before we touch SchedulerBinding.
    // This is idempotent — safe if the app already called ensureInitialized().
    WidgetsFlutterBinding.ensureInitialized();

    // ── Start daemon ───────────────────────────────────────────────────────
    int port;
    try {
      port = await _launcher.ensureRunning();
      _log('Analysis daemon ready on port $port. '
          'Open Flutter DevTools → JankDoc tab.');
    } on ProcessException catch (e) {
      _log('Could not start daemon: ${e.message}\n'
          'Run `dart run jankdoc:daemon` in a separate terminal, '
          'or install the JankDoc VS Code extension for zero-config setup.');
      return;
    } catch (e) {
      _log('Startup error: $e\n'
          'Run `dart run jankdoc:daemon` manually to diagnose.');
      return;
    }

    // ── Start telemetry collector ──────────────────────────────────────────
    try {
      _collector = await TelemetryCollector.create(port);
    } catch (e) {
      _log('Telemetry collector failed to start: $e\n'
          'Frame timing will not be collected this session.');
    }
  }

  /// Stop collecting telemetry and release resources.
  ///
  /// Normally not needed — the collector is automatically stopped when the
  /// Flutter app terminates. Call this explicitly only in tests or if you want
  /// to pause collection temporarily.
  static Future<void> detach() async {
    if (const bool.fromEnvironment('dart.vm.product')) return;
    await _collector?.dispose();
    _collector = null;
    _attached = false;
  }

  static void _log(String msg) {
    // ignore: avoid_print
    print('[JankDoc] $msg');
  }
}
