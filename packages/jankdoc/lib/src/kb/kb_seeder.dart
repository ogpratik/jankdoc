import 'package:jankdoc_core/jankdoc_core.dart';

import 'kb_catalog.dart';
import 'kb_entry.dart';

/// Seeds the [VectorStore] with [KbEntry] embeddings from [kbCatalog].
///
/// Seeding is idempotent: if the store already contains at least as many
/// entries as the catalog, it is a no-op. This allows fast daemon restarts
/// without re-embedding on every run.
///
/// Embedding happens lazily after daemon startup so that the HTTP server
/// is ready immediately and the first few real diagnoses are not delayed.
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
      _log('KB already seeded (${current} entries). Skipping.');
      return 0;
    }

    if (!await _llm.isAvailable()) {
      _log('Ollama not available — KB seeding deferred until next restart.');
      return 0;
    }

    _log('Seeding KB: ${kbCatalog.length} entries...');
    final sw = Stopwatch()..start();
    var count = 0;

    // Embed entries sequentially to avoid overwhelming Ollama.
    // nomic-embed-text processes ~1 entry/100ms → full catalog ~2s.
    for (final entry in kbCatalog) {
      try {
        final vector = await _llm.embed(_embedText(entry));
        await _store.upsert(VectorEntry(
          id: entry.id,
          vector: vector,
          metadata: entry.toMetadata(),
        ));
        count++;
      } catch (e) {
        _log('Failed to embed "${entry.id}": $e');
      }
    }

    await _store.flush();
    sw.stop();
    _log('KB seeded: $count/${kbCatalog.length} entries in ${sw.elapsedMilliseconds}ms');
    return count;
  }

  /// Re-embed all entries regardless of current store state.
  ///
  /// Use this when the catalog has changed and you want a full refresh.
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
          metadata: entry.toMetadata(),
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

  /// Returns a list of all catalog entry IDs for diagnostics.
  static List<String> get catalogIds => kbCatalog.map((e) => e.id).toList();

  /// Builds the text to embed for a KB entry.
  ///
  /// Title + tags give the embedding model strong signal for semantic search.
  /// Content is the primary RAG payload — it must be rich and specific.
  static String _embedText(KbEntry entry) =>
      '${entry.title}\n\nTags: ${entry.tags.join(', ')}\n\n${entry.content}';

  static void _log(String msg) =>
      // ignore: avoid_print
      print('[JankDoc/KB] $msg');
}
