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
/// 1. **Cache hit** — `~/.jankdoc/bin/jankdoc-daemon-<version>-<platform>/`
///    holds a bundle extracted from an archive whose SHA-256 matches the
///    manifest. Fastest path (~50 ms startup).
///
/// 2. **Download** — fetch `jankdoc-daemon-<version>-<platform>.tar.gz` from
///    GitHub Releases, verify its SHA-256 against
///    `assets/binary_checksums.json`, extract it into the cache. Platforms
///    without a manifest checksum skip this step: an unverified download is
///    never executed.
///
///    The archive holds the whole `dart build cli` bundle: on Linux the
///    executable is the AOT runtime and the program lives beside it, so a
///    lone executable cannot be shipped.
///
/// 3. **`dart run` fallback** — always works, even when offline or on a
///    platform that has no pre-compiled binary. Slower cold start (~5 s).
///    Emits a "running from source" log line so developers know why it's slow.
final class DaemonLauncher {
  static const _defaultPort = 9101;
  static const _lockFileName = 'daemon.lock';
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
    final process = await _spawnDetached(cmd.executable, cmd.args);
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

    final expectedChecksum = checksums[platform] ?? '';

    // ── Step 1: Cache hit ─────────────────────────────────────────────────
    if (expectedChecksum.isNotEmpty) {
      final cached = await _cachedExecutable(platform, expectedChecksum);
      if (cached != null) {
        _log('cache hit: $cached');
        return (executable: cached, args: _daemonArgs());
      }
    }

    // ── Step 2: Download ──────────────────────────────────────────────────
    if (platform != 'unknown' && expectedChecksum.isNotEmpty) {
      try {
        final downloaded = await _downloadBundle(platform, expectedChecksum);
        if (downloaded != null) {
          _log('downloaded daemon: $downloaded');
          return (executable: downloaded, args: _daemonArgs());
        }
      } on Object catch (e) {
        _log('daemon download failed ($e) — falling back to dart run.');
      }
    }

    // ── Step 3: dart run fallback ─────────────────────────────────────────
    _log(
      'RUNNING FROM SOURCE via dart run jankdoc:daemon.\n'
      '  This is slower than the pre-compiled binary (~5 s cold start).\n'
      '  To resolve: ensure network access on first run so the daemon\n'
      '  can be downloaded from the GitHub release.',
    );
    final dart = await _findDart();
    return (
      executable: dart,
      args: ['run', 'jankdoc:daemon', ...(_daemonArgs())],
    );
  }

  /// Starts the daemon fully detached from this app, with its output appended
  /// to `~/.jankdoc/daemon.log`.
  ///
  /// It must not share stdio pipes with the app: the daemon outlives the app
  /// (later runs reuse it), and once the app exits its next log line would hit
  /// a broken pipe and kill it — silently, mid-session for whichever run
  /// reused it.
  Future<Process> _spawnDetached(String executable, List<String> args) async {
    if (Platform.isWindows) {
      return Process.start(executable, args, mode: ProcessStartMode.detached);
    }
    final dir = await _jankdocDir();
    await Directory(dir).create(recursive: true);
    return Process.start(
      '/bin/sh',
      [
        '-c',
        r'exec "$0" "$@" >>"$JANKDOC_DAEMON_LOG" 2>&1',
        executable,
        ...args
      ],
      environment: {'JANKDOC_DAEMON_LOG': '$dir/daemon.log'},
      mode: ProcessStartMode.detached,
    );
  }

  // ── Cache helpers ───────────────────────────────────────────────────────────

  Future<String> _jankdocDir() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.jankdoc';
  }

  Future<String> _binaryDir() async => '${await _jankdocDir()}/bin';

  static String _bundleName(String platform) =>
      'jankdoc-daemon-$_kDaemonVersion-$platform';

  static String _executableIn(String bundleDir, String platform) =>
      '$bundleDir/bundle/bin/daemon${platform.startsWith('windows') ? '.exe' : ''}';

  /// Marker written after a verified extraction; holds the archive checksum.
  static const _verifiedMarker = '.sha256';

  /// Returns the cached daemon executable if it was extracted from an archive
  /// with [expectedChecksum], else null.
  Future<String?> _cachedExecutable(
    String platform,
    String expectedChecksum,
  ) async {
    final dir = '${await _binaryDir()}/${_bundleName(platform)}';
    final marker = File('$dir/$_verifiedMarker');
    final executable = _executableIn(dir, platform);
    if (!marker.existsSync() || !File(executable).existsSync()) return null;
    if (marker.readAsStringSync().trim() != expectedChecksum) return null;
    return executable;
  }

  // ── Download ────────────────────────────────────────────────────────────────

  Future<String?> _downloadBundle(
    String platform,
    String expectedChecksum,
  ) async {
    final archiveName = '${_bundleName(platform)}.tar.gz';
    // Daemon releases live under `daemon-v<version>` tags — separate from any
    // pub-package tags. Kept in sync with `.github/workflows/release.yaml`.
    final url =
        '$_kBinaryReleaseRepo/releases/download/daemon-v$_kDaemonVersion/$archiveName';

    _log('Downloading JankDoc daemon (~3 MB)…\n  $url');

    final client = http.Client();
    try {
      final response =
          await client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        _log('download failed: HTTP ${response.statusCode}');
        return null;
      }

      final bytes = response.bodyBytes;
      final actual = sha256.convert(bytes).toString();
      if (actual != expectedChecksum) {
        _log(
          'checksum mismatch for downloaded daemon!\n'
          '  expected: $expectedChecksum\n'
          '  actual:   $actual\n'
          'Refusing to execute. Will fall back to dart run.',
        );
        return null;
      }

      // Extract into a fresh directory; the marker is written last, so a
      // half-finished extraction is never mistaken for a cache hit.
      final dir = Directory('${await _binaryDir()}/${_bundleName(platform)}');
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final archive = File('${dir.path}/$archiveName');
      await archive.writeAsBytes(bytes);
      // `tar` ships with macOS, Linux and Windows 10+.
      final tar = await Process.run(
        'tar',
        ['-xzf', archiveName],
        workingDirectory: dir.path,
      );
      await archive.delete();
      final executable = _executableIn(dir.path, platform);
      if (tar.exitCode != 0 || !File(executable).existsSync()) {
        _log('could not extract $archiveName: ${tar.stderr}');
        return null;
      }
      await File('${dir.path}/$_verifiedMarker').writeAsString(actual);

      _log('daemon cached at ${dir.path}');
      return executable;
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
      final file = File('${await _jankdocDir()}/$_lockFileName');
      if (!file.existsSync()) return null;
      final content = file.readAsStringSync();
      final map = _parseLockJson(content);
      return map['port'] as int?;
    } on Object catch (_) {
      return null;
    }
  }

  Future<void> _writeLockFile(int port, int pid) async {
    final dir = await _jankdocDir();
    await Directory(dir).create(recursive: true);
    await File('$dir/$_lockFileName').writeAsString(
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
