# jankdoc_lints

**Live JankDoc analysis for Flutter.** Flags jank-causing code the moment it
is written — by you or by an AI coding agent — as warnings in your IDE, in
`dart analyze`, and in CI, with one-click quick fixes.

It complements the runtime [`jankdoc`](../jankdoc) package: runtime JankDoc
diagnoses jank it *observes* in a running app; `jankdoc_lints` catches the
same patterns in *source*, before the app runs and regardless of how fast the
dev machine is.

## Install

Requires Dart 3.11+ / Flutter 3.41+ (analyzer plugins landed in Dart 3.10).

Add to the `analysis_options.yaml` at your project (or workspace) root:

```yaml
plugins:
  jankdoc_lints: ^1.0.0-beta.1
```

Restart the Dart analysis server (VS Code: *Dart: Restart Analysis Server*;
Android Studio/IntelliJ: *Restart Dart Analysis Server*). No `pubspec.yaml`
change is needed — the analysis server fetches the plugin itself.

## What it catches

| Rule | Flags | Quick fix | JankDoc KB |
| :--- | :--- | :--- | :--- |
| `setstate_in_build` | `setState()` called — or scheduled via post-frame callback / microtask / timer — from `build()` | — | `setstate-in-build` |
| `sync_io_in_build` | blocking `dart:io` `…Sync()` calls during build | — | `sync-io-on-ui-thread` |
| `json_decode_in_build` | `jsonDecode` / `json.decode` during build | — | `json-decode-ui-thread` |
| `animated_opacity_widget` | `Opacity` driven by an `Animation`'s `.value` | → `FadeTransition` | `raster-overdraw-opacity` |
| `animated_builder_per_item` | an `AnimatedBuilder`/`ListenableBuilder` per list item in `itemBuilder` | — | `animated-builder-rebuild-storm` |
| `clip_save_layer` | `Clip.antiAliasWithSaveLayer` | → `Clip.antiAlias` | `raster-overdraw-clip` |
| `non_lazy_list` | `ListView`/`GridView.count` with generated `children` (`List.generate`, `.map().toList()`, collection-`for`) | → `ListView.builder` | `listview-non-lazy` |

"During build" includes builder callbacks (`itemBuilder:`, `builder:`) but
not event handlers (`onPressed:`, `onTap:` …) or work moved off the UI isolate
with `compute()` / `Isolate.run()`.

All rules are warnings and on by default. Turn one off:

```yaml
plugins:
  jankdoc_lints:
    version: ^1.0.0-beta.1
    diagnostics:
      non_lazy_list: false
```

Suppress a single occurrence with `// ignore: jankdoc_lints/non_lazy_list`.

## Command line and CI

```bash
dart analyze
```

Use `dart analyze`, not `flutter analyze`: as of Flutter 3.44, `flutter
analyze` exits before analyzer-plugin results arrive and reports no plugin
diagnostics.

## AI coding agents

Agents (Claude Code, Cursor, Copilot, …) see JankDoc findings anywhere they
see analyzer output: IDE diagnostics, or `dart analyze` runs. Two ways to make
it automatic:

**1. Tell the agent.** Add to your `AGENTS.md` / `CLAUDE.md`:

```markdown
After editing Dart files, run `dart analyze` and fix every
`jankdoc_lints/*` warning before finishing.
```

**2. Claude Code hook — check every edit as it happens.** `jankdoc_check
--hook` analyzes each file Claude edits; if it finds jank-causing code it
hands the findings straight back to Claude, which fixes them in the same
turn. Install the command and add the hook to `.claude/settings.json`:

```bash
dart pub global activate jankdoc_lints
```

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|MultiEdit|Write",
        "hooks": [
          { "type": "command", "command": "jankdoc_check --hook", "timeout": 120 }
        ]
      }
    ]
  }
}
```

`jankdoc_check [paths]` without `--hook` prints only JankDoc findings and
exits 1 if there are any — handy for agents without hooks, and for CI.

## Try it

[`examples/lint_demo`](../../examples/lint_demo) has one bad and one fixed
example per rule, plus a ready-made Claude Code hook. From
`packages/jankdoc_lints`, `dart run tool/check_demo.dart` asserts the plugin
reports exactly the expected diagnostics there.
