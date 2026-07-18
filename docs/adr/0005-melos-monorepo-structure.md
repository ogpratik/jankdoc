# Melos monorepo with five packages

JankDoc is organised as a Melos monorepo. Each package has a single, clearly bounded responsibility. Internal packages are not published to pub.dev; only `jankdoc` is.

```
jankdoc/                          # repo root (pub package + daemon + extension + eval)
├── packages/
│   ├── jankdoc/                  # pub-published. Adds VM Service capture + JankDoc.attach().
│   │   ├── lib/                  # JankDoc.attach(), VM Service client, telemetry capture
│   │   ├── assets/               # seed KB Bundle (v0 — 50 patterns, ships with the package)
│   │   └── bin/
│   │       └── daemon.dart       # dart compile exe → jankdoc_daemon native binary
│   ├── jankdoc_core/             # NOT published. Shared models: Diagnosis, TelemetryBatch,
│   │                             # Rule, Condition, KbEntry, KbBundle, DiagnoseRequest,
│   │                             # LlmProvider, VectorStore, KbLoader interfaces.
│   ├── jankdoc_extension/        # NOT published. Flutter web DevTools extension UI.
│   └── jankdoc_eval/             # NOT published. Eval harness (pure Dart, not Python).
│       └── test_apps/            # 20 mini Flutter apps with seeded performance issues.
├── melos.yaml
└── analysis_options.yaml         # shared lint rules across all packages

jankdoc-kb/                       # SEPARATE repository
├── entries/                      # KB Entry YAML source files
│   ├── build_rebuild/
│   ├── list_grid/
│   └── impeller/
├── rules/                        # Rule YAML source files (one per KB Entry)
├── scripts/
│   └── bundle.dart               # builds .jankdoc-kb artifact from YAML sources
├── schema/
│   └── kb_entry.schema.json      # JSON Schema for KB Entry validation in CI
└── CONTRIBUTING.md
```

## Dependency direction

```
jankdoc_extension → jankdoc_core
jankdoc (daemon) → jankdoc_core
jankdoc_eval → jankdoc_core
```

`jankdoc_core` depends on nothing internal. `jankdoc_rules` as a pub package no longer exists — the KB is distributed as KB Bundles from the `jankdoc-kb` repository, loaded at runtime.

## Why not a single package

Single-package repos are fine at 2,000 lines. At 20,000 lines — which this will reach given 50+ KB entries, 20+ rules, the eval harness, and the extension — a single package becomes untestable in isolation. The monorepo allows `jankdoc_rules` to be tested without spinning up Ollama, and `jankdoc_eval` to be run in CI without the DevTools extension.
