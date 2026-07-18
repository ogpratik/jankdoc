import 'dart:async';
import 'dart:io';

import 'package:jankdoc_core/jankdoc_core.dart';

import 'kb_seeder.dart';

/// How the daemon obtained its active KB.
enum KbSource { bundle, seeder }

/// Result of [KbManager.load].
final class KbLoadResult {
  const KbLoadResult({required this.source, this.bundle, this.version});

  final KbSource source;

  /// Non-null when [source] == [KbSource.bundle].
  final KbBundle? bundle;

  /// Version of the loaded bundle, or null for seeder fallback.
  final KbVersion? version;

  @override
  String toString() => source == KbSource.bundle
      ? 'bundle@${version ?? "unknown"}'
      : 'seeder-fallback';
}

/// Manages the KB lifecycle for the analysis daemon.
///
/// **Startup**: tries to load the highest cached [KbBundle] first.
/// Falls back to [KbSeeder] if no bundle is available.
///
/// **Hot-reload**: polls every [reloadInterval] for a newer bundle. When
/// [registry] is provided, each poll first checks the remote registry for a
/// newer version and downloads it to the cache before the local-cache check.
/// When found, hands the new bundle to [onBundleReloaded] and cleans up older
/// cached versions.
final class KbManager {
  KbManager({
    required this.loader,
    required this.seeder,
    this.channel = KbChannel.stable,
    this.reloadInterval = const Duration(seconds: 60),
    this.registry,
    this.onBundleReloaded,
  });

  final KbLoader loader;
  final KbSeeder seeder;
  final KbChannel channel;
  final Duration reloadInterval;

  /// Optional remote registry. When non-null, hot-reload polls the registry
  /// for newer bundles before checking the local cache.
  final KbRegistry? registry;

  /// Called when a newer bundle is loaded during hot-reload.
  final void Function(KbBundle bundle)? onBundleReloaded;

  KbVersion? _activeVersion;
  Timer? _reloadTimer;

  /// Load the KB at daemon startup and populate the vector store.
  ///
  /// 1. If [registry] is configured, check for a remote bundle and download
  ///    it to the local cache when a newer version is available.
  /// 2. Look for the latest cached bundle in [channel].
  /// 3. If found:
  ///    a. If the bundle ships with pre-computed embeddings,
  ///       [KbSeeder.seedFromBundle] is called and we return [KbSource.bundle].
  ///    b. If the bundle has no embeddings (e.g. early-beta bundles where
  ///       maintainer-side embedding hasn't been wired up yet),
  ///       [KbSeeder.seed] is called to embed at runtime via Ollama, and we
  ///       still return [KbSource.bundle] — the entries came from the bundle.
  /// 4. If no bundle is cached: run [KbSeeder.seed] and return [KbSource.seeder].
  ///
  /// Either way, the vector store is non-empty on return (assuming Ollama is
  /// reachable when runtime embedding is needed).
  Future<KbLoadResult> load() async {
    // Try to download from registry on first startup (best-effort).
    if (registry != null) {
      await _fetchFromRegistryIfNewer();
    }

    final latestVersion = await loader.latestCachedVersion(channel);

    if (latestVersion != null) {
      try {
        final cacheDir = await loader.cacheDir();
        final path = _bundlePath(cacheDir, latestVersion);
        final bundle = await loader.loadFromPath(path);
        _activeVersion = latestVersion;

        // Populate the vector store from the bundle.
        final seededFromBundle = await seeder.seedFromBundle(bundle);
        if (seededFromBundle == 0) {
          // Bundle has no embeddings — fall back to runtime embedding so the
          // LLM tier still has RAG context. Entries themselves came from the
          // bundle so this is still KbSource.bundle.
          stderr.writeln('[KbManager] Bundle $latestVersion has no embeddings; '
              'embedding at runtime via Ollama.');
          await seeder.seed();
        }

        return KbLoadResult(
          source: KbSource.bundle,
          bundle: bundle,
          version: latestVersion,
        );
      } on KbLoadException catch (e) {
        _logBundleLoadFailure(latestVersion, e, await loader.cacheDir());
        // Fall through to seeder.
      }
    }

    await seeder.seed();
    return const KbLoadResult(source: KbSource.seeder);
  }

  /// Start the hot-reload timer.
  ///
  /// Checks for a newer bundle every [reloadInterval]. Stops when [dispose]
  /// is called.
  void startHotReload() {
    _reloadTimer?.cancel();
    _reloadTimer =
        Timer.periodic(reloadInterval, (_) => _checkForNewerBundle());
  }

  void dispose() {
    _reloadTimer?.cancel();
    _reloadTimer = null;
  }

  Future<void> _checkForNewerBundle() async {
    try {
      // ── 1. Remote registry check (when configured) ────────────────────────
      if (registry != null) {
        await _fetchFromRegistryIfNewer();
      }

      // ── 2. Local cache check ──────────────────────────────────────────────
      final latest = await loader.latestCachedVersion(channel);
      if (latest == null) return;
      if (_activeVersion != null && latest.compareTo(_activeVersion!) <= 0) {
        return;
      }

      final cacheDir = await loader.cacheDir();
      final bundle = await loader.loadFromPath(_bundlePath(cacheDir, latest));

      stderr.writeln('[KbManager] hot-reload: $latest (was $_activeVersion)');
      _activeVersion = latest;
      onBundleReloaded?.call(bundle);

      // Evict bundles older than the newly active version.
      if (_activeVersion != null) {
        await loader.evictOlderThan(_activeVersion!);
      }
    } on Object catch (e) {
      stderr.writeln('[KbManager] hot-reload check failed: $e');
    }
  }

  /// Emit a clear, actionable error message when a bundle fails to load.
  ///
  /// Checksum mismatches get special treatment — the user is told to delete
  /// the corrupt file. Other failures get a generic message.
  void _logBundleLoadFailure(
    KbVersion version,
    KbLoadException e,
    String cacheDirectory,
  ) {
    final path = _bundlePath(cacheDirectory, version);
    if (e.message.contains('checksum mismatch')) {
      stderr.writeln(
        '[JankDoc] KB bundle $version checksum mismatch — refusing to load. '
        'File may be corrupt; delete $path and restart.',
      );
    } else {
      stderr.writeln('[JankDoc] KB bundle $version failed to load: $e');
    }
  }

  /// Check the remote registry and download if a newer version is available.
  /// Writes the bundle to the local cache so the subsequent local-cache check
  /// can pick it up. Swallows [KbRegistryException] to stay non-fatal.
  Future<void> _fetchFromRegistryIfNewer() async {
    try {
      final remoteVersion = await registry!.latestVersion(channel);
      if (remoteVersion == null) return;
      if (_activeVersion != null &&
          remoteVersion.compareTo(_activeVersion!) <= 0) {
        return;
      }

      stderr.writeln(
        '[KbManager] registry: newer bundle $remoteVersion available'
        '${_activeVersion != null ? " (have $_activeVersion)" : ""}. Downloading…',
      );

      final bytes = await registry!.download(remoteVersion);
      final cacheDir = await loader.cacheDir();
      final path = _bundlePath(cacheDir, remoteVersion);

      // Write to cache. The caller's local-cache check will then load + verify.
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);

      stderr.writeln('[KbManager] registry: downloaded $remoteVersion → $path');
    } on KbRegistryException catch (e) {
      // Registry errors are non-fatal — fall through to local cache.
      stderr.writeln('[KbManager] registry check failed (non-fatal): $e');
    }
  }

  static String _bundlePath(String cacheDir, KbVersion version) =>
      '$cacheDir/$_kPrefix$version$_kExtension';
}

const _kPrefix = 'jankdoc-kb-';
const _kExtension = '.jankdoc-kb';
