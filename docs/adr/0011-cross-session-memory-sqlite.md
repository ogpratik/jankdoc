# Cross-session memory stored in SQLite at ~/.jankdoc/sessions.db

JankDoc persists every Diagnosis across sessions in a local SQLite database using `package:sqlite3`. This enables trend analysis, pattern frequency tracking, and project-specific KB ranking.

## Schema

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  project_fingerprint TEXT NOT NULL,  -- sha256 of pubspec.yaml path
  flutter_version TEXT,
  dart_version TEXT,
  impeller_enabled INTEGER,
  target_platform TEXT,
  started_at INTEGER,
  ended_at INTEGER
);

CREATE TABLE diagnoses (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES sessions(id),
  frame_ts INTEGER,
  pattern_id TEXT,
  tier TEXT CHECK(tier IN ('rule', 'llm')),
  confidence REAL,
  file TEXT,
  line INTEGER,
  widget TEXT,
  explanation TEXT,
  fix TEXT,
  sources TEXT,         -- JSON array of source URLs
  fix_applied INTEGER,  -- 0 | 1 | NULL (NULL = unknown)
  created_at INTEGER
);

CREATE INDEX idx_diagnoses_project ON diagnoses(session_id);
CREATE INDEX idx_diagnoses_pattern ON diagnoses(pattern_id);
```

## What this enables

- **"You've seen this 5 times"** — the extension annotates recurring patterns: "AnimatedBuilder rebuild storm detected — this is the 4th occurrence in this project."
- **CI baseline** — the CI score is a delta from the project's stored baseline, not an absolute number. "3 new HIGH issues since last clean run."
- **Personalised RAG ranking** — patterns that appear frequently in the current project are boosted in the Vector Store retrieval ranking for future sessions.
- **Fix feedback loop** — when a user applies a fix and the issue disappears in the next session, `fix_applied = 1` is inferred. This data trains the confidence calibration for that KB entry.

## v1 scope boundary

Persistence is v1. Trend visualisation (charts, session history view in the extension) is v2. The data model is designed for both — the v1 extension simply shows the "seen N times" annotation without a full history panel.

## Privacy

All data stays in `~/.jankdoc/sessions.db` on the developer's machine. No sync, no cloud. The `project_fingerprint` is a hash of the pubspec path, not the project name or any source code. Deleting the file wipes all history.
