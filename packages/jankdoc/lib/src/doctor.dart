import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Outcome of one [DoctorCheck].
///
/// - [ok]      — the checked resource is healthy; JankDoc will use it as-is.
/// - [warn]    — the resource is degraded but JankDoc can still function
///               (e.g. seeder fallback KB, dart-run daemon).
/// - [fail]    — the resource is unavailable and blocks a JankDoc capability
///               (e.g. Ollama not reachable → LLM tier disabled).
enum DoctorStatus { ok, warn, fail }

/// A single [Doctor] check outcome, ready to render.
///
/// [fixHint] should be present whenever [status] is not [DoctorStatus.ok]. It
/// carries a copy-pasteable command or URL the user can act on immediately.
final class DoctorCheckResult {
  const DoctorCheckResult({
    required this.name,
    required this.status,
    required this.detail,
    this.fixHint,
  });

  final String name;
  final DoctorStatus status;
  final String detail;
  final String? fixHint;
}

/// A single diagnostic probe. Implementations must never throw; wrap any I/O
/// in a try/catch and return a `fail` result with an actionable fix hint.
abstract interface class DoctorCheck {
  String get name;
  Future<DoctorCheckResult> run();
}

/// Runs a suite of diagnostic checks against the local JankDoc install.
///
/// The default constructor wires up the standard beta-launch checks (Ollama
/// reachable, models pulled, KB cache present, port available). Pass a
/// custom `checks` list to override — mainly used by tests.
final class Doctor {
  Doctor({List<DoctorCheck>? checks}) : _checks = checks ?? _defaultChecks();

  final List<DoctorCheck> _checks;

  static List<DoctorCheck> _defaultChecks() => [
        OllamaReachableCheck(),
        OllamaModelCheck(modelId: 'qwen2.5-coder:7b'),
        OllamaModelCheck(modelId: 'nomic-embed-text'),
        DaemonPortCheck(port: 9101),
        KbBundleCacheCheck(),
        MacosEntitlementsCheck(),
      ];

  /// Runs every check in parallel and returns the ordered results.
  ///
  /// Order of the results matches the order of the check list passed to the
  /// constructor so the output stays deterministic across runs.
  Future<List<DoctorCheckResult>> run() async {
    final futures = _checks.map((c) => c.run()).toList();
    return Future.wait(futures);
  }

  /// Render results as a coloured, table-like report to [sink].
  ///
  /// Follows the same colour rules as the startup banner — respects
  /// `NO_COLOR` and `JANKDOC_COLOR=0`, and disables colour when [sink] is
  /// not the process's real `stdout`.
  static void report(List<DoctorCheckResult> results, {StringSink? sink}) {
    final out = sink ?? stdout;
    final colour = _useColor(out);
    out.writeln('JankDoc doctor — ${results.length} checks');
    out.writeln();
    for (final r in results) {
      final glyph = switch (r.status) {
        DoctorStatus.ok => '✓',
        DoctorStatus.warn => '⚠',
        DoctorStatus.fail => '✗',
      };
      final ansi = colour
          ? switch (r.status) {
              DoctorStatus.ok => '\x1B[32m',
              DoctorStatus.warn => '\x1B[33m',
              DoctorStatus.fail => '\x1B[31m',
            }
          : '';
      final reset = colour ? '\x1B[0m' : '';
      out.writeln('$ansi$glyph ${r.name}$reset — ${r.detail}');
      if (r.fixHint != null) {
        for (final line in r.fixHint!.split('\n')) {
          out.writeln('    → $line');
        }
      }
    }
    out.writeln();
    final failed = results.where((r) => r.status == DoctorStatus.fail).length;
    final warned = results.where((r) => r.status == DoctorStatus.warn).length;
    if (failed == 0 && warned == 0) {
      out.writeln('All checks passed.');
    } else {
      out.writeln('$failed failing, $warned warning.');
    }
  }

  /// Exit code convention: 0 when nothing failed, 1 otherwise.
  static int exitCode(List<DoctorCheckResult> results) =>
      results.any((r) => r.status == DoctorStatus.fail) ? 1 : 0;

  static bool _useColor(StringSink out) {
    if (Platform.environment.containsKey('NO_COLOR')) return false;
    if (Platform.environment['JANKDOC_COLOR'] == '0') return false;
    return identical(out, stdout) && stdout.hasTerminal;
  }
}

// ── Concrete checks ─────────────────────────────────────────────────────────

/// Verifies the Ollama HTTP API is reachable at [baseUrl].
final class OllamaReachableCheck implements DoctorCheck {
  OllamaReachableCheck({
    this.baseUrl = 'http://127.0.0.1:11434',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  String get name => 'Ollama reachable';

  @override
  Future<DoctorCheckResult> run() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        return DoctorCheckResult(
          name: name,
          status: DoctorStatus.ok,
          detail: 'reachable at $baseUrl',
        );
      }
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.fail,
        detail: 'HTTP ${response.statusCode} from $baseUrl',
        fixHint: 'Start Ollama: `ollama serve`',
      );
    } on Object catch (e) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.fail,
        detail: 'not reachable at $baseUrl ($e)',
        fixHint: 'Install: https://ollama.com\n'
            'Then start it: `ollama serve` (or launch the Ollama.app on macOS)',
      );
    }
  }
}

/// Verifies that a specific Ollama model has been pulled.
///
/// Requires the reachable check to succeed; if Ollama is down this check
/// will surface a `fail` too, but the reachable-check will have already
/// pointed the user at the fix.
final class OllamaModelCheck implements DoctorCheck {
  OllamaModelCheck({
    required this.modelId,
    this.baseUrl = 'http://127.0.0.1:11434',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String modelId;
  final String baseUrl;
  final http.Client _client;

  @override
  String get name => 'Ollama model: $modelId';

  @override
  Future<DoctorCheckResult> run() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        return DoctorCheckResult(
          name: name,
          status: DoctorStatus.fail,
          detail: 'Ollama not responding (HTTP ${response.statusCode})',
          fixHint: 'Run `dart run jankdoc:doctor` after fixing the '
              '"Ollama reachable" check above.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (body['models'] as List?) ?? [];
      // Ollama returns e.g. `qwen2.5-coder:7b` — allow the user's tag to match
      // either the fully qualified name or the family prefix.
      final present = models.any((m) {
        final tag = (m as Map<String, dynamic>)['name'] as String? ?? '';
        return tag == modelId || tag.startsWith('$modelId:');
      });
      if (present) {
        return DoctorCheckResult(
          name: name,
          status: DoctorStatus.ok,
          detail: 'pulled',
        );
      }
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.fail,
        detail: 'not pulled',
        fixHint: '`ollama pull $modelId`',
      );
    } on Object catch (e) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.fail,
        detail: 'could not query Ollama ($e)',
        fixHint: 'Fix the "Ollama reachable" check first, then re-run doctor.',
      );
    }
  }
}

/// Verifies the daemon's default listen port is free (or already held by a
/// healthy JankDoc daemon, which is a win — the launcher will reuse it).
final class DaemonPortCheck implements DoctorCheck {
  DaemonPortCheck({required this.port, http.Client? client})
      : _client = client ?? http.Client();

  final int port;
  final http.Client _client;

  @override
  String get name => 'Port $port';

  @override
  Future<DoctorCheckResult> run() async {
    // Try to hit /health — if a healthy JankDoc daemon is there, that's a
    // pass (the launcher will reuse it).
    try {
      final response = await _client
          .get(Uri.parse('http://127.0.0.1:$port/health'))
          .timeout(const Duration(milliseconds: 500));
      if (response.statusCode == 200 &&
          response.body.contains('"status":"ok"')) {
        return DoctorCheckResult(
          name: name,
          status: DoctorStatus.ok,
          detail: 'JankDoc daemon already running',
        );
      }
    } on Object {
      // Nothing listening — fall through to bind test.
    }

    // Attempt to bind — succeeds if the port is truly free.
    try {
      final server = await ServerSocket.bind('127.0.0.1', port);
      await server.close();
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.ok,
        detail: 'available',
      );
    } on SocketException catch (e) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.fail,
        detail: 'in use by another process ($e)',
        fixHint: 'Set `JANKDOC_PORT=<free-port>` before running Flutter, '
            'or stop the offending process.',
      );
    }
  }
}

/// Verifies that a KB bundle has been cached under `~/.jankdoc/kb-cache/`.
///
/// Warn (not fail) when no bundle is cached — the daemon can still fall back
/// to the runtime seeder, which needs Ollama's embedding endpoint.
final class KbBundleCacheCheck implements DoctorCheck {
  KbBundleCacheCheck({String? homeOverride}) : _home = homeOverride;

  final String? _home;

  @override
  String get name => 'KB bundle cache';

  @override
  Future<DoctorCheckResult> run() async {
    final home = _home ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.warn,
        detail: 'no HOME env var — bundle cache location unknown',
        fixHint: 'Set HOME before running the daemon.',
      );
    }
    final cacheDir = Directory('$home/.jankdoc/kb-cache');
    if (!cacheDir.existsSync()) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.warn,
        detail: 'no cache directory — will fall back to runtime seeder',
        fixHint: 'Bundle downloads on first daemon start. To force: '
            '`curl <REGISTRY_URL>/releases/latest/download/*.jankdoc-kb '
            '-o ${cacheDir.path}/jankdoc-kb-latest.jankdoc-kb`',
      );
    }
    final bundles = cacheDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jankdoc-kb'))
        .toList();
    if (bundles.isEmpty) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.warn,
        detail: 'cache dir empty — seeder fallback will be used',
        fixHint: 'The daemon will download a bundle on its next start.',
      );
    }
    return DoctorCheckResult(
      name: name,
      status: DoctorStatus.ok,
      detail: '${bundles.length} bundle(s) cached in ${cacheDir.path}',
    );
  }
}

/// Verifies that the current directory's Flutter app has the macOS
/// network-client entitlement JankDoc needs.
///
/// Flutter's default macOS scaffolding is sandboxed without the
/// `com.apple.security.network.client` entitlement, which means a built
/// `.app` can not even reach `127.0.0.1:9101`. `flutter run` in dev mode
/// works fine because dev-mode uses a broader entitlement set — but the
/// moment you build for profile/release, `JankDoc.attach()` fails silently
/// with `Operation not permitted`.
///
/// This check is the fastest way to catch that class of error. It:
///
/// - Skips (returns ok "not applicable") on non-macOS hosts.
/// - Skips ("no macos/ directory found") if the current directory is not a
///   Flutter app that supports macOS.
/// - Fails with a copy-pasteable XML snippet when the entitlement is
///   missing.
final class MacosEntitlementsCheck implements DoctorCheck {
  MacosEntitlementsCheck({String? projectDirOverride, bool? isMacosOverride})
      : _projectDir = projectDirOverride,
        _isMacos = isMacosOverride ?? Platform.isMacOS;

  final String? _projectDir;
  final bool _isMacos;

  @override
  String get name => 'macOS network-client entitlement';

  @override
  Future<DoctorCheckResult> run() async {
    if (!_isMacos) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.ok,
        detail: 'not applicable on ${Platform.operatingSystem}',
      );
    }

    final projectDir = _projectDir ?? Directory.current.path;
    final entitlements = File(
      '$projectDir/macos/Runner/DebugProfile.entitlements',
    );
    if (!entitlements.existsSync()) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.ok,
        detail: 'no macos/ directory found — not a macOS Flutter app '
            'or running from workspace root',
      );
    }

    final contents = entitlements.readAsStringSync();
    const key = 'com.apple.security.network.client';
    if (contents.contains(key)) {
      return DoctorCheckResult(
        name: name,
        status: DoctorStatus.ok,
        detail: 'entitlements grant $key',
      );
    }
    return DoctorCheckResult(
      name: name,
      status: DoctorStatus.fail,
      detail:
          'macos/Runner/DebugProfile.entitlements is missing $key. '
          'JankDoc daemon calls to 127.0.0.1 will fail in built .app bundles.',
      fixHint: 'Add these two lines inside the top-level <dict> of '
          'macos/Runner/DebugProfile.entitlements (and Release.entitlements '
          'if you profile release builds):\n'
          '  <key>com.apple.security.network.client</key>\n'
          '  <true/>',
    );
  }
}
