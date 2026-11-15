// A long-lived `dart language-server` that answers "what does JankDoc say
// about these files right now?" in tens of milliseconds once warm.
//
// The analysis server runs the jankdoc_lints plugin in its own isolate and
// merges the plugin's results into `textDocument/publishDiagnostics`. After
// a change the server first publishes its own fresh diagnostics together with
// the plugin's *previous* ones, and the plugin's fresh results follow in a
// later publish — sometimes after `$/analyzerStatus` already says idle. So
// neither the first publish nor the idle signal means "done".
//
// To know when the plugin has caught up, each check opens the file as an
// overlay with a probe appended: a reference to `Clip.antiAliasWithSaveLayer`
// on a known line, which `clip_save_layer` always flags. The publish that
// carries the probe's diagnostic is the plugin's result for exactly that
// content. The probe (and the `dart:ui` import it needs, added on an existing
// line so no real line moves) is stripped from the result, and the overlay is
// closed again so the server goes back to the file on disk.
//
// Files that cannot carry a probe (syntax errors, `part of` files, the rule
// switched off or ignored, packages without Flutter) fall back to waiting for the server to go idle plus a short
// quiet period.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'findings.dart';
import 'lsp.dart';
import 'project.dart';

/// The `dart` executable to run tools with. `Platform.resolvedExecutable` is
/// only `dart` when running on the VM (`dart run`, `pub global run`).
String dartExecutable() {
  final exe = Platform.resolvedExecutable;
  final name = exe.split(Platform.pathSeparator).last;
  return name == 'dart' || name == 'dart.exe' ? exe : 'dart';
}

final _ignoresAllLints = RegExp(r'ignore_for_file:[^\n]*type\s*=\s*lint');

class WarmAnalyzer {
  WarmAnalyzer._(this.root, this._lsp) {
    _lsp.notifications.listen(_onNotification);
    exited = _lsp.exitCode.then((_) => _dead = true);
  }

  /// Starts `dart language-server` on [root] (an absolute, symlink-resolved
  /// project directory) and waits for it to initialize.
  static Future<WarmAnalyzer> start(String root) async {
    final process = await Process.start(dartExecutable(), [
      'language-server',
      '--client-id=jankdoc_mcp',
    ], workingDirectory: root);
    process.stderr
        .transform(utf8.decoder)
        .listen((s) => stderr.write('[dart language-server] $s'));
    final lsp = LspConnection(process);
    final analyzer = WarmAnalyzer._(root, lsp);
    final rootUri = Uri.directory(root).toString();
    // The server ignores everything sent before it answers `initialize`.
    await lsp.request('initialize', {
      'processId': pid,
      'clientInfo': {'name': 'jankdoc_mcp'},
      'rootUri': rootUri,
      'workspaceFolders': [
        {'uri': rootUri, 'name': root.split('/').last},
      ],
      'capabilities': {
        'workspace': {'workspaceFolders': true},
        'textDocument': {'publishDiagnostics': <String, Object?>{}},
      },
      'initializationOptions': {
        'onlyAnalyzeProjectsWithOpenFiles': false,
        'closingLabels': false,
        'outline': false,
        'flutterOutline': false,
      },
    });
    lsp.notify('initialized', <String, Object?>{});
    return analyzer;
  }

  final String root;
  final LspConnection _lsp;

  /// Completes when the language server process exits.
  late final Future<void> exited;
  var _dead = false;

  /// Latest published diagnostics per absolute path.
  final _diagnostics = <String, List<Map<String, Object?>>>{};
  final _lastPublish = <String, DateTime>{};
  final _publishes = StreamController<String>.broadcast(sync: true);
  var _analyzing = false;
  DateTime _lastStatusChange = DateTime.now();

  /// Whether the plugin has answered a probe yet. Until it has, it may still
  /// be compiling or doing its first full analysis, which can take a while.
  var _warm = false;
  var _probeCount = 0;
  Future<void> _queue = Future.value();

  /// Fresh JankDoc findings for [paths] (absolute `.dart` files under
  /// [root] that exist on disk). Checks run one at a time.
  Future<CheckResult> check(List<String> paths) {
    final result = _queue.then((_) => _check(paths));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> dispose() async {
    try {
      await _lsp.request('shutdown', null).timeout(const Duration(seconds: 2));
      _lsp.notify('exit', null);
      await _lsp.exitCode.timeout(const Duration(seconds: 2));
    } on Object {
      _lsp.kill();
    }
  }

  Future<CheckResult> _check(List<String> paths) async {
    final clock = Stopwatch()..start();
    final findings = <Finding>[];
    final unverified = <String>[];
    final options = ProjectOptions();
    // Bounded batches keep the number of overlays (and the plugin's queue)
    // reasonable on big projects.
    for (var i = 0; i < paths.length; i += 64) {
      final batch = paths.sublist(i, (i + 64).clamp(0, paths.length));
      await Future.wait([
        for (final path in batch)
          _checkOne(path, options).then((r) {
            findings.addAll(r.$1);
            if (!r.$2) unverified.add(path);
          }),
      ]);
    }
    return CheckResult(
      findings: sortFindings(findings),
      filesChecked: paths.length,
      elapsed: clock.elapsed,
      unverified: unverified,
    );
  }

  /// Returns the file's findings and whether a probe confirmed them.
  Future<(List<Finding>, bool)> _checkOne(
    String path,
    ProjectOptions options,
  ) async {
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      throw CheckException('Could not read $path: ${e.message}');
    }
    final uri = Uri.file(path).toString();
    // `ignore_for_file: type=lint` (common in generated files) silences
    // every JankDoc rule: nothing to wait for.
    if (_ignoresAllLints.hasMatch(text)) return (const <Finding>[], true);
    // The probe needs `dart:ui` and the clip_save_layer rule.
    final canProbe =
        options.isFlutterPackage(path) &&
        !RegExp(
          r'clip_save_layer\s*:\s*(false|ignore)',
        ).hasMatch(options.analysisOptionsText(path) ?? '');
    final probe = canProbe ? Probe.build(text, ++_probeCount) : null;

    final sent = DateTime.now();
    final Future<List<Map<String, Object?>>?> done = probe == null
        ? _settled(path, sent)
        : _probeSeen(
            path,
            probe,
            _warm ? const Duration(seconds: 5) : const Duration(minutes: 3),
          );
    _lsp.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': probe?.text ?? text,
      },
    });
    // A crashed server never publishes: don't wait out the timeout.
    var diagnostics = await Future.any([done, exited.then((_) => null)]);
    if (_dead) {
      throw CheckException('dart language-server exited; check again.');
    }
    final verified = diagnostics != null && probe != null;
    if (verified) _warm = true;
    diagnostics ??= _diagnostics[path] ?? const [];
    _lsp.notify('textDocument/didClose', {
      'textDocument': {'uri': uri},
    });

    return (
      [
        for (var d in diagnostics)
          if (jankdocRules.containsKey(d['code']))
            if (probe == null)
              Finding.fromLsp(d, path)
            else if (probe.unprobe(d) case final real?)
              Finding.fromLsp(real, path),
      ],
      verified,
    );
  }

  /// Completes with the diagnostics of the first publish for [path] that
  /// contains [probe]'s diagnostic, or null after [timeout].
  Future<List<Map<String, Object?>>?> _probeSeen(
    String path,
    Probe probe,
    Duration timeout,
  ) {
    final completer = Completer<List<Map<String, Object?>>?>();
    late StreamSubscription<String> sub;
    final timer = Timer(timeout, () {
      sub.cancel();
      completer.complete(null);
    });
    sub = _publishes.stream.listen((published) {
      if (published != path) return;
      final diagnostics = _diagnostics[path]!;
      if (diagnostics.any(probe.isProbe)) {
        timer.cancel();
        sub.cancel();
        completer.complete(diagnostics);
      }
    });
    return completer.future;
  }

  /// Fallback for files without a probe: waits until the server has been
  /// idle, and [path] quiet, for 200 ms; returns null (use the cache).
  Future<List<Map<String, Object?>>?> _settled(
    String path,
    DateTime sent,
  ) async {
    const quiet = Duration(milliseconds: 200);
    final deadline = sent.add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final now = DateTime.now();
      final last = [
        sent,
        _lastStatusChange,
        ?_lastPublish[path],
      ].reduce((a, b) => a.isAfter(b) ? a : b);
      if (!_analyzing && now.difference(last) >= quiet) break;
    }
    return null;
  }

  void _onNotification(Map<String, Object?> m) {
    final params = m['params'];
    if (params is! Map<String, Object?>) return;
    switch (m['method']) {
      case r'$/analyzerStatus':
        _analyzing = params['isAnalyzing'] == true;
        _lastStatusChange = DateTime.now();
      case 'textDocument/publishDiagnostics':
        final uri = Uri.parse(params['uri'] as String);
        if (uri.scheme != 'file') return;
        final path = uri.toFilePath();
        _diagnostics[path] = (params['diagnostics'] as List)
            .cast<Map<String, Object?>>();
        _lastPublish[path] = DateTime.now();
        _publishes.add(path);
    }
  }
}

/// A copy of a file's text with a `clip_save_layer` trigger appended on a
/// known line, and the mapping back to the original positions.
class Probe {
  Probe._(
    this.text, {
    required int line,
    required int firstAddedLine,
    required int insertLine,
    required int insertColumn,
    required int insertLength,
  }) : _line = line,
       _firstAddedLine = firstAddedLine,
       _insertLine = insertLine,
       _insertColumn = insertColumn,
       _insertLength = insertLength;

  static const _prefix = 'jankdoc_probe';
  static const _import = "import 'dart:ui' as $_prefix;";

  /// Builds a probe for [original], or returns null when it cannot carry one
  /// (syntax errors, `part of` files, or an `ignore_for_file` covering
  /// `clip_save_layer` or `type=lint`). [nonce] varies the probe line between checks so a
  /// late publish of an earlier probe is never mistaken for this one.
  static Probe? build(String original, int nonce) {
    if (RegExp(r'ignore_for_file:[^\n]*clip_save_layer').hasMatch(original) ||
        _ignoresAllLints.hasMatch(original)) {
      return null;
    }
    final ParseStringResult parsed;
    try {
      parsed = parseString(content: original, throwIfDiagnostics: false);
    } on Object {
      return null;
    }
    if (parsed.errors.isNotEmpty) return null;
    final directives = parsed.unit.directives;
    if (directives.any((d) => d is PartOfDirective)) return null;

    // Put the import on an existing line — right after the last library,
    // import or export directive, else before the first part directive or
    // declaration — so every real diagnostic keeps its line.
    final beforeParts = directives.where((d) => d is! PartDirective);
    final int offset;
    final String insert;
    if (beforeParts.isNotEmpty) {
      offset = beforeParts.last.end;
      insert = ' $_import';
    } else {
      offset =
          directives.firstOrNull?.offset ??
          parsed.unit.declarations.firstOrNull?.offset ??
          original.length;
      insert = '$_import ';
    }
    final insertLine = _lineCount(original.substring(0, offset));
    final insertColumn = offset == 0
        ? 0
        : offset - (original.lastIndexOf('\n', offset - 1) + 1);

    var head =
        original.substring(0, offset) + insert + original.substring(offset);
    if (!head.endsWith('\n')) head += '\n';
    final padded = head + '\n' * (1 + nonce % 8);
    return Probe._(
      '${padded}final _jankdocProbe = $_prefix.Clip.antiAliasWithSaveLayer;\n',
      line: _lineCount(padded),
      firstAddedLine: _lineCount(head),
      insertLine: insertLine,
      insertColumn: insertColumn,
      insertLength: insert.length,
    );
  }

  /// The overlay text to analyze.
  final String text;

  /// 0-based line of the probe statement.
  final int _line;

  /// 0-based; lines from here on were added by the probe.
  final int _firstAddedLine;

  /// Where the `dart:ui` import was inserted (0-based line and column).
  final int _insertLine;
  final int _insertColumn;
  final int _insertLength;

  /// Whether [d] is the probe's own diagnostic.
  bool isProbe(Map<String, Object?> d) =>
      d['code'] == 'clip_save_layer' && _position(d, 'start').$1 == _line;

  /// [d] mapped back to the original text, or null if it is on added lines.
  Map<String, Object?>? unprobe(Map<String, Object?> d) {
    if (_position(d, 'start').$1 >= _firstAddedLine) return null;
    Map<String, Object?> back(String which) {
      final (line, column) = _position(d, which);
      return {
        'line': line,
        'character': line == _insertLine && column >= _insertColumn
            ? (column - _insertLength).clamp(_insertColumn, column)
            : column,
      };
    }

    return {
      ...d,
      'range': {'start': back('start'), 'end': back('end')},
    };
  }

  static (int, int) _position(Map<String, Object?> d, String which) {
    final p =
        (d['range'] as Map<String, Object?>)[which] as Map<String, Object?>;
    return (p['line'] as int, p['character'] as int);
  }

  static int _lineCount(String s) => '\n'.allMatches(s).length;
}
