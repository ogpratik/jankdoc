import 'package:jankdoc_core/jankdoc_core.dart';

import 'kb_catalog.dart';

/// Seeds the [VectorStore] with KB Entry embeddings from [kbCatalog].
///
/// Seeding calls Ollama at runtime to generate embeddings. This is a temporary
/// approach — once the `jankdoc-kb` repo ships KB Bundles, the [KbLoader] will
/// populate the [VectorStore] from the bundle's [EmbeddingManifest] instead,
/// and this class will be removed.
///
/// Seeding is idempotent: if the store already contains at least as many
/// entries as the catalog, it is a no-op. This allows fast daemon restarts
/// without re-embedding on every run.
final class KbSeeder {
  const KbSeeder({
    required VectorStore vectorStore,
    required LlmProvider llmProvider,
  })  : _store = vectorStore,
        _llm = llmProvider;

  final VectorStore _store;
  final LlmProvider _llm;

  /// Seed the vector store with all [kbCatalog] entries.
  ///
  /// Checks current store count first — skips if already up to date.
  /// Returns the number of entries actually embedded (0 if skipped).
  Future<int> seed() async {
    final current = await _store.count();
    if (current >= kbCatalog.length) {
      _log('KB already seeded ($current entries). Skipping.');
      return 0;
    }

    if (!await _llm.isAvailable()) {
      _log('Ollama not available — KB seeding deferred until next restart.');
      return 0;
    }

    _log('Seeding KB: ${kbCatalog.length} entries...');
    final sw = Stopwatch()..start();
    var count = 0;

    for (final entry in kbCatalog) {
      try {
        final vector = await _llm.embed(_embedText(entry));
        await _store.upsert(VectorEntry(
          id: entry.id,
          vector: vector,
          metadata: _toMetadata(entry),
        ));
        count++;
      } catch (e) {
        _log('Failed to embed "${entry.id}": $e');
      }
    }

    await _store.flush();
    sw.stop();
    _log(
        'KB seeded: $count/${kbCatalog.length} entries in ${sw.elapsedMilliseconds}ms');
    return count;
  }

  /// Re-embed all entries regardless of current store state.
  Future<int> reseed() async {
    _log('Reseeding KB (force)...');

    if (!await _llm.isAvailable()) {
      _log('Ollama not available — reseed aborted.');
      return 0;
    }

    var count = 0;
    for (final entry in kbCatalog) {
      try {
        final vector = await _llm.embed(_embedText(entry));
        await _store.upsert(VectorEntry(
          id: entry.id,
          vector: vector,
          metadata: _toMetadata(entry),
        ));
        count++;
      } catch (e) {
        _log('Failed to embed "${entry.id}": $e');
      }
    }

    await _store.flush();
    _log('KB reseeded: $count entries.');
    return count;
  }

  /// Populate the vector store from a bundle's pre-computed [EmbeddingManifest].
  ///
  /// Replaces runtime Ollama embedding calls with bundle-provided vectors.
  /// Much faster at startup — no LLM invocation needed.
  Future<int> seedFromBundle(KbBundle bundle) async {
    _log('Seeding KB from bundle ${bundle.version}...');
    final sw = Stopwatch()..start();
    var count = 0;

    for (final entry in bundle.activeEntries) {
      final vectors = bundle.embeddings.vectorsForEntry(entry.id);
      if (vectors.isEmpty) continue;
      // Use the first chunk's vector as the primary embedding for RAG lookup.
      await _store.upsert(VectorEntry(
        id: entry.id,
        vector: vectors.first.$2,
        metadata: _toMetadata(entry),
      ));
      count++;
    }

    await _store.flush();
    sw.stop();
    _log('Bundle seed: $count entries in ${sw.elapsedMilliseconds}ms');
    return count;
  }

  static List<String> get catalogIds => kbCatalog.map((e) => e.id).toList();

  /// Builds the text to embed. Title + fix guidance give strong semantic signal.
  /// Description is the primary RAG payload for the LLM prompt.
  static String _embedText(KbEntry entry) =>
      '${entry.title}\n\n${entry.fixGuidance}\n\n${entry.description}';

  /// Converts a KbEntry to the metadata map stored alongside the vector.
  /// The LLM Tier reads `content` from this metadata to build the RAG prompt.
  static Map<String, dynamic> _toMetadata(KbEntry entry) => {
        'id': entry.id,
        'title': entry.title,
        'content': entry.description,
        'fix_guidance': entry.fixGuidance,
        'sources': entry.sources,
        'category': entry.category.name,
        'severity': entry.severity.name,
      };

  static void _log(String msg) =>
      // ignore: avoid_print
      print('[JankDoc/KB] $msg');
}
