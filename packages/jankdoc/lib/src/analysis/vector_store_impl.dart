import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

// Hide jankdoc_core's Platform condition class so dart:io.Platform stays in scope.
import 'package:jankdoc_core/jankdoc_core.dart' hide Platform;

/// Pure-Dart in-memory vector store with JSON persistence.
///
/// Backed by the [VectorStore] interface. Uses brute-force cosine similarity
/// which is O(n×d) — trivially fast for n≤1000 KB entries.
/// Interface is swappable for LanceDB/sqlite-vec when n > 10k.
final class InMemoryVectorStore implements VectorStore {
  final Map<String, VectorEntry> _entries = {};

  static String get _persistPath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.jankdoc/vector_store.json';
  }

  @override
  Future<void> upsert(VectorEntry entry) async {
    _entries[entry.id] = entry;
  }

  @override
  Future<void> upsertAll(List<VectorEntry> entries) async {
    for (final e in entries) {
      _entries[e.id] = e;
    }
  }

  @override
  Future<List<ScoredEntry>> query({
    required List<double> queryVector,
    int k = 5,
    double minSimilarity = 0.5,
  }) async {
    if (_entries.isEmpty) return [];

    final scored = _entries.values
        .map((e) => ScoredEntry(
              entry: e,
              similarity: _cosineSimilarity(queryVector, e.vector),
            ))
        .where((s) => s.similarity >= minSimilarity)
        .toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));

    return scored.take(k).toList();
  }

  @override
  Future<int> count() async => _entries.length;

  @override
  Future<void> flush() async {
    final file = File(_persistPath);
    await file.parent.create(recursive: true);
    final data = {
      'version': 1,
      'entries': _entries.values
          .map((e) => {
                'id': e.id,
                'vector': e.vector,
                'metadata': e.metadata,
              })
          .toList(),
    };
    await file.writeAsString(jsonEncode(data));
  }

  @override
  Future<void> load() async {
    final file = File(_persistPath);
    if (!await file.exists()) return;

    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entries = (json['entries'] as List).cast<Map<String, dynamic>>();
      for (final e in entries) {
        final vector = (e['vector'] as List).cast<double>();
        _entries[e['id'] as String] = VectorEntry(
          id: e['id'] as String,
          vector: vector,
          metadata: e['metadata'] as Map<String, dynamic>,
        );
      }
    } catch (e) {
      // Corrupt store — start fresh. Will be rebuilt on next embed.
      _entries.clear();
    }
  }

  /// Cosine similarity between two equal-length float vectors.
  static double _cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length, 'Vector dimension mismatch');
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom == 0 ? 0.0 : (dot / denom).clamp(0.0, 1.0);
  }
}
