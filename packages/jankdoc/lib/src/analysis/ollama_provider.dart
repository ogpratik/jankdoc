import 'dart:convert';

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
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;

  @override
  final String modelId;

  final http.Client _client;

  static const _uuid = Uuid();

  /// The JSON schema Ollama will constrain its output to.
  static const _diagnosisSchema = {
    'type': 'object',
    'required': ['pattern_id', 'confidence', 'severity', 'root_cause', 'explanation', 'fix', 'sources'],
    'properties': {
      'pattern_id': {'type': 'string'},
      'confidence': {'type': 'number', 'minimum': 0.0, 'maximum': 1.0},
      'severity': {'type': 'string', 'enum': ['low', 'medium', 'high', 'critical']},
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
      'sources': {'type': 'array', 'items': {'type': 'string'}},
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
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw StateError('Ollama returned ${response.statusCode}: ${response.body}');
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

    await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (chunk.isEmpty) continue;
      try {
        final data = jsonDecode(chunk) as Map<String, dynamic>;
        yield data['response'] as String? ?? '';
      } catch (_) {
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
            'model': 'nomic-embed-text',
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
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _buildPrompt(DiagnoseRequest request) {
    final batch = request.batch;
    final frame = batch.worstFrame;
    final ragContext = request.ragChunks
        .map((c) => '--- ${c.entryId} (similarity: ${c.similarity.toStringAsFixed(2)})\n${c.content}')
        .join('\n\n');

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

Respond with a JSON diagnosis following the schema exactly.
Be specific about file and line. Cite the sources from the KB context.
If you are not confident about a file attribution, omit the file field.''';
  }

  Diagnosis _jsonToDiagnosis(
    Map<String, dynamic> json,
    DiagnoseRequest request,
  ) {
    final rootCauseJson = json['root_cause'] as Map<String, dynamic>;
    final fixJson = json['fix'] as Map<String, dynamic>;
    final improvJson =
        fixJson['expected_improvement_ms'] as Map<String, dynamic>;

    return Diagnosis(
      id: _uuid.v4(),
      sessionId: request.sessionId,
      frameTsMs: request.batch.worstFrame.timestamp ~/ 1000,
      patternId: json['pattern_id'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num).toDouble(),
      severity: Severity.values.byName(json['severity'] as String? ?? 'medium'),
      tier: DiagnosisTier.llm,
      rootCause: RootCause(
        file: rootCauseJson['file'] as String?,
        line: rootCauseJson['line'] as int?,
        widgetType: rootCauseJson['widget_type'] as String?,
        description: rootCauseJson['description'] as String,
      ),
      explanation: json['explanation'] as String,
      fix: Fix(
        summary: fixJson['summary'] as String,
        expectedImprovementMs: (
          (improvJson['min'] as num).toDouble(),
          (improvJson['max'] as num).toDouble(),
        ),
        codeBefore: fixJson['code_before'] as String?,
        codeAfter: fixJson['code_after'] as String?,
      ),
      sources: List<String>.from(json['sources'] as List? ?? []),
      createdAt: DateTime.now(),
    );
  }
}
