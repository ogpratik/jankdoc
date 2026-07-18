# JankDoc — Product Map & 30-Day Sprint

> **North Star**: JankDoc is the "Auto-Pilot for Performance" — a tool that guarantees
> high-performance apps by default. Developers never think about performance again.
>
> **Acquisition target**: Google (Flutter + Android team).
> **Valuation trigger**: Cross-engine coverage (Flutter + Jetpack Compose + SwiftUI + React Native)
> making JankDoc the performance layer for every Google-adjacent mobile platform.
>
> **Sprint start**: May 14, 2026
> **Hard deadline**: June 14, 2026 — ship everything.

---

## I. Current State (May 14, 2026)

### Built and working

| Layer | Component | Status |
|-------|-----------|--------|
| **Core** | Type system (Diagnosis, Rule, TelemetryBatch, KbEntry, KbBundle, KbVersion) | ✅ |
| **Core** | 4 interfaces (LlmProvider, VectorStore, RuleProvider, KbLoader) | ✅ |
| **Core** | Rule engine — 26 rules, <5ms, 14/14 eval passing | ✅ |
| **Core** | 14 Condition types (And/Or/Not, thread, widget, platform, GC) | ✅ |
| **Core** | KB type system — 4 channels (stable/candidate/experimental/local) | ✅ |
| **Daemon** | 2-tier diagnosis pipeline (Rule Pre-filter → LLM + RAG) | ✅ |
| **Daemon** | Telemetry capture (VM Service, frame timing, stack, GC, Impeller) | ✅ |
| **Daemon** | In-memory vector store with cosine similarity | ✅ |
| **Daemon** | Ollama HTTP client (embed + diagnose) | ✅ |
| **Daemon** | KB seeder (26 entries via Ollama at startup) | ✅ |
| **Daemon** | KB bundle loader (FilesystemKbBundleLoader, SHA-256 verify) | ✅ |
| **Daemon** | KB manager (bundle-first load, 60s hot-reload, seeder fallback) | ✅ |
| **Daemon** | HTTP server (8 endpoints incl. /kb/hot-reload, SSE stream) | ✅ |
| **Daemon** | SARIF 2.1.0 CI output (bin/ci.dart) | ✅ |
| **Eval** | Rule-only harness (20+ fixtures, 100% pass rate) | ✅ |
| **Extension** | Riverpod providers (daemon discovery, diagnosis stream, session) | ✅ |
| **Workspace** | Dart workspace (jankdoc_core + jankdoc + jankdoc_eval) | ✅ |

### Missing — blocks shipping

| Component | Gap | Sprint week |
|-----------|-----|-------------|
| Session persistence | SQLite schema + recurrence tracking | Week 1 |
| Extension UI | Widgets exist, not wired to providers | Week 1 |
| Daemon binary resolution | Compiled exe path + Windows .exe | Week 1 |
| KB Registry client | GitHub Releases API for bundle downloads | Week 1 |
| jankdoc-kb repo | KB YAML + bundle publishing pipeline | Week 1 |
| LLM eval harness | Ollama integration accuracy tests | Week 1 |

---

## II. 30-Day Sprint Plan

```
Week 1: May 14–21   ── Ship MVP (complete all Phase 0 gaps)
Week 2: May 21–28   ── IDE Auto-Pilot (lint plugin + Auto-Fix Engine)
Week 3: May 28–Jun 4 ─ Intelligence Layer (Oracle + multi-metric + team sync)
Week 4: Jun 4–14    ── Cross-Engine + Scale + Polish + Launch
```

---

## Week 1 — May 14–21: Ship MVP

**Goal**: A fully working, installable Flutter DevTools extension.
**Done signal**: Real Flutter app → DevTools → JankDoc tab → live diagnoses → one-click fix.

### Day 1–2: Session Persistence (SQLite)

**File**: `packages/jankdoc/lib/src/session/session_repository.dart`

```sql
-- Schema: ~/.jankdoc/sessions.db

CREATE TABLE sessions (
  id                TEXT PRIMARY KEY,
  project_fingerprint TEXT NOT NULL,
  flutter_version   TEXT,
  dart_version      TEXT,
  device_info_json  TEXT,
  started_at        INTEGER NOT NULL
);

CREATE TABLE diagnoses (
  id                TEXT PRIMARY KEY,
  session_id        TEXT NOT NULL REFERENCES sessions(id),
  project_fingerprint TEXT NOT NULL,
  pattern_id        TEXT NOT NULL,
  severity          TEXT NOT NULL,
  confidence        REAL NOT NULL,
  tier              TEXT NOT NULL,
  root_cause_json   TEXT,
  explanation       TEXT,
  fix_json          TEXT,
  sources_json      TEXT,
  recurrence_count  INTEGER DEFAULT 0,
  created_at        INTEGER NOT NULL
);

CREATE INDEX idx_diagnoses_project_pattern
  ON diagnoses(project_fingerprint, pattern_id);
```

Key methods:
- `saveSession(Session)` — upsert
- `saveDiagnosis(Diagnosis)` — insert
- `countRecurrences(projectFingerprint, patternId) → int`
- `listRecent(limit) → List<Session>`
- `findById(id) → Session?`
- `dispose()` — close SQLite connection

### Day 2–3: Extension UI Wire-Up

**Files**: `packages/jankdoc_extension/lib/src/widgets/`

```
DiagnosisListPanel
  └── watch(diagnosisStreamProvider)
      ├── sort: severity desc → confidence desc → time desc
      ├── filter bar: ALL / CRITICAL / HIGH / MEDIUM
      ├── RecurrenceChip on repeated patterns
      └── tap → DetailPanel

DetailPanel
  ├── Header: patternId, SeverityBadge, ConfidenceBadge, tier tag (RULE / LLM)
  ├── RootCause row: file:line link (ext.flutter.activeDevToolsServer)
  ├── Explanation block (collapsible)
  ├── FixPanel
  │   ├── Before/After code diff (monospace, syntax color)
  │   ├── Expected improvement: "-4ms to -12ms frame time"
  │   └── [Apply Fix] button → AutoFixer (Week 2)
  ├── Sources: clickable URLs
  └── RecurrenceHistory: "Seen 7 times in this project"
```

### Day 3: Daemon Binary Resolution

**File**: `packages/jankdoc/lib/src/daemon_launcher.dart`

```dart
String _resolveDaemonPath() {
  // 1. Compiled binary next to package (production)
  final binDir = Platform.script.resolve('../bin/').toFilePath();
  final ext = Platform.isWindows ? '.exe' : '';
  final compiled = '$binDir/jankdoc_daemon$ext';
  if (File(compiled).existsSync()) return compiled;

  // 2. dart run (development)
  return 'dart'; // args: ['run', 'jankdoc:daemon']
}
```

### Day 4: KB Registry Client

**File**: `packages/jankdoc/lib/src/kb/kb_registry_client.dart`

```dart
final class KbRegistryClient {
  static const _repoApi =
      'https://api.github.com/repos/ogpratik/jankdoc-kb/releases';

  Future<KbVersion?> latestVersion(KbChannel channel) async {
    // GET /releases → filter by channel tag prefix
    // stable: no pre-release tag; candidate: pre-release "candidate.*"; experimental: "exp.*"
  }

  Future<void> download(KbVersion version, String destPath) async {
    // GET /releases/tags/{version} → find .jankdoc-kb asset → stream to destPath
  }
}
```

Wire into KbManager: on startup, check registry → download if newer version available → existing hot-reload mechanism handles the rest.

### Day 5: jankdoc-kb Repository + Bundle Pipeline

**Repo**: `github.com/ogpratik/jankdoc-kb` (new public repo)

```
jankdoc-kb/
├── entries/
│   ├── rebuild/
│   │   ├── animated-builder-rebuild-storm.yaml
│   │   ├── setstate-in-build.yaml
│   │   └── ... (26 entries migrated from kb_catalog.dart)
│   ├── raster/
│   ├── impeller/
│   ├── async/
│   └── list_grid/
├── rules/
│   └── ... (26 rules migrated from builtin_rule_provider)
├── scripts/
│   ├── build_bundle.dart    — serialise entries + rules → KbBundle JSON → gzip
│   └── embed_bundle.dart    — call Ollama nomic-embed-text → write EmbeddingManifest
├── .github/workflows/
│   ├── validate.yml         — dart test packages/jankdoc_eval on every PR
│   └── publish.yml          — on tag push → build + embed → GitHub Releases upload
└── README.md
```

Tag `1.0.0` → Actions run → `jankdoc-kb-1.0.0.jankdoc-kb` uploaded to GitHub Releases.

### Day 5–6: LLM Eval Harness

**File**: `packages/jankdoc_eval/lib/src/llm_harness.dart`

```dart
final class LlmEvalHarness {
  // Requires: Ollama running locally
  // Env var: JANKDOC_EVAL_OLLAMA_URL (default: http://127.0.0.1:11434)
  Future<LlmEvalReport> run(List<EvalCase> cases, LlmProvider llm);
}

final class LlmEvalReport {
  final int total;
  final int patternIdMatches;   // exact patternId match
  final int severityMatches;    // correct severity
  final int hallucinations;     // non-existent file paths cited
  final double avgLatencyMs;
  final double mrr;             // mean reciprocal rank for RAG retrieval

  // Targets: accuracy ≥ 80%, hallucination < 5%, latency < 2000ms
}
```

**Done signal (Week 1)**: `flutter pub add jankdoc` → `JankDoc.attach()` → run app → DevTools tab shows live diagnoses with recurrence counts.

---

## Week 2 — May 21–28: IDE Auto-Pilot

**Goal**: JankDoc catches issues before the app runs. Squiggles while typing. One-click fixes applied and verified.
**Done signal**: Write `AnimatedBuilder` wrapping a `ListView` → squiggle appears → press Quick Fix → code rewritten → mini-benchmark confirms improvement.

### Day 8–9: Dart Analyzer Plugin (`jankdoc_lint`)

**New package**: `packages/jankdoc_lint/`

```yaml
# pubspec.yaml
name: jankdoc_lint
dependencies:
  analyzer: ^6.5.0
  analyzer_plugin: ^0.11.0
  jankdoc_core:
    path: ../jankdoc_core
```

**Static rules (AST-based, no Ollama needed)**:

| Rule ID | AST pattern | Severity |
|---------|-------------|----------|
| `missing_const_constructor` | Constructor call on non-const widget that could be const | warning |
| `animated_builder_wide_subtree` | AnimatedBuilder.builder returns subtree with ≥3 children | warning |
| `setstate_in_build` | `setState()` invocation inside `build()` method body | error |
| `listview_missing_extent` | `ListView()` constructor call without `itemExtent` arg | info |
| `sync_io_in_build` | `readAsStringSync()` / `writeAsStringSync()` inside `build()` | error |
| `json_decode_in_build` | `jsonDecode()` inside `build()` method body | warning |

**Quick Fix actions** (feeds into Auto-Fix Engine):
- `missing_const_constructor` → add `const` keyword
- `animated_builder_wide_subtree` → extract subtree to `StatelessWidget`
- `listview_missing_extent` → add `itemExtent: 56.0` with a TODO comment

**Distribution**: `analysis_options.yaml`:
```yaml
analyzer:
  plugins:
    - jankdoc_lint
```

### Day 9–11: Auto-Fix Engine

**New files**: `packages/jankdoc/lib/src/autofix/`

```
autofix/
├── auto_fixer.dart               — orchestrator: Diagnosis → patch → verify
├── fixers/
│   ├── const_extractor.dart      — inserts const keyword
│   ├── widget_extractor.dart     — extracts subtree to StatelessWidget
│   ├── repaint_boundary.dart     — wraps widget with RepaintBoundary
│   ├── animated_builder.dart     — narrows AnimatedBuilder scope
│   ├── listview_extent.dart      — adds itemExtent
│   └── isolate_mover.dart        — wraps heavy compute in Isolate.run()
└── fix_verifier.dart             — mini-benchmark: before vs after
```

**`auto_fixer.dart` interface**:
```dart
final class AutoFixer {
  // Takes a Diagnosis with rootCause.file + rootCause.line
  // Returns a unified diff patch string
  Future<FixPatch?> buildPatch(Diagnosis diagnosis);

  // Applies patch to source file (reversible — writes .bak first)
  Future<void> applyPatch(FixPatch patch);

  // Reverts to .bak
  Future<void> revert(FixPatch patch);
}

final class FixPatch {
  final String targetFile;
  final String unifiedDiff;
  final String patternId;
}
```

### Day 11–12: Fix Verification (Mini-Benchmark)

**`fix_verifier.dart`**:
```dart
final class FixVerifier {
  // Captures the TelemetryBatch that triggered the diagnosis (stored in session)
  // Re-evaluates the rule engine against the same batch after the patch is applied
  // For non-rule diagnoses: re-runs the LLM tier against the same query
  Future<FrameTimingDelta> verify({
    required TelemetryBatch original,
    required FixPatch patch,
  });
}
```

**Extension UI addition**:
```
DetailPanel → [Apply Fix] button
  → spinner "Applying..."
  → AutoFixer.buildPatch()
  → AutoFixer.applyPatch()
  → FixVerifier.verify()
  → result: "Frame time -6ms (was 22ms, now 16ms) ✅"
  → [Keep Fix] [Revert]
```

**Done signal (Week 2)**: `jankdoc_lint` squiggle on an AnimatedBuilder. One-click fix. Verified improvement shown in DevTools panel.

---

## Week 3 — May 28–June 4: Intelligence Layer

**Goal**: JankDoc is smarter than any human Flutter performance expert. The KB updates itself. Multi-metric vision live.
**Done signal**: flutter/flutter files a new Impeller performance issue → JankDoc proposes a KB entry within 24 hours → after review, it's live in the experimental channel.

### Day 15–16: Global Performance Oracle

**New service** (Python, separate from Dart monorepo): `jankdoc-oracle/`

```
jankdoc-oracle/
├── oracle/
│   ├── crawler.py          — polls flutter/flutter GitHub Issues
│   │                         filter: labels ["perf:", "impeller", "jank", "regression"]
│   ├── extractor.py        — sends issue body to LLM (Claude API)
│   │                         output: structured KbEntry YAML + Rule YAML
│   ├── validator.py        — calls jankdoc_eval fixtures: rule must pass ≥1 positive fixture
│   └── pr_creator.py       — opens GitHub PR to jankdoc-kb repo
├── prompts/
│   ├── kb_entry.md         — system prompt: how to write a KbEntry
│   └── rule_yaml.md        — system prompt: how to write a Rule
└── .github/workflows/
    └── oracle.yml          — runs daily at 08:00 UTC
```

**LLM prompt contract** (in `prompts/kb_entry.md`):
```
Given a Flutter performance GitHub issue, extract:
- id: kebab-case slug of the issue title
- category: one of [rebuild, raster, impeller, async, list_grid, memory, network, battery]
- severity: one of [low, medium, high, critical]
- title: short human-readable title
- description: what causes the jank, which widgets/APIs are involved
- detectionSignals: widgetTypes[], stackPatterns[], minUiThreadMs?, requiresImpeller?
- fixGuidance: concrete step-by-step fix
- sources: [github.com/flutter/flutter/issues/XXXXX]
Output: valid YAML matching KbEntry schema. No markdown fencing.
```

**PR template** (auto-generated):
```markdown
## Oracle-generated KB Entry

**Source**: flutter/flutter#XXXXX
**Confidence**: 0.82 (LLM score)
**Validation**: rule passes 1 synthetic fixture

Reviewer checklist:
- [ ] Source link is a real flutter/flutter issue
- [ ] Category is correct
- [ ] Fix guidance is actionable and correct
- [ ] Severity matches issue impact
```

### Day 16–17: Multi-Metric Diagnosis (Memory + Network + Battery)

**New Condition types** (`jankdoc_core/lib/src/models/rule.dart`):

```dart
// Memory signals
final class RetainedObjectCount extends Condition {
  const RetainedObjectCount({required this.greaterThan, required this.className});
  // Evaluate: batch.memorySnapshot?.retainedObjects[className] > greaterThan
}

final class ClosureLeak extends Condition {
  const ClosureLeak(this.contextClass);
  // Evaluate: batch.memorySnapshot?.suspectedLeaks.contains(contextClass) ?? false
}

// Network signals
final class RedundantApiCall extends Condition {
  const RedundantApiCall({this.withinMs = 5000});
  // Evaluate: duplicate URL in batch.networkEvents within time window
}

final class UncompressedImage extends Condition {
  const UncompressedImage({this.minSizeKb = 500});
  // Evaluate: batch.networkEvents any with content-type image/* and size > minSizeKb without webp/avif
}

// Battery/CPU spin signals
final class CpuSpinningIdle extends Condition {
  const CpuSpinningIdle({this.cpuThresholdPercent = 15.0});
  // Evaluate: batch.cpuProfile?.idleFrameCpuPercent > cpuThresholdPercent
}
```

**New TelemetryBatch fields**:
```dart
// telemetry_batch.dart additions:
final MemorySnapshot? memorySnapshot;
final List<NetworkEvent> networkEvents;
final CpuProfile? cpuProfile;
```

**New KB categories** (`kb_category.dart`):
```dart
enum KbCategory {
  // existing:
  rebuild, raster, overdraw, async, listGrid, impeller, animation, image, text,
  // new:
  memory,    // object retention, closure captures
  network,   // redundant fetches, image compression
  battery,   // background work, CPU spin
}
```

**New rules** (12 additional):
- `closure-context-leak` — closure retaining widget tree after dispose
- `stream-not-cancelled` — StreamSubscription not cancelled in dispose
- `timer-not-cancelled` — Timer.periodic not cancelled
- `redundant-api-call` — same URL fetched twice within 5s
- `uncompressed-network-image` — >500KB PNG/JPEG without caching
- `unnecessary-cache-bust` — cache-busting query params on static assets
- `cpu-spin-on-idle` — CPU >15% when no frames rendering
- `background-isolate-overuse` — >3 isolates running simultaneously
- `platform-channel-flood` — >10 platform channel calls/sec
- `large-json-response` — JSON response >1MB decoded on UI thread
- `image-decode-ui-thread` — `Image.memory()` with large bytes on UI thread
- `animation-tick-idle` — AnimationController ticking on static screen

### Day 17–18: Team Dashboard (Collaborative Performance History)

**Architecture**: Opt-in sync. Privacy-safe — only pattern IDs and file paths, never source code.

**New package**: `packages/jankdoc_cloud/`

```dart
// Cloud sync client
final class JankDocCloudClient {
  static const _apiBase = 'https://jankdoc.dev/api/v1';

  // Auth: GitHub OAuth (project token based on repo fingerprint)
  Future<void> syncDiagnosis(Diagnosis d, String projectFingerprint);
  Future<List<TeamDiagnosis>> fetchTeamHistory(String projectFingerprint);
  Future<List<RegressionAlert>> checkRegressions(String projectFingerprint);
}
```

**Team Dashboard** (web app at `jankdoc.dev/dashboard`):

```
Timeline view:
  2026-05-20 — @dev-london fixed animated-builder-rebuild-storm in lib/home_screen.dart
  2026-05-22 — @dev-sf saw setstate-in-build (same file, 3rd recurrence)
  2026-05-23 — REGRESSION: animated-builder-rebuild-storm reappeared after PR #234

"Never write the same jank twice" banner: patterns your team has already fixed.
```

**Privacy controls**:
```yaml
# jankdoc.yaml (project root)
cloud:
  enabled: true                    # opt-in
  share_file_paths: true           # default true — file paths only, no content
  share_pattern_ids: true          # default true
  share_fix_attribution: true      # default true — shows who fixed what
  team_id: "ogpratik/jankdoc"      # GitHub repo as team identifier
```

**Done signal (Week 3)**: New flutter/flutter issue filed → oracle proposes KB entry in PR within 24h. Memory leak diagnosed in a test app. Team sync shows diagnosis in dashboard.

---

## Week 4 — June 4–14: Cross-Engine + Scale + Launch

**Goal**: JankDoc works on Jetpack Compose, SwiftUI, and React Native. Performance Contracts shipping. Public launch.
**Done signal**: Same JankDoc KB entry catches animated-builder-rebuild-storm equivalent in Kotlin Compose code.

### Day 22–24: Jetpack Compose SDK

**New package**: `packages/jankdoc_compose/` (Kotlin)

```kotlin
// android/src/main/kotlin/dev/jankdoc/compose/JankDoc.kt
object JankDoc {
  fun attach(activity: ComponentActivity) {
    // 1. Register Choreographer.FrameCallback for frame timing
    // 2. Register RecompositionTracker for recomposition counts
    // 3. Start HTTP client → POST to daemon (same protocol, new platform field)
  }
}
```

**Signal mapping to TelemetryBatch**:
```
Choreographer frame time → uiThreadMs + rasterThreadMs
Recomposition counts → rebuildCounts
ComposeUI backtrace → uiStack
android.os.Build.MODEL → gpuName
Jetpack Compose BuildConfig.VERSION → flutterVersion field (reused as frameworkVersion)
```

**New `TargetPlatform` values** (`jankdoc_core`):
```dart
enum TargetPlatform {
  android, ios, macos, windows, linux, fuchsia,  // existing
  androidCompose,   // new
  iosSwiftUI,       // new
  reactNative,      // new
}
```

**Compose-specific rules** (new file: `jankdoc_core/lib/src/rules/compose_rules.dart`):
```dart
const List<Rule> composeRules = [
  Rule(
    id: 'compose-recomposition-storm',
    // Mirror of animated-builder-rebuild-storm
    // RebuildStorm('LazyColumn', factor: 1.5) + AnyWidgetType(['LazyColumn', 'LazyRow'])
  ),
  Rule(
    id: 'compose-missing-key',
    // Mirror of list-missing-keys
  ),
  Rule(
    id: 'compose-remember-missing',
    // UiDominant + StackContains('remember') missing in hot path
  ),
  Rule(
    id: 'compose-side-effect-in-composition',
    // Mirror of setstate-in-build
    // StackContains('SideEffect') inside composable function body
  ),
  Rule(
    id: 'compose-unstable-lambda',
    // Mirror of missing-const-constructor
  ),
];
```

**Android Studio plugin** (new module: `jankdoc-android-studio/`):
- Same architecture as VS Code extension
- Auto-starts daemon, shows diagnoses in a tool window

### Day 24–25: SwiftUI SDK

**New package**: `packages/jankdoc_swiftui/` (Swift)

```swift
// Sources/JankDoc/JankDoc.swift
public class JankDoc {
    public static func attach(to scene: UIScene) {
        // 1. CADisplayLink for frame timing
        // 2. SwiftUI ViewBodyEvaluationTracker (Instruments-compatible)
        // 3. POST TelemetryBatch to daemon
    }
}
```

**SwiftUI-specific rules**:
- `swiftui-view-identity-lost` — missing `id()` modifier on dynamic lists
- `swiftui-expensive-body` — @State changes trigger full body re-evaluation
- `swiftui-missing-equatable` — ObservableObject not conforming to Equatable
- `swiftui-animation-main-thread` — withAnimation block containing heavy compute

**Xcode extension** (new module: `jankdoc-xcode/`):
- Xcode Source Extension: shows JankDoc diagnoses inline

### Day 25–26: React Native SDK

**New package**: `packages/jankdoc_rn/` (TypeScript)

```typescript
// src/JankDoc.ts
export class JankDoc {
  static attach(config?: { daemonUrl?: string }): void {
    // 1. PerformanceObserver for frame timing
    // 2. React DevTools hook for render counts
    // 3. POST TelemetryBatch to daemon
  }
}
```

**React Native-specific rules**:
- `rn-unnecessary-rerender` — component rendering with same props (missing React.memo)
- `rn-javascript-thread-block` — long JS task blocking bridge
- `rn-bridge-flood` — >10 native bridge calls per frame
- `rn-flatlist-no-keyextractor` — FlatList without keyExtractor (mirror of list-missing-keys)

### Day 26–27: Performance Contracts

**New annotation** (`jankdoc_core`):

```dart
// jankdoc_core/lib/src/contracts/performance_contract.dart
@immutable
final class JankDocContract {
  const JankDocContract({
    this.maxFrameTimeMs = 16.0,
    this.maxRebuildCount = 60,
    this.maxRasterMs = 8.0,
    this.tier = PerformanceTier.standard,
  });

  final double maxFrameTimeMs;
  final int maxRebuildCount;
  final double maxRasterMs;
  final PerformanceTier tier;
}

enum PerformanceTier {
  standard,   // 60fps target
  premium,    // 120fps target
  critical,   // zero-jank SLA (paid features, onboarding)
}
```

**Usage**:
```dart
@JankDocContract(maxFrameTimeMs: 16.0, tier: PerformanceTier.premium)
class CheckoutScreen extends StatelessWidget { ... }
```

**Runtime enforcement**:
- Daemon monitors TelemetryBatches for screens with contracts
- Contract breach → Diagnosis with severity = critical, patternId = 'contract-breach'
- CI gate: contract breach → exit 1 (even for medium severity)

**Static enforcement** (`jankdoc_lint`):
- New lint: `contract_breach_static` — if rule engine would match on the widget, show error

### Day 27–28: Fleet Analytics (Enterprise)

**New dashboard section** at `jankdoc.dev/fleet`:

```
Segmented jank rates:
  iOS 17.x:          0.3% of sessions see HIGH jank
  Android 14 (Pixel): 1.2% of sessions see HIGH jank
  Android 14 (Samsung Exynos): 4.8% of sessions (!)

Top patterns this week:
  1. impeller-scroll-jank-ios       → 23% of iOS sessions
  2. shader-compilation-jank        → 18% of sessions
  3. animated-builder-rebuild-storm → 14% of sessions

Regression detection:
  Deploy 2.4.1 introduced "raster-overdraw-opacity" for 8.2% of users
  [View PR diff]  [File issue]
```

**New daemon endpoint**: `GET /fleet/report` → aggregated anonymised stats.

**Privacy**: All fleet data is opt-in, aggregated, and never contains source code.

### Day 28–30: Launch Polish

1. **README** (`README.md` rewrite):
   - 30-second install (3 lines)
   - GIF showing: code → squiggle → fix → verified
   - Badges: pub.dev version, CI status, eval pass rate, rule count
   - "Supported engines" section: Flutter / Compose / SwiftUI / React Native

2. **GitHub Action** (`jankdoc-action`):
   ```yaml
   # .github/workflows/perf.yml
   - uses: ogpratik/jankdoc-action@v1
     with:
       severity: high          # fail on HIGH+
       sarif-upload: true      # upload to GitHub Code Scanning
   ```

3. **pub.dev publish**: `jankdoc 1.0.0` + `jankdoc_lint 1.0.0` + `jankdoc_core 1.0.0`

4. **Show HN post** (June 14, 2026):
   ```
   Show HN: JankDoc — auto-pilot for Flutter/Compose/SwiftUI/RN performance
   
   We built a tool that:
   - Detects jank while you type (IDE plugin)
   - Fixes it automatically (one-click, verified improvement)
   - Works across Flutter, Jetpack Compose, SwiftUI, React Native
   - Updates its KB from flutter/flutter issues autonomously
   - Runs 100% locally — zero data egress
   
   26 built-in rules, <5ms detection, SARIF CI integration.
   ```

---

## III. Feature Dependency Graph (Sprint Order)

```
Session Persistence ────────────────► Recurrence tracking ────► Team Dashboard
                                                                        │
Extension UI Wire-up ───────────────► Usable MVP ──────────────────────┤
                                                                        │
KB Registry + jankdoc-kb repo ──────► Dynamic KB ──────────────────────┤
                                              │                         │
                                              ▼                         │
KbManager hot-reload (✅ built) ────────────► Live updates             │
                                                                        │
jankdoc_lint (analyzer plugin) ──────────────────────────────► Shift-Left
         │
         ▼
Auto-Fix Engine ────────────────────► Fix Verifier ─────────► One-click repair
                                                                        │
Global Performance Oracle ──────────► Self-updating KB ────────────────┤
                                                                        │
Multi-Metric (memory/network/battery) ──────────────────────────────── ┤
                                                                        │
Compose SDK ────────────────────────────────────────────────── Cross-engine
SwiftUI SDK ─────────────────────────────────────────────────────────── │
React Native SDK ────────────────────────────────────────────────────── │
                                                                        │
Performance Contracts ──────────────────────────────────────── SLA enforcement
                                                                        │
Fleet Analytics ────────────────────────────────────────────── Enterprise tier
                                                                        │
                                                              Google acquisition
```

---

## IV. Current Architecture Reference

### Package map

| Package | Language | Purpose |
|---------|----------|---------|
| `jankdoc_core` | pure Dart | Types, interfaces, rule engine, KB models |
| `jankdoc` | Flutter | Daemon server, telemetry, analysis pipeline |
| `jankdoc_eval` | pure Dart | Eval harness, fixtures, accuracy measurement |
| `jankdoc_extension` | Flutter web | DevTools extension UI |
| `jankdoc_lint` | pure Dart | Analyzer plugin for IDE squiggles *(Week 2)* |
| `jankdoc_cloud` | pure Dart | Team sync client *(Week 3)* |
| `jankdoc_compose` | Kotlin | Jetpack Compose SDK *(Week 4)* |
| `jankdoc_swiftui` | Swift | SwiftUI SDK *(Week 4)* |
| `jankdoc_rn` | TypeScript | React Native SDK *(Week 4)* |

### Daemon HTTP API (port 9101)

```
GET  /health
GET  /info
POST /telemetry/batch          → receives TelemetryBatch
GET  /diagnoses/stream         → SSE stream of Diagnosis
GET  /sessions                 → list recent sessions
GET  /sessions/:id
GET  /kb/status
POST /kb/reseed
POST /kb/hot-reload
GET  /fleet/report             → fleet analytics (Week 4)
```

### Rule inventory (26 built-in + 38 planned)

```
Current (26 rules):
  Build/Rebuild (7): animated-builder-rebuild-storm, setstate-in-build,
    missing-const-constructor, expensive-computation-in-build,
    inherited-widget-over-rebuild, helper-method-instead-of-widget,
    value-notifier-whole-tree-rebuild
  Raster (5): raster-overdraw-opacity, raster-overdraw-clip,
    shader-compilation-jank, backdrop-filter-overdraw, missing-repaint-boundary
  Impeller (5): impeller-scroll-jank-ios, impeller-powervr-rogue-spike,
    impeller-elevation-rounded-corners, impeller-custom-scroll-view-android,
    impeller-general-regression
  Async (4): sync-io-on-ui-thread, json-decode-ui-thread,
    heavy-compute-main-isolate, platform-channel-ui-block
  List/Grid (5): listview-missing-extent, listview-non-lazy,
    list-missing-keys, image-in-list-no-cache, image-no-resize-cache

Week 3 additions (12 rules — multi-metric):
  Memory (3): closure-context-leak, stream-not-cancelled, timer-not-cancelled
  Network (4): redundant-api-call, uncompressed-network-image,
    unnecessary-cache-bust, large-json-response
  Battery/CPU (3): cpu-spin-on-idle, background-isolate-overuse,
    platform-channel-flood
  Mixed (2): image-decode-ui-thread, animation-tick-idle

Week 4 additions (14 rules — cross-engine):
  Compose (5): compose-recomposition-storm, compose-missing-key,
    compose-remember-missing, compose-side-effect-in-composition,
    compose-unstable-lambda
  SwiftUI (4): swiftui-view-identity-lost, swiftui-expensive-body,
    swiftui-missing-equatable, swiftui-animation-main-thread
  React Native (4): rn-unnecessary-rerender, rn-javascript-thread-block,
    rn-bridge-flood, rn-flatlist-no-keyextractor
  Contracts (1): contract-breach

Total at launch: 64 rules across 4 platforms
```

---

## V. Engineering Principles (Non-Negotiable)

1. **Deterministic first** — Rule Pre-filter always <5ms. LLM never in hot path.
2. **Local-first** — Zero data egress without explicit opt-in. All processing on-device.
3. **Pure Dart runtime** — No Python, Rust, or native extensions in the user-facing binary.
4. **Interface-first** — Every external dep (LLM, vector store, KB, cloud) behind an interface.
5. **Curated over crowdsourced** — Every KB entry has primary source + review + eval test.
6. **Fail gracefully** — Ollama unavailable = rules only. KB missing = hardcoded catalog.
7. **Privacy by design** — Source code never leaves the machine. Pattern IDs only for sync.
8. **Contracts are law** — A Performance Contract breach is always a CI failure. No bypass.

---

## VI. Sprint Checklist

### Week 1 (May 14–21) — MVP
- [ ] Session persistence: SQLite schema + SessionRepository
- [ ] Extension UI: wire providers to widgets, filter bar, recurrence chips
- [ ] Daemon binary resolution: compiled exe + Windows .exe
- [ ] KB Registry client: GitHub Releases API
- [ ] jankdoc-kb repo: 26 entries migrated, bundle pipeline, Actions CI
- [ ] LLM eval harness: Ollama integration, accuracy + latency metrics

### Week 2 (May 21–28) — IDE Auto-Pilot
- [ ] jankdoc_lint package: 6 static rules with analyzer plugin
- [ ] Quick Fix actions wired to auto_fixer.dart
- [ ] Auto-Fix Engine: 6 fixer implementations
- [ ] Fix Verifier: mini-benchmark before/after
- [ ] Extension [Apply Fix] button + result display

### Week 3 (May 28–Jun 4) — Intelligence
- [ ] jankdoc-oracle Python service: crawler + extractor + validator + pr_creator
- [ ] Multi-metric Conditions: memory, network, battery (6 new types)
- [ ] TelemetryBatch: memorySnapshot, networkEvents, cpuProfile fields
- [ ] 12 new multi-metric rules + KB entries
- [ ] jankdoc_cloud package: opt-in sync client
- [ ] jankdoc.dev/dashboard: team timeline + regression alerts

### Week 4 (Jun 4–14) — Cross-Engine + Launch
- [ ] jankdoc_compose (Kotlin): attach(), signal mapping, 5 rules
- [ ] Android Studio plugin: tool window + diagnosis list
- [ ] jankdoc_swiftui (Swift): attach(), CADisplayLink, 4 rules
- [ ] Xcode extension: inline diagnosis display
- [ ] jankdoc_rn (TypeScript): attach(), PerformanceObserver, 4 rules
- [ ] Performance Contracts: annotation + runtime enforcement + lint rule
- [ ] Fleet analytics: /fleet/report endpoint + jankdoc.dev/fleet dashboard
- [ ] jankdoc-action GitHub Action
- [ ] pub.dev publish: jankdoc 1.0.0 + jankdoc_lint 1.0.0
- [ ] README rewrite with GIF + multi-engine badges
- [ ] Show HN (June 14, 2026)

---

*Sprint started: May 14, 2026*
*Hard deadline: June 14, 2026*
*64 rules × 4 platforms × auto-pilot = acquisition-ready*
