# Changelog

## 1.0.0-beta.1

First public beta.

### Included

- **Models** — `TelemetryBatch`, `Diagnosis`, `Rule`, `Condition` AST,
  `Session`, `KbEntry`, `KbBundle`, `KbVersion`.
- **Interfaces** — `RuleProvider`, `RuleEngine`, `KbLoader`, `KbRegistry`,
  `LlmProvider`, `VectorStore`.
- **Built-in rules** — 26 rules across 5 categories:
  - Build / rebuild (7): `animated-builder-rebuild-storm`,
    `setstate-in-build`, `missing-const-constructor`,
    `expensive-computation-in-build`, `inherited-widget-over-rebuild`,
    `helper-method-instead-of-widget`, `value-notifier-whole-tree-rebuild`.
  - Raster (5): `raster-overdraw-opacity`, `raster-overdraw-clip`,
    `shader-compilation-jank`, `backdrop-filter-overdraw`,
    `missing-repaint-boundary`.
  - Impeller (5): `impeller-scroll-jank-ios`,
    `impeller-elevation-rounded-corners`, `impeller-general-regression`,
    `impeller-custom-scroll-view-android`, `impeller-powervr-rogue-spike`.
  - Async (4): `sync-io-on-ui-thread`, `json-decode-ui-thread`,
    `heavy-compute-main-isolate`, `platform-channel-ui-block`.
  - List/grid (5): `listview-missing-extent`, `listview-non-lazy`,
    `image-in-list-no-cache`, `image-no-resize-cache`, `list-missing-keys`.

### Requirements

- Dart ≥ 3.6
- Pure Dart, no Flutter dependency — suitable for CI use.
