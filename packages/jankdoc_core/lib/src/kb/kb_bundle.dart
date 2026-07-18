import 'package:meta/meta.dart';

import 'kb_channel.dart';
import 'kb_entry.dart';
import 'kb_version.dart';

/// A single versioned KB artifact containing all entries, their serialised rules,
/// and pre-computed embeddings for a given KB Version and channel.
///
/// Distributed as a gzipped JSON file (`*.jankdoc-kb`) via GitHub Releases.
/// The daemon loads and hot-reloads KB Bundles without restarting.
@immutable
final class KbBundle {
  const KbBundle({
    required this.version,
    required this.publishedAt,
    required this.flutterVersionRange,
    required this.dartSdkConstraint,
    required this.entries,
    required this.embeddings,
    required this.checksum,
  });

  factory KbBundle.fromJson(Map<String, dynamic> json) => KbBundle(
        version: KbVersion.parse(json['version'] as String),
        publishedAt: DateTime.parse(json['published_at'] as String),
        flutterVersionRange: json['flutter_version_range'] as String,
        dartSdkConstraint: json['dart_sdk_constraint'] as String,
        entries: (json['entries'] as List)
            .map((e) => KbEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        embeddings: EmbeddingManifest.fromJson(
          json['embeddings'] as Map<String, dynamic>,
        ),
        checksum: json['checksum'] as String,
      );

  final KbVersion version;
  KbChannel get channel => version.channel;

  /// ISO-8601 timestamp of when this bundle was published to the KB Registry.
  final DateTime publishedAt;

  /// pub_semver constraint for Flutter versions this bundle targets.
  final String flutterVersionRange;

  /// Minimum Dart SDK this bundle is compatible with.
  final String dartSdkConstraint;

  /// All KB entries for this channel (superset of lower channels, per ADR-0013).
  final List<KbEntry> entries;

  /// Pre-computed embedding vectors for all entries in this bundle.
  final EmbeddingManifest embeddings;

  /// SHA-256 of the canonical JSON content, hex-encoded.
  /// Verified by the daemon after download; mismatch aborts the load.
  final String checksum;

  /// Entries that are not deprecated.
  List<KbEntry> get activeEntries =>
      entries.where((e) => !e.deprecated).toList();

  /// Look up an entry by its stable ID. Returns null if not found.
  KbEntry? findEntry(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'version': version.toString(),
        'published_at': publishedAt.toIso8601String(),
        'flutter_version_range': flutterVersionRange,
        'dart_sdk_constraint': dartSdkConstraint,
        'entries': entries.map((e) => e.toJson()).toList(),
        'embeddings': embeddings.toJson(),
        'checksum': checksum,
      };
}

/// The embedding manifest stored in a KB Bundle.
///
/// Contains pre-computed embedding vectors for all DetectionSignals.embedChunks
/// across every KbEntry in the bundle. The Vector Store is populated from this
/// manifest at daemon startup — no cold-start embedding delay.
@immutable
final class EmbeddingManifest {
  const EmbeddingManifest({
    required this.modelId,
    required this.dimensions,
    required this.vectors,
  });

  factory EmbeddingManifest.fromJson(Map<String, dynamic> json) =>
      EmbeddingManifest(
        modelId: json['model_id'] as String,
        dimensions: json['dimensions'] as int,
        vectors: (json['vectors'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(
            k,
            (v as List).map((e) => (e as num).toDouble()).toList(),
          ),
        ),
      );

  /// The Ollama model used to embed the chunks (e.g. "nomic-embed-text:latest").
  /// The daemon validates this matches the configured embedding model at load time.
  final String modelId;

  /// Number of dimensions in each embedding vector.
  final int dimensions;

  /// Maps "$entryId/$chunkIndex" → embedding vector.
  /// The daemon uses these to populate the Vector Store without calling Ollama.
  final Map<String, List<double>> vectors;

  /// All entry IDs that have at least one embedding in this manifest.
  Set<String> get entryIds =>
      vectors.keys.map((k) => k.split('/').first).toSet();

  /// Retrieve all vectors for a given entry ID, in chunk order.
  List<(int index, List<double> vector)> vectorsForEntry(String entryId) {
    final result = <(int, List<double>)>[];
    for (final key in vectors.keys) {
      final parts = key.split('/');
      if (parts.first == entryId) {
        result.add((int.parse(parts.last), vectors[key]!));
      }
    }
    result.sort((a, b) => a.$1.compareTo(b.$1));
    return result;
  }

  Map<String, dynamic> toJson() => {
        'model_id': modelId,
        'dimensions': dimensions,
        'vectors': vectors,
      };
}
