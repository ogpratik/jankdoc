// JankDoc MCP server: lets any MCP-capable AI coding agent (Claude Code,
// Codex, Cursor, Copilot agent mode, Windsurf …) check Flutter code for jank.
//
//   jankdoc_mcp [project_dir]
//
// Speaks MCP over stdio (one JSON-RPC message per line). Tools:
//   check_file(path)             JankDoc findings for one .dart file
//   check_project(path?)         findings for every .dart file under a dir
//   explain_pattern(pattern_id)  KB explanation + before/after fix
//
// Keeps one `dart language-server` per project warm, so a check takes tens
// of milliseconds instead of a `dart analyze` run's seconds. [project_dir]
// (default: the working directory) is where relative paths resolve, and is
// analyzed at startup so the first check is fast too.
//
// While running, it also serves `jankdoc_check --hook` (see
// lib/src/agent/hook_endpoint.dart). Logs go to stderr; stdout is protocol.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jankdoc_lints/src/agent/checker.dart';
import 'package:jankdoc_lints/src/agent/hook_endpoint.dart';
import 'package:jankdoc_lints/src/agent/mcp_server.dart';
import 'package:jankdoc_lints/src/agent/warm_analyzer.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(
      'Usage: jankdoc_mcp [project_dir]\n\n'
      'JankDoc MCP server (stdio). Add it to your AI coding agent; see\n'
      'https://github.com/ogpratik/jankdoc/tree/main/packages/jankdoc_lints',
    );
    return;
  }
  final positional = args.where((a) => !a.startsWith('-')).toList();
  final cwd = Directory(
    positional.isNotEmpty ? positional.first : Directory.current.path,
  ).absolute.path;

  final endpoints = <HookEndpoint>[];
  final checker = WarmChecker(
    onStarted: (analyzer) async {
      stderr.writeln('jankdoc_mcp: analysis server ready for ${analyzer.root}');
      try {
        endpoints.add(
          await HookEndpoint.serve(
            analyzer.root,
            (path) async => pluginEnabledFor(path)
                ? (await analyzer.check([path])).findings
                : const [],
          ),
        );
      } on Object catch (e) {
        stderr.writeln('jankdoc_mcp: hook endpoint unavailable: $e');
      }
    },
  );
  final server = McpServer(checker, workingDirectory: cwd);

  var shuttingDown = false;
  Future<void> shutdown() async {
    if (shuttingDown) return;
    shuttingDown = true;
    for (final e in endpoints) {
      await e.close();
    }
    await checker.dispose();
    exit(0);
  }

  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }
  ProcessSignal.sigint.watch().listen((_) => shutdown());

  unawaited(
    checker.prewarm(cwd).catchError((Object e) {
      stderr.writeln('jankdoc_mcp: prewarm failed: $e');
    }),
  );

  final inFlight = <Future<void>>{};
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    late final Future<void> done;
    done = server
        .handleLine(line)
        .then((out) {
          if (out != null) stdout.write('$out\n');
        })
        .whenComplete(() => inFlight.remove(done));
    inFlight.add(done);
  }
  await Future.wait(inFlight);
  await shutdown();
}
