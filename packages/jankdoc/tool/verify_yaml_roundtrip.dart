/// Round-trip verification: parses each YAML file under jankdoc-kb/entries/,
/// reconstructs a [KbEntry], and compares it byte-for-byte against the
/// corresponding entry in the in-source [kbCatalog].
///
/// Exits non-zero on any mismatch and prints a unified diff of the JSON.
///
/// Usage:
///   dart run packages/jankdoc/tool/verify_yaml_roundtrip.dart
///   dart run packages/jankdoc/tool/verify_yaml_roundtrip.dart --in ../jankdoc-kb/entries
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:yaml/yaml.dart';

import '../lib/src/kb/kb_catalog.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('in',
        defaultsTo: '../jankdoc-kb/entries',
        help: 'Input directory containing entries/<category>/<id>.yaml')
    ..addFlag('help', abbr: 'h', negatable: false);

  final opts = parser.parse(args);
  if (opts['help'] as bool) {
    stdout.writeln('Verify jankdoc-kb YAML round-trips against kb_catalog.dart.\n');
    stdout.writeln(parser.usage);
    return;
  }

  final inDir = Directory(opts['in'] as String).absolute;
  if (!inDir.existsSync()) {
    stderr.writeln('[verify] input dir not found: ${inDir.path}');
    exit(2);
  }

  // Build a {id → KbEntry} lookup for the source of truth.
  final source = {for (final e in kbCatalog) e.id: e};

  // Walk the YAML tree.
  final yamlFiles = inDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))
      .toList();

  if (yamlFiles.isEmpty) {
    stderr.writeln('[verify] no YAML files found under ${inDir.path}');
    exit(2);
  }

  stdout.writeln('[verify] checking ${yamlFiles.length} file(s) against '
      '${source.length} catalog entries');

  var mismatches = 0;
  var missingFromCatalog = 0;
  var seenIds = <String>{};

  for (final file in yamlFiles) {
    final raw = file.readAsStringSync();
    final yamlDoc = loadYaml(raw);
    if (yamlDoc is! Map) {
      stderr.writeln('[verify] ${file.path}: not a YAML mapping');
      mismatches++;
      continue;
    }
    final json = _toPlainMap(yamlDoc) as Map<String, dynamic>;

    final id = json['id'] as String?;
    if (id == null) {
      stderr.writeln('[verify] ${file.path}: missing "id" field');
      mismatches++;
      continue;
    }
    seenIds.add(id);

    final sourceEntry = source[id];
    if (sourceEntry == null) {
      stderr.writeln('[verify] ${file.path}: id "$id" not in kbCatalog');
      missingFromCatalog++;
      continue;
    }

    // Reconstruct KbEntry from the YAML.
    final KbEntry reconstructed;
    try {
      reconstructed = KbEntry.fromJson(json);
    } catch (e) {
      stderr.writeln('[verify] ${file.path}: KbEntry.fromJson failed: $e');
      mismatches++;
      continue;
    }

    // Compare via canonical JSON.
    final sourceJson = _canonical(sourceEntry.toJson());
    final reconstructedJson = _canonical(reconstructed.toJson());
    if (sourceJson != reconstructedJson) {
      stderr.writeln('[verify] ${file.path}: round-trip mismatch for "$id"');
      stderr.writeln('  source:        $sourceJson');
      stderr.writeln('  reconstructed: $reconstructedJson');
      mismatches++;
    }
  }

  // Catch entries that exist in kbCatalog but have no YAML file.
  final missingFromYaml =
      source.keys.where((id) => !seenIds.contains(id)).toList();
  for (final id in missingFromYaml) {
    stderr.writeln('[verify] catalog entry "$id" has no YAML file');
  }

  final totalProblems = mismatches + missingFromCatalog + missingFromYaml.length;
  if (totalProblems == 0) {
    stdout.writeln('[verify] ✓ all ${yamlFiles.length} entries round-trip cleanly');
    exit(0);
  } else {
    stderr.writeln('[verify] ✗ $totalProblems problem(s) found:');
    stderr.writeln('  - $mismatches round-trip mismatches');
    stderr.writeln('  - $missingFromCatalog YAML entries not in kbCatalog');
    stderr.writeln('  - ${missingFromYaml.length} kbCatalog entries with no YAML');
    exit(1);
  }
}

/// Recursively convert YamlMap/YamlList to plain Dart Map/List for KbEntry.fromJson.
dynamic _toPlainMap(dynamic node) {
  if (node is YamlMap) {
    return <String, dynamic>{
      for (final entry in node.entries) entry.key.toString(): _toPlainMap(entry.value),
    };
  }
  if (node is YamlList) {
    return node.map(_toPlainMap).toList();
  }
  return node;
}

/// Stable JSON representation (sorted keys, recursively).
String _canonical(Object? value) => jsonEncode(_sortKeys(value));

dynamic _sortKeys(dynamic value) {
  if (value is Map) {
    final sorted = <String, dynamic>{};
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    for (final k in keys) {
      sorted[k] = _sortKeys(value[k]);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_sortKeys).toList();
  }
  return value;
}
