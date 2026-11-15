// Maps check requests to one warm language server per project.
import 'dart:async';
import 'dart:io';

import 'findings.dart';
import 'mcp_server.dart';
import 'project.dart';
import 'warm_analyzer.dart';

const _notEnabled =
    'jankdoc_lints is not enabled for {path}. Add it to the project\'s root '
    'analysis_options.yaml:\n\nplugins:\n  jankdoc_lints: ^1.0.0-beta.1';

CheckResult _noFindings(int filesChecked) => CheckResult(
  findings: const [],
  filesChecked: filesChecked,
  elapsed: Duration.zero,
  unverified: const [],
);

class WarmChecker implements Checker {
  WarmChecker({this.onStarted});

  /// Called once per language server, after it initializes.
  final FutureOr<void> Function(WarmAnalyzer)? onStarted;

  final _analyzers = <String, Future<WarmAnalyzer>>{};

  @override
  Future<CheckResult> checkFile(String path) async {
    final options = ProjectOptions();
    if (!options.pluginEnabled(path)) {
      throw CheckException(_notEnabled.replaceAll('{path}', path));
    }
    // The server never reports on excluded files; don't wait for it.
    if (options.excluded(path)) return _noFindings(1);
    return (await _analyzerFor(path)).check([path]);
  }

  @override
  Future<CheckResult> checkProject(String directory) async {
    final files = dartFilesWithPlugin(directory);
    if (files.isEmpty) {
      if (!pluginEnabledFor(directory)) {
        throw CheckException(_notEnabled.replaceAll('{path}', directory));
      }
      return _noFindings(0);
    }
    return (await _analyzerFor(directory)).check(files);
  }

  /// Starts the language server for [directory] and runs one check so the
  /// plugin is compiled and warm before the first real request.
  Future<void> prewarm(String directory) async {
    if (!pluginEnabledFor(directory)) return;
    final analyzer = await _analyzerFor(directory);
    final lib = Directory('${analyzer.root}/lib');
    final sample = lib.existsSync()
        ? dartFilesWithPlugin(lib.path).firstOrNull
        : null;
    if (sample != null) await analyzer.check([sample]);
  }

  Future<void> dispose() async {
    await Future.wait([
      for (final a in _analyzers.values)
        a.then((a) => a.dispose(), onError: (_) {}),
    ]);
  }

  Future<WarmAnalyzer> _analyzerFor(String path) {
    for (final MapEntry(key: root, value: analyzer) in _analyzers.entries) {
      if (path == root || path.startsWith('$root/')) return analyzer;
    }
    final dir = FileSystemEntity.isDirectorySync(path)
        ? path
        : File(path).parent.path;
    final root = Directory(
      projectRootFor(dir) ?? dir,
    ).resolveSymbolicLinksSync();
    for (final MapEntry(key: r, value: analyzer) in _analyzers.entries) {
      if (r == root) return analyzer;
    }
    final started = WarmAnalyzer.start(root).then((a) async {
      // A crashed server is replaced on the next check.
      unawaited(a.exited.then((_) => _analyzers.remove(root)));
      await onStarted?.call(a);
      return a;
    });
    _analyzers[root] = started;
    started.then(
      (_) {},
      onError: (Object _) {
        _analyzers.remove(root);
      },
    );
    return started;
  }
}

/// The `.dart` files under [directory] that the plugin analyzes: skips
/// files where it is not enabled, `analyzer: exclude:` matches, hidden
/// directories (`.dart_tool`, `.git` …) and `build/`.
List<String> dartFilesWithPlugin(String directory) {
  final options = ProjectOptions();
  final out = <String>[];
  void walk(Directory dir) {
    final enabled = options.pluginEnabled(dir.path);
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      return;
    }
    for (final e in entries) {
      final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (e is Directory) {
        if (!name.startsWith('.') && name != 'build') walk(e);
      } else if (e is File &&
          enabled &&
          name.endsWith('.dart') &&
          !options.excluded(e.path)) {
        out.add(e.path);
      }
    }
  }

  walk(Directory(directory));
  return out;
}
