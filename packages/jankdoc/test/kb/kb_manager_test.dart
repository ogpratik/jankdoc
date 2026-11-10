import 'dart:typed_data';

import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:test/test.dart';

import '../../lib/src/kb/kb_manager.dart';
import '../../lib/src/kb/kb_seeder.dart';

// ── Stub KbLoader ──────────────────────────────────────────────────────────────

/// Configurable stub for [KbLoader].
///
/// [version] controls what [latestCachedVersion] returns.
/// [bundle]  controls what [loadFromPath] returns (ignores path).
final class _StubLoader implements KbLoader {
  _StubLoader({this.version, this.bundle});

  KbVersion? version;
  KbBundle? bundle;
  var evictCallCount = 0;

  @override
  Future<KbBundle> loadFromPath(String path) async {
    if (bundle == null) throw const KbLoadException('No bundle configured');
    return bundle!;
  }

  @override
  Future<KbBundle> loadFromBytes(Uint8List bytes) =>
      Future.error(UnimplementedError('not used in KbManager tests'));

  @override
  Future<KbVersion?> latestCachedVersion(KbChannel channel) async => version;

  @override
  Future<String> cacheDir() async => '/tmp/kb_manager_stub';

  @override
  Future<List<KbVersion>> listCachedVersions() async =>
      version != null ? [version!] : [];

  @override
  Future<void> evictOlderThan(KbVersion keepVersion) async {
    evictCallCount++;
  }
}

// ── Stub VectorStore + LlmProvider (needed to construct KbSeeder) ─────────────

final class _StubVectorStore implements VectorStore {
  final _entries = <String, VectorEntry>{};

  @override
  Future<void> upsert(VectorEntry e) async => _entries[e.id] = e;

  @override
  Future<void> upsertAll(List<VectorEntry> es) async {
    for (final e in es) {
      _entries[e.id] = e;
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
  Future<int> count() async => _entries.length;

  @override
  Future<void> load() async {}

  @override
  Future<void> flush() async {}
}

final class _StubLlmProvider implements LlmProvider {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<Diagnosis> diagnose(DiagnoseRequest r) =>
      Future.error(StateError('LLM unavailable in unit tests'));

  @override
  Stream<String> diagnoseStream(DiagnoseRequest r) => const Stream.empty();

  @override
  Future<List<double>> embed(String text) async => [];

  @override
  String get modelId => 'stub-model';
}

KbSeeder _makeSeeder() => KbSeeder(
      vectorStore: _StubVectorStore(),
      llmProvider: _StubLlmProvider(),
    );

// ── Bundle factory ─────────────────────────────────────────────────────────────

/// Build a minimal [KbBundle] at [version] with one entry that has one
/// pre-computed embedding vector so [KbSeeder.seedFromBundle] returns 1.
KbBundle _stubBundle(KbVersion version) {
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
    sources: ['https://flutter.dev'],
    fixGuidance: 'Fix the issue.',
    expectedImprovement: const ExpectedImprovement(
      minReductionPercent: 20,
      maxReductionPercent: 50,
      description: 'Noticeable improvement.',
    ),
    introducedIn: KbVersion.stable(1, 0, 0),
  );

  return KbBundle(
    version: version,
    publishedAt: DateTime(2026, 1, 1).toUtc(),
    flutterVersionRange: '>=3.0.0',
    dartSdkConstraint: '>=3.6.0 <4.0.0',
    entries: [entry],
    // Pre-computed vector: seedFromBundle reads this and calls _store.upsert.
    embeddings: EmbeddingManifest(
      modelId: 'nomic-embed-text',
      dimensions: 2,
      vectors: {'test-entry/0': const [0.1, 0.9]},
    ),
    // Checksum is not re-verified when KbLoader is a stub (stub returns the
    // bundle object directly without disk I/O or SHA-256 verification).
    checksum: 'stub-checksum-bypass',
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  final v1 = KbVersion.stable(1, 0, 0);
  final v2 = KbVersion.stable(1, 1, 0);

  group('KbManager.load', () {
    test('returns KbSource.bundle when a cached bundle is present', () async {
      final loader = _StubLoader(version: v1, bundle: _stubBundle(v1));

      final manager = KbManager(loader: loader, seeder: _makeSeeder());
      final result = await manager.load();
      manager.dispose();

      expect(result.source, KbSource.bundle,
          reason: 'Cached bundle should yield KbSource.bundle');
      expect(result.version, v1);
      expect(result.bundle, isNotNull);
    });

    test('returns KbSource.seeder when no bundle is cached', () async {
      // No version configured → latestCachedVersion returns null.
      final loader = _StubLoader();

      final manager = KbManager(loader: loader, seeder: _makeSeeder());
      final result = await manager.load();
      manager.dispose();

      expect(result.source, KbSource.seeder,
          reason: 'No cached bundle should trigger seeder fallback');
      expect(result.bundle, isNull);
      expect(result.version, isNull);
    });
  });

  group('KbManager hot-reload', () {
    test('calls onBundleReloaded when a newer bundle appears in cache', () async {
      final loader = _StubLoader(version: v1, bundle: _stubBundle(v1));
      final reloaded = <KbBundle>[];

      final manager = KbManager(
        loader: loader,
        seeder: _makeSeeder(),
        // 1ms interval ensures the timer fires well within the 200ms wait below.
        reloadInterval: const Duration(milliseconds: 1),
        onBundleReloaded: reloaded.add,
      );

      // First load: _activeVersion is set to v1.
      await manager.load();

      // Simulate a newer bundle arriving in the local cache.
      loader.version = v2;
      loader.bundle = _stubBundle(v2);

      manager.startHotReload();
      // Give the 1ms timer plenty of time to fire and run _checkForNewerBundle.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      manager.dispose();

      expect(reloaded, isNotEmpty,
          reason: 'onBundleReloaded must fire when a newer cached version exists');
      expect(reloaded.first.version, v2,
          reason: 'Reloaded bundle must carry the newer version');
    });

    test('does NOT call onBundleReloaded when latest cached version equals active',
        () async {
      final loader = _StubLoader(version: v1, bundle: _stubBundle(v1));
      var reloadCount = 0;

      final manager = KbManager(
        loader: loader,
        seeder: _makeSeeder(),
        reloadInterval: const Duration(milliseconds: 1),
        onBundleReloaded: (_) => reloadCount++,
      );

      // First load: _activeVersion = v1.
      await manager.load();

      // Loader still returns v1 — same as active.
      manager.startHotReload();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      manager.dispose();

      expect(reloadCount, 0,
          reason: 'Hot-reload must no-op when latest version equals active version');
    });
  });
}
