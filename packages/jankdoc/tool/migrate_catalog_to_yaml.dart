/// One-shot migration: read the built-in [kbCatalog] and emit one YAML file
/// per entry into the sibling `jankdoc-kb/entries/<category>/<id>.yaml` tree.
///
/// Usage (from the monorepo root):
///   dart run packages/jankdoc/tool/migrate_catalog_to_yaml.dart
///   dart run packages/jankdoc/tool/migrate_catalog_to_yaml.dart --out ../jankdoc-kb/entries
///
/// Idempotent: overwrites existing files. Run again after editing the catalog.
///
/// After Phase 1.1.4 verifies the output, this script can be deleted — the
/// jankdoc-kb repo becomes the source of truth and `kb_catalog.dart` is
/// regenerated from bundles via `KbSeeder.seedFromBundle`.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

import '../lib/src/kb/kb_catalog.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('out',
        defaultsTo: '../jankdoc-kb/entries',
        help: 'Output directory for entries/<category>/<id>.yaml')
    ..addFlag('dry-run',
        defaultsTo: false,
        negatable: false,
        help: 'Print what would be written, do not touch disk.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final opts = parser.parse(args);
  if (opts['help'] as bool) {
    stdout.writeln('Migrate kb_catalog.dart entries to jankdoc-kb YAML.\n');
    stdout.writeln(parser.usage);
    return;
  }

  final outDirArg = opts['out'] as String;
  final dryRun = opts['dry-run'] as bool;

  // Resolve relative to the script's invocation directory.
  final outDir = Directory(outDirArg).absolute;
  if (!dryRun) {
    outDir.createSync(recursive: true);
  }

  stdout.writeln('[migrate] writing ${kbCatalog.length} entries to ${outDir.path}');

  var written = 0;
  for (final entry in kbCatalog) {
    final subdir = Directory('${outDir.path}/${entry.category.name}');
    if (!dryRun) subdir.createSync(recursive: true);

    final file = File('${subdir.path}/${entry.id}.yaml');
    final yaml = _emitEntryYaml(entry);

    if (dryRun) {
      stdout.writeln('--- ${file.path}');
      stdout.writeln(yaml);
    } else {
      file.writeAsStringSync(yaml);
      written++;
    }
  }

  stdout.writeln('[migrate] done — $written file(s) written.');
}

// ─── YAML emitter (purpose-built for the KbEntry schema) ──────────────────────

/// Custom emitter rather than a generic YAML library. Reason: we want exact
/// control over multi-line block scalars (using `|` literal style for prose
/// fields like `description` and `fix_guidance`) and predictable key order
/// for clean diffs. `KbEntry.toJson()` produces the right key set; we walk
/// it in a fixed canonical order.

const _orderedKeys = <String>[
  'id',
  'category',
  'channel',
  'severity',
  'title',
  'description',
  'flutter_version_range',
  'introduced_in',
  'detection_signals',
  'sources',
  'fix_guidance',
  'expected_improvement',
  'deprecated',
  'deprecation_reason',
  'superseded_by',
];

const _detectionSignalKeys = <String>[
  'widget_types',
  'stack_patterns',
  'min_ui_thread_ms',
  'min_raster_thread_ms',
  'requires_impeller',
  'min_rebuild_count',
  'embed_chunks',
];

const _expectedImprovementKeys = <String>[
  'min_reduction_percent',
  'max_reduction_percent',
  'description',
];

/// Multi-line fields: emit using `|` block-literal style. Other strings: inline.
const _blockLiteralFields = <String>{
  'description',
  'fix_guidance',
};

String _emitEntryYaml(KbEntry entry) {
  final json = entry.toJson();
  final buf = StringBuffer()
    ..writeln('# ${entry.title}')
    ..writeln('# Auto-generated from kb_catalog.dart by migrate_catalog_to_yaml.dart')
    ..writeln('# Edit this file to update the entry. See ../../SCHEMA.md.')
    ..writeln();

  for (final key in _orderedKeys) {
    if (!json.containsKey(key)) continue;
    final value = json[key];
    if (value == null) continue;

    if (key == 'detection_signals' && value is Map) {
      buf.writeln('$key:');
      _emitNestedMap(buf, value.cast<String, dynamic>(), _detectionSignalKeys,
          indent: 2);
    } else if (key == 'expected_improvement' && value is Map) {
      buf.writeln('$key:');
      _emitNestedMap(
          buf, value.cast<String, dynamic>(), _expectedImprovementKeys,
          indent: 2,
          blockLiteralFields: {'description'});
    } else if (value is List) {
      _emitList(buf, key, value, indent: 0);
    } else if (_blockLiteralFields.contains(key) &&
        value is String &&
        value.contains('\n')) {
      _emitBlockLiteral(buf, key, value, indent: 0);
    } else {
      buf.writeln('$key: ${_scalar(value)}');
    }
  }

  return buf.toString();
}

void _emitNestedMap(
  StringBuffer buf,
  Map<String, dynamic> map,
  List<String> orderedKeys, {
  required int indent,
  Set<String> blockLiteralFields = const {},
}) {
  final pad = ' ' * indent;
  for (final key in orderedKeys) {
    if (!map.containsKey(key)) continue;
    final value = map[key];
    if (value == null) continue;

    if (value is List) {
      _emitList(buf, key, value, indent: indent);
    } else if (blockLiteralFields.contains(key) &&
        value is String &&
        value.contains('\n')) {
      _emitBlockLiteral(buf, key, value, indent: indent);
    } else {
      buf.writeln('$pad$key: ${_scalar(value)}');
    }
  }
}

void _emitList(StringBuffer buf, String key, List<dynamic> items,
    {required int indent}) {
  final pad = ' ' * indent;
  if (items.isEmpty) {
    buf.writeln('$pad$key: []');
    return;
  }
  buf.writeln('$pad$key:');
  for (final item in items) {
    if (item is String && item.contains('\n')) {
      // Multi-line list item — use block-literal with strip indicator
      // so the trailing newline is not preserved.
      buf.writeln('$pad  - |-');
      final trimmed = item.replaceAll(RegExp(r'\n+$'), '');
      for (final line in trimmed.split('\n')) {
        buf.writeln('$pad      $line');
      }
    } else {
      buf.writeln('$pad  - ${_scalar(item)}');
    }
  }
}

void _emitBlockLiteral(StringBuffer buf, String key, String value,
    {required int indent}) {
  final pad = ' ' * indent;
  // Use `|-` (strip chomping indicator) so the trailing newline is NOT
  // preserved on parse. Dart source strings have no trailing newline,
  // so this round-trips losslessly.
  buf.writeln('$pad$key: |-');
  final trimmed = value.replaceAll(RegExp(r'\n+$'), '');
  for (final line in trimmed.split('\n')) {
    buf.writeln('$pad  $line');
  }
}

/// Render a scalar value (string/number/bool) safely.
String _scalar(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  final s = value.toString();
  // Quote strings that contain YAML-significant characters or look like other types.
  if (s.isEmpty || _needsQuoting(s)) {
    return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
  return s;
}

bool _needsQuoting(String s) {
  // Quote strings that:
  //   - start with YAML indicators
  //   - look like booleans/null
  //   - contain colons, hashes, or other unsafe chars
  if (s.startsWith('-') || s.startsWith('?') || s.startsWith(':') ||
      s.startsWith('[') || s.startsWith('{') || s.startsWith('>') ||
      s.startsWith('|') || s.startsWith('!') || s.startsWith('&') ||
      s.startsWith('*') || s.startsWith('@') || s.startsWith('`')) {
    return true;
  }
  const reserved = {'true', 'false', 'null', 'yes', 'no', 'on', 'off', '~'};
  if (reserved.contains(s.toLowerCase())) return true;
  if (s.contains(': ') || s.contains(' #') || s.contains('\t')) return true;
  if (s.contains('"') || s.contains("'") || s.contains('\n')) return true;
  return false;
}
