# JankDoc

> **Flutter jank diagnosis at the code level. Local AI. Zero data egress.**

JankDoc is a Flutter DevTools extension that watches your app's frame timing in real time and tells you exactly what's causing jank — with a specific file, line, and fix. No guessing, no dashboards, no cloud.

---

## How it works

```
Flutter app  →  VM Service (frame timing, stacks, rebuilds)
                    ↓
            Analysis Daemon (port 9101)
                    ↓
        ┌─── Rule Pre-filter (<5ms, no LLM) ────────────────┐
        │   26 built-in rules across 5 categories            │
        │   impeller · rebuild · raster · async · list/grid  │
        └───────────────────────────────────────────────────┘
                    ↓ no match
        ┌─── LLM Tier (Ollama + RAG) ───────────────────────┐
        │   Qwen 2.5 Coder 7B · nomic-embed-text            │
        │   Output validated against real stack frames       │
        └───────────────────────────────────────────────────┘
                    ↓
            DevTools Extension (live UI)
```

---

## Quick start

### 1. Prerequisites

```bash
# Install Ollama
brew install ollama        # macOS
# See https://ollama.com for Linux/Windows

# Pull both models JankDoc uses
ollama pull qwen2.5-coder:7b
ollama pull nomic-embed-text
```

### 2. Add to your Flutter app

Until the packages are on pub.dev, depend on this repository directly.
`jankdoc_core` needs the override because `jankdoc` would otherwise look for
it on pub.dev:

```yaml
# pubspec.yaml
dev_dependencies:
  jankdoc:
    git:
      url: https://github.com/ogpratik/jankdoc.git
      path: packages/jankdoc

dependency_overrides:
  jankdoc_core:
    git:
      url: https://github.com/ogpratik/jankdoc.git
      path: packages/jankdoc_core
```

(Once published: `dev_dependencies: jankdoc: ^1.0.0-beta.1`.)

```dart
// lib/main.dart
import 'package:jankdoc/jankdoc.dart';

void main() async {
  await JankDoc.attach(); // one line, no-op in release builds
  runApp(const MyApp());
}
```

### 3. Run your app in debug mode

```bash
flutter run
```

The daemon starts automatically. Open DevTools → **JankDoc** tab.

`JankDoc.attach()` uses a cached daemon binary, downloads one from the
GitHub release, or falls back to `dart run jankdoc:daemon` (slower first
start, same behaviour). On macOS, debug builds must not be sandboxed — set
`com.apple.security.app-sandbox` to `false` in
`macos/Runner/DebugProfile.entitlements`, as `examples/sample_app` does.

### 4. Stuck? Run the doctor.

```bash
dart run jankdoc:doctor
```

Checks Ollama, both models, the daemon port, and the KB bundle cache. Prints
a copy-pasteable fix for every failing check.

---

## VS Code users: zero-code-change setup

The companion extension in [`jankdoc-vscode`](jankdoc-vscode) starts and
stops the daemon with your Flutter debug session, so no `JankDoc.attach()` is
needed. It is not on the Marketplace yet; build and install it locally:

```bash
cd jankdoc-vscode && npm install && npx @vscode/vsce package
code --install-extension jankdoc-*.vsix
```

---

## Live analysis while you (or your AI) write code

[`jankdoc_lints`](packages/jankdoc_lints) is an analyzer plugin that flags
jank-causing code as it is typed — `setState` in `build()`, sync I/O or
`jsonDecode` during build, animated `Opacity`, per-item `AnimatedBuilder`,
`Clip.antiAliasWithSaveLayer`, eager `ListView` children — with quick fixes.
Findings show up in the IDE, in `dart analyze`, and therefore to AI coding
agents; a Claude Code hook can check every edit the agent makes.

```yaml
# analysis_options.yaml (Dart 3.11+ / Flutter 3.41+)
plugins:
  jankdoc_lints:
    path: /path/to/jankdoc/packages/jankdoc_lints   # until it is on pub.dev
```

Run `dart analyze` (not `flutter analyze`, which exits before plugin results
arrive). See [`packages/jankdoc_lints`](packages/jankdoc_lints) for the rule
list, quick fixes, and the AI-agent hook; [`examples/lint_demo`](examples/lint_demo)
shows every rule firing.

---

## What you get

### Real-time diagnosis panel

Every jank frame produces a structured diagnosis:

| Field | Example |
|---|---|
| Pattern | `animated-builder-rebuild-storm` |
| File:line | `lib/home_screen.dart:42` |
| Widget | `AnimatedBuilder` |
| Confidence | `95%` |
| Severity | `CRITICAL` |
| Fix | Wrap child with `const` or use `AnimatedWidget` |
| Saves | `4–8ms` per frame |
| Recurrence | Seen `3×` in this project |

### Before/after code diff

Every fix includes a code snippet showing exactly what to change.

### Cross-session memory

JankDoc tracks recurrence across sessions in `~/.jankdoc/sessions.db`.
If the same pattern fires in your codebase 10 sessions in a row, the
confidence and severity escalate.

---

## CI mode

```bash
dart run jankdoc:ci --threshold critical=0,high=5
```

Outputs a **SARIF 2.1.0** report that GitHub renders as Code Scanning alerts directly on your PR diff.

To get telemetry to analyse, record a real session: start the daemon with
`dart run jankdoc:daemon --record session.jsonl`, run your app, then
`dart run jankdoc:ci --input session.jsonl`.

```yaml
# .github/workflows/ci.yaml
- name: JankDoc CI
  run: dart run jankdoc:ci
- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  if: always()
  with:
    sarif_file: jankdoc-report.sarif
```

---

## Built-in rule categories

| Category | Rules | Examples |
|---|---|---|
| **Build / Rebuild** | 7 | `animated-builder-rebuild-storm`, `setstate-in-build`, `missing-const-constructor` |
| **Raster** | 5 | `shader-compilation-jank`, `backdrop-filter-overdraw`, `raster-overdraw-opacity` |
| **Impeller** | 5 | `impeller-scroll-jank-ios`, `impeller-elevation-rounded-corners` |
| **Async** | 4 | `sync-io-on-ui-thread`, `json-decode-ui-thread`, `heavy-compute-main-isolate` |
| **List / Grid** | 5 | `listview-missing-extent`, `image-in-list-no-cache` |

---

## Configuration

Zero config required. To customise, add `jankdoc.yaml` to your project root:

```yaml
daemon:
  port: 9101
  model: qwen2.5-coder:7b
analysis:
  llm_enabled: true
  min_over_budget_ms: 5.0
ci:
  thresholds:
    critical: 0
```

See [full schema reference](docs/jankdoc-yaml-schema.md).

---

## Architecture

```
packages/
  jankdoc_core/       → Models, interfaces, built-in rules. No internal deps.
  jankdoc/            → Published package + analysis daemon + doctor.
  jankdoc_extension/  → Flutter DevTools extension (web UI).
  jankdoc_eval/       → Eval harness (pure Dart, no Ollama required).
  jankdoc_lints/      → Analyzer plugin: live warnings + quick fixes in the IDE.
examples/
  sample_app/         → Minimal Flutter app that triggers 3 jank antipatterns.
  lint_demo/          → One example per jankdoc_lints rule.
jankdoc-vscode/       → VS Code companion extension (TypeScript).
```

Dependency direction: `core ← jankdoc ← extension`

---

## Development

This is a Dart workspace (`resolution: workspace`). Standard `pub` commands
work at the root:

```bash
# Fetch all workspace deps
flutter pub get

# Tests
(cd packages/jankdoc && flutter test)
(cd packages/jankdoc_eval && dart test)
(cd packages/jankdoc_extension && flutter test --platform chrome)
(cd packages/jankdoc_lints && dart test && dart run tool/check_demo.dart)

# End-to-end: drives all three sample screens against a real daemon (macOS)
(cd examples/sample_app && flutter test integration_test/e2e_test.dart -d macos)

# Run the sample app
cd examples/sample_app && flutter run

# Health check on your local install
dart run jankdoc:doctor
```

---

## License

MIT © Pratik Pandey
