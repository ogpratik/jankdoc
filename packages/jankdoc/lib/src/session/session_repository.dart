import 'dart:convert';
import 'dart:io';

// Hide jankdoc_core's Platform condition class so dart:io.Platform stays in scope.
import 'package:jankdoc_core/jankdoc_core.dart' hide Platform;
// Hide sqlite3's Session extension type so jankdoc_core.Session stays in scope.
import 'package:sqlite3/sqlite3.dart' hide Session;

/// Persists sessions and diagnoses to ~/.jankdoc/sessions.db.
///
/// Uses SQLite via package:sqlite3. Enables cross-session memory:
/// recurrence counts, CI baseline deltas, and pattern trend analysis.
final class SessionRepository {
  SessionRepository() {
    _db = _openDatabase();
    _migrate(_db);
  }

  late final Database _db;

  static String get _dbPath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.jankdoc/sessions.db';
  }

  static Database _openDatabase() {
    final file = File(_dbPath);
    file.parent.createSync(recursive: true);
    return sqlite3.open(_dbPath);
  }

  static void _migrate(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        project_fingerprint TEXT NOT NULL,
        flutter_version TEXT,
        dart_version TEXT,
        device_info TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        diagnosis_count INTEGER DEFAULT 0
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS diagnoses (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES sessions(id),
        frame_ts_ms INTEGER NOT NULL,
        pattern_id TEXT NOT NULL,
        tier TEXT NOT NULL,
        confidence REAL NOT NULL,
        severity TEXT NOT NULL,
        file TEXT,
        line INTEGER,
        widget_type TEXT,
        explanation TEXT NOT NULL,
        fix_summary TEXT,
        sources TEXT,
        fix_applied INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_diagnoses_pattern
      ON diagnoses(pattern_id)
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_diagnoses_session
      ON diagnoses(session_id)
    ''');
  }

  Future<void> saveSession(Session session) async {
    _db.execute('''
      INSERT OR REPLACE INTO sessions
        (id, project_fingerprint, flutter_version, dart_version,
         device_info, started_at, ended_at, diagnosis_count)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      session.id,
      session.projectFingerprint,
      session.flutterVersion,
      session.dartVersion,
      jsonEncode(session.deviceInfo.toJson()),
      session.startedAt.millisecondsSinceEpoch,
      session.endedAt?.millisecondsSinceEpoch,
      session.diagnosisCount,
    ]);
  }

  Future<void> saveDiagnosis(Diagnosis diagnosis) async {
    _db.execute('''
      INSERT OR REPLACE INTO diagnoses
        (id, session_id, frame_ts_ms, pattern_id, tier, confidence,
         severity, file, line, widget_type, explanation, fix_summary,
         sources, fix_applied, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      diagnosis.id,
      diagnosis.sessionId,
      diagnosis.frameTsMs,
      diagnosis.patternId,
      diagnosis.tier.name,
      diagnosis.confidence,
      diagnosis.severity.name,
      diagnosis.rootCause.file,
      diagnosis.rootCause.line,
      diagnosis.rootCause.widgetType,
      diagnosis.explanation,
      diagnosis.fix.summary,
      jsonEncode(diagnosis.sources),
      null, // fix_applied unknown until user provides feedback
      (diagnosis.createdAt ?? DateTime.now()).millisecondsSinceEpoch,
    ]);

    // Increment session diagnosis count
    _db.execute('''
      UPDATE sessions
      SET diagnosis_count = diagnosis_count + 1
      WHERE id = ?
    ''', [diagnosis.sessionId]);
  }

  Future<int> countRecurrences({
    required String projectFingerprint,
    required String patternId,
  }) async {
    final result = _db.select('''
      SELECT COUNT(*) as cnt
      FROM diagnoses d
      JOIN sessions s ON d.session_id = s.id
      WHERE s.project_fingerprint = ?
        AND d.pattern_id = ?
    ''', [projectFingerprint, patternId]);

    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<List<Session>> listRecent({int limit = 20}) async {
    final rows = _db.select('''
      SELECT * FROM sessions
      ORDER BY started_at DESC
      LIMIT ?
    ''', [limit]);

    return rows.map(_rowToSession).toList();
  }

  Future<Session?> findById(String id) async {
    final rows = _db.select(
      'SELECT * FROM sessions WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _rowToSession(rows.first);
  }

  Session _rowToSession(Row row) => Session(
        id: row['id'] as String,
        projectFingerprint: row['project_fingerprint'] as String,
        flutterVersion: row['flutter_version'] as String? ?? '',
        dartVersion: row['dart_version'] as String? ?? '',
        deviceInfo: DeviceInfo.fromJson(
          jsonDecode(row['device_info'] as String) as Map<String, dynamic>,
        ),
        startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
        endedAt: row['ended_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['ended_at'] as int)
            : null,
        diagnosisCount: (row['diagnosis_count'] as int?) ?? 0,
      );

  void dispose() => _db.dispose();
}
