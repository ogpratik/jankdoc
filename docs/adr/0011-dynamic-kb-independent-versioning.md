# KB is a separately versioned artifact; rules hot-reload without daemon restart

status: supersedes ADR-0003 (rule format) and ADR-0001 (KB distribution model)

The Knowledge Base is decoupled from the `jankdoc` pub package release cycle. It lives in a
separate repository (`jankdoc-kb`), has its own semantic version, and is distributed as a
self-contained KB Bundle. The daemon fetches, caches, and hot-reloads the KB without restarting.
Users never need to upgrade the `jankdoc` package to get new rules — they get them automatically.

## The problem with compiled-in rules

Flutter ships quarterly. Impeller patterns are evolving weekly in 2026. If rules are compiled into
the `jankdoc` native binary, a user on `jankdoc: ^1.0.0` with Flutter 3.42 will run rules
calibrated for Flutter 3.38. The KB decays from day one of each Flutter release. This is the
exact failure mode JankDoc must avoid — it is supposed to be the tool that knows about new jank
patterns, not the tool that's perpetually two releases behind.

## Architecture

### KB Bundle

A KB Bundle is a single `.jankdoc-kb` file (gzipped JSON) containing:
```json
{
  "kb_version": "1.4.2",
  "min_jankdoc_version": "1.0.0",
  "flutter_version_range": ">=3.27.0",
  "entries": [ ... ],
  "rules": [ ... ],
  "embeddings": { "model": "nomic-embed-text", "vectors": { ... } }
}
```

Entries and rules are serialised from YAML source files in the `jankdoc-kb` repository.
Embeddings are pre-computed at KB build time — no embedding call needed on first use.

### KB Registry

`github.com/[org]/jankdoc-kb` hosts versioned KB Bundles as GitHub Releases. The daemon
resolves the latest compatible bundle via:
```
GET https://api.github.com/repos/[org]/jankdoc-kb/releases/latest
```
No custom server. No proprietary CDN. GitHub Releases is the registry.

### KB Cache

Bundles are cached at `~/.jankdoc/kb/<kb_version>.jankdoc-kb`. Multiple versions coexist;
the daemon uses the highest compatible version. Cache is never purged automatically — users
manage it with `dart run jankdoc:kb clean`.

### Daemon KB lifecycle

1. **Startup**: Load the highest cached KB version compatible with the running Flutter version.
   If no cache exists, use the seed KB bundled in the `jankdoc` package (the 50 v1 patterns).
2. **Background check**: 60 seconds after startup, check GitHub Releases for a newer KB version.
   Download in the background if found. Apply without daemon restart via hot-reload.
3. **Hot-reload**: The daemon's `RuleEngine` and `VectorStore` are behind a `KbContext` reference.
   Swapping to a new KB atomically updates both. In-flight analysis requests complete against the
   old KB; new requests use the new KB.
4. **Offline**: If GitHub is unreachable, the daemon logs once and continues with the cached KB.
   Zero crash, zero degradation — the cached KB is always good enough.

### Rule format: YAML source, deserialised at load time

Rules are YAML in the `jankdoc-kb` repository. The daemon deserialises them into the same
`Rule` / `Condition` model from `jankdoc_core`. There are no compiled Dart rule constants in
the binary — the binary contains only the deserialiser and the execution engine.

```yaml
# jankdoc-kb/rules/build_rebuild/excessive-rebuild-animated-builder.yaml
id: excessive-rebuild-animated-builder
kb_entry: excessive-rebuild-animated-builder
confidence: 0.95
conditions:
  and:
    - widget_type: AnimatedBuilder
    - parent_type: [ListView, GridView]
    - rebuild_count:
        greater_than:
          fps_multiple: 1.5
```

This means:
- KB contributors write YAML, not Dart. Zero Dart knowledge required.
- The KB repo CI validates every rule YAML against the schema before merge.
- New rules appear in users' daemons within 60 seconds of a KB release — no pub upgrade.

### CI reproducibility

For CI Mode, the KB version is pinned in `jankdoc.yaml`:
```yaml
jankdoc:
  kb_version: "1.4.x"   # pin minor, float patches
```
This guarantees that a CI run today and a CI run in 3 months use the same rules,
making SARIF report deltas meaningful.

## What does NOT change from ADR-0003

- Rules are still declarative data structures, not imperative code
- The Condition combinator model (`And`, `Or`, `Not`, `WidgetType`, `ThreadMs`, etc.) is identical
- Rules are still fully testable in isolation in `jankdoc_eval`
- The `Rule` and `Condition` types in `jankdoc_core` are unchanged — only their source (YAML, not
  Dart constants) and load time (runtime, not compile time) change

## What changes from ADR-0001 (vector store)

Pre-computed embeddings ship inside the KB Bundle. The daemon loads them at KB hot-reload time
rather than computing them on first query. This eliminates the cold-start embedding delay entirely.
The `VectorStore` interface is unchanged; `InMemoryVectorStore` is populated from the bundle.

## Enterprise / airgapped environments

```yaml
jankdoc:
  kb_updates: disabled       # no GitHub check, use cached or bundled KB only
  kb_path: /shared/kb/       # optional: point at a locally-hosted KB bundle directory
```

## Considered options

- **Compiled Dart constants** (ADR-0003) — rejected. Couples KB freshness to package release
  cycle. KB becomes stale within one Flutter release.
- **Separate pub package (`jankdoc_rules`)** — rejected. `pub upgrade` is still a manual step.
  Enterprise Flutter teams pin dependencies and may not upgrade for months.
- **Dynamic rule download on every analysis request** — rejected. Introduces latency and makes
  offline mode unreliable.
- **Versioned KB Bundle with background hot-reload** — selected. Decouples KB freshness from
  package releases, preserves offline capability, maintains determinism via version pinning.
