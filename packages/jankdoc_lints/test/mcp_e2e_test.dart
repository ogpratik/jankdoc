// End to end: runs bin/jankdoc_mcp.dart over stdio against
// examples/lint_demo with the real Flutter SDK and a real
// `dart language-server`, and checks the findings against the
// `// expect: <rule>` comments in lib/bad.dart.
//
// Needs `flutter pub get` in examples/lint_demo first.
@Tags(['e2e'])
@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jankdoc_lints/src/agent/hook_endpoint.dart';
import 'package:test/test.dart';

void main() {
  final demo = Directory(
    '${Directory.current.path}/../../examples/lint_demo',
  ).resolveSymbolicLinksSync();
  final bad = '$demo/lib/bad.dart';
  final good = '$demo/lib/good.dart';

  late Process server;
  late StreamIterator<String> responses;
  var nextId = 0;

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?>? params,
  ]) async {
    final id = ++nextId;
    server.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    while (await responses.moveNext()) {
      final m = jsonDecode(responses.current) as Map<String, Object?>;
      if (m['id'] == id) return m;
    }
    throw StateError('server exited');
  }

  Future<Map<String, Object?>> tool(
    String name,
    Map<String, Object?> args,
  ) async {
    final r = await call('tools/call', {'name': name, 'arguments': args});
    return r['result'] as Map<String, Object?>;
  }

  Set<String> found(Map<String, Object?> result) => {
    for (final f in (result['structuredContent'] as Map)['findings'] as List)
      '${((f as Map)['file'] as String).substring(demo.length + 1)}:'
          '${f['line']} ${(f['rule'] as String).split('/').last}',
  };

  final expected = <String>{};
  final lines = File(bad).readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'// expect: (\w+)').firstMatch(lines[i]);
    if (m != null) expected.add('lib/bad.dart:${i + 1} ${m[1]}');
  }

  setUpAll(() async {
    if (!File('$demo/.dart_tool/package_config.json').existsSync()) {
      fail('Run `flutter pub get` in examples/lint_demo first.');
    }
    server = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/jankdoc_mcp.dart',
      demo,
    ]);
    server.stderr.transform(utf8.decoder).listen(stderr.write);
    responses = StreamIterator(
      server.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final init = await call('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'e2e', 'version': '0'},
    });
    expect((init['result'] as Map)['protocolVersion'], '2025-06-18');
    server.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
  });

  tearDownAll(() async {
    await server.stdin.close();
    final code = await server.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        server.kill();
        return -1;
      },
    );
    expect(code, 0, reason: 'server should exit cleanly when stdin closes');
    expect(
      File('$demo/.dart_tool/jankdoc_lints/mcp_endpoint.json').existsSync(),
      isFalse,
      reason: 'hook endpoint file should be removed on exit',
    );
  });

  test('expects one finding per rule in bad.dart', () {
    expect(expected, hasLength(7));
  });

  test('check_file finds exactly the expected issues in bad.dart', () async {
    // The first check may wait for the plugin to compile and warm up.
    final result = await tool('check_file', {'path': 'lib/bad.dart'});
    expect(result['isError'], false, reason: '$result');
    expect(found(result), expected);
    expect((result['structuredContent'] as Map)['unverified'], isEmpty);
  });

  test('check_file finds nothing in good.dart', () async {
    final result = await tool('check_file', {'path': good});
    expect(result['isError'], false, reason: '$result');
    expect(found(result), isEmpty);
  });

  test('a warm check takes well under 0.5 s', () async {
    for (var i = 0; i < 5; i++) {
      final clock = Stopwatch()..start();
      final result = await tool('check_file', {'path': 'lib/bad.dart'});
      final roundTrip = clock.elapsedMilliseconds;
      expect(found(result), expected);
      final ms = (result['structuredContent'] as Map)['elapsedMs'] as int;
      printOnFailure('warm check: $ms ms in the server, $roundTrip ms total');
      expect(roundTrip, lessThan(500));
    }
  });

  test('check_project finds the bad.dart issues and nothing else', () async {
    final result = await tool('check_project', {});
    expect(result['isError'], false, reason: '$result');
    expect(found(result), expected);
    expect((result['structuredContent'] as Map)['filesChecked'], 2);
  });

  test('explain_pattern returns the KB entry and a fix', () async {
    final result = await tool('explain_pattern', {
      'pattern_id': 'clip_save_layer',
    });
    final data = result['structuredContent'] as Map;
    expect(data['pattern'], 'raster-overdraw-clip');
    expect((data['fix'] as Map)['after'], contains('Clip.antiAlias'));
  });

  test('jankdoc_check --hook reuses the warm server', () async {
    // The endpoint answers directly (no `dart analyze` fallback)…
    final direct = await checkViaRunningServer(bad);
    expect(direct, isNotNull, reason: 'no running server answered');
    expect({
      for (final f in direct!) 'lib/bad.dart:${f.line} ${f.rule}',
    }, expected);

    // …and the hook prints its findings for Claude.
    final clock = Stopwatch()..start();
    final hook = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/jankdoc_check.dart',
      '--hook',
    ]);
    hook.stdin.write(
      jsonEncode({
        'tool_name': 'Edit',
        'tool_input': {'file_path': bad},
        'cwd': demo,
      }),
    );
    await hook.stdin.close();
    final err = await hook.stderr.transform(utf8.decoder).join();
    expect(await hook.exitCode, 2);
    final reported = {
      for (final m in RegExp(
        r'^(lib/bad\.dart):(\d+):\d+ \[jankdoc_lints/(\w+)\]',
        multiLine: true,
      ).allMatches(err))
        '${m[1]}:${m[2]} ${m[3]}',
    };
    expect(reported, expected);
    printOnFailure('hook: ${clock.elapsedMilliseconds} ms');
  });
}
