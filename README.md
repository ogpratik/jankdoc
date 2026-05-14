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
# See https://ollama.ai for Linux/Windows

# Pull the model
ollama pull qwen2.5-coder:7b
```

### 2. Add to your Flutter app

```yaml
# pubspec.yaml
dev_dependencies:
  jankdoc: ^1.0.0
```

```dart
// lib/main.dart
import 'package:jankdoc/jankdoc.dart';

void main() async {
  await JankDoc.attach(); // ← one line, zero overhead in release
  runApp(const MyApp());
}
```

### 3. Run your app in debug mode

```bash
flutter run
```

The daemon starts automatically. Open DevTools → **JankDoc** tab.

---

## VS Code users: zero-code-change setup

Install the [JankDoc VS Code extension](https://marketplace.visualstudio.com/items?itemName=ogpratik.jankdoc).

The daemon starts and stops automatically with your Flutter debug session.
No `JankDoc.attach()` needed.

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
  jankdoc_core/       → Models, interfaces. No internal deps.
  jankdoc_rules/      → Rule engine + 26 built-in rules.
  jankdoc/            → Published package + analysis daemon binary.
  jankdoc_extension/  → Flutter DevTools extension (web UI).
  jankdoc_eval/       → Eval harness (pure Dart, no Ollama required).
jankdoc-vscode/       → VS Code companion extension (TypeScript).
```

Dependency direction: `core ← rules ← jankdoc ← extension`

---

## Development

```bash
# Install Melos
dart pub global activate melos

# Bootstrap all packages
melos bootstrap

# Run all tests
melos run test

# Run eval suite
melos run test:eval

# Build daemon binary
melos run daemon:build

# Build DevTools extension
melos run extension:build
```

---

## License

MIT © Pratik Pandey
