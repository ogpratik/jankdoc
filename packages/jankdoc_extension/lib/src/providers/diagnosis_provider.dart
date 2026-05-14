import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jankdoc_core/jankdoc_core.dart';

import 'daemon_provider.dart';

// ── Accumulated diagnosis list ────────────────────────────────────────────────

/// Maintains a live, ordered list of [Diagnosis] objects received from the
/// daemon SSE stream. Newest first. Hard-capped at 500 entries.
class DiagnosisNotifier extends StateNotifier<List<Diagnosis>> {
  DiagnosisNotifier() : super(const []);

  static const _maxEntries = 500;

  void add(Diagnosis diagnosis) {
    final next = [diagnosis, ...state];
    state = next.length > _maxEntries ? next.sublist(0, _maxEntries) : next;
  }

  void clear() => state = const [];
}

final diagnosisNotifierProvider =
    StateNotifierProvider<DiagnosisNotifier, List<Diagnosis>>(
  (_) => DiagnosisNotifier(),
);

// ── Live SSE subscription ─────────────────────────────────────────────────────

/// Subscribes to the daemon's diagnosis SSE stream. Each emitted [Diagnosis]
/// is automatically added to [diagnosisNotifierProvider].
///
/// The provider is inactive (empty stream) when the daemon client is null.
final diagnosisStreamProvider = StreamProvider<Diagnosis>((ref) async* {
  final client = ref.watch(daemonClientProvider);
  if (client == null) return;

  await for (final diagnosis in client.diagnosisStream()) {
    ref.read(diagnosisNotifierProvider.notifier).add(diagnosis);
    yield diagnosis;
  }
});

// ── Selection ─────────────────────────────────────────────────────────────────

/// The diagnosis currently shown in the detail panel.
final selectedDiagnosisProvider = StateProvider<Diagnosis?>((ref) => null);

// ── Filtering ─────────────────────────────────────────────────────────────────

enum DiagnosisFilter {
  all('All'),
  rule('Rule-tier'),
  llm('LLM-tier'),
  critical('Critical');

  const DiagnosisFilter(this.label);
  final String label;
}

final diagnosisFilterProvider =
    StateProvider<DiagnosisFilter>((_) => DiagnosisFilter.all);

/// Derived list after applying [diagnosisFilterProvider].
final filteredDiagnosesProvider = Provider<List<Diagnosis>>((ref) {
  final all = ref.watch(diagnosisNotifierProvider);
  final filter = ref.watch(diagnosisFilterProvider);

  return switch (filter) {
    DiagnosisFilter.all => all,
    DiagnosisFilter.rule =>
      all.where((d) => d.tier == DiagnosisTier.rule).toList(),
    DiagnosisFilter.llm =>
      all.where((d) => d.tier == DiagnosisTier.llm).toList(),
    DiagnosisFilter.critical =>
      all.where((d) => d.severity == Severity.critical).toList(),
  };
});

// ── Stats ─────────────────────────────────────────────────────────────────────

final class DiagnosisStats {
  const DiagnosisStats({
    required this.total,
    required this.critical,
    required this.high,
    required this.ruleTier,
    required this.llmTier,
    required this.avgConfidence,
  });

  final int total;
  final int critical;
  final int high;
  final int ruleTier;
  final int llmTier;
  final double avgConfidence;
}

final diagnosisStatsProvider = Provider<DiagnosisStats>((ref) {
  final all = ref.watch(diagnosisNotifierProvider);
  if (all.isEmpty) {
    return const DiagnosisStats(
      total: 0,
      critical: 0,
      high: 0,
      ruleTier: 0,
      llmTier: 0,
      avgConfidence: 0,
    );
  }

  final totalConf = all.fold(0.0, (sum, d) => sum + d.confidence);
  return DiagnosisStats(
    total: all.length,
    critical: all.where((d) => d.severity == Severity.critical).length,
    high: all.where((d) => d.severity == Severity.high).length,
    ruleTier: all.where((d) => d.tier == DiagnosisTier.rule).length,
    llmTier: all.where((d) => d.tier == DiagnosisTier.llm).length,
    avgConfidence: totalConf / all.length,
  );
});
