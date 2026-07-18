# Changelog

## 1.0.0-beta.1

First public beta.

### What's in the box

- **`JankDoc.attach()`** — one-line integration. Idempotent, hot-restart safe,
  compile-time no-op in release builds.
- **Analysis daemon** — HTTP server on `127.0.0.1:9101`. Bundled as a native
  binary; falls back to `dart run jankdoc:daemon` when the binary is missing.
- **Two-tier diagnosis pipeline**:
  - Rule pre-filter — 26 built-in rules across 5 categories
    (impeller · rebuild · raster · async · list/grid). Deterministic, <5 ms.
  - LLM tier — Ollama (`qwen2.5-coder:7b` + `nomic-embed-text` for RAG).
    Output validated against the actual stack frames before emit.
- **DevTools extension** — live diagnosis list + detail panel, cross-session
  recurrence counts, before/after code snippets.
- **Cross-session memory** — SQLite at `~/.jankdoc/sessions.db`.
- **Knowledge base** — versioned bundles from GitHub Releases, SHA-256
  verified. Hot-reloads without restarting the daemon.
- **CI runner** — `dart run jankdoc:ci` emits SARIF 2.1.0 for GitHub Code
  Scanning.

### New in beta.1

- **First-run banner** — colour-coded 5-line summary on `JankDoc.attach()`
  covering daemon URL, LLM tier, KB source, rule count, and ready state.
  Suppress with `attach(quiet: true)` or `JANKDOC_QUIET=1`.
- **`dart run jankdoc:doctor`** — health check that verifies Ollama, both
  required models, port availability, KB cache, and the macOS
  network-client entitlement. Prints copy-pasteable fixes for every failing
  check; exit code 1 on any fail.
- **`~/.jankdoc/setup-ollama.md`** — auto-generated when Ollama isn't
  reachable. Platform-specific install commands.
- **Sample app** — `examples/sample_app/` triggers three antipatterns
  (`animated-builder-rebuild-storm`, `setstate-in-build`,
  `raster-overdraw-opacity`).

### Requirements

- Flutter ≥ 3.29
- Dart ≥ 3.6
- Optional: [Ollama](https://ollama.com) for the LLM tier

### Known limitations

- LLM accuracy baseline against novel jank patterns is not yet published.
- Windows binaries not yet in GitHub Releases — Windows users get the
  `dart run` fallback path.
- **macOS entitlements**: Flutter's default macOS scaffolding is sandboxed
  without network-client permission, so a built `.app` cannot reach the
  JankDoc daemon on `127.0.0.1:9101`. Add
  `com.apple.security.network.client` to your
  `macos/Runner/DebugProfile.entitlements` (and `Release.entitlements` if
  you profile release builds). `flutter run` in dev mode works without this;
  only built `.app` bundles hit it. See the README's macOS section.
