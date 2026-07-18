# JankDoc Sample App

A minimal Flutter app that intentionally triggers three common jank
antipatterns. Use it to verify a fresh JankDoc install end-to-end — daemon,
telemetry, DevTools extension, and diagnosis output — in about 30 seconds.

## Run

```bash
cd examples/sample_app
flutter run
```

Then open **Flutter DevTools → JankDoc** tab.

## What each screen triggers

| Screen | Antipattern | Expected diagnosis (pattern_id) | Tier | Confidence |
| :--- | :--- | :--- | :--- | :--- |
| A · AnimatedBuilder storm | `AnimatedBuilder` per list item, ticking every frame | `animated-builder-rebuild-storm` | rule | ≥ 0.95 |
| B · setState in build() | `setState` scheduled from within `build()` | `setstate-in-build` | rule | ≥ 0.92 |
| C · Opacity overdraw | Grid of animating `Opacity` widgets forcing `saveLayer` | `raster-overdraw-opacity` | rule | ≥ 0.90 |

Each diagnosis includes the pattern description, a suggested fix, code before/after
snippets, and citations to the KB entry that produced it.

## Troubleshooting

- **No diagnoses appear** → confirm the daemon started (look for
  `[JankDoc] Analysis daemon ready on port …` in the debug console).
- **Amber "daemon not reachable" banner** → the extension polled for 30 s and
  gave up. Restart `flutter run`; JankDoc's `attach()` must complete before
  `runApp()`.
- **Rule-tier only, no LLM output** → Ollama is not running or the model is
  not pulled. Install [Ollama](https://ollama.com), run
  `ollama pull qwen2.5-coder:7b`, and restart.
- **macOS "Could not start daemon: Operation not permitted"** → the built
  `.app` is sandboxed without network-client permission. This app's
  [`DebugProfile.entitlements`](macos/Runner/DebugProfile.entitlements)
  already includes `com.apple.security.network.client` and
  `com.apple.security.network.server`; anyone copying this pattern into
  their own app needs to add both entitlements too. `flutter run` from dev
  mode works without them, but a built `.app` (or profile-mode Instruments
  run) requires them.

## Health check

If anything looks off, run:

```bash
dart run jankdoc:doctor
```

from the workspace root. It runs 5 parallel checks (Ollama reachability,
both models pulled, daemon port free, KB bundle cache) and prints a
copy-pasteable fix for anything failing.

## Purpose

This app doubles as a manual smoke test for every JankDoc release. Every
antipattern here maps to an existing rule in `jankdoc_core/lib/src/rules/`;
if a rule regresses, the corresponding screen will stop producing its
expected diagnosis.
