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

Agents see JankDoc findings anywhere they see analyzer output (IDE
diagnostics, `dart analyze`). For agents that write code outside an IDE's
diagnostics loop, JankDoc ships an **MCP server**, so any MCP-capable agent
(Claude Code, OpenAI Codex CLI, Cursor, GitHub Copilot agent mode, Windsurf
…) can check its own edits directly.

### Install

```bash
dart pub global activate jankdoc_lints
```

Until it is on pub.dev, install from the repository instead:

```bash
dart pub global activate --source git https://github.com/ogpratik/jankdoc.git --git-path packages/jankdoc_lints
```

This puts `jankdoc_mcp` and `jankdoc_check` in `~/.pub-cache/bin` (add it to
your `PATH`). The project must enable the plugin in its `analysis_options.yaml`
(see [Install](#install)).

### MCP server: `jankdoc_mcp`

| Tool | Returns |
| :--- | :--- |
| `check_file(path)` | JankDoc findings for one `.dart` file as it is on disk: rule, `file:line:col`, message, fix, KB pattern id |
| `check_project(path?)` | Findings for every `.dart` file under a directory (default: the server's working directory) |
| `explain_pattern(pattern_id)` | The KB explanation, fix and before/after code for a rule (`non_lazy_list`) or KB id (`listview-non-lazy`) |

The server keeps one `dart language-server` per project warm, so a check
takes about 20–50 ms instead of the ~3 s a `dart analyze` run costs. The
first check after startup waits for the analysis server and plugin to warm
up (a few seconds; the server starts that as soon as it launches).
Relative paths resolve against the server's working directory, or the
directory passed as its only argument: `jankdoc_mcp [project_dir]`.

Connect your agent (if a GUI editor can't find `jankdoc_mcp`, use the full
path from `which jankdoc_mcp`):

**Claude Code** — from your project directory:

```bash
claude mcp add jankdoc -- jankdoc_mcp
```

or share it with the team in `.mcp.json` at the project root:

```json
{
  "mcpServers": {
    "jankdoc": { "command": "jankdoc_mcp", "args": [] }
  }
}
```

**OpenAI Codex CLI** — `~/.codex/config.toml`:

```toml
[mcp_servers.jankdoc]
command = "jankdoc_mcp"
```

Codex starts the server in the directory you run `codex` from.

**Cursor** — `.cursor/mcp.json` in the project (or `~/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "jankdoc": { "command": "jankdoc_mcp", "args": ["${workspaceFolder}"] }
  }
}
```

**VS Code (GitHub Copilot agent mode)** — `.vscode/mcp.json`:

```json
{
  "servers": {
    "jankdoc": {
      "type": "stdio",
      "command": "jankdoc_mcp",
      "args": ["${workspaceFolder}"]
    }
  }
}
```

**Windsurf** — `~/.codeium/windsurf/mcp_config.json`:

```json
{
  "mcpServers": {
    "jankdoc": { "command": "jankdoc_mcp", "args": ["/path/to/your/app"] }
  }
}
```

Then tell the agent to use it — add to your `AGENTS.md` / `CLAUDE.md`:

```markdown
After editing Dart files, call the JankDoc `check_file` tool on each edited
file and fix every finding before finishing (`explain_pattern` explains
one). Without the tool, run `dart analyze` and fix every `jankdoc_lints/*`
warning.
```

### Claude Code hook: check every edit as it happens

`jankdoc_check --hook` analyzes each file Claude edits; if it finds
jank-causing code it hands the findings straight back to Claude, which fixes
them in the same turn. Add the hook to `.claude/settings.json`:

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

If `jankdoc_mcp` is also running for the project, the hook asks it instead
of starting `dart analyze`, so each edit costs about 0.3 s instead of ~3 s.
(The server advertises itself to the hook through
`.dart_tool/jankdoc_lints/mcp_endpoint.json`, a loopback port plus a random
token; it only checks files inside its project.)

`jankdoc_check [paths]` without `--hook` prints only JankDoc findings and
exits 1 if there are any — handy for agents without MCP or hooks, and for CI.

## Try it

[`examples/lint_demo`](../../examples/lint_demo) has one bad and one fixed
example per rule, plus ready-made MCP configs (`.mcp.json`,
`.cursor/mcp.json`, `.vscode/mcp.json`) and a Claude Code hook. From
`packages/jankdoc_lints`, `dart run tool/check_demo.dart` asserts the plugin
reports exactly the expected diagnostics there, and `dart test -t e2e` runs
the MCP server against it.
