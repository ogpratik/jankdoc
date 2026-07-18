/// Verifies a built jankdoc-kb bundle loads cleanly via FilesystemKbBundleLoader.
///
/// Usage:
///   dart run packages/jankdoc/tool/verify_bundle.dart \
///     --bundle ../jankdoc-kb/dist/jankdoc-kb-1.0.0.jankdoc-kb
library;

import 'dart:io';

import 'package:args/args.dart';

import '../lib/src/kb/kb_bundle_loader.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('bundle',
        help: 'Path to the .jankdoc-kb file to verify. Required.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final opts = parser.parse(args);
  if (opts['help'] as bool) {
    stdout.writeln('Verify a jankdoc-kb bundle loads via FilesystemKbBundleLoader.\n');
    stdout.writeln(parser.usage);
    return;
  }

  final bundlePath = opts['bundle'] as String?;
  if (bundlePath == null) {
    stderr.writeln('[verify-bundle] --bundle is required');
    exit(2);
  }

  final loader = FilesystemKbBundleLoader();
  try {
    final bundle = await loader.loadFromPath(bundlePath);
    stdout
      ..writeln('[verify-bundle] ✓ loaded $bundlePath')
      ..writeln('[verify-bundle]   version:    ${bundle.version}')
      ..writeln('[verify-bundle]   channel:    ${bundle.channel.name}')
      ..writeln('[verify-bundle]   published:  ${bundle.publishedAt}')
      ..writeln('[verify-bundle]   entries:    ${bundle.entries.length}')
      ..writeln('[verify-bundle]   embeddings: ${bundle.embeddings.vectors.length} '
          '(model: "${bundle.embeddings.modelId}", '
          'dims: ${bundle.embeddings.dimensions})')
      ..writeln('[verify-bundle]   checksum:   ${bundle.checksum.substring(0, 16)}…')
      ..writeln('[verify-bundle]   flutter:    ${bundle.flutterVersionRange}')
      ..writeln('[verify-bundle]   dart sdk:   ${bundle.dartSdkConstraint}');

    // Spot-check three entries.
    for (final id in [
      'animated-builder-rebuild-storm',
      'sync-io-on-ui-thread',
      'impeller-scroll-jank-ios',
    ]) {
      final entry = bundle.findEntry(id);
      if (entry == null) {
        stderr.writeln('[verify-bundle] ✗ missing expected entry: $id');
        exit(1);
      }
      stdout.writeln('[verify-bundle]   ✓ found $id — "${entry.title}"');
    }
  } catch (e, st) {
    stderr.writeln('[verify-bundle] ✗ load failed: $e');
    stderr.writeln(st);
    exit(1);
  }
}
