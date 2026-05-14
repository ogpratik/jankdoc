/// A single Knowledge Base entry.
///
/// Entries are embedded once at daemon startup by [KbSeeder] and stored in
/// the [VectorStore] for RAG retrieval. Each entry maps 1:1 to a [Rule]
/// patternId so the LLM tier receives authoritative fix guidance.
final class KbEntry {
  const KbEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.sources,
    this.tags = const [],
  });

  /// Matches [Rule.patternId] exactly.
  final String id;

  final String title;

  /// Rich text content used as RAG context for the LLM prompt.
  /// Should include: problem description, root cause, fix steps, code snippets.
  final String content;

  final List<String> sources;

  final List<String> tags;

  /// Converts to the metadata map stored alongside the vector.
  Map<String, dynamic> toMetadata() => {
        'id': id,
        'title': title,
        'content': content,
        'sources': sources,
        'tags': tags,
      };
}
