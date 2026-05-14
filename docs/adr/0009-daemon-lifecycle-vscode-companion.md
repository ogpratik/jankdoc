# Daemon lifecycle managed by a companion VS Code extension

The DevTools extension (Flutter web iframe) cannot spawn processes. The daemon must be started by something in the developer's environment. The zero-friction path — identical to how Dart-Code starts the Dart language server and how DevTools itself starts automatically — is a companion VS Code extension.

## Architecture

```
flutter run
  └─▶ Dart-Code detects debug session
        └─▶ jankdoc-vscode detects jankdoc in pubspec.yaml
              └─▶ spawns: dart run jankdoc:daemon
                    └─▶ daemon opens port 9101
                          └─▶ DevTools extension connects automatically
```

The companion extension (`jankdoc-vscode`) is ~200 lines of TypeScript. It has no UI of its own — no sidebar, no commands, no settings panels. Its sole responsibility is daemon lifecycle: start on Flutter debug session open, stop on session close. It is published to the VS Code marketplace as a separate extension and is a peer dependency, not bundled with the pub package.

**Activation condition:** Only starts the daemon if `jankdoc` appears in the project's `pubspec.yaml` `dev_dependencies`. Silent no-op otherwise.

## Fallback for JetBrains / terminal users (v1)

```
dart run jankdoc:daemon
```

The DevTools extension shows a status indicator: "Daemon connected" (green) / "Daemon not running — run `dart run jankdoc:daemon`" (yellow, with a copy button). This is honest and unambiguous. No silent failure.

## Why not a DTD plugin

The Dart Tooling Daemon plugin API is the correct long-term path — it would make the companion extension unnecessary by letting the daemon register itself as a DTD service that auto-starts when the project loads. However, the DTD plugin API is new (Dart 3.6+) and lacks stable documentation for third-party process spawning. Building on it for v1 risks a breaking API change before launch. Revisit for v2 when the API stabilises.

## Considered options

- **Manual terminal command only** — adds friction at every session start. Rejected: the target users (enterprise Flutter engineers) will not tolerate this.
- **Service extension inside the Flutter app** — requires user to modify `main.dart` or add an import. Rejected: user code changes are a distribution tax that kills OSS adoption.
- **DTD plugin** — correct long-term, API too new for v1. Deferred to v2.
- **VS Code companion extension** — same pattern as Dart-Code (language server), dart_frog (dev server), Prisma (daemon). Proven, zero friction after one-time marketplace install.
