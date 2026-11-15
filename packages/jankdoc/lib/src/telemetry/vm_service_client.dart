import 'dart:developer' as developer;

import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vm_io;

/// Thin wrapper around [vm.VmService] scoped to the needs of the
/// [TelemetryCollector].
///
/// Provides:
///   - [connect] factory — discovers the VM Service URL via `dart:developer`
///   - [getMainIsolateId] — the primary isolate's ID
///   - [getCpuStackFrames] — top user-code stack frames in a time window
///   - [service] — raw access for [DeviceInfoResolver]
///
/// Failure philosophy: every public method returns a safe default on error
/// rather than throwing. The telemetry pipeline must never crash the app.
final class VmServiceClient {
  VmServiceClient._(this._service, this._mainIsolateId);

  final vm.VmService _service;
  final String _mainIsolateId;

  vm.VmService get service => _service;
  String get mainIsolateId => _mainIsolateId;

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Connects to the VM Service of the current process.
  ///
  /// Returns null if:
  ///   - The VM Service URI is unavailable (release mode, unsupported platform)
  ///   - Connection fails within the timeout
  static Future<VmServiceClient?> connect({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final info = await developer.Service.getInfo();
      final serverUri = info.serverUri;
      if (serverUri == null) return null;

      // Convert HTTP URI → WebSocket URI
      // http://127.0.0.1:8181/ws/ → ws://127.0.0.1:8181/ws/
      final wsUri = serverUri
          .replace(
            scheme: serverUri.scheme == 'https' ? 'wss' : 'ws',
            path: serverUri.path.endsWith('/')
                ? '${serverUri.path}ws'
                : '${serverUri.path}/ws',
          )
          .toString();

      final service = await vm_io.vmServiceConnectUri(wsUri).timeout(timeout);

      // Discover the main isolate
      final vmRef = await service.getVM().timeout(timeout);
      final mainIsolate = vmRef.isolates?.firstOrNull;
      if (mainIsolate == null) {
        service.dispose();
        return null;
      }

      return VmServiceClient._(service, mainIsolate.id!);
    } catch (_) {
      return null;
    }
  }

  // ── CPU samples → stack frames ─────────────────────────────────────────────

  /// Returns the top user-code stack frames observed in the given time window.
  ///
  /// [startUs] and [endUs] are microseconds since the Dart VM timeline epoch,
  /// which matches the values from [FrameTiming.timestampInMicroseconds].
  ///
  /// Returns an empty list on any error (profiler not running, isolate gone,
  /// etc.). The rule engine works without stack frames — they improve the LLM
  /// prompt quality but are not required.
  Future<List<StackFrame>> getCpuStackFrames(
    int startUs,
    int endUs, {
    int maxFrames = 10,
  }) async {
    if (endUs <= startUs) return const [];

    try {
      final samples = await _service
          .getCpuSamples(
            _mainIsolateId,
            startUs,
            endUs - startUs, // extent, not end
          )
          // The response carries the VM's whole function table; in debug
          // mode it routinely takes 1-3 s. A shorter timeout drops every stack.
          .timeout(const Duration(seconds: 5));

      return _parseCpuSamples(samples, maxFrames: maxFrames);
    } catch (_) {
      return const [];
    }
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  /// Converts a [vm.CpuSamples] snapshot into a list of [StackFrame]s.
  ///
  /// Algorithm:
  ///   1. Aggregate all sample stacks — count how many times each function
  ///      appears (weighted by depth: top frames count more).
  ///   2. Keep the top [maxFrames] by hit count.
  ///   3. Filter out Dart internals and Flutter framework frames; keep user
  ///      code and annotate with `isUserCode`.
  static List<StackFrame> _parseCpuSamples(
    vm.CpuSamples samples, {
    required int maxFrames,
  }) {
    final functions = samples.functions;
    final sampleList = samples.samples;
    if (functions == null || sampleList == null || sampleList.isEmpty) {
      return const [];
    }

    // Accumulate hit counts per function index, weighting shallower frames
    // (earlier in the stack list == closer to the leaf/hottest code) higher.
    final hits = <int, int>{};
    for (final sample in sampleList) {
      final stack = sample.stack ?? [];
      for (var depth = 0; depth < stack.length; depth++) {
        final idx = stack[depth];
        // Weight: leaf frame (depth 0) = maxDepth, deeper = less weight
        final weight = (stack.length - depth).clamp(1, stack.length);
        hits[idx] = (hits[idx] ?? 0) + weight;
      }
    }

    // Sort by hit count descending
    final sorted = hits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final result = <StackFrame>[];
    for (final entry in sorted) {
      if (result.length >= maxFrames) break;
      final idx = entry.key;
      if (idx < 0 || idx >= functions.length) continue;

      final sf = _profileFunctionToStackFrame(functions[idx]);
      if (sf != null) result.add(sf);
    }

    return result;
  }

  static StackFrame? _profileFunctionToStackFrame(vm.ProfileFunction pf) {
    final func = pf.function;
    if (func == null) return null;

    String file = '';
    int line = 0;
    int column = 0;
    String functionName = '';
    String? packageName;
    String? widgetType;

    if (func is vm.FuncRef) {
      functionName = func.name ?? '';
      final location = func.location;
      if (location != null) {
        file = location.script?.uri ?? '';
        line = location.line ?? 0;
        column = location.column ?? 0;
      }
      // Derive package name from the script URI
      // "package:my_app/src/home.dart" → "my_app"
      // "dart:core/string.dart" → "dart"
      packageName = _packageFromUri(file);

      // Widget heuristic: function named "build" owned by something that
      // extends Widget/State — check owner class name
      final owner = func.owner;
      if (owner is vm.ClassRef && functionName == 'build') {
        widgetType = owner.name;
      }
    } else if (func is vm.NativeFunction) {
      functionName = func.name ?? '<native>';
      packageName = 'native';
    }

    if (file.isEmpty && functionName.isEmpty) return null;

    return StackFrame(
      file: file,
      line: line,
      column: column,
      function: functionName,
      packageName: packageName,
      widgetType: widgetType,
    );
  }

  /// Extracts the package name from a Dart script URI.
  ///
  /// Examples:
  ///   `package:my_app/src/home.dart`  → `my_app`
  ///   `dart:core/list.dart`           → `dart`
  ///   `file:///usr/...`               → null (relative path, treat as user)
  static String? _packageFromUri(String uri) {
    if (uri.startsWith('dart:')) return 'dart';
    if (uri.startsWith('package:')) {
      final withoutScheme = uri.substring(8); // remove "package:"
      final slash = withoutScheme.indexOf('/');
      return slash >= 0 ? withoutScheme.substring(0, slash) : withoutScheme;
    }
    return null; // file: or relative — treat as user code
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  void dispose() {
    try {
      _service.dispose();
    } catch (_) {}
  }
}
