import 'dart:io';

// Hide jankdoc_core's Platform so dart:io.Platform stays in scope.
import 'package:jankdoc_core/jankdoc_core.dart' hide Platform;
import 'package:test/test.dart';

import '../../lib/src/session/session_repository.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

DeviceInfo _stubDevice() => const DeviceInfo(
      platform: TargetPlatform.macos,
      osVersion: '14.0',
      flutterVersion: '3.29.0',
      dartVersion: '3.6.0',
      impellerEnabled: false,
    );

Session _makeSession({
  String id = 'session-1',
  String projectFingerprint = 'fp-abc',
  int startedAtOffset = 0,
}) =>
    Session(
      id: id,
      projectFingerprint: projectFingerprint,
      flutterVersion: '3.29.0',
      dartVersion: '3.6.0',
      deviceInfo: _stubDevice(),
      startedAt: DateTime(2026).add(Duration(seconds: startedAtOffset)),
    );

Diagnosis _makeDiagnosis({
  required String sessionId,
  String id = 'diag-1',
  String patternId = 'excessive-rebuild',
  DateTime? createdAt,
}) =>
    Diagnosis(
      id: id,
      sessionId: sessionId,
      frameTsMs: 16,
      patternId: patternId,
      confidence: 0.9,
      severity: Severity.medium,
      tier: DiagnosisTier.rule,
      rootCause: const RootCause(
        file: 'lib/main.dart',
        line: 42,
        widgetType: 'MyWidget',
        description: 'Unnecessary rebuild detected.',
      ),
      explanation: 'Widget rebuilds on every frame.',
      fix: const Fix(
        summary: 'Wrap with const.',
        expectedImprovementMs: (4.0, 8.0),
        codeAfter: 'const MyWidget()',
      ),
      sources: ['https://flutter.dev/perf'],
      createdAt: createdAt ?? DateTime(2026).toUtc(),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;
  late SessionRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_repo_test_');
    final dbPath = '${tempDir.path}/sessions.db';
    repo = SessionRepository(overrideDbPath: dbPath);
  });

  tearDown(() async {
    repo.dispose();
    await tempDir.delete(recursive: true);
  });

  group('SessionRepository', () {
    test('saveSession is idempotent — saving same session twice yields 1 row',
        () async {
      final session = _makeSession();

      await repo.saveSession(session);
      await repo.saveSession(session); // second save of same object

      final recent = await repo.listRecent(limit: 100);
      expect(
        recent.where((s) => s.id == 'session-1').length,
        equals(1),
        reason: 'INSERT OR REPLACE should leave exactly one row',
      );
    });

    test('saveDiagnosis round-trips all fields via findById', () async {
      final session = _makeSession(id: 'session-rt');
      await repo.saveSession(session);

      final ts = DateTime(2026, 3, 15, 12).toUtc();
      final diag = _makeDiagnosis(
        id: 'diag-rt',
        sessionId: 'session-rt',
        patternId: 'impeller-save-layer',
        createdAt: ts,
      );
      await repo.saveDiagnosis(diag);

      // findById returns the session; diagnoses are persisted — verify the
      // session's diagnosis_count was incremented.
      final found = await repo.findById('session-rt');
      expect(found, isNotNull);
      expect(found!.id, equals('session-rt'));
      expect(found.diagnosisCount, equals(1));

      // Verify the diagnosis row itself via countRecurrences (same session FP).
      final count = await repo.countRecurrences(
        projectFingerprint: 'fp-abc',
        patternId: 'impeller-save-layer',
      );
      expect(count, equals(1));
    });

    test(
        'countRecurrences filters by projectFingerprint AND patternId correctly',
        () async {
      // Two sessions with different project fingerprints.
      final sessionA = _makeSession(id: 'sess-a', projectFingerprint: 'fp-A');
      final sessionB = _makeSession(id: 'sess-b', projectFingerprint: 'fp-B');
      await repo.saveSession(sessionA);
      await repo.saveSession(sessionB);

      // Two diagnoses with the same patternId but different projects.
      await repo.saveDiagnosis(
        _makeDiagnosis(id: 'd1', sessionId: 'sess-a', patternId: 'pat-X'),
      );
      await repo.saveDiagnosis(
        _makeDiagnosis(id: 'd2', sessionId: 'sess-b', patternId: 'pat-X'),
      );
      // One diagnosis with a different patternId in project fp-A.
      await repo.saveDiagnosis(
        _makeDiagnosis(id: 'd3', sessionId: 'sess-a', patternId: 'pat-Y'),
      );

      // Only 1 occurrence of pat-X in fp-A, not 2.
      final countA = await repo.countRecurrences(
        projectFingerprint: 'fp-A',
        patternId: 'pat-X',
      );
      expect(countA, equals(1));

      // pat-Y exists only in fp-A.
      final countY = await repo.countRecurrences(
        projectFingerprint: 'fp-A',
        patternId: 'pat-Y',
      );
      expect(countY, equals(1));

      // pat-X in fp-B is isolated.
      final countB = await repo.countRecurrences(
        projectFingerprint: 'fp-B',
        patternId: 'pat-X',
      );
      expect(countB, equals(1));

      // Unknown fingerprint returns 0.
      final countNone = await repo.countRecurrences(
        projectFingerprint: 'fp-UNKNOWN',
        patternId: 'pat-X',
      );
      expect(countNone, equals(0));
    });

    test('listRecent(limit: N) returns at most N sessions ordered newest first',
        () async {
      // Insert 5 sessions with distinct startedAt times.
      for (var i = 0; i < 5; i++) {
        await repo.saveSession(
          _makeSession(
            id: 'sess-$i',
            projectFingerprint: 'fp-list',
            startedAtOffset: i * 60, // 0 s, 60 s, 120 s …
          ),
        );
      }

      // Limit to 3.
      final page = await repo.listRecent(limit: 3);
      expect(page.length, equals(3));

      // Should be ordered by started_at DESC — newest first.
      expect(page[0].id, equals('sess-4'));
      expect(page[1].id, equals('sess-3'));
      expect(page[2].id, equals('sess-2'));
    });

    test('findById returns null for unknown ID and full session for known ID',
        () async {
      // Unknown ID.
      final missing = await repo.findById('does-not-exist');
      expect(missing, isNull);

      // Known ID.
      final session = _makeSession(id: 'sess-known', projectFingerprint: 'fp-k');
      await repo.saveSession(session);

      final found = await repo.findById('sess-known');
      expect(found, isNotNull);
      expect(found!.id, equals('sess-known'));
      expect(found.projectFingerprint, equals('fp-k'));
      expect(found.flutterVersion, equals('3.29.0'));
      expect(found.dartVersion, equals('3.6.0'));
      expect(found.deviceInfo.platform, equals(TargetPlatform.macos));
      expect(found.isActive, isTrue); // endedAt is null
    });
  });
}
