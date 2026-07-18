import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:test/test.dart';

import '../../lib/src/kb/kb_bundle_loader.dart';
import '../../lib/src/kb/kb_manager.dart';
import '../../lib/src/kb/kb_seeder.dart';

// ─── Mock KbRegistry ─────────────────────────────────────────────────────────

final class _MockRegistry implements KbRegistry {
  _MockRegistry({
    required this.latestVersionResult,
    this.downloadBytes,
    this.throwOnCall = false,
  });

  final KbVersion? latestVersionResult;
  final Uint8List? downloadBytes;
  final bool throwOnCall;

  var downloadCallCount = 0;
  var latestVersionCallCount = 0;

  @override
  Future<KbVersion?> latestVersion(KbChannel channel) async {
    latestVersionCallCount++;
    if (throwOnCall) {
      throw const KbRegistryException('Simulated network error');
    }
    return latestVersionResult;
  }

  @override
  Future<Uint8List> download(KbVersion version) async {
    downloadCallCount++;
    if (downloadBytes == null) {
      throw KbRegistryException('No bytes configured for $version');
    }
    return downloadBytes!;
  }
}

// ─── Stub LlmProvider + VectorStore (for KbSeeder) ────────────────────────────

/// A VectorStore that records upserts and never requires I/O.
final class _StubVectorStore implements VectorStore {
  final _vectors = <String, VectorEntry>{};

  @override
  Future<void> upsert(VectorEntry entry) async => _vectors[entry.id] = entry;

  @override
  Future<void> upsertAll(List<VectorEntry> entries) async {
    for (final e in entries) {
      _vectors[e.id] = e;
    }
  }

  @override
  Future<List<ScoredEntry>> query({
    required List<double> queryVector,
    int k = 5,
    double minSimilarity = 0.5,
  }) async =>
      [];

  @override
  Future<int> count() async => _vectors.length;

  @override
  Future<void> load() async {}

  @override
  Future<void> flush() async {}
}

/// A stub LlmProvider that reports unavailability (no Ollama in unit tests).
final class _StubLlmProvider implements LlmProvider {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<Diagnosis> diagnose(DiagnoseRequest request) =>
      Future.error(StateError('LLM not available in tests'));

  @override
  Stream<String> diagnoseStream(DiagnoseRequest request) =>
      const Stream.empty();

  @override
  Future<List<double>> embed(String text) async => [];

  @override
  String get modelId => 'stub-model';
}

// ─── Bundle builder ────────────────────────────────────────────────────────────

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
    publishedAt: DateTime(2026, 1, 1).toUtc(),
    flutterVersionRange: '>=3.0.0',
    dartSdkConstraint: '>=3.6.0 <4.0.0',
    entries: [entry],
    embeddings: EmbeddingManifest(
      modelId: 'nomic-embed-text',
      dimensions: 2,
      vectors: {'test-entry/0': const [0.1, 0.9]},
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
    for (final k in keys) sorted[k] = _sortKeys(value[k]);
    return sorted;
  }
  if (value is List) return value.map(_sortKeys).toList();
  return value;
}

// ─── Test setup helpers ───────────────────────────────────────────────────────

KbSeeder _makeSeeder() => KbSeeder(
      vectorStore: _StubVectorStore(),
      llmProvider: _StubLlmProvider(),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kb_manager_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('KbManager.load — with registry', () {
    test('downloads bundle on startup when cache is empty', () async {
      final version = KbVersion.stable(1, 0, 0);
      final bundleBytes = _buildMinimalBundle(version);

      final registry = _MockRegistry(
        latestVersionResult: version,
        downloadBytes: bundleBytes,
      );
      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final seeder = _makeSeeder();

      final manager = KbManager(
        loader: loader,
        seeder: seeder,
        registry: registry,
      );

      final result = await manager.load();

      expect(result.source, equals(KbSource.bundle));
      expect(result.version.toString(), equals('1.0.0'));
      expect(registry.downloadCallCount, equals(1));

      // Verify bundle was written to the cache.
      final cacheFile = File('${tempDir.path}/jankdoc-kb-1.0.0.jankdoc-kb');
      expect(cacheFile.existsSync(), isTrue);
    });

    test('does not re-download when active version == registry version',
        () async {
      final version = KbVersion.stable(1, 0, 0);
      final bundleBytes = _buildMinimalBundle(version);

      // Pre-populate cache.
      await File('${tempDir.path}/jankdoc-kb-1.0.0.jankdoc-kb')
          .writeAsBytes(bundleBytes);

      final registry = _MockRegistry(
        latestVersionResult: version,
        downloadBytes: bundleBytes,
      );
      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final manager = KbManager(
        loader: loader,
        seeder: _makeSeeder(),
        registry: registry,
      );

      await manager.load(); // loads v1.0.0, _activeVersion = 1.0.0
      final firstCount = registry.downloadCallCount;

      await manager.load(); // registry still says 1.0.0 == active → no download
      expect(registry.downloadCallCount, equals(firstCount),
          reason: 'Should not re-download when cache is current');
    });

    test('downloads newer bundle when registry version > cached version',
        () async {
      final oldVersion = KbVersion.stable(1, 0, 0);
      final newVersion = KbVersion.stable(1, 1, 0);

      await File('${tempDir.path}/jankdoc-kb-1.0.0.jankdoc-kb')
          .writeAsBytes(_buildMinimalBundle(oldVersion));

      final registry = _MockRegistry(
        latestVersionResult: newVersion,
        downloadBytes: _buildMinimalBundle(newVersion),
      );
      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final manager = KbManager(
        loader: loader,
        seeder: _makeSeeder(),
        registry: registry,
      );

      final result = await manager.load();

      expect(result.version.toString(), equals('1.1.0'));
      expect(registry.downloadCallCount, equals(1));
      expect(
        File('${tempDir.path}/jankdoc-kb-1.1.0.jankdoc-kb').existsSync(),
        isTrue,
      );
    });

    test('falls back to seeder when registry returns null and cache is empty',
        () async {
      final registry = _MockRegistry(latestVersionResult: null);
      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final manager = KbManager(
        loader: loader,
        seeder: _makeSeeder(),
        registry: registry,
      );

      final result = await manager.load();
      expect(result.source, equals(KbSource.seeder));
      expect(registry.downloadCallCount, equals(0));
    });

    test('falls back gracefully when registry throws KbRegistryException',
        () async {
      final version = KbVersion.stable(1, 0, 0);
      await File('${tempDir.path}/jankdoc-kb-1.0.0.jankdoc-kb')
          .writeAsBytes(_buildMinimalBundle(version));

      // Registry throws — should not propagate; load succeeds from cache.
      final registry = _MockRegistry(
        latestVersionResult: version,
        throwOnCall: true,
      );
      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final manager = KbManager(
        loader: loader,
        seeder: _makeSeeder(),
        registry: registry,
      );

      final result = await manager.load();
      expect(result.source, equals(KbSource.bundle),
          reason: 'Should load from cache even when registry throws');
    });
  });

  group('KbManager.load — without registry', () {
    test('loads bundle from cache when present', () async {
      final version = KbVersion.stable(1, 0, 0);
      await File('${tempDir.path}/jankdoc-kb-1.0.0.jankdoc-kb')
          .writeAsBytes(_buildMinimalBundle(version));

      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final manager = KbManager(loader: loader, seeder: _makeSeeder());

      final result = await manager.load();
      expect(result.source, equals(KbSource.bundle));
      expect(result.version.toString(), equals('1.0.0'));
    });

    test('falls back to seeder when cache is empty and no registry', () async {
      final loader = FilesystemKbBundleLoader(overrideCacheDir: tempDir.path);
      final manager = KbManager(loader: loader, seeder: _makeSeeder());

      final result = await manager.load();
      expect(result.source, equals(KbSource.seeder));
    });
  });
}
