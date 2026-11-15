// Project lookups shared by jankdoc_mcp and jankdoc_check: which project a
// file belongs to, and what its analysis_options.yaml says.
//
// No `package:analyzer` imports: the hook imports this and must start fast.
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';

/// The project a path belongs to: the nearest ancestor (or [path] itself)
/// with both `pubspec.yaml` and `analysis_options.yaml`, else the nearest
/// with `pubspec.yaml`.
String? projectRootFor(String path) {
  String? pubspecOnly;
  for (Directory? d = _dirOf(path).absolute; d != null; d = d.parent) {
    final hasPubspec = File('${d.path}/pubspec.yaml').existsSync();
    if (hasPubspec && File('${d.path}/analysis_options.yaml').existsSync()) {
      return d.path;
    }
    if (hasPubspec) pubspecOnly ??= d.path;
    if (d.parent.path == d.path) break;
  }
  return pubspecOnly;
}

/// Whether the jankdoc_lints plugin is enabled for [path].
bool pluginEnabledFor(String path) => ProjectOptions().pluginEnabled(path);

/// Reads analysis options and pubspecs, each at most once per directory.
///
/// Make one per check, so an edit to analysis_options.yaml or pubspec.yaml
/// is picked up by the next check.
class ProjectOptions {
  final _options = <String, _Options?>{};
  final _flutter = <String, bool>{};

  /// The text of the analysis_options.yaml that applies to [path] (the
  /// nearest one in an enclosing directory), or null if there is none.
  String? analysisOptionsText(String path) => _nearest(_dirOf(path).path)?.text;

  /// Whether the jankdoc_lints plugin is enabled for [path].
  bool pluginEnabled(String path) =>
      analysisOptionsText(
        path,
      )?.contains(RegExp(r'^\s+jankdoc_lints\s*:', multiLine: true)) ??
      false;

  /// Whether [file] matches an `analyzer: exclude:` glob of the options that
  /// apply to it. The analysis server never reports on excluded files.
  bool excluded(String file) {
    final options = _nearest(_dirOf(file).path);
    if (options == null || !file.startsWith('${options.dir}/')) return false;
    final relative = file.substring(options.dir.length + 1);
    return options.excludes.any((g) => g.matches(relative));
  }

  /// Whether [path] is in a package that depends on Flutter (so `dart:ui`
  /// resolves). Unknown counts as Flutter.
  bool isFlutterPackage(String path) {
    for (Directory? d = _dirOf(path).absolute; d != null; d = d.parent) {
      final known = _flutter[d.path];
      if (known != null) return known;
      final pubspec = File('${d.path}/pubspec.yaml');
      if (pubspec.existsSync()) {
        return _flutter[d.path] = _dependsOnFlutter(pubspec);
      }
      if (d.parent.path == d.path) break;
    }
    return true;
  }

  _Options? _nearest(String dir) {
    if (_options.containsKey(dir)) return _options[dir];
    final file = File('$dir/analysis_options.yaml');
    final parent = Directory(dir).parent.path;
    return _options[dir] = file.existsSync()
        ? _Options(dir, file.readAsStringSync())
        : parent == dir
        ? null
        : _nearest(parent);
  }
}

class _Options {
  _Options(this.dir, this.text);

  final String dir;
  final String text;

  late final List<Glob> excludes = () {
    try {
      final analyzer = (loadYaml(text) as Map?)?['analyzer'];
      final exclude = analyzer is Map ? analyzer['exclude'] : null;
      return [
        if (exclude is List)
          for (final pattern in exclude)
            if (pattern is String) Glob(pattern),
      ];
    } on Object {
      return const <Glob>[];
    }
  }();
}

bool _dependsOnFlutter(File pubspec) {
  try {
    final dependencies =
        (loadYaml(pubspec.readAsStringSync()) as Map?)?['dependencies'];
    return dependencies is Map && dependencies.containsKey('flutter');
  } on Object {
    return true;
  }
}

Directory _dirOf(String path) => FileSystemEntity.isDirectorySync(path)
    ? Directory(path)
    : File(path).parent;
