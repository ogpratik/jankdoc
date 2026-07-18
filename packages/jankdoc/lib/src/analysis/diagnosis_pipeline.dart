import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:uuid/uuid.dart';

import 'ollama_provider.dart';
import 'output_validator.dart';
import 'vector_store_impl.dart';
import '../session/session_repository.dart';

/// Orchestrates the two-tier diagnostic pipeline.
///
/// For each [TelemetryBatch]:
///   1. Rule Pre-filter — <5ms, no LLM
///   2. LLM Tier — RAG + Ollama, only if no rule matched
final class DiagnosisPipeline {
  DiagnosisPipeline({
    required this.ruleEngine,
    required this.llmProvider,
    required this.vectorStore,
    required this.validator,
    required this.sessionRepo,
  });

  final RuleEngine ruleEngine;
  final OllamaProvider llmProvider;
  final InMemoryVectorStore vectorStore;
  final OutputValidator validator;
  final SessionRepository sessionRepo;

  static const _uuid = Uuid();

  /// Process a [TelemetryBatch] and yield zero or more [Diagnosis] objects.
  ///
  /// Yields immediately on a rule match. Yields after LLM completion otherwise.
  Stream<Diagnosis> process(TelemetryBatch batch) async* {
    // ── Tier 1: Rule Pre-filter ──────────────────────────────────────────
    final ruleMatch = ruleEngine.evaluate(batch);
    if (ruleMatch != null) {
      final d = await _buildRuleDiagnosis(ruleMatch, batch);
      await sessionRepo.saveDiagnosis(d);
      yield d;
      return;
    }

    // ── Tier 2: LLM ──────────────────────────────────────────────────────
    // Check Ollama availability first — silent degradation if unavailable.
    if (!await llmProvider.isAvailable()) return;

    // RAG retrieval
    final queryText = _buildQueryText(batch);
    final queryVector = await llmProvider.embed(queryText);
    final chunks = await vectorStore.query(queryVector: queryVector, k: 5);

    if (chunks.isEmpty) return;

    final ragChunks = chunks
        .map((s) => RagChunk(
              entryId: s.entry.id,
              content: s.entry.metadata['content'] as String? ?? '',
              similarity: s.similarity,
              sources: List<String>.from(
                s.entry.metadata['sources'] as List? ?? [],
              ),
            ))
        .toList();

    final request = DiagnoseRequest(
      batch: batch,
      ragChunks: ragChunks,
      sessionId: batch.sessionId,
    );

    final raw = await llmProvider.diagnose(request);
    final validated = validator.validate(raw, batch);
    final withRecurrence = await _annotateRecurrence(
      validated,
      projectFingerprint: batch.projectFingerprint,
    );

    await sessionRepo.saveDiagnosis(withRecurrence);
    yield withRecurrence;
  }

  Future<Diagnosis> _buildRuleDiagnosis(
    RuleMatch match,
    TelemetryBatch batch,
  ) async {
    final rule = match.rule;
    final frame = batch.worstFrame;

    // Find the most relevant user-code stack frame
    final userFrame = frame.uiStack.firstWhere(
      (f) => f.isUserCode,
      orElse: () => frame.uiStack.first,
    );

    final recurrence = await sessionRepo.countRecurrences(
      projectFingerprint: batch.projectFingerprint,
      patternId: rule.patternId,
    );

    return Diagnosis(
      id: _uuid.v4(),
      sessionId: batch.sessionId,
      frameTsMs: frame.timestamp ~/ 1000,
      patternId: rule.patternId,
      confidence: rule.confidence,
      severity: rule.severity,
      tier: DiagnosisTier.rule,
      rootCause: RootCause(
        file: userFrame.file,
        line: userFrame.line,
        column: userFrame.column,
        widgetType: userFrame.widgetType,
        description: 'Matched rule: ${rule.id}',
      ),
      explanation: _explanationForPattern(rule.patternId, frame),
      fix: _fixForPattern(rule.patternId),
      sources: _sourcesForPattern(rule.patternId),
      recurrenceCount: recurrence,
      createdAt: DateTime.now(),
    );
  }

  Future<Diagnosis> _annotateRecurrence(
    Diagnosis d, {
    required String projectFingerprint,
  }) async {
    final count = await sessionRepo.countRecurrences(
      projectFingerprint: projectFingerprint,
      patternId: d.patternId,
    );
    return count > 0 ? d.copyWith(recurrenceCount: count) : d;
  }

  String _buildQueryText(TelemetryBatch batch) {
    final frame = batch.worstFrame;
    // Include enough per-case signal (widget types, function names, file
    // paths) so semantically-distinct cases produce semantically-distinct
    // embeddings. The prior version was too generic: every case's embedding
    // clustered around a "Flutter perf issue" centroid, so RAG kept
    // retrieving the same nearest neighbor.
    final widgetTypes = frame.uiStack
        .map((s) => s.widgetType)
        .whereType<String>()
        .toSet()
        .join(', ');
    final userFiles = frame.uiStack
        .where((s) => s.isUserCode)
        .map((s) => s.file)
        .toSet()
        .take(3)
        .join(', ');
    final threadDominance = frame.rasterThreadMs > frame.uiThreadMs
        ? 'raster-thread bound'
        : 'ui-thread bound';
    final parts = <String>[
      'Flutter performance issue — $threadDominance:',
      'UI thread: ${frame.uiThreadMs.toStringAsFixed(1)}ms',
      'Raster thread: ${frame.rasterThreadMs.toStringAsFixed(1)}ms',
      if (widgetTypes.isNotEmpty) 'Widgets: $widgetTypes',
      if (frame.hasRebuildData)
        'Rebuilt widgets: ${frame.rebuildCounts.entries.take(5).map((e) => '${e.key}×${e.value}').join(', ')}',
      'Stack: ${frame.uiStack.take(5).map((s) => s.function).join(' → ')}',
      if (userFiles.isNotEmpty) 'Files: $userFiles',
      if (batch.deviceInfo.impellerEnabled) 'Impeller enabled',
      'Platform: ${batch.deviceInfo.platform.name}',
    ];
    return parts.join('\n');
  }

  // ── Pattern-specific canned content ────────────────────────────────────
  // In production these are loaded from KB entry YAML files.
  // Scaffolded here as inline strings for the initial implementation.

  String _explanationForPattern(String patternId, dynamic frame) =>
      switch (patternId) {
        'animated-builder-rebuild-storm' =>
          'AnimatedBuilder is wrapping too high in the widget tree, '
              'triggering excessive rebuilds on list items. '
              'Move AnimatedBuilder to wrap only the animated child.',
        'sync-io-on-ui-thread' =>
          'Synchronous I/O detected on the UI thread. File reads/writes '
              'must be performed asynchronously or in an Isolate.',
        'json-decode-ui-thread' =>
          'JSON decoding is blocking the UI thread. Use `compute()` or '
              '`Isolate.run()` to decode large payloads off the main isolate.',
        'raster-overdraw-opacity' =>
          'Opacity widget is triggering a saveLayer() call on the raster thread, '
              'causing GPU overdraw. Replace with AnimatedOpacity or use '
              'FadeTransition for animated opacity changes.',
        'impeller-scroll-jank-ios' =>
          'Impeller-specific scroll jank detected on iOS. This matches '
              'flutter/flutter#137992. Consider adding RepaintBoundary around '
              'complex list items and filing device-specific data on the issue.',
        'impeller-elevation-rounded-corners' =>
          'Material elevation combined with BorderRadius is triggering '
              'expensive Impeller path rendering (flutter/flutter#162312). '
              'Consider using ShadowedBox or caching the shadow layer.',
        _ => 'Performance issue detected: $patternId. '
            'See the sources below for remediation guidance.',
      };

  Fix _fixForPattern(String patternId) => switch (patternId) {
        'animated-builder-rebuild-storm' => const Fix(
            summary:
                'Move AnimatedBuilder to wrap only the animated child widget.',
            expectedImprovementMs: (4.0, 12.0),
            codeBefore: '''
// ❌ Wraps too high — rebuilds entire list item
AnimatedBuilder(
  animation: _controller,
  builder: (context, child) => ListTile(
    title: Text(item.title),           // rebuilds every frame
    trailing: RotatedBox(...),         // the only animated part
  ),
)''',
            codeAfter: '''
// ✅ Wraps only the animated child
ListTile(
  title: Text(item.title),            // rebuilt only when item changes
  trailing: AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => RotatedBox(...),
  ),
)''',
          ),
        'json-decode-ui-thread' => const Fix(
            summary: 'Move JSON decoding to an isolate with compute().',
            expectedImprovementMs: (8.0, 20.0),
            codeBefore: "final data = jsonDecode(response.body);",
            codeAfter: "final data = await compute(jsonDecode, response.body);",
          ),
        'raster-overdraw-opacity' => const Fix(
            summary: 'Replace Opacity with FadeTransition for animated fades.',
            expectedImprovementMs: (3.0, 8.0),
            codeBefore: '''
// ❌ Triggers saveLayer on every frame
Opacity(opacity: _animation.value, child: MyWidget())''',
            codeAfter: '''
// ✅ Uses RenderObject-level compositing
FadeTransition(opacity: _animation, child: MyWidget())''',
          ),
        _ => Fix(
            summary: 'See sources for remediation guidance.',
            expectedImprovementMs: (2.0, 10.0),
          ),
      };

  List<String> _sourcesForPattern(String patternId) => switch (patternId) {
        'animated-builder-rebuild-storm' => [
            'https://docs.flutter.dev/perf/best-practices',
            'https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html',
          ],
        'sync-io-on-ui-thread' => [
            'https://docs.flutter.dev/perf/best-practices#avoid-expensive-synchronous-work-in-build',
          ],
        'json-decode-ui-thread' => [
            'https://docs.flutter.dev/cookbook/networking/background-parsing',
          ],
        'raster-overdraw-opacity' => [
            'https://docs.flutter.dev/perf/rendering-performance#opacity-and-clipping',
          ],
        'impeller-scroll-jank-ios' => [
            'https://github.com/flutter/flutter/issues/137992',
          ],
        'impeller-elevation-rounded-corners' => [
            'https://github.com/flutter/flutter/issues/162312',
          ],
        _ => [],
      };
}
