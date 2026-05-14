# Melos monorepo with five packages

JankDoc is organised as a Melos monorepo. Each package has a single, clearly bounded responsibility. Internal packages are not published to pub.dev; only `jankdoc` is.

```
jankdoc/                          # repo root
├── packages/
│   ├── jankdoc/                  # pub-published. Adds VM Service capture to the target app.
│   │   ├── lib/                  # JankDocService (user-facing API)
│   │   └── bin/
│   │       └── daemon.dart       # compiled → jankdoc_daemon native binary
│   ├── jankdoc_core/             # NOT published. Shared models: Diagnosis, TelemetryBatch,
│   │                             # Rule, Condition, KbEntry, DiagnoseRequest, LlmProvider.
│   ├── jankdoc_rules/            # NOT published. All built-in Rules + KB entries.
│   │                             # Community PRs target this package exclusively.
│   ├── jankdoc_extension/        # NOT published. Flutter web DevTools extension.
│   └── jankdoc_eval/             # NOT published. Eval harness (pure Dart, not Python).
│       └── test_apps/            # 20 mini Flutter apps with seeded performance issues.
├── melos.yaml
└── analysis_options.yaml         # shared lint rules across all packages
```

## Dependency direction (enforced by melos bootstrap)

```
jankdoc_extension → jankdoc_core
jankdoc (daemon) → jankdoc_core, jankdoc_rules
jankdoc_rules → jankdoc_core
jankdoc_eval → jankdoc_core, jankdoc_rules
```

`jankdoc_core` depends on nothing internal. This is the dependency inversion that keeps the architecture clean as the codebase grows.

## Why not a single package

Single-package repos are fine at 2,000 lines. At 20,000 lines — which this will reach given 50+ KB entries, 20+ rules, the eval harness, and the extension — a single package becomes untestable in isolation. The monorepo allows `jankdoc_rules` to be tested without spinning up Ollama, and `jankdoc_eval` to be run in CI without the DevTools extension.
