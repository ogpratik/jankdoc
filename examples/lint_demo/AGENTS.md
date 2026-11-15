# Notes for AI coding agents

This project uses **JankDoc** (`jankdoc_lints` analyzer plugin) to catch
Flutter code that causes jank.

- After editing Dart files, call the JankDoc MCP tool `check_file` on each
  edited file (or `check_project` once at the end) and fix every finding
  before finishing. `explain_pattern` gives the background and a
  before/after fix for a finding's rule.
- Without the MCP server, run `dart analyze` (not `flutter analyze`, which
  does not wait for analyzer-plugin results) and fix every
  `jankdoc_lints/*` warning.
- Each warning's correction message says what to change; the KB id in
  parentheses (e.g. `setstate-in-build`) names the pattern.
- `dart run ../../packages/jankdoc_lints/bin/jankdoc_check.dart` prints only
  JankDoc findings and exits 1 if there are any.

The MCP configs here (`.mcp.json` for Claude Code, `.cursor/mcp.json`,
`.vscode/mcp.json` for Copilot) run the server from this checkout; open
`examples/lint_demo` itself as the project/workspace so the relative paths
resolve.
