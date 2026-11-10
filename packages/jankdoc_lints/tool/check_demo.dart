// End-to-end check of the plugin against the real Flutter SDK.
//
// Runs `dart analyze` in examples/lint_demo (where the plugin is enabled) and
// asserts JankDoc reports exactly the `// expect: <rule>` lines of
// lib/bad.dart and nothing anywhere else.
//
//   dart run tool/check_demo.dart [path/to/lint_demo]
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final demo = Directory(
    Directory(
      args.isNotEmpty
          ? args.first
          : '${_packageRoot()}/../../examples/lint_demo',
    ).resolveSymbolicLinksSync(),
  );

  final expected = <String>{};
  final bad = File('${demo.path}/lib/bad.dart').readAsLinesSync();
  for (var i = 0; i < bad.length; i++) {
    final m = RegExp(r'// expect: (\w+)').firstMatch(bad[i]);
    if (m != null) expected.add('lib/bad.dart:${i + 1} ${m[1]}');
  }

  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    '--format=json',
  ], workingDirectory: demo.path);
  final out = result.stdout as String;
  final json = jsonDecode(out.substring(out.indexOf('{'))) as Map;
  final actual = <String>{};
  for (final d in (json['diagnostics'] as List).cast<Map>()) {
    final location = d['location'] as Map;
    final line = ((location['range'] as Map)['start'] as Map)['line'];
    final file = (location['file'] as String).substring(demo.path.length + 1);
    actual.add('$file:$line ${d['code']}');
  }

  final missing = expected.difference(actual);
  final unexpected = actual.difference(expected);
  for (final m in missing) {
    stderr.writeln('MISSING     $m');
  }
  for (final u in unexpected) {
    stderr.writeln('UNEXPECTED  $u');
  }
  if (missing.isEmpty && unexpected.isEmpty) {
    stdout.writeln(
      'lint_demo: all ${expected.length} expected diagnostics, '
      'no others.',
    );
  }
  exit(missing.isEmpty && unexpected.isEmpty ? 0 : 1);
}

String _packageRoot() => File.fromUri(Platform.script).parent.parent.path;
