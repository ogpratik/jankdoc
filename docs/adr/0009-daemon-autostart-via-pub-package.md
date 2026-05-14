# Daemon auto-starts via the pub package; zero manual terminal commands

The Analysis Daemon is spawned automatically by the `jankdoc` pub package running inside the target Flutter app. Users add one declaration before `runApp()`. No separate terminal, no manual `dart run`, no IDE extension required.

## User-facing API

```dart
// main.dart — the only change required
void main() {
  JankDoc.attach(); // no-op in release mode
  runApp(const MyApp());
}
```

## How it works

1. User adds `jankdoc` to `dev_dependencies` and calls `JankDoc.attach()` before `runApp()`.
2. In debug or profile mode: `JankDoc.attach()` spawns the daemon via:
   ```dart
   Process.start('dart', ['run', 'jankdoc:daemon', '--port', port.toString()])
   ```
   `dart run jankdoc:daemon` resolves the `daemon.dart` entry point from the project's `.dart_tool/package_config.json` — no global activation needed, no pre-compilation step.
3. The daemon starts on port 9101 (or the next free port). It registers a VM Service extension `ext.jankdoc.daemonUrl` with the running Flutter app via `dart:developer`.
4. The DevTools extension loads (Flutter web iframe), calls `ext.jankdoc.daemonUrl` via `serviceManager`, and connects to the daemon over HTTP + SSE.
5. When the Flutter app stops (hot restart, quit, IDE disconnect), the daemon process is killed as its child process exits.

## Why this is correct

- **Zero friction** — same mental model as DevTools itself: run your app, open DevTools, the tool is there.
- **No IDE extension** — works identically in VS Code, Android Studio, and terminal `flutter run`.
- **Release mode safety** — `JankDoc.attach()` is a compile-time no-op in release builds. Zero overhead in production.
- **Dart is always on PATH** — if Flutter is installed, `dart run` works. No separate toolchain.
- **Daemon lifecycle is tied to the app** — no orphaned daemon processes. Stop the app, stop the daemon.
- **`dart run` caches the compiled daemon** — subsequent starts are fast (the Dart kernel is cached in `.dart_tool/`).

## The VM Service extension as the handshake

`ext.jankdoc.daemonUrl` is the contract between the pub package and the DevTools extension:
- **Returns** `{ "url": "http://127.0.0.1:9101", "version": "1.0.0" }` when the daemon is running
- **Returns** `{ "error": "daemon_not_ready" }` during the startup window (<500ms typically)
- The DevTools extension polls this extension with exponential backoff (100ms → 200ms → 400ms → …, max 5s) before showing a "connecting…" state

## What happens if Ollama is not running

The daemon starts successfully. The first LLM-tier analysis request returns a structured error:
```json
{ "error": "ollama_unavailable", "message": "Ollama not found at http://127.0.0.1:11434. Start Ollama and try again." }
```
The Rule Pre-filter continues to work without Ollama — 100% of rule-matched diagnoses are unaffected.

## Considered options

- **Manual `dart run jankdoc:daemon` in terminal** — rejected. Two terminals, extra cognitive load, breaks the "just works" expectation of a DevTools extension.
- **VS Code extension starts daemon** — rejected for v1. Fragments the experience between editors. Revisit in v2 as an enhancement (not a replacement).
- **DTD plugin** — the correct long-term answer. DTD (Dart Tooling Daemon) has a service registration API that could start the daemon without touching the target app. Rejected for v1 because the DTD plugin API is insufficiently documented and would add significant implementation risk in week 1. Planned for v2.
- **Daemon runs inside the Flutter app isolate** — rejected. The daemon does heavy I/O (Ollama HTTP, file reads, SSE) that would interfere with the UI thread budget of the app being profiled. It must be a separate process.
