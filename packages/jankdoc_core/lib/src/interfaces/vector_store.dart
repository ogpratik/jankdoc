/// The vector store abstraction for RAG retrieval.
///
/// v1 implementation: pure-Dart in-memory cosine similarity with JSON persistence.
/// Future: swappable for LanceDB or sqlite-vec when KB exceeds 10k entries.
abstract interface class VectorStore {
  /// Add or update an entry in the store.
  Future<void> upsert(VectorEntry entry);

  /// Add or update multiple entries in a single batch.
  Future<void> upsertAll(List<VectorEntry> entries);

  /// Retrieve the top-[k] most similar entries to the [queryVector].
  Future<List<ScoredEntry>> query({
    required List<double> queryVector,
    int k = 5,
    double minSimilarity = 0.5,
  });

  /// Total number of entries in the store.
  Future<int> count();

  /// Persist the store to disk. No-op for non-persistent implementations.
  Future<void> flush();

  /// Load previously persisted data. No-op for non-persistent implementations.
  Future<void> load();
}

final class VectorEntry {
  const VectorEntry({
    required this.id,
    required this.vector,
    required this.metadata,
  });

  /// Entry ID (matches KB Entry ID).
  final String id;

  /// Float embedding vector.
  final List<double> vector;

  /// Arbitrary metadata stored alongside the vector.
  final Map<String, dynamic> metadata;
}

final class ScoredEntry {
  const ScoredEntry({required this.entry, required this.similarity});

  final VectorEntry entry;

  /// Cosine similarity [0.0, 1.0].
  final double similarity;
}
