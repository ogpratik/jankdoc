import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:test/test.dart';

import '../../lib/src/kb/kb_bundle_loader.dart';

// ─── Bundle builder (copied from kb_manager_registry_test.dart) ───────────────

Uint8List _buildMinimalBundle(KbVersion version) {
  final entry = KbEntry(
    id: 'test-entry',
    category: KbCategory.rebuild,
    channel: KbChannel.stable,
    severity: Severity.medium,
    title: 'Test Entry',
    description: 'A test KB entry.',
    flutterVersionRange: 'any',
    detectionSignals: const DetectionSignals(
      widgetTypes: ['TestWidget'],
      embedChunks: ['test chunk'],
    ),
    sources: ['https://flutter.dev/test'],
    fixGuidance: 'Fix it.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 50,
      description: 'Some improvement.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  );

  final bundle = KbBundle(
    version: version,
    publishedAt: DateTime(2026).toUtc(),
    flutterVersionRange: '>=3.0.0',
    dartSdkConstraint: '>=3.6.0 <4.0.0',
    entries: [entry],
    embeddings: const EmbeddingManifest(
      modelId: 'nomic-embed-text',
      dimensions: 2,
      vectors: {'test-entry/0': [0.1, 0.9]},
    ),
    checksum: '',
  );

  final rawJson = bundle.toJson();
  final canonical = _canonicalJson(rawJson);
  final checksum = sha256.convert(utf8.encode(canonical)).toString();
  rawJson['checksum'] = checksum;

  final finalJson = jsonEncode(rawJson);
  return Uint8List.fromList(gzip.encode(utf8.encode(finalJson)));
}

String _canonicalJson(Map<String, dynamic> json) {
  final mutable = Map<String, dynamic>.from(json);
  mutable['checksum'] = '';
  return jsonEncode(_sortKeys(mutable));
}

dynamic _sortKeys(dynamic value) {
  if (value is Map) {
    final sorted = <String, dynamic>{};
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    for (final k in keys) {
      sorted[k] = _sortKeys(value[k]);
    }
    return sorted;
  }
  if (value is List) return value.map(_sortKeys).toList();
  return value;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kb_bundle_loader_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('FilesystemKbBundleLoader', () {
    test('loadFromPath loads a valid bundle and returns correct version + entry count',
        () async {
      final version = KbVersion.stable(2, 0, 0);
      final bytes = _buildMinimalBundle(version);
      final filePath = '${tempDir.path}/jankdoc-kb-2.0.0.jankdoc-kb';
      await File(filePath).writeAsBytes(bytes);

      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final bundle = await loader.loadFromPath(filePath);

      expect(bundle.version.toString(), equals('2.0.0'));
      expect(bundle.entries.length, equals(1));
      expect(bundle.entries.first.id, equals('test-entry'));
    });

    test('loadFromPath throws KbLoadException on corrupt gzip bytes', () async {
      final filePath = '${tempDir.path}/corrupt.jankdoc-kb';
      // Write random non-gzip bytes.
      await File(filePath).writeAsBytes(Uint8List.fromList([0x00, 0xFF, 0xAB, 0xCD, 0x01]));

      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);

      await expectLater(
        () => loader.loadFromPath(filePath),
        throwsA(isA<KbLoadException>()),
      );
    });

    test(
        'loadFromPath throws KbLoadException on checksum mismatch '
        '(JSON tampered after checksumming)', () async {
      final version = KbVersion.stable(1, 5, 0);
      final bytes = _buildMinimalBundle(version);

      // Decompress → parse JSON → tamper a field → recompress without
      // recomputing the checksum.
      final jsonBytes = Uint8List.fromList(GZipCodec().decode(bytes));
      final json = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
      json['flutter_version_range'] = 'tampered'; // changes content, not checksum
      final tamperedBytes = Uint8List.fromList(
        gzip.encode(utf8.encode(jsonEncode(json))),
      );

      final filePath = '${tempDir.path}/tampered.jankdoc-kb';
      await File(filePath).writeAsBytes(tamperedBytes);

      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);

      await expectLater(
        () => loader.loadFromPath(filePath),
        throwsA(isA<KbLoadException>()),
      );
    });

    test(
        'latestCachedVersion(KbChannel.stable) returns highest stable version '
        'when multiple bundles are in the cache', () async {
      final versions = [
        KbVersion.stable(1, 0, 0),
        KbVersion.stable(1, 2, 0),
        KbVersion.stable(1, 1, 0),
      ];
      for (final v in versions) {
        await File('${tempDir.path}/jankdoc-kb-$v.jankdoc-kb')
            .writeAsBytes(_buildMinimalBundle(v));
      }

      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final latest = await loader.latestCachedVersion(KbChannel.stable);

      expect(latest, isNotNull);
      expect(latest!.toString(), equals('1.2.0'));
    });

    test(
        'evictOlderThan(v) deletes bundles older than v and keeps v itself',
        () async {
      final old1 = KbVersion.stable(1, 0, 0);
      final old2 = KbVersion.stable(1, 1, 0);
      final keep = KbVersion.stable(1, 2, 0);

      for (final v in [old1, old2, keep]) {
        await File('${tempDir.path}/jankdoc-kb-$v.jankdoc-kb')
            .writeAsBytes(_buildMinimalBundle(v));
      }

      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      await loader.evictOlderThan(keep);

      final remaining = await loader.listCachedVersions();
      expect(remaining.length, equals(1));
      expect(remaining.first.toString(), equals('1.2.0'));

      // The older files must be gone from disk.
      expect(
        File('${tempDir.path}/jankdoc-kb-1.0.0.jankdoc-kb').existsSync(),
        isFalse,
      );
      expect(
        File('${tempDir.path}/jankdoc-kb-1.1.0.jankdoc-kb').existsSync(),
        isFalse,
      );
    });
  });
}
