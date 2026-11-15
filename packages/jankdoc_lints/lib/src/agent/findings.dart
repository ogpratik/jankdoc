// What the agent integrations (MCP server, `jankdoc_check`) report.
//
// Deliberately free of `package:analyzer` imports: `jankdoc_check --hook`
// imports this and runs via `dart run` on every edit, so it must compile fast.

/// The `jankdoc_lints` rules, each mapped to its JankDoc KB pattern id.
const jankdocRules = {
  'setstate_in_build': 'setstate-in-build',
  'sync_io_in_build': 'sync-io-on-ui-thread',
  'json_decode_in_build': 'json-decode-ui-thread',
  'animated_opacity_widget': 'raster-overdraw-opacity',
  'animated_builder_per_item': 'animated-builder-rebuild-storm',
  'clip_save_layer': 'raster-overdraw-clip',
  'non_lazy_list': 'listview-non-lazy',
};

/// One JankDoc diagnostic in a source file.
class Finding {
  const Finding({
    required this.rule,
    required this.file,
    required this.line,
    required this.column,
    required this.message,
    required this.fix,
  });

  /// From a `dart analyze --format=json` diagnostic (1-based positions).
  factory Finding.fromAnalyzeJson(Map<String, Object?> d) {
    final location = d['location'] as Map<String, Object?>;
    final start =
        (location['range'] as Map<String, Object?>)['start']
            as Map<String, Object?>;
    return Finding(
      rule: d['code'] as String,
      file: location['file'] as String,
      line: start['line'] as int,
      column: start['column'] as int,
      message: d['problemMessage'] as String? ?? '',
      fix: d['correctionMessage'] as String? ?? '',
    );
  }

  /// From an LSP `Diagnostic` (0-based positions; the analysis server sends
  /// the correction as the second paragraph of `message`).
  factory Finding.fromLsp(Map<String, Object?> d, String file) {
    final start =
        (d['range'] as Map<String, Object?>)['start'] as Map<String, Object?>;
    final text = d['message'] as String? ?? '';
    final split = text.indexOf('\n');
    return Finding(
      rule: d['code'] as String,
      file: file,
      line: (start['line'] as int) + 1,
      column: (start['character'] as int) + 1,
      message: split < 0 ? text : text.substring(0, split),
      fix: split < 0 ? '' : text.substring(split + 1).trim(),
    );
  }

  factory Finding.fromJson(Map<String, Object?> json) => Finding(
    rule: (json['rule'] as String).replaceFirst('jankdoc_lints/', ''),
    file: json['file'] as String,
    line: json['line'] as int,
    column: json['column'] as int,
    message: json['message'] as String,
    fix: json['fix'] as String,
  );

  /// Bare rule name, e.g. `non_lazy_list`.
  final String rule;

  /// Absolute path.
  final String file;

  /// 1-based.
  final int line;

  /// 1-based.
  final int column;
  final String message;
  final String fix;

  /// The JankDoc KB pattern id, for `explain_pattern`.
  String? get pattern => jankdocRules[rule];

  Map<String, Object?> toJson() => {
    'rule': 'jankdoc_lints/$rule',
    'file': file,
    'line': line,
    'column': column,
    'message': message,
    'fix': fix,
    'pattern': pattern,
  };

  /// `lib/a.dart:3:5 [jankdoc_lints/rule] message` + an indented fix line;
  /// [file] is shown relative to [root] when inside it.
  String format([String? root]) {
    var path = file;
    if (root != null && path.startsWith('$root/')) {
      path = path.substring(root.length + 1);
    }
    return '$path:$line:$column [jankdoc_lints/$rule] $message\n'
        '    fix: $fix';
  }

  @override
  String toString() => format();
}

/// Sorts by file, then position.
List<Finding> sortFindings(Iterable<Finding> findings) =>
    findings.toList()..sort(
      (a, b) => a.file != b.file
          ? a.file.compareTo(b.file)
          : a.line != b.line
          ? a.line - b.line
          : a.column - b.column,
    );

/// Thrown when a check cannot run at all (as opposed to finding nothing).
class CheckException implements Exception {
  CheckException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CheckResult {
  const CheckResult({
    required this.findings,
    required this.filesChecked,
    required this.elapsed,
    required this.unverified,
  });

  final List<Finding> findings;
  final int filesChecked;
  final Duration elapsed;

  /// Files whose result came from the idle-and-quiet fallback rather than a
  /// probe-confirmed plugin publish.
  final List<String> unverified;
}
