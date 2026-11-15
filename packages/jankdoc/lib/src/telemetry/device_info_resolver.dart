import 'dart:io';
import 'dart:ui' as ui;

// Hide jankdoc_core's Platform condition class so dart:io.Platform stays in scope.
import 'package:jankdoc_core/jankdoc_core.dart' hide Platform;
import 'package:vm_service/vm_service.dart' as vm;

/// Resolves [DeviceInfo] from the current runtime environment.
///
/// Called once at [TelemetryCollector.start] and cached for the session.
/// Combines `dart:io.Platform`, `dart:ui.PlatformDispatcher`, and
/// the VM Service for the most accurate picture possible.
abstract final class DeviceInfoResolver {
  DeviceInfoResolver._();

  /// Resolve [DeviceInfo]. Never throws — returns a best-effort result.
  static Future<DeviceInfo> resolve({
    vm.VmService? vmService,
    String? mainIsolateId,
  }) async {
    final platform = _targetPlatform();
    final dartVersion = _dartVersion();

    // `flutter run`/`flutter build` define FLUTTER_VERSION (the source of
    // FlutterVersion.version, which is newer than our 3.29 floor). The VM
    // banner only carries the Dart version, so there is no other source;
    // report nothing rather than the Dart version.
    const flutterVersion = bool.hasEnvironment('FLUTTER_VERSION')
        ? String.fromEnvironment('FLUTTER_VERSION')
        : '';

    final impellerEnabled = await _detectImpeller(
      platform,
      vmService: vmService,
      isolateId: mainIsolateId,
      dartVersion: dartVersion,
    );

    return DeviceInfo(
      platform: platform,
      osVersion: Platform.operatingSystemVersion,
      flutterVersion: flutterVersion,
      dartVersion: dartVersion,
      impellerEnabled: impellerEnabled,
      gpuName: null, // Not accessible from pure Dart
      physicalMemoryMb: null,
      cpuCores: _safeInt(() => Platform.numberOfProcessors),
    );
  }

  // ── Platform ──────────────────────────────────────────────────────────────

  static TargetPlatform _targetPlatform() {
    if (Platform.isAndroid) return TargetPlatform.android;
    if (Platform.isIOS) return TargetPlatform.ios;
    if (Platform.isMacOS) return TargetPlatform.macos;
    if (Platform.isWindows) return TargetPlatform.windows;
    if (Platform.isLinux) return TargetPlatform.linux;
    return TargetPlatform.android;
  }

  // ── Dart version ──────────────────────────────────────────────────────────

  /// Returns the semver part of `Platform.version`, e.g. `"3.6.0"`.
  static String _dartVersion() {
    return _parseVersion(Platform.version);
  }

  static String _parseVersion(String banner) {
    // "3.6.0 (stable) (xxx)" or "Dart VM version: 3.6.0 (stable)..."
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(banner);
    return match?.group(1) ?? '';
  }

  // ── Impeller detection ────────────────────────────────────────────────────

  /// Detects whether Impeller is the active renderer.
  ///
  /// Detection order:
  ///   1. `ext.flutter.impellerEnabled` (Flutter ≥ 3.22, most accurate)
  ///   2. Platform + Dart version heuristic (conservative fallback)
  ///
  /// Known defaults:
  ///   iOS:     Impeller on by default since Flutter 3.10 (Dart 3.0)
  ///   Android: Impeller on by default since Flutter 3.27 (Dart 3.6)
  static Future<bool> _detectImpeller(
    TargetPlatform platform, {
    vm.VmService? vmService,
    String? isolateId,
    required String dartVersion,
  }) async {
    // 1. VM Service extension (most accurate — reflects actual renderer)
    if (vmService != null && isolateId != null) {
      try {
        final result = await vmService.callServiceExtension(
          'ext.flutter.impellerEnabled',
          isolateId: isolateId,
        );
        final enabled = result.json?['enabled'];
        if (enabled is bool) return enabled;
        if (enabled is String) return enabled == 'true';
      } catch (_) {
        // Extension not registered — fall through to heuristic
      }
    }

    // 2. Heuristic: parse Dart version → infer Flutter release stream
    final parts = dartVersion.split('.');
    final major = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final minor = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;

    return switch (platform) {
      TargetPlatform.ios =>
        // Dart ≥ 3.0 ≈ Flutter ≥ 3.10 (Impeller default)
        major >= 3,
      TargetPlatform.android =>
        // Dart ≥ 3.6 ≈ Flutter ≥ 3.27 (Impeller default)
        major > 3 || (major == 3 && minor >= 6),
      _ => false,
    };
  }

  // ── Display ───────────────────────────────────────────────────────────────

  /// Target refresh rate of the primary display, defaults to 60.
  static double displayRefreshRate() {
    try {
      final views = ui.PlatformDispatcher.instance.views.toList();
      if (views.isNotEmpty) {
        final rate = views.first.display.refreshRate;
        if (rate > 0) return rate;
      }
    } catch (_) {}
    return 60.0;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static int? _safeInt(int Function() fn) {
    try {
      return fn();
    } catch (_) {
      return null;
    }
  }
}
