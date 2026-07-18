import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_extension/src/providers/daemon_provider.dart';
import 'package:jankdoc_extension/src/providers/diagnosis_provider.dart';
import 'package:jankdoc_extension/src/services/daemon_client.dart';

void main() {
  // ── DiagnosisNotifier ───────────────────────────────────────────────────────

  group('DiagnosisNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('starts with an empty list', () {
      final list = container.read(diagnosisNotifierProvider);
      expect(list, isEmpty);
    });

    test('add() prepends — newest diagnosis appears first', () {
      final notifier = container.read(diagnosisNotifierProvider.notifier);
      notifier.add(_d('first'));
      notifier.add(_d('second'));
      notifier.add(_d('third'));

      final list = container.read(diagnosisNotifierProvider);
      expect(list.map((d) => d.id).toList(), ['third', 'second', 'first']);
    });

    test('clear() empties the list', () {
      final notifier = container.read(diagnosisNotifierProvider.notifier);
      notifier.add(_d('a'));
      notifier.add(_d('b'));
      notifier.clear();

      expect(container.read(diagnosisNotifierProvider), isEmpty);
    });

    test('caps at 500 entries — oldest are dropped', () {
      final notifier = container.read(diagnosisNotifierProvider.notifier);
      for (var i = 0; i < 505; i++) {
        notifier.add(_d('d-$i'));
      }

      final list = container.read(diagnosisNotifierProvider);
      expect(list.length, 500);
      // Most recently added should still be at index 0
      expect(list.first.id, 'd-504');
      // d-0 through d-4 were evicted
      expect(list.any((d) => d.id == 'd-0'), isFalse);
    });
  });

  // ── filteredDiagnosesProvider ───────────────────────────────────────────────

  group('filteredDiagnosesProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('DiagnosisFilter.all returns every diagnosis', () {
      _seedDiagnoses(container);
      container.read(diagnosisFilterProvider.notifier).state =
          DiagnosisFilter.all;

      expect(container.read(filteredDiagnosesProvider).length, 4);
    });

    test('DiagnosisFilter.rule returns only rule-tier diagnoses', () {
      _seedDiagnoses(container);
      container.read(diagnosisFilterProvider.notifier).state =
          DiagnosisFilter.rule;

      final result = container.read(filteredDiagnosesProvider);
      expect(result, isNotEmpty);
      expect(result.every((d) => d.tier == DiagnosisTier.rule), isTrue);
    });

    test('DiagnosisFilter.llm returns only llm-tier diagnoses', () {
      _seedDiagnoses(container);
      container.read(diagnosisFilterProvider.notifier).state =
          DiagnosisFilter.llm;

      final result = container.read(filteredDiagnosesProvider);
      expect(result, isNotEmpty);
      expect(result.every((d) => d.tier == DiagnosisTier.llm), isTrue);
    });

    test('DiagnosisFilter.critical returns only critical-severity diagnoses', () {
      _seedDiagnoses(container);
      container.read(diagnosisFilterProvider.notifier).state =
          DiagnosisFilter.critical;

      final result = container.read(filteredDiagnosesProvider);
      expect(result, isNotEmpty);
      expect(result.every((d) => d.severity == Severity.critical), isTrue);
    });

    test('returns empty list when notifier is empty', () {
      container.read(diagnosisFilterProvider.notifier).state =
          DiagnosisFilter.rule;
      expect(container.read(filteredDiagnosesProvider), isEmpty);
    });
  });

  // ── diagnosisStatsProvider ──────────────────────────────────────────────────

  group('diagnosisStatsProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('returns zero stats when list is empty', () {
      final stats = container.read(diagnosisStatsProvider);
      expect(stats.total, 0);
      expect(stats.critical, 0);
      expect(stats.avgConfidence, 0.0);
    });

    test('counts totals correctly', () {
      _seedDiagnoses(container); // 4 diagnoses
      final stats = container.read(diagnosisStatsProvider);

      expect(stats.total, 4);
    });

    test('counts rule-tier and llm-tier separately', () {
      _seedDiagnoses(container);
      final stats = container.read(diagnosisStatsProvider);

      expect(stats.ruleTier + stats.llmTier, stats.total);
    });

    test('avgConfidence is within [0,1]', () {
      _seedDiagnoses(container);
      final stats = container.read(diagnosisStatsProvider);

      expect(stats.avgConfidence, inInclusiveRange(0.0, 1.0));
    });

    test('critical count matches number of Severity.critical diagnoses', () {
      _seedDiagnoses(container);
      final stats = container.read(diagnosisStatsProvider);

      final expected = container
          .read(diagnosisNotifierProvider)
          .where((d) => d.severity == Severity.critical)
          .length;
      expect(stats.critical, expected);
    });
  });

  // ── connectionStateProvider (no-URL path) ──────────────────────────────────

  group('connectionStateProvider (no daemon URL)', () {
    test('emits disconnected immediately when daemonUrlProvider yields null',
        () async {
      final container = ProviderContainer(
        overrides: [
          // Override URL discovery so it never calls serviceManager
          daemonUrlProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container
          .read(connectionStateProvider.future);
      expect(state, DaemonConnectionState.disconnected);
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Seeds 4 diagnoses — 2 rule + 2 llm, 1 critical + 1 high + 2 medium.
void _seedDiagnoses(ProviderContainer container) {
  final notifier = container.read(diagnosisNotifierProvider.notifier);
  notifier.add(_d('r1', tier: DiagnosisTier.rule, severity: Severity.critical));
  notifier.add(_d('r2', tier: DiagnosisTier.rule, severity: Severity.high));
  notifier.add(_d('l1', tier: DiagnosisTier.llm, severity: Severity.medium));
  notifier.add(_d('l2', tier: DiagnosisTier.llm, severity: Severity.medium));
}

Diagnosis _d(
  String id, {
  DiagnosisTier tier = DiagnosisTier.rule,
  Severity severity = Severity.high,
  double confidence = 0.9,
}) =>
    Diagnosis(
      id: id,
      sessionId: 'test-session',
      frameTsMs: 1_000_000,
      patternId: 'test-pattern',
      confidence: confidence,
      severity: severity,
      tier: tier,
      rootCause: const RootCause(description: 'test root cause'),
      explanation: 'Explanation for $id.',
      fix: const Fix(
        summary: 'Use const',
        expectedImprovementMs: (2.0, 5.0),
      ),
      sources: const [],
    );
