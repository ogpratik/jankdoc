# Daemon lifecycle: dual-path startup, single discovery contract

Two paths start the daemon; both register the same VM Service extension so the DevTools extension's discovery logic is identical regardless of path.

## The discovery contract

When the daemon is running, the VM Service extension `ext.jankdoc.daemonUrl` is registered on the app's main isolate. The DevTools extension calls this extension on load to get the daemon's HTTP address. If the extension is not registered, the DevTools extension shows a non-blocking status: "JankDoc not active — add `await JankDoc.attach()` before runApp() or install the VS Code companion extension."

## Path 1 — JankDoc.attach() (universal, one-line)

```dart
void main() async {
  await JankDoc.attach(); // no-op in release mode, <10ms in debug/profile
  runApp(const MyApp());
}
```

`JankDoc.attach()`:
1. Checks if a daemon is already listening on port 9101 (handles hot restart — reuses the existing process)
2. If not: spawns `jankdoc_daemon` as a detached child process via `dart:io Process.start()`
3. Waits for the daemon to open its HTTP port (max 3s, with a timeout error)
4. Registers `ext.jankdoc.daemonUrl` with the daemon's address via `dart:developer registerExtension()`
5. Exits cleanly in release mode via `kReleaseMode` guard (compile-time no-op with tree shaking)

Works in VS Code, JetBrains, terminal, and CI. No IDE extension required.

## Path 2 — VS Code companion extension (zero-friction, zero code changes)

A companion VS Code extension (`jankdoc-vscode`, ~200 lines TypeScript) detects Flutter debug sessions, checks for `jankdoc` in `pubspec.yaml`, and spawns `dart run jankdoc:daemon` as a managed process. On session end, it stops the daemon.

The VS Code companion is for teams who cannot or will not modify `main.dart` (e.g. strictly controlled codebases). It is published separately to the VS Code marketplace.

## Hot restart handling

`JankDoc.attach()` checks port 9101 before spawning. If the daemon is already running (from a previous `main()` invocation before a hot restart), the attach call completes in <1ms without spawning a duplicate. The daemon holds a PID lock file in `~/.jankdoc/daemon.lock` to prevent orphaned processes.

## Why not DTD plugin (primary path)

DTD plugin API (Dart 3.6+) would eliminate both paths above and make daemon startup fully automatic with zero user action. Deferred to v2: the API lacks stable documentation for third-party process spawning and risks a breaking change before the v1 launch window.
