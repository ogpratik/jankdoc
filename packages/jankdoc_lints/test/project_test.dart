// Project lookups: analysis options, excludes, Flutter detection, and the
// file list check_project uses.
import 'dart:io';

import 'package:jankdoc_lints/src/agent/checker.dart';
import 'package:jankdoc_lints/src/agent/project.dart';
import 'package:jankdoc_lints/src/agent/warm_analyzer.dart';
import 'package:test/test.dart';

void main() {
  late String root;

  void write(String path, String text) {
    File('$root/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    root = Directory.systemTemp
        .createTempSync('jankdoc_project_')
        .resolveSymbolicLinksSync();
    write('pubspec.yaml', '''
name: app
dependencies:
  flutter:
    sdk: flutter
''');
    write('analysis_options.yaml', '''
analyzer:
  exclude:
    - "**/*.g.dart"
    - lib/generated/**
plugins:
  jankdoc_lints: ^1.0.0
''');
    write('lib/main.dart', 'void main() {}\n');
    write('lib/model.g.dart', '// generated\n');
    write('lib/generated/l10n.dart', '// generated\n');
    write('lib/src/widget.dart', 'class W {}\n');
    write('build/out.dart', '// build output\n');
    write('.dart_tool/x.dart', '// tool\n');
  });

  tearDown(() => Directory(root).deleteSync(recursive: true));

  test('projectRootFor finds the project from a nested file', () {
    expect(projectRootFor('$root/lib/src/widget.dart'), root);
  });

  test('plugin enabled, excludes matched relative to the options file', () {
    final options = ProjectOptions();
    expect(options.pluginEnabled('$root/lib/main.dart'), isTrue);
    expect(options.excluded('$root/lib/main.dart'), isFalse);
    expect(options.excluded('$root/lib/model.g.dart'), isTrue);
    expect(options.excluded('$root/lib/generated/l10n.dart'), isTrue);
    expect(options.excluded('$root/lib/src/widget.dart'), isFalse);
  });

  test('a nested analysis_options.yaml replaces the outer one', () {
    write('tool/analysis_options.yaml', 'linter:\n  rules: []\n');
    write('tool/run.dart', 'void main() {}\n');
    final options = ProjectOptions();
    expect(options.pluginEnabled('$root/tool/run.dart'), isFalse);
    expect(pluginEnabledFor('$root/lib/main.dart'), isTrue);
  });

  test('check_project skips excluded, hidden and build files', () {
    expect(dartFilesWithPlugin(root), [
      '$root/lib/main.dart',
      '$root/lib/src/widget.dart',
    ]);
  });

  test('isFlutterPackage reads the nearest pubspec', () {
    write(
      'packages/core/pubspec.yaml',
      'name: core\ndependencies:\n  meta: any\n',
    );
    write('packages/core/lib/core.dart', '\n');
    final options = ProjectOptions();
    expect(options.isFlutterPackage('$root/lib/main.dart'), isTrue);
    expect(
      options.isFlutterPackage('$root/packages/core/lib/core.dart'),
      isFalse,
    );
  });

  test('no probe for files that silence all lints', () {
    expect(
      Probe.build('// ignore_for_file: type=lint\nclass A {}\n', 0),
      isNull,
    );
  });
}
