# JankDoc

A Flutter DevTools extension that diagnoses Flutter jank at the code level — naming the root-cause widget, file, and line, and prescribing a concrete fix. Local-first: all analysis runs on the developer's machine via Ollama. Zero data egress.

## Language

**JankDoc**:
The product name. A Flutter DevTools extension for diagnosing Flutter jank.
_Avoid_: FlutterLens (prior working name, deprecated)

**jankdoc**:
The pub.dev package name and repo/directory identifier. Lowercase, no spaces.
_Avoid_: flutter_lens, flutterlens

**Jank Frame**:
A rendered frame that exceeded the device's frame budget: >16ms at 60fps, >8ms at 120fps. The atomic unit of telemetry that triggers analysis.
_Avoid_: "slow frame", "dropped frame", "lag"

**Telemetry Batch**:
A 500ms window of VM Service events. Only batches that contain at least one Jank Frame are forwarded to the Analysis Daemon. All other batches are discarded. Reduces raw event volume by ~95%.
_Avoid_: "log batch", "event stream", "telemetry payload"

**Analysis Daemon**:
A Dart native binary (`dart compile exe`) that owns: telemetry ingestion, the Rule Pre-filter, RAG retrieval, Ollama HTTP calls, output validation, and KB management. Runs as a local background process on port 9101. Communicates with the DevTools Extension over HTTP + SSE.
_Avoid_: "backend", "server", "Python daemon"

**Rule Pre-filter**:
The first diagnostic pass. Runs declarative rules against a Telemetry Batch in <5ms. On match: returns a canned KB Diagnosis with confidence ≥0.85, no LLM invoked. On no-match: forwards the batch to the LLM Tier. The pre-filter is the primary source of trustworthy, instant diagnoses.
_Avoid_: "rule engine" when meaning the whole system, "classifier", "heuristic layer"

**LLM Tier**:
The second diagnostic pass. Only invoked when the Rule Pre-filter produces no match. Sends a RAG-augmented prompt to Ollama and validates the structured JSON response against real stack frames.
_Avoid_: "AI layer", "GPT", "model", "the LLM"

**Rule**:
A declarative data structure — not a Dart function — that expresses a performance antipattern as a composable set of Conditions plus a confidence score and a KB pattern reference. Rules are defined as Dart constant objects; no recompilation is required to add one.
_Avoid_: "heuristic", "check", "detector"

**Condition**:
A composable predicate over a Telemetry Batch. Conditions are composed with `And`, `Or`, `Not` combinators. Examples: `WidgetType('AnimatedBuilder')`, `RebuildCount(greaterThan: FpsMultiple(1.5))`, `ThreadMs(thread: ui, greaterThan: 8.0)`.
_Avoid_: "filter", "check", "signal"

**Knowledge Base (KB)**:
The curated corpus of Flutter performance antipatterns. Each KB Entry is a YAML-front-matter + Markdown file with `id`, `category`, `severity`, `flutter_version_range`, `detection_signals`, and `sources` citing primary Flutter docs or GitHub issues. Seeded with ~50 entries at v1.
_Avoid_: "training data", "dataset", "prompt library", "pattern library"

**KB Entry**:
A single antipattern document in the Knowledge Base. The atomic unit of diagnostic knowledge. Each entry maps to one or more Rules (for the pre-filter) and one or more embedding chunks (for RAG).
_Avoid_: "pattern", "template", "document"

**Diagnosis**:
The structured output JankDoc produces for one analysis request: `{ session_id, frame_ts, pattern_id, confidence, root_cause: { file, line, widget }, explanation, fix, sources, tier }`. The unit of value the user sees. `tier` is either `"rule"` (pre-filter) or `"llm"`.
_Avoid_: "result", "report", "finding", "suggestion", "recommendation"

**Confidence**:
A float [0.0, 1.0] attached to every Diagnosis indicating how certain JankDoc is about the root cause attribution. Rule-tier diagnoses start at the rule's declared confidence (≥0.85). LLM-tier diagnoses are capped at 0.5 if the cited file path is not present in the actual stack frames.
_Avoid_: "score", "probability", "certainty"

**Output Validator**:
The component that cross-checks every LLM-tier Diagnosis against the actual stack frames in the Telemetry Batch. If the cited file is not in the stack, confidence is capped at 0.5 and the explanation is annotated with `(file attribution uncertain)`. Prevents hallucinated file paths from destroying user trust.
_Avoid_: "hallucination filter", "file checker"

**Vector Store**:
The component inside the Analysis Daemon that stores KB Entry embeddings and answers cosine similarity queries for RAG retrieval. In v1: pure-Dart in-memory store with JSON persistence, backed by the `VectorStore` interface. Swappable for a heavier implementation when the KB exceeds 10k entries.
_Avoid_: "LanceDB" (not used in v1), "RAG database", "embedding store"

**Deep Analysis Mode**:
A JankDoc session run against a Flutter app in debug mode. Captures widget rebuild counts with file/line attribution via `ext.flutter.inspector.trackRebuildDirtyWidgets`. Optimised for rebuild-storm diagnosis. Lower frame timing fidelity due to debug overhead.
_Avoid_: "debug mode", "rebuild mode"

**Timing Mode**:
A JankDoc session run against a Flutter app in profile mode. Captures accurate frame budgets, raster/UI thread split, and isolate CPU. No rebuild counts (VM Service limitation: flutter/devtools#9730). Optimised for raster-thread and layout-phase diagnosis.
_Avoid_: "profile mode", "perf mode", "performance mode"

**JankDoc.attach()**:
The single user-facing API call that activates JankDoc. Called before `runApp()` in `main.dart`. In debug/profile mode: spawns the Analysis Daemon as a child process and registers `ext.jankdoc.daemonUrl` with the VM Service. In release mode: compile-time no-op.
_Avoid_: "initialize", "setup", "enable", "JankDocService.init()"

**ext.jankdoc.daemonUrl**:
The VM Service extension registered by the pub package once the daemon is running. The DevTools extension calls this to discover the daemon's HTTP address. The handshake contract between the pub package and the DevTools extension.
_Avoid_: "daemon discovery endpoint", "health check"

**Impeller Diagnostics**:
A sub-set of KB Entries and Rules specific to the Impeller rendering backend (Android API 29+ / iOS default since Flutter 3.27). The v1 launch wedge: 5 Impeller-specific KB entries seeded from open flutter/flutter issues (#137992, #161304, #162312, #168788, #169423).
_Avoid_: "Impeller mode", "Impeller checker"

**Session**:
A single JankDoc analysis run — from `JankDoc.attach()` to app termination. Each session has a unique ID and is persisted in `~/.jankdoc/sessions.db`. All Diagnoses produced in a session belong to it.
_Avoid_: "run", "instance", "recording"

**Session History**:
The SQLite database at `~/.jankdoc/sessions.db` storing all Diagnoses across all sessions for all projects. Used for recurring-pattern annotation, CI baseline delta, and personalised RAG ranking.
_Avoid_: "database", "history file", "local storage"

**CI Mode**:
Headless operation via `dart run jankdoc:ci`. Runs the app against a user-defined interaction script, collects telemetry, produces Diagnoses, and writes a SARIF 2.1.0 report. Exits non-zero if any Diagnosis meets the configured severity threshold.
_Avoid_: "batch mode", "headless mode", "automated mode"

**SARIF Report**:
The machine-readable output of CI Mode. Compatible with GitHub Code Scanning — uploading `jankdoc-results.sarif` to GitHub Actions renders JankDoc findings as first-class code scanning alerts with file/line annotations in PRs.
_Avoid_: "JSON report", "CI output"

**jankdoc.yaml**:
The per-project configuration file at the Flutter project root. Configures LLM provider, model, daemon port, CI interaction script, and severity thresholds. Committed to source control.
_Avoid_: "config file", "settings", "jankdoc config"

## Relationships

- A **Jank Frame** triggers collection of a **Telemetry Batch**
- A **Telemetry Batch** is processed first by the **Rule Pre-filter**, then (if no match) by the **LLM Tier**
- The **Rule Pre-filter** evaluates a list of **Rules**; each **Rule** is a tree of **Conditions**
- The **LLM Tier** retrieves chunks from the **Vector Store** (RAG) before calling Ollama
- Both tiers produce a **Diagnosis**; the **Output Validator** post-processes LLM-tier output
- A **KB Entry** contributes both Rules (to the pre-filter) and embedding chunks (to the Vector Store)
- A **Diagnosis** is persisted to **Session History** immediately after production
- **CI Mode** runs the same pipeline as dev-time analysis but writes a **SARIF Report** instead of streaming to the extension

## Architecture principles

- **Rule-first, LLM-second.** The pre-filter is the primary trust mechanism. The LLM handles the long tail.
- **Pure Dart in the runtime path.** No Python, no Rust, no native extensions in v1. The daemon is `dart compile exe`.
- **Interface-first on every external dependency.** `VectorStore`, `LlmProvider`, `RuleProvider` are interfaces. Implementations swap without touching business logic.
- **Zero data egress by default.** All network calls go to localhost (Ollama, daemon). No telemetry. No analytics.
- **Declarative rules, not imperative code.** A Rule is data. Adding a rule requires no Dart knowledge.
- **Confidence is always explicit.** Every Diagnosis carries a confidence score. Never hide uncertainty.

## Constraints

- DevTools extension runs as Flutter web (iframe) — no native FFI, no process spawning from the extension
- Widget rebuild counts unavailable in profile mode (flutter/devtools#9730) — requires Deep Analysis Mode (debug)
- VM Service unavailable in release mode — JankDoc is dev-time only; mobile and desktop in v1, Flutter Web is v2
- Ollama must be running locally before analysis starts — JankDoc does not manage Ollama's lifecycle

## Flagged ambiguities

- "FlutterLens" was the working name in the v1.0 build plan PDF. Resolved: the product is **JankDoc**. The pub package is `jankdoc`.
- "70% of cases" (rule pre-filter hit rate) is a design target, not a measured claim. The measured number ships with the Week 5 eval results and is published in the README. Marketing copy uses "known patterns are diagnosed in <5ms without invoking the LLM" until the number is measured.
