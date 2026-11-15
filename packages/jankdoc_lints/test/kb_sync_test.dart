// lib/src/agent/kb_data.dart must match the runtime package's KB catalog.
// (Compares data, not text, so `dart format` cannot break it.)
import 'dart:io';

import 'package:jankdoc_lints/src/agent/kb_data.dart';
import 'package:test/test.dart';

import '../tool/sync_kb.dart';

void main() {
  // `dart test` runs with the package root as the working directory.
  final root = Directory.current.path;
  final catalog = File(catalogPath(root));

  test(
    'kb_data.dart is up to date (run: dart run tool/sync_kb.dart)',
    () {
      expect(kbEntries, extractKb(catalog.readAsStringSync()));
    },
    skip: catalog.existsSync() ? false : 'not in the jankdoc repository',
  );
}
