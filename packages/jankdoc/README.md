# JankDoc

**Flutter jank diagnosis at the code level. Local AI. Zero data egress.**

JankDoc is a Flutter DevTools extension that watches your app's frame timing in
real time and tells you exactly what's causing jank — with a specific file,
line, and fix. No cloud, no telemetry leaves your machine.

---

## 30-second install

```yaml
# pubspec.yaml
dev_dependencies:
  jankdoc: ^1.0.0
```

```dart
// lib/main.dart
import 'package:jankdoc/jankdoc.dart';

void main() async {
  await JankDoc.attach();   // one line, no-op in release builds
  runApp(const MyApp());
}
```

```bash
flutter run
```

Open Flutter DevTools → **JankDoc** tab. That's it.

---

## How it works

Two tiers. Rule pre-filter runs first (deterministic, <5 ms); LLM only fires
when no rule matches.

```
Flutter app → VM Service (frame timing, stacks, rebuilds)
                    ↓
            Analysis Daemon (127.0.0.1:9101, local)
                    ↓
   ┌── Rule pre-filter (26 built-in, <5 ms, no LLM) ────────┐
   │   impeller · rebuild · raster · async · list/grid       │
   └────────────────────────────────────────────────────────┘
                    ↓ no rule matches
   ┌── LLM tier (Ollama + RAG) ────────────────────────────┐
   │   qwen2.5-coder:7b · nomic-embed-text                  │
   │   Output validated against real stack frames           │
   └────────────────────────────────────────────────────────┘
                    ↓
            DevTools extension (live UI)
```

---

## What it detects

26 built-in rules across 5 categories. A sample:

- `animated-builder-rebuild-storm` — AnimatedBuilder in a list, rebuilding every tick
- `setstate-in-build` — infinite rebuild loop from `setState` in `build()`
- `raster-overdraw-opacity` — `Opacity` forcing a `saveLayer` on the raster thread
- `shader-compilation-jank` — first-frame shader compile spikes
- `impeller-scroll-jank-ios` — Impeller-specific iOS scroll regressions
- `sync-io-on-ui-thread` — blocking file I/O on the UI isolate
- `json-decode-ui-thread` — heavy `jsonDecode` in the paint path
- `listview-missing-extent` — non-lazy ListView without `itemExtent`

Full list in [`packages/jankdoc_core/lib/src/rules/`](https://github.com/ogpratik/jankdoc/tree/main/packages/jankdoc_core/lib/src/rules).

---

## Privacy

Everything runs on `127.0.0.1`. No network calls except:

1. Optional KB bundle downloads from a public GitHub Releases URL.
2. Optional daemon binary downloads from a public GitHub Releases URL.

Both are one-time, verified with SHA-256 checksums, and can be disabled
(`--no-kb-registry`). Telemetry, source code, and diagnoses never leave your
machine.

---

## First-run diagnostics

`JankDoc.attach()` prints a colour-coded startup banner:

```
✓ [JankDoc] daemon http://127.0.0.1:9101
✓ [JankDoc] LLM tier: enabled (qwen2.5-coder:7b @ http://127.0.0.1:11434)
✓ [JankDoc] KB: 1.0.0 (26 entries, bundle-loaded)
✓ [JankDoc] Rules: 26 built-in
✓ [JankDoc] ready — open Flutter DevTools → JankDoc tab
```

If Ollama isn't running, that middle line goes red with a one-line install
hint. Pass `quiet: true` (or set `JANKDOC_QUIET=1`) to suppress the banner
in CI.

## Troubleshooting: `jankdoc:doctor`

```bash
dart run jankdoc:doctor
```

Checks Ollama reachability, both required models, daemon port availability,
cached KB bundles, and the macOS network-client entitlement. Every failing
check prints a copy-pasteable fix (`ollama pull qwen2.5-coder:7b`,
`JANKDOC_PORT=9200`, an XML entitlement snippet, etc.). Exit code 1 on
any fail — safe to gate CI on.

---

## CI mode

```yaml
# .github/workflows/ci.yaml
- name: JankDoc CI
  run: dart run jankdoc:ci --input telemetry.json --output jankdoc.sarif
- uses: github/codeql-action/upload-sarif@v3
  if: always()
  with:
    sarif_file: jankdoc.sarif
```

Outputs [SARIF 2.1.0](https://sarifweb.azurewebsites.net/) — GitHub renders it
as Code Scanning alerts on the PR diff.

---

## Try it in 30 seconds

```bash
git clone https://github.com/ogpratik/jankdoc
cd jankdoc/examples/sample_app
flutter run
```

Three intentional jank screens; each fires a specific rule. See
[`examples/sample_app/README.md`](https://github.com/ogpratik/jankdoc/tree/main/examples/sample_app)
for the expected output.

---

## Requirements

- Flutter ≥ 3.29
- Dart ≥ 3.6
- (Optional, for LLM tier) [Ollama](https://ollama.com) with `qwen2.5-coder:7b`
  and `nomic-embed-text` pulled

### macOS: enable the network-client entitlement

Flutter's macOS scaffolding is fully sandboxed by default. JankDoc talks to
its daemon over `127.0.0.1:9101`, so the sandbox needs to allow outgoing
localhost connections. Add this to both
`macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

Without these, `JankDoc.attach()` will report `Could not start daemon:
Operation not permitted` in the console. `flutter run` from dev mode works
without them (dev mode uses a different entitlement set), but a built `.app`
does not — including anything you launch via Instruments or Xcode profile.
See [`examples/sample_app/macos/Runner/DebugProfile.entitlements`](https://github.com/ogpratik/jankdoc/blob/main/examples/sample_app/macos/Runner/DebugProfile.entitlements)
for the exact snippet.

---

## Links

- Source: <https://github.com/ogpratik/jankdoc>
- KB contributor repo: <https://github.com/ogpratik/jankdoc-kb>
- Issue tracker: <https://github.com/ogpratik/jankdoc/issues>

MIT license.
