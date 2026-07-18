import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

/// Bundle file prefix and extension.
const _kPrefix = 'jankdoc-kb-';
const _kExtension = '.jankdoc-kb';

/// Loads and caches KB Bundles from the local filesystem.
///
/// Bundle files are gzipped JSON named `jankdoc-kb-{semver}.jankdoc-kb`
/// stored under `~/.jankdoc/kb/`.
///
/// SHA-256 is verified on every load. The checksum field in the bundle JSON
/// is computed over the canonical JSON (checksum key zeroed, keys sorted
/// alphabetically). See [_verifyChecksum].
final class FilesystemKbBundleLoader implements KbLoader {
  FilesystemKbBundleLoader({String? overrideCacheDir})
      : _overrideCacheDir = overrideCacheDir;

  final String? _overrideCacheDir;

  @override
  Future<String> cacheDir() async {
    if (_overrideCacheDir != null) return _overrideCacheDir;
    return _defaultCacheDir();
  }

  static String _defaultCacheDir() {
    final home = io.Platform.environment['HOME'] ??
        io.Platform.environment['USERPROFILE'] ?? // Windows
        '.';
    return '$home/.jankdoc/kb';
  }

  @override
  Future<KbBundle> loadFromPath(String path) async {
    final file = io.File(path);
    if (!file.existsSync()) {
      throw KbLoadException('Bundle file not found: $path');
    }
    final bytes = await file.readAsBytes();
    return _decode(bytes, sourcePath: path);
  }

  @override
  Future<KbBundle> loadFromBytes(Uint8List bytes) async => _decode(bytes);

  @override
  Future<KbVersion?> latestCachedVersion(KbChannel channel) async {
    final versions = await listCachedVersions();
    for (final v in versions) {
      if (channel.includes(v.channel)) return v;
    }
    return null;
  }

  @override
  Future<List<KbVersion>> listCachedVersions() async {
    final dir = io.Directory(await cacheDir());
    if (!dir.existsSync()) return [];

    final versions = <KbVersion>[];
    for (final entity in dir.listSync()) {
      if (entity is! io.File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_kPrefix) || !name.endsWith(_kExtension)) continue;
      final versionStr =
          name.substring(_kPrefix.length, name.length - _kExtension.length);
      try {
        versions.add(KbVersion.parse(versionStr));
      } catch (_) {
        // Skip malformed filenames.
      }
    }
    versions.sort((a, b) => b.compareTo(a));
    return versions;
  }

  @override
  Future<void> evictOlderThan(KbVersion keepVersion) async {
    final dir = io.Directory(await cacheDir());
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync()) {
      if (entity is! io.File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_kPrefix) || !name.endsWith(_kExtension)) continue;
      final versionStr =
          name.substring(_kPrefix.length, name.length - _kExtension.length);
      try {
        final v = KbVersion.parse(versionStr);
        if (v.compareTo(keepVersion) < 0) {
          await entity.delete();
        }
      } catch (_) {
        // Skip malformed filenames.
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  KbBundle _decode(Uint8List bytes, {String? sourcePath}) {
    final Uint8List jsonBytes;
    try {
      jsonBytes = Uint8List.fromList(io.GZipCodec().decode(bytes));
    } catch (e) {
      throw KbLoadException(
        'Failed to decompress bundle${sourcePath != null ? " at $sourcePath" : ""}',
        cause: e,
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw KbLoadException('Failed to parse bundle JSON', cause: e);
    }

    final bundle = KbBundle.fromJson(json);
    _verifyChecksum(json, bundle.checksum, sourcePath: sourcePath);
    return bundle;
  }

  void _verifyChecksum(
    Map<String, dynamic> json,
    String storedChecksum, {
    String? sourcePath,
  }) {
    if (storedChecksum.isEmpty) return;

    final mutable = Map<String, dynamic>.from(json);
    mutable['checksum'] = '';
    final canonical = jsonEncode(_sortKeys(mutable));
    final computed = sha256.convert(utf8.encode(canonical)).toString();

    if (computed != storedChecksum) {
      throw KbLoadException(
        'Bundle checksum mismatch${sourcePath != null ? " ($sourcePath)" : ""}: '
        'expected $storedChecksum, got $computed',
      );
    }
  }

  dynamic _sortKeys(dynamic value) {
    if (value is Map<String, dynamic>) {
      final sorted = <String, dynamic>{};
      for (final key in value.keys.toList()..sort()) {
        sorted[key] = _sortKeys(value[key]);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_sortKeys).toList();
    }
    return value;
  }
}
