// LSP framing and the warm analyzer's probe bookkeeping.
import 'dart:convert';

import 'package:jankdoc_lints/src/agent/lsp.dart';
import 'package:jankdoc_lints/src/agent/warm_analyzer.dart';
import 'package:test/test.dart';

List<int> frame(Object body, {String extraHeaders = ''}) {
  final bytes = utf8.encode(jsonEncode(body));
  return [
    ...ascii.encode('Content-Length: ${bytes.length}\r\n$extraHeaders\r\n'),
    ...bytes,
  ];
}

void main() {
  group('LspFramer', () {
    test('one message per chunk', () {
      final framer = LspFramer();
      expect(framer.add(frame({'id': 1})), [
        {'id': 1},
      ]);
    });

    test('several messages in one chunk', () {
      final framer = LspFramer();
      expect(
        framer.add([
          ...frame({'a': 1}),
          ...frame({'b': 2}),
        ]),
        [
          {'a': 1},
          {'b': 2},
        ],
      );
    });

    test('a message split at every byte', () {
      final framer = LspFramer();
      final bytes = frame({'text': 'héllo ✓'});
      final out = <Map<String, Object?>>[];
      for (final b in bytes) {
        out.addAll(framer.add([b]));
      }
      expect(out, [
        {'text': 'héllo ✓'},
      ]);
    });

    test('Content-Length counts bytes, not characters', () {
      final framer = LspFramer();
      final first = frame({'s': '日本語'});
      expect(
        framer.add([
          ...first,
          ...frame({'n': 2}),
        ]).length,
        2,
      );
    });

    test('extra headers, in any order and case', () {
      final framer = LspFramer();
      final body = utf8.encode('{"ok":true}');
      final bytes = [
        ...ascii.encode(
          'Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n'
          'content-length: ${body.length}\r\n\r\n',
        ),
        ...body,
      ];
      expect(framer.add(bytes), [
        {'ok': true},
      ]);
    });

    test('keeps a partial message for the next chunk', () {
      final framer = LspFramer();
      final bytes = frame({'x': 1});
      expect(framer.add(bytes.sublist(0, 10)), isEmpty);
      expect(framer.add(bytes.sublist(10)), [
        {'x': 1},
      ]);
    });

    test('rejects a header block without Content-Length', () {
      expect(
        () => LspFramer().add(ascii.encode('Foo: 1\r\n\r\n{}')),
        throwsFormatException,
      );
    });

    test('round-trips lspEncode', () {
      expect(LspFramer().add(lspEncode({'id': 3, 'method': 'm'})), [
        {'jsonrpc': '2.0', 'id': 3, 'method': 'm'},
      ]);
    });
  });

  group('Probe', () {
    Map<String, Object?> diag(String code, int line, int character) => {
      'code': code,
      'message': 'm',
      'range': {
        'start': {'line': line, 'character': character},
        'end': {'line': line, 'character': character + 4},
      },
    };

    const source = '''
import 'package:flutter/widgets.dart'; // trailing

class A {}
''';

    test('adds the import without moving any line', () {
      final probe = Probe.build(source, 0)!;
      final lines = probe.text.split('\n');
      expect(lines[0], startsWith("import 'package:flutter/widgets.dart';"));
      expect(lines[0], contains("import 'dart:ui' as jankdoc_probe;"));
      expect(lines[0], endsWith('// trailing'));
      expect(lines[2], 'class A {}');
      expect(probe.text, contains('jankdoc_probe.Clip.antiAliasWithSaveLayer'));
    });

    test('recognises its own diagnostic and nothing else', () {
      final probe = Probe.build(source, 0)!;
      final line = probe.text
          .split('\n')
          .indexWhere((l) => l.contains('_jankdocProbe'));
      expect(probe.isProbe(diag('clip_save_layer', line, 40)), isTrue);
      expect(probe.isProbe(diag('clip_save_layer', 2, 0)), isFalse);
      expect(probe.isProbe(diag('non_lazy_list', line, 40)), isFalse);
      expect(probe.unprobe(diag('clip_save_layer', line, 40)), isNull);
    });

    test('the nonce moves the probe line', () {
      final lines = {
        for (var n = 0; n < 8; n++)
          Probe.build(
            source,
            n,
          )!.text.split('\n').indexWhere((l) => l.contains('_jankdocProbe')),
      };
      expect(lines, hasLength(8));
    });

    test('maps columns after the inserted import back', () {
      final probe = Probe.build(source, 0)!;
      final insertedAt = "import 'package:flutter/widgets.dart';".length;
      final inserted = " import 'dart:ui' as jankdoc_probe;".length;
      // A diagnostic on the trailing comment, after the insertion.
      final moved = probe.unprobe(diag('x', 0, insertedAt + inserted + 1))!;
      expect(
        ((moved['range'] as Map)['start'] as Map)['character'],
        insertedAt + 1,
      );
      // Before the insertion, and on other lines: unchanged.
      final before = probe.unprobe(diag('x', 0, 3))!;
      expect(((before['range'] as Map)['start'] as Map)['character'], 3);
      final other = probe.unprobe(diag('x', 2, 6))!;
      expect(((other['range'] as Map)['start'] as Map), {
        'line': 2,
        'character': 6,
      });
    });

    test('a file without directives gets the import before its code', () {
      final probe = Probe.build('class A {}\n', 0)!;
      expect(
        probe.text,
        startsWith("import 'dart:ui' as jankdoc_probe; class A {}"),
      );
      final mapped = probe.unprobe(diag('x', 0, 35 + 6))!;
      expect(((mapped['range'] as Map)['start'] as Map)['character'], 6);
    });

    test('the import goes before part directives', () {
      final probe = Probe.build("library;\npart 'b.dart';\nclass A {}\n", 0)!;
      expect(
        probe.text,
        startsWith("library; import 'dart:ui' as jankdoc_probe;\npart"),
      );
    });

    test('no probe for part files, broken files, or ignored rules', () {
      expect(Probe.build("part of 'a.dart';\nclass B {}\n", 0), isNull);
      expect(Probe.build('class A {\n', 0), isNull);
      expect(
        Probe.build(
          '// ignore_for_file: jankdoc_lints/clip_save_layer\nclass A {}\n',
          0,
        ),
        isNull,
      );
    });

    test('a file without a trailing newline', () {
      final probe = Probe.build('class A {}', 0)!;
      expect(probe.text.split('\n').first, endsWith('class A {}'));
    });
  });
}
