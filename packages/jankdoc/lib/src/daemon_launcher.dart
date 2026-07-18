import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// The daemon version this launcher knows how to run.
/// Must match the version string in `assets/binary_checksums.json`.
const _kDaemonVersion = '1.0.0';

/// GitHub repository that hosts daemon release binaries.
const _kBinaryReleaseRepo = 'https://github.com/ogpratik/jankdoc';

/// Manages the Analysis Daemon lifecycle from within the Flutter app.
///
/// Called by [JankDoc.attach()] in debug/profile mode. In release mode this
/// entire class is dead code and is tree-shaken away.
///
/// ## Daemon resolution (ADR-0014 — Hybrid strategy)
///
/// `_resolveDaemonCommand()` tries three strategies in order:
///
/// 1. **Cache hit** — `~/.jankdoc/bin/jankdoc-daemon-<version>-<platform>`
///    exists and passes SHA-256 verification. Fastest path (~50 ms startup).
///
/// 2. **Download** — fetch the pre-compiled native binary from GitHub Releases,
///    verify checksum, chmod +x, store in cache. Emits a user-visible
///    "Downloading JankDoc daemon…" log during the ~5–10 s download window.
///
/// 3. **`dart run` fallback** — always works, even when offline or on a
///    platform that has no pre-compiled binary. Slower cold start (~5 s).
///    Emits a "running from source" log line so developers know why it's slow.
final class DaemonLauncher {
  static const _defaultPort = 9101;
  static const _lockFile = '.jankdoc_daemon.lock';
  static const _readyTimeout = Duration(seconds: 15);

  int? _port;

  int get port => _port ?? _defaultPort;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Ensure the daemon is running. Returns the port it's listening on.
  ///
  /// - If already running (lock file + health check passes): reuses it.
  /// - If not running: resolves the binary (cache → download → dart run),
  ///   spawns it, waits for readiness, registers the DevTools service ext.
  Future<int> ensureRunning() async {
    // 1. Check lock file first.
    final existingPort = await _readLockFile();
    if (existingPort != null && await _isHealthy(existingPort)) {
      _port = existingPort;
      await _registerServiceExtension(existingPort);
      return existingPort;
    }

    // 2. Check default port directly — handles manually-started daemons.
    if (await _isHealthy(_defaultPort)) {
      _port = _defaultPort;
      await _writeLockFile(_defaultPort, -1);
      await _registerServiceExtension(_defaultPort);
      return _defaultPort;
    }

    // 3. Resolve the best way to start the daemon.
    final cmd = await _resolveDaemonCommand();

    // 4. Spawn the daemon process (detached so it survives hot-restart).
    final process = await Process.start(
      cmd.executable,
      cmd.args,
      mode: ProcessStartMode.detachedWithStdio,
    );
    await _writeLockFile(_defaultPort, process.pid);

    // 5. Poll until healthy or timeout.
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy(_defaultPort)) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    if (!await _isHealthy(_defaultPort)) {
      throw StateError(
        '[JankDoc] Daemon failed to start within ${_readyTimeout.inSeconds}s.\n'
        'Run the daemon manually to see startup errors:\n'
        '  dart run jankdoc:daemon --port $_defaultPort',
      );
    }

    _port = _defaultPort;
    await _registerServiceExtension(_defaultPort);
    return _defaultPort;
  }

  // ── Binary resolution ───────────────────────────────────────────────────────

  /// Resolve the best command to start the daemon.
  ///
  /// See class-level documentation for the three-step resolution order.
  Future<({String executable, List<String> args})>
      _resolveDaemonCommand() async {
    final platform = await _platformString();

    // Load the bundled checksum manifest once.
    final checksums = await _loadChecksums();

    // ── Step 1: Cache hit ─────────────────────────────────────────────────
    final cached = await _cachedBinaryPath(platform);
    if (cached != null) {
      final expectedChecksum = checksums[platform];
      if (expectedChecksum == null || expectedChecksum.isEmpty) {
        // No checksum in manifest yet (beta) — trust the cached binary.
        _log('cache hit (no checksum enforced): $cached');
        return (executable: cached, args: _daemonArgs());
      }
      final actual = await _sha256OfFile(cached);
      if (actual == expectedChecksum) {
        _log('cache hit: $cached');
        return (executable: cached, args: _daemonArgs());
      }
      _log('cached binary checksum mismatch — re-downloading.');
      await File(cached).delete();
    }

    // ── Step 2: Download ──────────────────────────────────────────────────
    if (platform != 'unknown') {
      try {
        final downloaded = await _downloadBinary(platform, checksums[platform]);
        if (downloaded != null) {
          _log('downloaded binary: $downloaded');
          return (executable: downloaded, args: _daemonArgs());
        }
      } on Object catch (e) {
        _log('binary download failed ($e) — falling back to dart run.');
      }
    }

    // ── Step 3: dart run fallback ─────────────────────────────────────────
    _log(
      'RUNNING FROM SOURCE via dart run jankdoc:daemon.\n'
      '  This is slower than the pre-compiled binary (~5 s cold start).\n'
      '  To resolve: ensure network access on first run so the daemon\n'
      '  binary can be downloaded, or place a pre-compiled binary at:\n'
      '    ${await _binaryDir()}/${_binaryName(_kDaemonVersion, platform)}',
    );
    final dart = await _findDart();
    return (
      executable: dart,
      args: ['run', 'jankdoc:daemon', ...(_daemonArgs())],
    );
  }

  // ── Cache helpers ───────────────────────────────────────────────────────────

  Future<String> _binaryDir() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.jankdoc/bin';
  }

  static String _binaryName(String version, String platform) {
    final ext = platform.startsWith('windows') ? '.exe' : '';
    return 'jankdoc-daemon-$version-$platform$ext';
  }

  /// Returns the path to the cached binary if it exists, else null.
  Future<String?> _cachedBinaryPath(String platform) async {
    final dir = await _binaryDir();
    final path = '$dir/${_binaryName(_kDaemonVersion, platform)}';
    if (File(path).existsSync()) return path;
    return null;
  }

  // ── Download ────────────────────────────────────────────────────────────────

  Future<String?> _downloadBinary(
    String platform,
    String? expectedChecksum,
  ) async {
    final binaryName = _binaryName(_kDaemonVersion, platform);
    // Daemon binaries live under `daemon-v<version>` tags — separate from any
    // pub-package tags. Kept in sync with `.github/workflows/release.yaml`.
    final url =
        '$_kBinaryReleaseRepo/releases/download/daemon-v$_kDaemonVersion/$binaryName';

    _log('Downloading JankDoc daemon binary (~5 MB)…\n  $url');

    final client = http.Client();
    try {
      final response =
          await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        _log('download failed: HTTP ${response.statusCode}');
        return null;
      }

      final bytes = response.bodyBytes;

      // Verify checksum if we have one.
      if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
        final actual = sha256.convert(bytes).toString();
        if (actual != expectedChecksum) {
          _log(
            'checksum mismatch for downloaded binary!\n'
            '  expected: $expectedChecksum\n'
            '  actual:   $actual\n'
            'Refusing to execute. Will fall back to dart run.',
          );
          return null;
        }
      }

      // Write to cache.
      final dir = await _binaryDir();
      await Directory(dir).create(recursive: true);
      final destPath = '$dir/$binaryName';
      final destFile = File(destPath);
      await destFile.writeAsBytes(bytes);

      // Make executable on Unix.
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', destPath]);
      }

      _log('daemon binary cached at $destPath');
      return destPath;
    } finally {
      client.close();
    }
  }

  // ── Checksum manifest ───────────────────────────────────────────────────────

  /// Load `assets/binary_checksums.json` from the Flutter asset bundle.
  ///
  /// Returns an empty map if the asset can't be loaded (graceful degradation).
  Future<Map<String, String>> _loadChecksums() async {
    try {
      final raw = await rootBundle
          .loadString('packages/jankdoc/assets/binary_checksums.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final binaries = json['binaries'] as Map<String, dynamic>? ?? {};
      return binaries.map((k, v) => MapEntry(k, v as String));
    } on Object catch (_) {
      return {};
    }
  }

  static Future<String> _sha256OfFile(String path) async {
    final bytes = File(path).readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  // ── Platform detection ──────────────────────────────────────────────────────

  static Future<String> _platformString() async {
    final os = Platform.operatingSystem;
    if (os == 'macos') {
      try {
        final result = await Process.run('uname', ['-m']);
        final arch = (result.stdout as String).trim();
        return arch == 'arm64' ? 'macos-arm64' : 'macos-x64';
      } on Object catch (_) {
        // Default to arm64 for modern (post-2020) Macs.
        return 'macos-arm64';
      }
    }
    if (os == 'linux') return 'linux-x64';
    if (os == 'windows') return 'windows-x64';
    return 'unknown';
  }

  // ── Process helpers ─────────────────────────────────────────────────────────

  List<String> _daemonArgs() => ['--port', '$_defaultPort'];

  static Future<String> _findDart() async {
    // Try dart from PATH via `which` (Unix) / `where` (Windows)
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final r = await Process.run(cmd, ['dart']);
      if (r.exitCode == 0) {
        final path = (r.stdout as String).split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } on Object catch (_) {/* ignore — try candidates below */}

    // Common install locations.
    final candidates = Platform.isWindows
        ? [r'C:\tools\dart-sdk\bin\dart.exe']
        : [
            '/opt/homebrew/bin/dart',
            '/usr/local/bin/dart',
            '/usr/bin/dart',
          ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return 'dart'; // Last resort — let the OS resolve it.
  }

  // ── Health check ────────────────────────────────────────────────────────────

  Future<bool> _isHealthy(int port) async {
    try {
      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
          .timeout(const Duration(milliseconds: 500));
      final response = await request.close();
      client.close();
      return response.statusCode == 200;
    } on Object catch (_) {
      return false;
    }
  }

  // ── Lock file ───────────────────────────────────────────────────────────────

  Future<int?> _readLockFile() async {
    try {
      final file = File(_lockFile);
      if (!file.existsSync()) return null;
      final content = file.readAsStringSync();
      final map = _parseLockJson(content);
      return map['port'] as int?;
    } on Object catch (_) {
      return null;
    }
  }

  Future<void> _writeLockFile(int port, int pid) async {
    await File(_lockFile).writeAsString(
      '{"port":$port,"pid":$pid,"started":"${DateTime.now().toIso8601String()}"}',
    );
  }

  Map<String, dynamic> _parseLockJson(String s) {
    final map = <String, dynamic>{};
    final cleaned = s.replaceAll(RegExp(r'[{}" ]'), '');
    for (final pair in cleaned.split(',')) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        final v = parts[1].trim();
        map[parts[0].trim()] = int.tryParse(v) ?? v;
      }
    }
    return map;
  }

  // ── DevTools service extension ──────────────────────────────────────────────

  Future<void> _registerServiceExtension(int port) async {
    developer.registerExtension(
      'ext.jankdoc.daemonUrl',
      (_, __) async => developer.ServiceExtensionResponse.result(
        '{"url": "http://127.0.0.1:$port"}',
      ),
    );
  }

  // ── Logging ─────────────────────────────────────────────────────────────────

  static void _log(String message) {
    // ignore: avoid_print
    print('[JankDoc] $message');
  }
}
