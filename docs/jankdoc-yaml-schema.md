# `jankdoc.yaml` — Configuration Reference

Place `jankdoc.yaml` in your Flutter project root (next to `pubspec.yaml`).
All fields are optional — JankDoc works with zero configuration.

```yaml
# jankdoc.yaml — JankDoc configuration
# Full schema reference: https://jankdoc.dev/config

# ── Daemon ────────────────────────────────────────────────────────────────────
daemon:
  # TCP port the analysis daemon listens on.
  # Default: 9101
  port: 9101

  # Base URL of the local Ollama instance.
  # Default: http://127.0.0.1:11434
  ollama_url: http://127.0.0.1:11434

  # Ollama model to use for LLM-tier diagnosis.
  # Must be pulled: `ollama pull qwen2.5-coder:7b`
  # Default: qwen2.5-coder:7b
  model: qwen2.5-coder:7b

# ── Analysis ──────────────────────────────────────────────────────────────────
analysis:
  # Frame budget override in milliseconds.
  # JankDoc uses the device's actual refresh rate by default (16ms at 60fps).
  # Override for 120Hz devices if auto-detection fails.
  # Default: auto
  frame_budget_ms: auto

  # Minimum over-budget threshold before a frame triggers analysis (ms).
  # Prevents noisy diagnoses on 1–2ms overruns.
  # Default: 5.0
  min_over_budget_ms: 5.0

  # Maximum number of diagnoses to buffer in memory.
  # Default: 500
  max_buffered_diagnoses: 500

  # Whether to run LLM-tier analysis when no rule matches.
  # Set to false to disable Ollama entirely (rule-tier only).
  # Default: true
  llm_enabled: true

# ── CI mode ───────────────────────────────────────────────────────────────────
ci:
  # Enable CI mode. In CI mode, JankDoc writes a SARIF 2.1.0 report
  # and exits with a non-zero status if diagnoses exceed the threshold.
  # Default: false (auto-detected from CI environment variable)
  enabled: false

  # SARIF report output path (relative to project root).
  # Default: jankdoc-report.sarif
  output: jankdoc-report.sarif

  # Maximum allowed diagnoses of each severity before failing CI.
  # Unset severities are not checked.
  thresholds:
    critical: 0   # any critical diagnosis fails the build
    high: 5
    # medium and low are not checked by default

  # Baseline file path. If set, only NEW diagnoses (not in baseline) fail CI.
  # Generate with: `dart run jankdoc:baseline generate`
  # Default: null (no baseline — all diagnoses evaluated)
  baseline: null

# ── Knowledge Base ────────────────────────────────────────────────────────────
kb:
  # Additional KB entry directories to merge with the built-in KB.
  # Each directory should contain YAML files matching the KB entry schema.
  # Default: []
  extra_dirs:
    - kb/custom

  # Disable specific built-in KB entries by pattern ID.
  # Default: []
  disabled_patterns: []
```

## Minimal configuration

Zero config works out of the box. The only reason to add `jankdoc.yaml` is to:

- Change the port or Ollama URL
- Configure CI thresholds
- Add custom KB entries
- Disable specific patterns

## CI integration example

```yaml
# jankdoc.yaml (CI-focused)
ci:
  enabled: true
  output: jankdoc-report.sarif
  thresholds:
    critical: 0
    high: 3
```

GitHub Actions usage:
```yaml
- name: Run JankDoc CI
  run: dart run jankdoc:ci

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  if: always()
  with:
    sarif_file: jankdoc-report.sarif
```
