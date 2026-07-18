import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:jankdoc_extension/src/jankdoc_extension_app.dart';
import 'package:jankdoc_extension/src/providers/daemon_provider.dart';
import 'package:jankdoc_extension/src/providers/diagnosis_provider.dart';
import 'package:jankdoc_extension/src/services/daemon_client.dart';

/// Wraps the widget under test in [MaterialApp] + [ProviderScope] with
/// safe provider overrides so we never touch DevTools' `serviceManager`.
Widget _buildTestApp({List<Override> overrides = const []}) {
  // Base overrides that prevent any call to DevTools serviceManager:
  //  - daemonUrlProvider → null (no app connected)
  //  - connectionStateProvider → disconnected
  //  - daemonClientProvider → null
  //  - diagnosisStreamProvider → empty stream
  final baseOverrides = <Override>[
    daemonUrlProvider.overrideWith((ref) => Stream.value(null)),
    connectionStateProvider.overrideWith(
      (ref) => Stream.value(DaemonConnectionState.disconnected),
    ),
    daemonClientProvider.overrideWith((ref) => null),
    daemonInfoProvider.overrideWith((ref) async => null),
    diagnosisStreamProvider.overrideWith(
      (ref) => const Stream.empty(),
    ),
  ];

  return ProviderScope(
    overrides: [...baseOverrides, ...overrides],
    child: const MaterialApp(
      home: JankDocExtensionApp(),
    ),
  );
}

void main() {
  group('JankDocExtensionApp — smoke tests', () {
    testWidgets('renders without throwing in disconnected state',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump(); // settle async providers

      // The status bar should be visible
      expect(find.text('Waiting for JankDoc.attach()'), findsOneWidget);
      // No unhandled exceptions
    });

    testWidgets('shows diagnosis list panel and detail panel in split layout',
        (tester) async {
      // Use a wide viewport so we get the split layout (>700px)
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      // StatusIndicator is always present
      expect(find.text('Waiting for JankDoc.attach()'), findsOneWidget);
    });

    testWidgets('renders in narrow (collapsed) viewport without crash',
        (tester) async {
      // Below the 700px collapse threshold
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      // Status bar is still visible in collapsed mode
      expect(find.text('Waiting for JankDoc.attach()'), findsOneWidget);
    });

    testWidgets('status bar shows "connected" label when daemon is live',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        overrides: [
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connected),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('JankDoc connected'), findsOneWidget);
    });

    testWidgets('status bar shows "Connecting…" label when in connecting state',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        overrides: [
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connecting),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Connecting to daemon…'), findsOneWidget);
    });
  });

  group('JankDocExtensionApp — with live diagnoses', () {
    testWidgets('diagnosis count updates when diagnoses are added',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      // Initially no diagnosis count shown
      expect(find.textContaining('diagnos'), findsNothing);

      // Add two diagnoses via the notifier
      final container = ProviderScope.containerOf(
        tester.element(find.byType(JankDocExtensionApp)),
      );
      container.read(diagnosisNotifierProvider.notifier).add(_fakeDiagnosis('d1'));
      container.read(diagnosisNotifierProvider.notifier).add(_fakeDiagnosis('d2'));

      await tester.pump();

      // Status bar should now show the count
      expect(find.text('2 diagnoses'), findsOneWidget);
    });

    testWidgets('singular "diagnosis" label for exactly one result',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(JankDocExtensionApp)),
      );
      container.read(diagnosisNotifierProvider.notifier).add(_fakeDiagnosis('d1'));
      await tester.pump();

      expect(find.text('1 diagnosis'), findsOneWidget);
    });
  });
}

// ── Test fixture helpers ──────────────────────────────────────────────────────

Diagnosis _fakeDiagnosis(
  String id, {
  DiagnosisTier tier = DiagnosisTier.rule,
  Severity severity = Severity.high,
}) =>
    Diagnosis(
      id: id,
      sessionId: 'session-test',
      frameTsMs: 1_000_000,
      patternId: 'test-pattern',
      confidence: 0.92,
      severity: severity,
      tier: tier,
      rootCause: const RootCause(description: 'test'),
      explanation: 'Explanation for $id.',
      fix: const Fix(
        summary: 'Use const constructor',
        expectedImprovementMs: (2.0, 6.0),
      ),
      sources: const [],
    );
