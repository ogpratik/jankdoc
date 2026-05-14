import '../models/diagnosis.dart';
import '../models/telemetry_batch.dart';

/// The LLM abstraction layer. All inference goes through this interface.
///
/// Default implementation: [OllamaProvider].
/// Alternative: [OpenAiCompatibleProvider] for LM Studio, vLLM, llama.cpp server.
abstract interface class LlmProvider {
  /// Produce a structured [Diagnosis] for the given batch and RAG context.
  ///
  /// [ragChunks] are the top-k KB Entry chunks retrieved by the Vector Store.
  /// The implementation is responsible for prompt construction, JSON-schema
  /// constrained decoding, and streaming.
  Future<Diagnosis> diagnose(DiagnoseRequest request);

  /// Stream token-by-token output for progressive UI rendering.
  Stream<String> diagnoseStream(DiagnoseRequest request);

  /// Embed [text] into a float vector for RAG retrieval.
  Future<List<double>> embed(String text);

  /// Returns true if the provider is reachable (health check).
  Future<bool> isAvailable();

  /// The model identifier being used (e.g. 'qwen2.5-coder:7b').
  String get modelId;
}

/// Input to a single LLM diagnosis request.
final class DiagnoseRequest {
  const DiagnoseRequest({
    required this.batch,
    required this.ragChunks,
    required this.sessionId,
    this.projectContext,
  });

  final TelemetryBatch batch;

  /// Top-k RAG chunks retrieved from the Vector Store.
  final List<RagChunk> ragChunks;

  final String sessionId;

  /// Optional project-level context (Flutter version, recent diagnoses, etc.).
  final String? projectContext;
}

/// A single Knowledge Base chunk retrieved for RAG context.
final class RagChunk {
  const RagChunk({
    required this.entryId,
    required this.content,
    required this.similarity,
    required this.sources,
  });

  final String entryId;
  final String content;

  /// Cosine similarity score [0.0, 1.0].
  final double similarity;

  /// Primary source URLs cited in this chunk.
  final List<String> sources;
}
