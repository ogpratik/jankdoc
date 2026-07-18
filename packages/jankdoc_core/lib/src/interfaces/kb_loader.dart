import 'dart:typed_data';

import '../kb/kb_bundle.dart';
import '../kb/kb_channel.dart';
import '../kb/kb_version.dart';

/// Loads KB Bundles from disk or raw bytes and manages the local KB cache.
///
/// The default implementation reads gzipped JSON from `~/.jankdoc/kb/`
/// and verifies the SHA-256 checksum before deserialising.
abstract interface class KbLoader {
  /// Load a KB Bundle from an absolute file path on disk.
  ///
  /// Verifies the bundle's checksum. Throws [KbLoadException] on failure.
  Future<KbBundle> loadFromPath(String path);

  /// Load a KB Bundle from raw gzipped JSON bytes.
  ///
  /// Verifies the bundle's checksum. Throws [KbLoadException] on failure.
  Future<KbBundle> loadFromBytes(Uint8List bytes);

  /// Returns the highest cached [KbVersion] compatible with [channel],
  /// or null if no compatible bundle is cached.
  Future<KbVersion?> latestCachedVersion(KbChannel channel);

  /// Returns the absolute path to the local KB cache directory.
  /// Defaults to `~/.jankdoc/kb/`.
  Future<String> cacheDir();

  /// Lists all cached KB Bundle versions, sorted descending.
  Future<List<KbVersion>> listCachedVersions();

  /// Delete all cached bundles for versions older than [keepVersion].
  Future<void> evictOlderThan(KbVersion keepVersion);
}

/// Thrown when a KB Bundle cannot be loaded.
final class KbLoadException implements Exception {
  const KbLoadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'KbLoadException: $message (caused by: $cause)'
      : 'KbLoadException: $message';
}
