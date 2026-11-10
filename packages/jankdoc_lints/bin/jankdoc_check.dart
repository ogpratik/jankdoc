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
// `plugins:` in the project's analysis_options.yaml.
import 'dart:convert';
import 'dart:io';

const _rules = {
  'setstate_in_build',
  'sync_io_in_build',
  'json_decode_in_build',
  'animated_opacity_widget',
  'animated_builder_per_item',
  'clip_save_layer',
  'non_lazy_list',
};

Future<void> main(List<String> args) async {
  if (args.contains('--hook')) {
    exit(await _hook());
  }
  final paths = args.where((a) => !a.startsWith('-')).toList();
  final findings = await _analyze(Directory.current.path, paths);
  for (final f in findings) {
    stdout.writeln(f);
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
  final root =
      _projectRoot(File(file).parent) ??
      (event['cwd'] as String? ?? Directory.current.path);
  final findings = await _analyze(root, [file]);
  if (findings.isEmpty) return 0;
  stderr
    ..writeln(
      'JankDoc found jank-causing code in $file. '
      'Fix these before continuing:',
    )
    ..writeAll(findings, '\n')
    ..writeln();
  return 2;
}

/// Nearest ancestor containing analysis_options.yaml + pubspec.yaml.
String? _projectRoot(Directory dir) {
  for (Directory? d = dir; d != null; d = d.parent) {
    if (File('${d.path}/pubspec.yaml').existsSync() &&
        File('${d.path}/analysis_options.yaml').existsSync()) {
      return d.path;
    }
    if (d.parent.path == d.path) break;
  }
  return null;
}

Future<List<String>> _analyze(String root, List<String> paths) async {
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
      if (_rules.contains(d['code'])) _format(d, root),
  ];
}

String _format(Map<String, Object?> d, String root) {
  final location = d['location'] as Map<String, Object?>;
  final start =
      (location['range'] as Map<String, Object?>)['start']
          as Map<String, Object?>;
  var file = location['file'] as String;
  if (file.startsWith('$root/')) file = file.substring(root.length + 1);
  return '$file:${start['line']}:${start['column']} '
      '[jankdoc_lints/${d['code']}] ${d['problemMessage']}\n'
      '    fix: ${d['correctionMessage']}';
}
