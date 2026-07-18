import 'dart:io';

import 'package:jankdoc/src/setup_hints.dart';
import 'package:test/test.dart';

void main() {
  group('writeSetupOllamaFile', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('jankdoc_setup_');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('creates ~/.jankdoc/setup-ollama.md and returns its path', () {
      final path = writeSetupOllamaFile(homeOverride: tempDir.path);
      expect(path, isNotNull);
      expect(path, endsWith('/.jankdoc/setup-ollama.md'));
      expect(File(path!).existsSync(), isTrue);
    });

    test('includes the configured model IDs in pull commands', () {
      final path = writeSetupOllamaFile(
        homeOverride: tempDir.path,
        modelId: 'my-model:foo',
        embedModelId: 'my-embed:bar',
      );
      final content = File(path!).readAsStringSync();
      expect(content, contains('ollama pull my-model:foo'));
      expect(content, contains('ollama pull my-embed:bar'));
    });

    test('always includes the doctor command as verification step', () {
      final path = writeSetupOllamaFile(homeOverride: tempDir.path);
      final content = File(path!).readAsStringSync();
      expect(content, contains('dart run jankdoc:doctor'));
    });

    test('rewriting is idempotent (safe to call on every daemon start)', () {
      final path1 = writeSetupOllamaFile(homeOverride: tempDir.path);
      final path2 = writeSetupOllamaFile(homeOverride: tempDir.path);
      expect(path1, path2);
      expect(File(path1!).existsSync(), isTrue);
    });
  });
}
