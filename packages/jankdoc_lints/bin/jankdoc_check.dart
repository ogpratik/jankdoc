// JankDoc check for AI coding agents and CI.
//
//   jankdoc_check [paths...]   Analyze paths (default: lib), print only
//                              JankDoc findings; exit 1 if there are any.
//   jankdoc_check --hook       Claude Code PostToolUse hook: reads the hook
//                              event from stdin, analyzes the edited .dart
//                              file, and on findings exits 2 so Claude sees
//                              them and fixes the code in the same turn.
//
// Runs `dart analyze --format=json`, so it needs `jankdoc_lints` enabled under
// `plugins:` in the project's analysis_options.yaml. With --hook, if a
// jankdoc_mcp server is running for the project it asks that instead: its
// analysis is already warm, so the check takes milliseconds, not seconds.
import 'dart:convert';
import 'dart:io';

import 'package:jankdoc_lints/src/agent/findings.dart';
import 'package:jankdoc_lints/src/agent/hook_endpoint.dart';
import 'package:jankdoc_lints/src/agent/project.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--hook')) {
    exit(await _hook());
  }
  final paths = args.where((a) => !a.startsWith('-')).toList();
  final findings = await _analyze(Directory.current.path, paths);
  for (final f in findings) {
    stdout.writeln(f.format(Directory.current.path));
  }
  stdout.writeln(
    findings.isEmpty
        ? 'JankDoc: no issues found.'
        : 'JankDoc: ${findings.length} issue(s) found.',
  );
  exit(findings.isEmpty ? 0 : 1);
}

Future<int> _hook() async {
  final Map<String, Object?> event;
  try {
    event =
        jsonDecode(await stdin.transform(utf8.decoder).join())
            as Map<String, Object?>;
  } on FormatException {
    return 0; // Not a hook payload — never block the agent on our own bug.
  }
  final input = event['tool_input'];
  final file = input is Map ? input['file_path'] : null;
  if (file is! String || !file.endsWith('.dart') || !File(file).existsSync()) {
    return 0;
  }
  // Symlink-resolved, so findings print relative to root.
  final real = File(file).resolveSymbolicLinksSync();
  final root = Directory(
    projectRootFor(real) ?? event['cwd'] as String? ?? Directory.current.path,
  ).resolveSymbolicLinksSync();
  final findings =
      await checkViaRunningServer(real) ?? await _analyze(root, [real]);
  if (findings.isEmpty) return 0;
  stderr
    ..writeln(
      'JankDoc found jank-causing code in $file. '
      'Fix these before continuing:',
    )
    ..writeAll(findings.map((f) => f.format(root)), '\n')
    ..writeln();
  return 2;
}

Future<List<Finding>> _analyze(String root, List<String> paths) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    '--format=json',
    ...paths,
  ], workingDirectory: root);
  final out = result.stdout as String;
  final start = out.indexOf('{');
  if (start < 0) return const [];
  final json = jsonDecode(out.substring(start)) as Map<String, Object?>;
  final diagnostics = (json['diagnostics'] as List? ?? const [])
      .cast<Map<String, Object?>>();
  return [
    for (final d in diagnostics)
      if (jankdocRules.containsKey(d['code'])) Finding.fromAnalyzeJson(d),
  ];
}
