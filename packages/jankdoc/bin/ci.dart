/// JankDoc CI runner — rule-tier analysis with SARIF 2.1.0 output.
///
/// Usage:
///   dart run bin/ci.dart --input telemetry.json [--output results.sarif.json]
///   dart run bin/ci.dart --eval          # runs built-in eval fixtures
///   cat telemetry.json | dart run bin/ci.dart
///
/// Stdin mode: reads a single TelemetryBatch JSON from stdin.
/// File mode:  reads from --input (single batch or JSON array of batches).
/// Eval mode:  runs the built-in eval fixture suite and reports pass/fail.
///
/// Exit codes:
///   0 — no issues found (or eval passed)
///   1 — one or more HIGH/CRITICAL diagnoses found (or eval failed)
///   2 — usage error or unreadable input
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_rules/jankdoc_rules.dart';

// Eval fixtures are in jankdoc_eval — use a local import when available.
// For the compiled binary distribution, the eval harness is a dev dependency.

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('input', abbr: 'i', help: 'Path to telemetry JSON input file.')
    ..addOption('output', abbr: 'o', help: 'Path to write SARIF output (default: stdout).')
    ..addFlag('eval', help: 'Run built-in eval fixture suite.', negatable: false)
    ..addFlag('fail-on-warning', help: 'Exit 1 on MEDIUM severity too.', negatable: false)
    ..addFlag('verbose', abbr: 'v', help: 'Print matched rules to stderr.', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: $e\n${parser.usage}');
    exit(2);
  }

  if (results['help'] as bool) {
    stdout.writeln('JankDoc CI runner\n\n${parser.usage}');
    exit(0);
  }

  final verbose = results['verbose'] as bool;
  final failOnWarning = results['fail-on-warning'] as bool;
  final outputPath = results['output'] as String?;

  if (results['eval'] as bool) {
    await _runEvalMode(verbose: verbose);
    return;
  }

  // ── Telemetry analysis mode ──────────────────────────────────────────────
  final batches = await _loadBatches(results['input'] as String?);
  if (batches == null) exit(2);

  final ruleProvider = BuiltInRuleProvider();
  final engine = RuleEngine(ruleProvider);
  final diagnoses = <_CiDiagnosis>[];

  for (final batch in batches) {
    final match = engine.evaluate(batch);
    if (match == null) continue;

    final frame = batch.worstFrame;
    final userFrame = frame.uiStack.firstWhereOrNull((s) => s.isUserCode);

    diagnoses.add(_CiDiagnosis(
      ruleId: match.rule.id,
      patternId: match.rule.patternId,
      severity: match.rule.severity,
      confidence: match.rule.confidence,
      file: userFrame?.file ?? 'unknown',
      line: userFrame?.line ?? 1,
      column: userFrame?.column ?? 0,
      uiMs: frame.uiThreadMs,
      rasterMs: frame.rasterThreadMs,
      sessionId: batch.sessionId,
    ));

    if (verbose) {
      stderr.writeln(
        '[JankDoc] ${match.rule.severity.name.toUpperCase()} '
        '${match.rule.id} @ ${userFrame?.file}:${userFrame?.line} '
        '(ui:${frame.uiThreadMs.toStringAsFixed(1)}ms, '
        'raster:${frame.rasterThreadMs.toStringAsFixed(1)}ms)',
      );
    }
  }

  final sarif = _buildSarif(diagnoses, ruleProvider.rules);
  final output = const JsonEncoder.withIndent('  ').convert(sarif);

  if (outputPath != null) {
    await File(outputPath).writeAsString(output);
    stderr.writeln('[JankDoc] SARIF written to $outputPath (${diagnoses.length} findings)');
  } else {
    stdout.writeln(output);
  }

  // Exit 1 if any relevant severity found
  final threshold = failOnWarning ? Severity.medium : Severity.high;
  final hasIssues = diagnoses.any((d) => d.severity.index >= threshold.index);
  exit(hasIssues ? 1 : 0);
}

// ─── Batch loading ────────────────────────────────────────────────────────────

Future<List<TelemetryBatch>?> _loadBatches(String? inputPath) async {
  final String raw;
  try {
    if (inputPath != null) {
      raw = await File(inputPath).readAsString();
    } else if (!stdin.hasTerminal) {
      raw = await stdin.transform(utf8.decoder).join();
    } else {
      stderr.writeln('Error: provide --input <file> or pipe telemetry JSON via stdin.');
      return null;
    }
  } catch (e) {
    stderr.writeln('Error reading input: $e');
    return null;
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .cast<Map<String, dynamic>>()
          .map(TelemetryBatch.fromJson)
          .toList();
    } else if (decoded is Map<String, dynamic>) {
      return [TelemetryBatch.fromJson(decoded)];
    } else {
      stderr.writeln('Error: input must be a TelemetryBatch JSON object or array.');
      return null;
    }
  } catch (e) {
    stderr.writeln('Error parsing JSON: $e');
    return null;
  }
}

// ─── Eval mode ────────────────────────────────────────────────────────────────

Future<void> _runEvalMode({required bool verbose}) async {
  stderr.writeln('[JankDoc] Eval mode — running built-in fixture suite...');

  final ruleProvider = BuiltInRuleProvider();
  final engine = RuleEngine(ruleProvider);

  // Inline fixture definitions matching jankdoc_eval's EvalFixtures.all.
  // Keeping CI self-contained avoids a cross-package dev dependency in the binary.
  final fixtures = _ciFixtures();
  var passed = 0;
  var failed = 0;

  for (final f in fixtures) {
    final match = engine.evaluate(f.batch);
    final ok = match?.rule.patternId == f.expectedPatternId;
    if (ok) {
      passed++;
      if (verbose) stderr.writeln('  ✓ ${f.name}');
    } else {
      failed++;
      stderr.writeln(
        '  ✗ ${f.name}: '
        'expected="${f.expectedPatternId}" '
        'got="${match?.rule.patternId ?? 'null'}"',
      );
    }
  }

  stderr.writeln('[JankDoc] Eval: $passed passed, $failed failed / ${fixtures.length} total');
  exit(failed > 0 ? 1 : 0);
}

// ─── SARIF builder ────────────────────────────────────────────────────────────

Map<String, dynamic> _buildSarif(
  List<_CiDiagnosis> diagnoses,
  List<Rule> rules,
) {
  return {
    '\$schema': 'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': 'JankDoc',
            'version': '1.0.0',
            'informationUri': 'https://github.com/ogpratik/jankdoc',
            'rules': rules.map((r) => _sarifRule(r)).toList(),
          },
        },
        'results': diagnoses.map((d) => _sarifResult(d)).toList(),
        'columnKind': 'utf16CodeUnits',
      }
    ],
  };
}

Map<String, dynamic> _sarifRule(Rule rule) => {
      'id': rule.id,
      'name': _camelCase(rule.id),
      'shortDescription': {'text': _humanName(rule.patternId)},
      'fullDescription': {'text': _humanDescription(rule.patternId)},
      'defaultConfiguration': {
        'level': _sarifLevel(rule.severity),
      },
      'properties': {
        'tags': ['flutter', 'performance', 'jank'],
        'precision': 'high',
        'problem.severity': rule.severity.name,
      },
    };

Map<String, dynamic> _sarifResult(_CiDiagnosis d) => {
      'ruleId': d.ruleId,
      'level': _sarifLevel(d.severity),
      'message': {
        'text': '${_humanName(d.patternId)}: '
            'UI=${d.uiMs.toStringAsFixed(1)}ms, '
            'Raster=${d.rasterMs.toStringAsFixed(1)}ms. '
            'Confidence: ${(d.confidence * 100).toStringAsFixed(0)}%',
      },
      'locations': [
        {
          'physicalLocation': {
            'artifactLocation': {
              'uri': d.file,
              'uriBaseId': '%SRCROOT%',
            },
            'region': {
              'startLine': d.line,
              'startColumn': d.column > 0 ? d.column : 1,
            },
          },
        },
      ],
      'properties': {
        'sessionId': d.sessionId,
        'patternId': d.patternId,
        'confidence': d.confidence,
      },
    };

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _sarifLevel(Severity s) => switch (s) {
      Severity.critical => 'error',
      Severity.high => 'error',
      Severity.medium => 'warning',
      Severity.low => 'note',
    };

String _camelCase(String kebab) => kebab
    .split('-')
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join();

String _humanName(String patternId) => switch (patternId) {
      'animated-builder-rebuild-storm' => 'AnimatedBuilder Rebuild Storm',
      'setstate-in-build' => 'setState Called in Build',
      'missing-const-constructor' => 'Missing const Constructor',
      'expensive-computation-in-build' => 'Expensive Computation in Build',
      'inherited-widget-over-rebuild' => 'InheritedWidget Over-Rebuild',
      'helper-method-instead-of-widget' => 'Helper Method Instead of Widget',
      'value-notifier-whole-tree-rebuild' => 'ValueNotifier Whole-Tree Rebuild',
      'raster-overdraw-opacity' => 'Opacity saveLayer Overdraw',
      'raster-overdraw-clip' => 'ClipRRect/ClipPath Overdraw',
      'shader-compilation-jank' => 'Shader Compilation Jank',
      'backdrop-filter-overdraw' => 'BackdropFilter Overdraw',
      'missing-repaint-boundary' => 'Missing RepaintBoundary',
      'sync-io-on-ui-thread' => 'Synchronous I/O on UI Thread',
      'json-decode-ui-thread' => 'JSON Decode on UI Thread',
      'heavy-compute-main-isolate' => 'Heavy Computation on Main Isolate',
      'platform-channel-ui-block' => 'Platform Channel Blocking UI',
      'impeller-scroll-jank-ios' => 'Impeller Scroll Jank (iOS)',
      'impeller-powervr-rogue-spike' => 'Impeller PowerVR Rogue Spike',
      'impeller-elevation-rounded-corners' => 'Impeller Elevation + Rounded Corners',
      'impeller-custom-scroll-view-android' => 'Impeller CustomScrollView Android',
      'impeller-general-regression' => 'Impeller General Regression',
      'listview-missing-extent' => 'ListView Missing itemExtent',
      'listview-non-lazy' => 'Non-Lazy ListView',
      'list-missing-keys' => 'Dynamic List Missing Keys',
      'image-in-list-no-cache' => 'Network Image Without Cache',
      'image-no-resize-cache' => 'Image Without Resize Cache',
      _ => patternId,
    };

String _humanDescription(String patternId) => switch (patternId) {
      'animated-builder-rebuild-storm' =>
        'AnimatedBuilder is wrapping too much of the widget tree, causing excessive rebuilds on every animation frame.',
      'setstate-in-build' =>
        'setState() is being called during the build phase, creating a rebuild loop.',
      'missing-const-constructor' =>
        'Widgets are missing const constructors, causing unnecessary rebuilds on every parent setState().',
      'sync-io-on-ui-thread' =>
        'Synchronous I/O operation is blocking the UI thread. Use async I/O or Isolate.run().',
      'json-decode-ui-thread' =>
        'JSON decoding is blocking the UI thread. Use compute() or Isolate.run() for large payloads.',
      'raster-overdraw-opacity' =>
        'Opacity widget is forcing a saveLayer GPU pass. Use FadeTransition or AnimatedOpacity instead.',
      'shader-compilation-jank' =>
        'First-use shader compilation is causing raster thread spikes. Use SkSL warm-up or migrate to Impeller.',
      'listview-missing-extent' =>
        'ListView without itemExtent performs O(n) layout. Set itemExtent for O(1) viewport calculations.',
      _ =>
        'Performance issue detected: $patternId. Review the Flutter performance documentation for guidance.',
    };

// ─── Inline eval fixtures for self-contained CI binary ───────────────────────

final class _EvalFixture {
  const _EvalFixture({
    required this.name,
    required this.batch,
    required this.expectedPatternId,
  });
  final String name;
  final TelemetryBatch batch;
  final String expectedPatternId;
}

List<_EvalFixture> _ciFixtures() {
  const androidDevice = DeviceInfo(
    platform: TargetPlatform.android,
    osVersion: '14',
    flutterVersion: '3.29.0',
    dartVersion: '3.6.0',
    impellerEnabled: false,
  );

  const iosDevice = DeviceInfo(
    platform: TargetPlatform.ios,
    osVersion: '17.4',
    flutterVersion: '3.29.0',
    dartVersion: '3.6.0',
    impellerEnabled: true,
    gpuName: 'Apple GPU',
  );

  JankFrame frame({
    required double uiMs,
    double rasterMs = 4.0,
    List<StackFrame> uiStack = const [],
    Map<String, int> rebuilds = const {},
    DeviceInfo device = androidDevice,
  }) =>
      JankFrame(
        timestamp: 1_000_000,
        uiThreadMs: uiMs,
        rasterThreadMs: rasterMs,
        totalMs: uiMs + rasterMs,
        targetFps: 60,
        uiStack: uiStack,
        rasterStack: const [],
        rebuildCounts: rebuilds,
      );

  TelemetryBatch batch({
    required JankFrame f,
    DeviceInfo device = androidDevice,
  }) =>
      TelemetryBatch(
        sessionId: 'ci-eval',
        windowStartMs: 0,
        windowEndMs: 33,
        jankFrames: [f],
        analysisMode: AnalysisMode.deep,
        deviceInfo: device,
      );

  StackFrame sf(String fn, {bool userCode = true}) => StackFrame(
        file: userCode ? 'lib/widget.dart' : 'flutter',
        line: 1,
        column: 0,
        function: fn,
        packageName: userCode ? 'my_app' : 'flutter',
      );

  return [
    _EvalFixture(
      name: 'animated-builder-rebuild-storm',
      batch: batch(
        f: frame(
          uiMs: 12.0,
          uiStack: [sf('build')],
          rebuilds: {'AnimatedBuilder': 100, 'ListView': 10},
        ),
      ),
      expectedPatternId: 'animated-builder-rebuild-storm',
    ),
    _EvalFixture(
      name: 'setstate-in-build',
      batch: batch(
        f: frame(
          uiMs: 30.0,
          uiStack: [sf('build'), sf('setState')],
          rebuilds: {'MyWidget': 120},
        ),
      ),
      expectedPatternId: 'setstate-in-build',
    ),
    _EvalFixture(
      name: 'sync-io-on-ui-thread',
      batch: batch(
        f: frame(
          uiMs: 40.0,
          uiStack: [sf('readAsStringSync'), sf('loadConfig')],
        ),
      ),
      expectedPatternId: 'sync-io-on-ui-thread',
    ),
    _EvalFixture(
      name: 'json-decode-on-ui-thread',
      batch: batch(
        f: frame(
          uiMs: 35.0,
          uiStack: [sf('jsonDecode', userCode: false), sf('parseResponse')],
        ),
      ),
      expectedPatternId: 'json-decode-ui-thread',
    ),
    _EvalFixture(
      name: 'shader-compilation-jank',
      batch: batch(
        f: frame(
          uiMs: 5.0,
          rasterMs: 55.0,
          uiStack: [sf('compileShader', userCode: false)],
        ),
      ),
      expectedPatternId: 'shader-compilation-jank',
    ),
    _EvalFixture(
      name: 'impeller-scroll-jank-ios',
      batch: batch(
        f: frame(
          uiMs: 5.0,
          rasterMs: 45.0,
          rebuilds: {'ListView': 10},
          device: iosDevice,
        ),
        device: iosDevice,
      ),
      expectedPatternId: 'impeller-scroll-jank-ios',
    ),
  ];
}

// ─── Domain types ─────────────────────────────────────────────────────────────

final class _CiDiagnosis {
  const _CiDiagnosis({
    required this.ruleId,
    required this.patternId,
    required this.severity,
    required this.confidence,
    required this.file,
    required this.line,
    required this.column,
    required this.uiMs,
    required this.rasterMs,
    required this.sessionId,
  });

  final String ruleId;
  final String patternId;
  final Severity severity;
  final double confidence;
  final String file;
  final int line;
  final int column;
  final double uiMs;
  final double rasterMs;
  final String sessionId;
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
