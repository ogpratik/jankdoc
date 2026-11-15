// JSON-RPC / MCP handling of jankdoc_mcp, with a fake checker.
import 'dart:convert';
import 'dart:io';

import 'package:jankdoc_lints/src/agent/findings.dart';
import 'package:jankdoc_lints/src/agent/mcp_server.dart';
import 'package:test/test.dart';

class FakeChecker implements Checker {
  final calls = <String>[];
  List<Finding> findings = const [];
  CheckException? fail;

  @override
  Future<CheckResult> checkFile(String path) => _run('file $path');

  @override
  Future<CheckResult> checkProject(String directory) =>
      _run('project $directory');

  Future<CheckResult> _run(String call) async {
    calls.add(call);
    if (fail case final e?) throw e;
    return CheckResult(
      findings: findings,
      filesChecked: 1,
      elapsed: const Duration(milliseconds: 12),
      unverified: const [],
    );
  }
}

void main() {
  late Directory project;
  late FakeChecker checker;
  late McpServer server;

  setUp(() {
    project = Directory.systemTemp.createTempSync('jankdoc_mcp_test');
    project = Directory(project.resolveSymbolicLinksSync());
    File('${project.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('// a');
    checker = FakeChecker();
    server = McpServer(checker, workingDirectory: project.path);
  });

  tearDown(() => project.deleteSync(recursive: true));

  Future<Map<String, Object?>?> send(Object message) async {
    final out = await server.handleLine(jsonEncode(message));
    return out == null ? null : jsonDecode(out) as Map<String, Object?>;
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?>? params,
    int id = 1,
  ]) async => (await send({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': ?params,
  }))!;

  Future<Map<String, Object?>> callTool(
    String name,
    Map<String, Object?> args,
  ) async {
    final response = await request('tools/call', {
      'name': name,
      'arguments': args,
    });
    return response['result'] as Map<String, Object?>;
  }

  String text(Map<String, Object?> result) =>
      ((result['content'] as List).single as Map)['text'] as String;

  group('initialize', () {
    test('echoes a supported protocol version', () async {
      final r = await request('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 't', 'version': '1'},
      });
      expect(r['id'], 1);
      final result = r['result'] as Map;
      expect(result['protocolVersion'], '2024-11-05');
      expect(result['capabilities'], {
        'tools': {'listChanged': false},
      });
      expect((result['serverInfo'] as Map)['name'], 'jankdoc');
    });

    test('answers an unknown version with the newest it supports', () async {
      final r = await request('initialize', {'protocolVersion': '1999-01-01'});
      expect(
        (r['result'] as Map)['protocolVersion'],
        supportedProtocolVersions.first,
      );
    });
  });

  test('ping returns an empty result', () async {
    expect((await request('ping'))['result'], <String, Object?>{});
  });

  test('tools/list describes the three tools', () async {
    final tools =
        ((await request('tools/list'))['result'] as Map)['tools'] as List;
    expect(tools.map((t) => (t as Map)['name']), [
      'check_file',
      'check_project',
      'explain_pattern',
    ]);
    for (final t in tools.cast<Map>()) {
      expect(t['description'], isA<String>());
      expect((t['inputSchema'] as Map)['type'], 'object');
    }
    final checkFile = tools.first as Map;
    expect((checkFile['inputSchema'] as Map)['required'], ['path']);
  });

  group('JSON-RPC errors', () {
    test('parse error', () async {
      final r = jsonDecode((await server.handleLine('{not json'))!) as Map;
      expect(r['id'], isNull);
      expect((r['error'] as Map)['code'], JsonRpcError.parseError);
    });

    test('invalid request keeps the id', () async {
      final r = (await send({'id': 7, 'method': 'ping'}))!;
      expect(r['id'], 7);
      expect((r['error'] as Map)['code'], JsonRpcError.invalidRequest);
    });

    test('unknown method', () async {
      final r = await request('resources/list');
      expect((r['error'] as Map)['code'], JsonRpcError.methodNotFound);
    });

    test('unknown tool', () async {
      final r = await request('tools/call', {'name': 'nope'});
      expect((r['error'] as Map)['code'], JsonRpcError.invalidParams);
    });

    test('string ids round-trip', () async {
      final r = (await send({
        'jsonrpc': '2.0',
        'id': 'abc',
        'method': 'ping',
      }))!;
      expect(r['id'], 'abc');
    });
  });

  test('notifications get no response', () async {
    expect(
      await send({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      isNull,
    );
    expect(await send({'jsonrpc': '2.0', 'method': 'ping'}), isNull);
    expect(await server.handleLine('   '), isNull);
  });

  test('client responses are ignored', () async {
    expect(await send({'jsonrpc': '2.0', 'id': 3, 'result': {}}), isNull);
  });

  test('batches get a batch of responses', () async {
    final out = await server.handleLine(
      jsonEncode([
        {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'nope'},
      ]),
    );
    final responses = (jsonDecode(out!) as List).cast<Map>();
    expect(responses.map((r) => r['id']), [1, 2]);
  });

  group('check_file', () {
    test('resolves relative paths against the working directory', () async {
      final result = await callTool('check_file', {'path': 'lib/a.dart'});
      expect(result['isError'], false);
      expect(checker.calls, ['file ${project.path}/lib/a.dart']);
      expect(text(result), contains('no issues in lib/a.dart'));
    });

    test('reports findings as text and structured content', () async {
      await request('initialize', {'protocolVersion': '2025-06-18'});
      checker.findings = [
        Finding(
          rule: 'non_lazy_list',
          file: '${project.path}/lib/a.dart',
          line: 3,
          column: 5,
          message: "'ListView' builds every child eagerly.",
          fix: "Use 'ListView.builder'.",
        ),
      ];
      final result = await callTool('check_file', {
        'path': '${project.path}/lib/a.dart',
      });
      expect(
        text(result),
        allOf(
          contains('1 issue(s) in lib/a.dart'),
          contains(
            "lib/a.dart:3:5 [jankdoc_lints/non_lazy_list] 'ListView' builds",
          ),
          contains("fix: Use 'ListView.builder'."),
        ),
      );
      final data = result['structuredContent'] as Map;
      expect(data['filesChecked'], 1);
      expect(data['elapsedMs'], 12);
      expect(data['findings'], [
        {
          'rule': 'jankdoc_lints/non_lazy_list',
          'file': '${project.path}/lib/a.dart',
          'line': 3,
          'column': 5,
          'message': "'ListView' builds every child eagerly.",
          'fix': "Use 'ListView.builder'.",
          'pattern': 'listview-non-lazy',
        },
      ]);
    });

    test('no structuredContent before protocol 2025-06-18', () async {
      await request('initialize', {'protocolVersion': '2025-03-26'});
      final result = await callTool('check_file', {'path': 'lib/a.dart'});
      expect(result.containsKey('structuredContent'), isFalse);
    });

    test('bad paths are tool errors, not protocol errors', () async {
      for (final args in [
        <String, Object?>{},
        {'path': 'lib/missing.dart'},
        {'path': 'pubspec.yaml'},
      ]) {
        final result = await callTool('check_file', args);
        expect(result['isError'], true, reason: '$args');
      }
      expect(checker.calls, isEmpty);
    });

    test('a checker failure is a tool error', () async {
      checker.fail = CheckException('jankdoc_lints is not enabled');
      final result = await callTool('check_file', {'path': 'lib/a.dart'});
      expect(result['isError'], true);
      expect(text(result), 'jankdoc_lints is not enabled');
    });
  });

  test('check_project defaults to the working directory', () async {
    final result = await callTool('check_project', {});
    expect(result['isError'], false);
    expect(checker.calls, ['project ${project.path}']);
    await callTool('check_project', {'path': 'lib'});
    expect(checker.calls.last, 'project ${project.path}/lib');
    expect(
      (await callTool('check_project', {'path': 'nope'}))['isError'],
      true,
    );
  });

  group('explain_pattern', () {
    test('accepts rule names and KB pattern ids', () async {
      await request('initialize', {'protocolVersion': '2025-06-18'});
      for (final id in [
        'non_lazy_list',
        'jankdoc_lints/non_lazy_list',
        'listview-non-lazy',
      ]) {
        final result = await callTool('explain_pattern', {'pattern_id': id});
        expect(result['isError'], false, reason: id);
        final data = result['structuredContent'] as Map;
        expect(data['pattern'], 'listview-non-lazy');
        expect(data['rule'], 'jankdoc_lints/non_lazy_list');
        final fix = data['fix'] as Map;
        expect(fix['before'], contains('List.generate'));
        expect(fix['after'], contains('ListView.builder'));
        expect(text(result), contains('```dart'));
      }
    });

    test('every rule has an explanation', () async {
      for (final rule in jankdocRules.keys) {
        final result = await callTool('explain_pattern', {'pattern_id': rule});
        expect(result['isError'], false, reason: rule);
      }
    });

    test('unknown ids list the known ones', () async {
      final result = await callTool('explain_pattern', {'pattern_id': 'x'});
      expect(result['isError'], true);
      expect(text(result), contains('setstate_in_build'));
    });
  });
}
