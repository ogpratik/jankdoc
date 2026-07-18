import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Prints a 5-line startup banner summarizing daemon, LLM tier, KB, and rules.
///
/// Each line is colorized based on real state fetched from the daemon's
/// `/info` endpoint:
///
/// - Green ✓ — component is healthy
/// - Yellow ⚠ — component is degraded but functional (e.g. seeder fallback)
/// - Red ✗ — component is unavailable (e.g. Ollama not reachable)
///
/// Colors are ANSI escape sequences; suppressed when stdout is not a terminal
/// (redirected to a file, CI log capture, etc.) or when `JANKDOC_QUIET` /
/// `NO_COLOR` env vars are set.
///
/// Set the `JANKDOC_QUIET` env variable to skip the banner entirely — useful
/// for CI or benchmark runs where startup output is noise.
final class StartupBanner {
  StartupBanner({
    required this.port,
    http.Client? client,
    bool? quiet,
    StringSink? sink,
  })  : _client = client ?? http.Client(),
        _quiet = quiet ?? _envQuiet(),
        _out = sink ?? stdout;

  final int port;
  final http.Client _client;
  final bool _quiet;
  final StringSink _out;

  static bool _envQuiet() {
    final v = Platform.environment['JANKDOC_QUIET'];
    return v != null && v != '0' && v.toLowerCase() != 'false';
  }

  /// Print the banner. Never throws — network failures degrade to a minimal
  /// two-line message so the user always sees *something* on startup.
  Future<void> render() async {
    if (_quiet) return;

    Map<String, dynamic>? info;
    try {
      final response = await _client
          .get(Uri.parse('http://127.0.0.1:$port/info'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        info = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } on Object {
      // Fall through — info stays null and we print the degraded banner.
    }

    _writeLine(
      _StatusLine.ok('[JankDoc] daemon http://127.0.0.1:$port'),
    );

    if (info == null) {
      _writeLine(const _StatusLine.warn(
        '[JankDoc] daemon /info unavailable — banner incomplete',
      ));
      return;
    }

    final llmAvailable = info['llm_available'] as bool? ?? false;
    final model = info['model'] as String? ?? '?';
    final ollamaUrl = info['ollama_url'] as String? ?? '';
    if (llmAvailable) {
      _writeLine(_StatusLine.ok(
        '[JankDoc] LLM tier: enabled ($model @ $ollamaUrl)',
      ));
    } else {
      _writeLine(_StatusLine.err(
        '[JankDoc] LLM tier: disabled — install Ollama at https://ollama.com '
        'and run `ollama pull $model` to enable',
      ));
    }

    final kbSource = info['kb_source'] as String? ?? 'seeder';
    final kbVersion = info['kb_version'] as String?;
    final kbEntries = info['kb_entries'] as int? ?? 0;
    if (kbSource == 'bundle') {
      _writeLine(_StatusLine.ok(
        '[JankDoc] KB: ${kbVersion ?? "unknown"} '
        '($kbEntries entries, bundle-loaded)',
      ));
    } else {
      _writeLine(_StatusLine.warn(
        '[JankDoc] KB: seeder fallback ($kbEntries entries) — '
        'no cached bundle found',
      ));
    }

    final rules = info['rules'] as int? ?? 0;
    _writeLine(_StatusLine.ok(
      '[JankDoc] Rules: $rules built-in',
    ));

    _writeLine(const _StatusLine.ok(
      '[JankDoc] ready — open Flutter DevTools → JankDoc tab',
    ));
  }

  void _writeLine(_StatusLine line) {
    if (_useColor) {
      _out.writeln('${line.colour}${line.glyph} ${line.body}$_reset');
    } else {
      _out.writeln('${line.glyph} ${line.body}');
    }
  }

  bool get _useColor {
    if (Platform.environment.containsKey('NO_COLOR')) return false;
    if (Platform.environment['JANKDOC_COLOR'] == '0') return false;
    // Only colorize when stdout is an actual terminal.
    return stdout.hasTerminal;
  }

  static const _reset = '\x1B[0m';
}

/// One coloured status line in the startup banner.
///
/// Glyph + colour convey severity at a glance: ✓ green (ok), ⚠ yellow (warn),
/// ✗ red (error). Kept as a value object so [StartupBanner] can render each
/// line uniformly.
final class _StatusLine {
  const _StatusLine.ok(this.body)
      : glyph = '✓',
        colour = '\x1B[32m'; // green
  const _StatusLine.warn(this.body)
      : glyph = '⚠',
        colour = '\x1B[33m'; // yellow
  const _StatusLine.err(this.body)
      : glyph = '✗',
        colour = '\x1B[31m'; // red

  final String glyph;
  final String colour;
  final String body;
}
