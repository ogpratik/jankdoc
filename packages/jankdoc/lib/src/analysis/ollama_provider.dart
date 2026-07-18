import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:uuid/uuid.dart';

/// [LlmProvider] implementation targeting Ollama's local HTTP API.
///
/// Supports: JSON-schema constrained decoding, streaming SSE, embedding.
/// Compatible with any Ollama-served model.
final class OllamaProvider implements LlmProvider {
  OllamaProvider({
    required this.baseUrl,
    required this.modelId,
    this.embedModelId = 'nomic-embed-text',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;

  @override
  final String modelId;

  /// The Ollama model used for embedding KB entries and query text.
  ///
  /// Defaults to `nomic-embed-text` — a lightweight, high-quality embedding
  /// model available in Ollama. Override via `--embed-model` daemon flag
  /// if you have a different model pulled locally.
  final String embedModelId;

  final http.Client _client;

  static const _uuid = Uuid();

  /// Throttle: emit at most one "LLM unavailable" log per minute.
  DateTime? _lastUnavailableLog;

  /// The JSON schema Ollama will constrain its output to.
  static const _diagnosisSchema = {
    'type': 'object',
    'required': [
      'pattern_id',
      'confidence',
      'severity',
      'root_cause',
      'explanation',
      'fix',
      'sources'
    ],
    'properties': {
      'pattern_id': {'type': 'string'},
      'confidence': {'type': 'number', 'minimum': 0.0, 'maximum': 1.0},
      'severity': {
        'type': 'string',
        'enum': ['low', 'medium', 'high', 'critical']
      },
      'root_cause': {
        'type': 'object',
        'properties': {
          'file': {'type': 'string'},
          'line': {'type': 'integer'},
          'widget_type': {'type': 'string'},
          'description': {'type': 'string'},
        },
        'required': ['description'],
      },
      'explanation': {'type': 'string'},
      'fix': {
        'type': 'object',
        'properties': {
          'summary': {'type': 'string'},
          'expected_improvement_ms': {
            'type': 'object',
            'properties': {
              'min': {'type': 'number'},
              'max': {'type': 'number'},
            },
          },
          'code_before': {'type': 'string'},
          'code_after': {'type': 'string'},
        },
        'required': ['summary', 'expected_improvement_ms'],
      },
      'sources': {
        'type': 'array',
        'items': {'type': 'string'}
      },
    },
  };

  @override
  Future<Diagnosis> diagnose(DiagnoseRequest request) async {
    final prompt = _buildPrompt(request);

    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': modelId,
            'prompt': prompt,
            'stream': false,
            'format': _diagnosisSchema,
            'options': {
              'temperature': 0.1, // Low temperature for deterministic diagnosis
              'num_predict': 1024,
            },
          }),
        )
        // 60s covers the full schema-constrained decode path for 7B models on
        // consumer hardware. The 10s original was tuned for streaming
        // partial-frame emits; here we wait for the complete JSON.
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw StateError(
          'Ollama returned ${response.statusCode}: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final responseText = body['response'] as String;
    final llmJson = jsonDecode(responseText) as Map<String, dynamic>;

    return _jsonToDiagnosis(llmJson, request);
  }

  @override
  Stream<String> diagnoseStream(DiagnoseRequest request) async* {
    final prompt = _buildPrompt(request);

    final streamRequest = http.Request(
      'POST',
      Uri.parse('$baseUrl/api/generate'),
    )
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': modelId,
        'prompt': prompt,
        'stream': true,
        'format': _diagnosisSchema,
        'options': {'temperature': 0.1},
      });

    final response = await _client.send(streamRequest);

    await for (final chunk in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (chunk.isEmpty) continue;
      try {
        final data = jsonDecode(chunk) as Map<String, dynamic>;
        yield data['response'] as String? ?? '';
      } on Object {
        continue;
      }
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/embeddings'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': embedModelId,
            'prompt': text,
          }),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw StateError('Ollama embed returned ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['embedding'] as List).cast<double>();
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) return true;
    } on Object {
      // Network error — fall through to log + return false.
    }
    _logUnavailableThrottled();
    return false;
  }

  /// Emit an actionable "LLM tier disabled" message at most once per minute.
  ///
  /// Suppresses duplicate log lines during sustained Ollama outages so the
  /// user sees one clear message rather than one per analysed frame.
  void _logUnavailableThrottled() {
    final now = DateTime.now();
    if (_lastUnavailableLog != null &&
        now.difference(_lastUnavailableLog!) < const Duration(minutes: 1)) {
      return;
    }
    _lastUnavailableLog = now;
    stderr.writeln(
      '[JankDoc] LLM tier disabled: Ollama not reachable at $baseUrl. '
      'Install: https://ollama.com  '
      '(Rule-tier still active.)',
    );
  }

  String _buildPrompt(DiagnoseRequest request) {
    final batch = request.batch;
    final frame = batch.worstFrame;
    final ragContext = request.ragChunks
        .map((c) =>
            '--- entry_id: ${c.entryId} (similarity: ${c.similarity.toStringAsFixed(2)})\n${c.content}')
        .join('\n\n');
    // Extract just the entry IDs so we can list the closed-vocabulary
    // explicitly. Without this, the LLM tends to invent generic pattern
    // names (e.g. "expensive-computation-in-build") for any raster issue,
    // producing 0% accuracy against the KB vocabulary.
    final candidateIds =
        request.ragChunks.map((c) => c.entryId).join(', ');

    return '''You are JankDoc, a Flutter performance diagnosis engine.
Analyse this Flutter frame timing data and identify the root cause of the jank.

## Telemetry
- Platform: ${batch.deviceInfo.platform.name}
- Impeller: ${batch.deviceInfo.impellerEnabled}
- Flutter: ${batch.deviceInfo.flutterVersion}
- UI thread: ${frame.uiThreadMs.toStringAsFixed(1)}ms (budget: ${frame.budgetMs.toStringAsFixed(0)}ms)
- Raster thread: ${frame.rasterThreadMs.toStringAsFixed(1)}ms
- Over budget by: ${frame.overBudgetMs.toStringAsFixed(1)}ms
${frame.hasRebuildData ? '- Widget rebuilds: ${frame.rebuildCounts.entries.take(8).map((e) => "${e.key}×${e.value}").join(", ")}' : ''}

## UI Thread Stack (top frames)
${frame.uiStack.take(8).map((s) => "  ${s.file}:${s.line} ${s.function}").join("\n")}

## Raster Thread Stack
${frame.rasterStack.take(4).map((s) => "  ${s.function}").join("\n")}

## Knowledge Base Context
$ragContext

## Instructions
- You MUST set `pattern_id` to exactly one of these known entry_ids from the
  KB context above: $candidateIds
- Do NOT invent new pattern_ids. If none of the candidates fit, pick the
  closest match (e.g. a rebuild-storm entry for any per-frame widget rebuild
  pattern, an overdraw entry for any raster-heavy scenario).
- Be specific about file and line — take them from the UI Thread Stack.
- Cite the sources from the KB context in the `sources` array.
- If you are not confident about file attribution, omit the file field.''';
  }

  Diagnosis _jsonToDiagnosis(
    Map<String, dynamic> json,
    DiagnoseRequest request,
  ) {
    // Defensively pull sub-objects — an under-specified schema-constrained
    // response may omit optional-looking sections. Missing objects become
    // empty maps so we still produce a Diagnosis instead of throwing and
    // being counted as a hard error.
    final rootCauseJson =
        (json['root_cause'] as Map<String, dynamic>?) ?? const {};
    final fixJson = (json['fix'] as Map<String, dynamic>?) ?? const {};
    final improvJson =
        (fixJson['expected_improvement_ms'] as Map<String, dynamic>?) ??
            const {};

    return Diagnosis(
      id: _uuid.v4(),
      sessionId: request.sessionId,
      frameTsMs: request.batch.worstFrame.timestamp ~/ 1000,
      patternId: json['pattern_id'] as String? ?? 'unknown',
      confidence: ((json['confidence'] as num?) ?? 0.5).toDouble(),
      severity: Severity.values.byName(json['severity'] as String? ?? 'medium'),
      tier: DiagnosisTier.llm,
      rootCause: RootCause(
        file: rootCauseJson['file'] as String?,
        line: rootCauseJson['line'] as int?,
        widgetType: rootCauseJson['widget_type'] as String?,
        description:
            rootCauseJson['description'] as String? ?? 'No description provided',
      ),
      explanation: json['explanation'] as String? ?? '',
      fix: Fix(
        summary: fixJson['summary'] as String? ?? 'See KB entry for guidance.',
        expectedImprovementMs: (
          ((improvJson['min'] as num?) ?? 0).toDouble(),
          ((improvJson['max'] as num?) ?? 0).toDouble(),
        ),
        codeBefore: fixJson['code_before'] as String?,
        codeAfter: fixJson['code_after'] as String?,
      ),
      sources: List<String>.from(json['sources'] as List? ?? []),
      createdAt: DateTime.now(),
    );
  }
}
