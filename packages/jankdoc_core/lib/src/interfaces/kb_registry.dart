import 'dart:typed_data';

import '../kb/kb_channel.dart';
import '../kb/kb_version.dart';

/// Discovers and downloads KB Bundles from a remote registry.
///
/// The canonical implementation ([GithubReleasesKbRegistry]) talks to the
/// GitHub Releases API for `ogpratik/jankdoc-kb`. The interface is kept in
/// `jankdoc_core` so that test doubles can be declared there without pulling
/// in HTTP or GitHub details.
///
/// Contract:
/// - [latestVersion] must be safe to call frequently (the implementation
///   should respect rate limits and cache the result for at least 60 s).
/// - [download] returns the raw gzipped bundle bytes. Callers are responsible
///   for writing bytes to disk and verifying the checksum via [KbLoader].
/// - Both methods throw [KbRegistryException] on network errors, 4xx/5xx
///   responses, or malformed payloads.
abstract interface class KbRegistry {
  /// Returns the latest [KbVersion] available on the registry for [channel],
  /// or `null` if no release exists for that channel.
  Future<KbVersion?> latestVersion(KbChannel channel);

  /// Downloads the bundle asset for [version] and returns the raw bytes.
  ///
  /// Throws [KbRegistryException] if the download fails.
  Future<Uint8List> download(KbVersion version);
}

/// Thrown when the registry cannot fulfil a request.
final class KbRegistryException implements Exception {
  const KbRegistryException(this.message, {this.cause, this.statusCode});

  final String message;
  final Object? cause;

  /// HTTP status code if the failure was a non-2xx response, else null.
  final int? statusCode;

  @override
  String toString() {
    final parts = <String>['KbRegistryException: $message'];
    if (statusCode != null) parts.add('(HTTP $statusCode)');
    if (cause != null) parts.add('caused by: $cause');
    return parts.join(' ');
  }
}
