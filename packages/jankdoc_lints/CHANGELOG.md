## 1.0.0-beta.1

- First release: analyzer plugin with 7 warning rules — `setstate_in_build`,
  `sync_io_in_build`, `json_decode_in_build`, `animated_opacity_widget`,
  `animated_builder_per_item`, `clip_save_layer`, `non_lazy_list` — each
  mapped to its JankDoc KB pattern.
- Quick fixes: `Clip.antiAlias`, `FadeTransition`, `ListView.builder`.
- `jankdoc_check` executable for CI and AI agents, with `--hook` mode for
  Claude Code `PostToolUse` hooks.
- `jankdoc_mcp` MCP server (stdio) for any MCP-capable coding agent, with
  `check_file`, `check_project` and `explain_pattern` tools, backed by a warm
  `dart language-server` (~20–50 ms per check). `jankdoc_check --hook` reuses
  a running server when there is one.
