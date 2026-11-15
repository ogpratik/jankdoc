// The Model Context Protocol (MCP) side of `jankdoc_mcp`: JSON-RPC 2.0
// messages, one per line on stdio, exposing three tools to AI coding agents.
//
// Kept independent of the analysis machinery (see [Checker]) so the protocol
// handling is unit-testable without a language server.
import 'dart:convert';
import 'dart:io';

import 'findings.dart';
import 'patterns.dart';

const packageVersion = '1.0.0-beta.1';

/// Newest first. The server answers with the client's version when it is
/// listed here, else with the newest.
const supportedProtocolVersions = [
  '2025-11-25',
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];

/// Runs JankDoc checks; paths are absolute.
abstract interface class Checker {
  Future<CheckResult> checkFile(String path);
  Future<CheckResult> checkProject(String directory);
}

class JsonRpcError implements Exception {
  JsonRpcError(this.code, this.message);

  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  final int code;
  final String message;
}

class McpServer {
  McpServer(this._checker, {String? workingDirectory})
    : _cwd = (workingDirectory ?? Directory.current.path).replaceFirst(
        RegExp(r'(?<=.)/+$'),
        '',
      );

  final Checker _checker;
  final String _cwd;
  String _protocolVersion = supportedProtocolVersions.first;

  /// Handles one line of input; returns the line to write back, or null for
  /// notifications.
  Future<String?> handleLine(String line) async {
    if (line.trim().isEmpty) return null;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException catch (e) {
      return jsonEncode(
        _error(null, JsonRpcError(JsonRpcError.parseError, e.message)),
      );
    }
    // Batches were part of protocol 2025-03-26.
    if (message is List) {
      if (message.isEmpty) {
        return jsonEncode(
          _error(
            null,
            JsonRpcError(JsonRpcError.invalidRequest, 'Empty batch'),
          ),
        );
      }
      final responses = [
        for (final m in message) await handle(m),
      ].nonNulls.toList();
      return responses.isEmpty ? null : jsonEncode(responses);
    }
    final response = await handle(message);
    return response == null ? null : jsonEncode(response);
  }

  /// Handles one decoded JSON-RPC message; null for notifications.
  Future<Map<String, Object?>?> handle(Object? message) async {
    if (message is! Map<String, Object?> ||
        message['jsonrpc'] != '2.0' ||
        message['method'] is! String) {
      final id = message is Map ? message['id'] : null;
      // A response from the client (we never send requests) — ignore.
      if (message is Map &&
          message['method'] == null &&
          (message.containsKey('result') || message.containsKey('error'))) {
        return null;
      }
      return _error(
        id,
        JsonRpcError(JsonRpcError.invalidRequest, 'Not a JSON-RPC 2.0 request'),
      );
    }
    final id = message['id'];
    final isNotification = !message.containsKey('id');
    final method = message['method'] as String;
    final params = message['params'];
    try {
      final result = await _dispatch(
        method,
        params is Map<String, Object?> ? params : const {},
      );
      if (isNotification) return null;
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on JsonRpcError catch (e) {
      return isNotification ? null : _error(id, e);
    } on Object catch (e) {
      return isNotification
          ? null
          : _error(id, JsonRpcError(JsonRpcError.internalError, '$e'));
    }
  }

  Future<Object?> _dispatch(String method, Map<String, Object?> params) async {
    switch (method) {
      case 'initialize':
        final requested = params['protocolVersion'];
        _protocolVersion = supportedProtocolVersions.contains(requested)
            ? requested as String
            : supportedProtocolVersions.first;
        return {
          'protocolVersion': _protocolVersion,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {
            'name': 'jankdoc',
            'title': 'JankDoc',
            'version': packageVersion,
          },
          'instructions':
              'JankDoc finds Flutter code that causes jank (dropped frames). '
              'After editing Dart files, call check_file on each edited file '
              '(or check_project once at the end) and fix every finding '
              'before finishing. Use explain_pattern for background and a '
              'before/after fix.',
        };
      case 'ping':
        return <String, Object?>{};
      case 'tools/list':
        return {'tools': _tools};
      case 'tools/call':
        return _callTool(params);
      default:
        if (method.startsWith('notifications/')) return null;
        throw JsonRpcError(
          JsonRpcError.methodNotFound,
          'Method not found: $method',
        );
    }
  }

  List<Map<String, Object?>> get _tools => [
    {
      'name': 'check_file',
      'title': 'Check a Dart file for jank',
      'description':
          'Runs JankDoc on one Dart file as it is on disk and returns every '
          'jank-causing pattern it contains (rule, file:line:col, message, '
          'fix). Call after each edit to a Flutter .dart file and fix all '
          'findings. Fast: ~20-50 ms once warm.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'The .dart file, absolute or relative to the server\'s '
                'working directory.',
          },
        },
        'required': ['path'],
      },
      'annotations': {'readOnlyHint': true, 'openWorldHint': false},
    },
    {
      'name': 'check_project',
      'title': 'Check a Flutter project for jank',
      'description':
          'Runs JankDoc on every .dart file under a directory (a project or '
          'any folder in it) and returns all findings.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Directory to check, absolute or relative to the server\'s '
                'working directory. Defaults to the working directory.',
          },
        },
      },
      'annotations': {'readOnlyHint': true, 'openWorldHint': false},
    },
    {
      'name': 'explain_pattern',
      'title': 'Explain a JankDoc pattern',
      'description':
          'Explains a JankDoc jank pattern: why it drops frames, how to fix '
          'it, and before/after code. Accepts a rule name from a finding '
          '(e.g. non_lazy_list) or a JankDoc KB pattern id (e.g. '
          'listview-non-lazy).',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'pattern_id': {
            'type': 'string',
            'enum': knownPatternIds,
            'description': 'Rule name or KB pattern id.',
          },
        },
        'required': ['pattern_id'],
      },
      'annotations': {'readOnlyHint': true, 'openWorldHint': false},
    },
  ];

  Future<Map<String, Object?>> _callTool(Map<String, Object?> params) async {
    final name = params['name'];
    final rawArgs = params['arguments'];
    final args = rawArgs is Map<String, Object?> ? rawArgs : const {};
    switch (name) {
      case 'check_file':
        final path = args['path'];
        if (path is! String || path.isEmpty) {
          return _toolError('check_file needs a "path" argument.');
        }
        final file = _resolve(path);
        if (!file.endsWith('.dart')) {
          return _toolError('$file is not a .dart file.');
        }
        if (!File(file).existsSync()) {
          return _toolError('$file does not exist.');
        }
        final real = File(file).resolveSymbolicLinksSync();
        return _checkResult(() => _checker.checkFile(real), real);
      case 'check_project':
        final path = args['path'];
        final dir = _resolve(path is String && path.isNotEmpty ? path : '.');
        if (!Directory(dir).existsSync()) {
          return _toolError('$dir is not a directory.');
        }
        final real = Directory(dir).resolveSymbolicLinksSync();
        return _checkResult(() => _checker.checkProject(real), real);
      case 'explain_pattern':
        final id = args['pattern_id'];
        final explanation = id is String ? explainPattern(id) : null;
        if (explanation == null) {
          return _toolError(
            'Unknown pattern "${id ?? ''}". Known: '
            '${knownPatternIds.join(', ')}.',
          );
        }
        return _toolResult(explainPatternText(explanation), explanation);
      default:
        throw JsonRpcError(JsonRpcError.invalidParams, 'Unknown tool: $name');
    }
  }

  Future<Map<String, Object?>> _checkResult(
    Future<CheckResult> Function() run,
    String target,
  ) async {
    final CheckResult result;
    try {
      result = await run();
    } on CheckException catch (e) {
      return _toolError(e.message);
    } on ProcessException catch (e) {
      return _toolError(
        'Could not start `dart language-server` (${e.message}). Is the Dart '
        'or Flutter SDK on PATH?',
      );
    }
    final ms = result.elapsed.inMilliseconds;
    final shown = _relative(target);
    final text = StringBuffer();
    if (result.findings.isEmpty) {
      text.write(
        'JankDoc: no issues in $shown '
        '(${result.filesChecked} file(s), $ms ms).',
      );
    } else {
      text
        ..writeln(
          'JankDoc: ${result.findings.length} issue(s) in $shown '
          '(${result.filesChecked} file(s), $ms ms). Fix each one; '
          'explain_pattern gives background and a before/after fix.',
        )
        ..writeln()
        ..writeAll(result.findings.map((f) => f.format(_cwd)), '\n');
    }
    if (result.unverified.isNotEmpty) {
      text.write(
        '\n\nNote: ${result.unverified.length} file(s) could not be '
        'confirmed fresh (syntax errors, part files, or no Flutter '
        'dependency); their results may '
        'lag the last edit.',
      );
    }
    return _toolResult(text.toString(), {
      'findings': [for (final f in result.findings) f.toJson()],
      'filesChecked': result.filesChecked,
      'elapsedMs': ms,
      'unverified': result.unverified,
    });
  }

  Map<String, Object?> _toolResult(String text, Map<String, Object?> data) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    // structuredContent arrived in protocol 2025-06-18.
    if (_protocolVersion.compareTo('2025-06-18') >= 0)
      'structuredContent': data,
    'isError': false,
  };

  Map<String, Object?> _toolError(String text) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': true,
  };

  String _resolve(String path) {
    final base = Uri.directory(_cwd);
    var resolved = File.fromUri(base.resolveUri(Uri.file(path))).path;
    while (resolved.length > 1 && resolved.endsWith('/')) {
      resolved = resolved.substring(0, resolved.length - 1);
    }
    return resolved;
  }

  String _relative(String path) =>
      path == _cwd ? '.' : path.replaceFirst('$_cwd/', '');

  static Map<String, Object?> _error(Object? id, JsonRpcError e) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': e.code, 'message': e.message},
  };
}
