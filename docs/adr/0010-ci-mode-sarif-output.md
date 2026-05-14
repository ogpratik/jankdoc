# CI mode outputs SARIF; exits non-zero on HIGH severity findings

`dart run jankdoc:ci` is a headless command that runs JankDoc against a Flutter app in a CI environment and produces a machine-readable report.

## What it does

1. Starts the target Flutter app in profile mode via `flutter run --machine --profile`
2. Runs a user-defined interaction script from `jankdoc.yaml` (tap sequences, scroll gestures, navigation paths) that exercises the performance-critical paths
3. Collects telemetry for the duration of the script (or a configured timeout)
4. Produces diagnoses via the same Rule Pre-filter + LLM Tier pipeline
5. Writes a SARIF 2.1.0 report to `jankdoc-results.sarif`
6. Exits with code 1 if any Diagnosis has severity `HIGH` (configurable threshold)

## Why SARIF

SARIF (Static Analysis Results Interchange Format) is the GitHub Code Scanning standard. GitHub Actions renders SARIF reports directly in the Security tab with file/line annotations, without any additional tooling. This is the enterprise moat: JankDoc findings appear as first-class code scanning alerts in PR reviews. No competitor in the Flutter space does this.

```yaml
# .github/workflows/jankdoc.yml
- name: Run JankDoc CI
  run: dart run jankdoc:ci
- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: jankdoc-results.sarif
```

## jankdoc.yaml CI configuration

```yaml
jankdoc:
  ci:
    entry_point: lib/main.dart
    device: emulator-5554
    timeout_seconds: 60
    fail_on_severity: high   # high | medium | low
    script:
      - scroll: { widget: HomeListView, times: 5 }
      - navigate: /profile
      - scroll: { widget: ProfileTimeline, times: 3 }
  llm:
    provider: ollama
    model: qwen2.5-coder:7b
```

## Architecture note

In CI, the LLM tier is optional — if Ollama is not available in the CI environment, JankDoc falls back to rule-only mode. This is explicitly stated in the CI output. Rule-only mode still catches the 70%+ of known patterns.
