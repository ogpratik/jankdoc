import 'dart:developer' as developer;
import 'dart:io';

/// Manages the Analysis Daemon lifecycle from within the Flutter app.
///
/// Called by [JankDoc.attach()] in debug/profile mode. In release mode this
/// entire class is dead code and is tree-shaken away.
final class DaemonLauncher {
  static const _defaultPort = 9101;
  static const _lockFile = '.jankdoc_daemon.lock';
  static const _readyTimeout = Duration(seconds: 5);

  int? _port;

  int get port => _port ?? _defaultPort;

  /// Ensure the daemon is running. Returns the port it's listening on.
  ///
  /// - If already running (lock file + health check passes): reuses it.
  /// - If not running: spawns it, waits for readiness, registers service ext.
  Future<int> ensureRunning() async {
    // 1. Check if already running
    final existingPort = await _readLockFile();
    if (existingPort != null && await _isHealthy(existingPort)) {
      _port = existingPort;
      await _registerServiceExtension(existingPort);
      return existingPort;
    }

    // 2. Find the daemon binary (or fall back to `dart run`)
    final cmd = await _resolveDaemonCommand();

    // 3. Spawn the daemon
    final process = await Process.start(
      cmd.executable,
      cmd.args,
      mode: ProcessStartMode.detachedWithStdio,
    );

    // Write PID lock file
    await _writeLockFile(_defaultPort, process.pid);

    // 4. Wait until healthy
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy(_defaultPort)) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (!await _isHealthy(_defaultPort)) {
      throw StateError(
        'JankDoc daemon failed to start within ${_readyTimeout.inSeconds}s. '
        'Run `dart run jankdoc:daemon --port $_defaultPort` manually and '
        'check for errors.',
      );
    }

    _port = _defaultPort;
    await _registerServiceExtension(_defaultPort);
    return _defaultPort;
  }

  Future<void> _registerServiceExtension(int port) async {
    developer.registerExtension('ext.jankdoc.daemonUrl', (_, __) async {
      return developer.ServiceExtensionResponse.result(
        '{"url": "http://127.0.0.1:$port"}',
      );
    });
  }

  Future<bool> _isHealthy(int port) async {
    try {
      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
          .timeout(const Duration(milliseconds: 500));
      final response = await request.close();
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _readLockFile() async {
    try {
      final file = File(_lockFile);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = Map<String, dynamic>.from(
        // simple parse — avoid importing dart:convert for this
        _parseLockJson(content),
      );
      return json['port'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLockFile(int port, int pid) async {
    await File(_lockFile).writeAsString(
      '{"port":$port,"pid":$pid,"started":"${DateTime.now().toIso8601String()}"}',
    );
  }

  /// Resolves the best way to start the daemon.
  ///
  /// Returns a record of `(executable, args)` ready to pass to [Process.start].
  ///
  /// Priority:
  ///   1. Pre-compiled native binary at `<package>/bin/jankdoc_daemon` — fastest startup (~50ms)
  ///   2. `dart run jankdoc:daemon` — works everywhere without pre-compilation
  Future<({String executable, List<String> args})> _resolveDaemonCommand() async {
    // 1. Compiled binary alongside the package
    final script = Platform.script.toFilePath();
    final packageDir = File(script).parent.parent.path;
    for (final name in ['jankdoc_daemon', 'jankdoc_daemon.exe']) {
      final compiled = File('$packageDir/bin/$name');
      if (await compiled.exists()) {
        return (
          executable: compiled.path,
          args: ['--port', '$_defaultPort'],
        );
      }
    }

    // 2. Fall back to `dart run jankdoc:daemon`
    // Platform.executable is the path to the Dart VM (e.g. /usr/local/bin/dart).
    return (
      executable: Platform.executable,
      args: ['run', 'jankdoc:daemon', '--port', '$_defaultPort'],
    );
  }

  Map<String, dynamic> _parseLockJson(String s) {
    // Minimal JSON parse for the lock file — avoids a dart:convert import
    // at the library root which would pull it into release builds.
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
}
