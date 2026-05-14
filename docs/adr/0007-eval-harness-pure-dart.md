# Eval harness is pure Dart, not Python

The build plan proposed Python (promptfoo, DeepEval, RAGAS, Arize Phoenix) for the eval harness. Decision: the eval harness is pure Dart, living in `packages/jankdoc_eval/`.

## Why

- Running Flutter apps headlessly uses `flutter run --machine` or `flutter test` — already Dart-native. Wrapping this in Python adds a process boundary with no benefit.
- A Dart eval harness means contributors do not need Python to run evals. This lowers the contributor bar significantly for a Flutter-native OSS project.
- The metrics JankDoc cares about (diagnosis accuracy, fix validity, fix effectiveness, retrieval precision) can all be computed in Dart without an ML framework.
- Python eval frameworks (promptfoo, RAGAS) are designed for LLM app developers without a typed domain model. JankDoc has a typed `Diagnosis` struct — assertions against it are more precise as Dart unit tests than as YAML prompt-eval configs.

## What replaces each tool

| Python tool | Dart replacement |
|-------------|-----------------|
| promptfoo | `jankdoc_eval` test suite using `package:test` |
| DeepEval | Custom `DiagnosisAssertion` matchers in `jankdoc_eval` |
| RAGAS | `RetrievalQualityReport` computed over top-k retrieved chunks vs ground truth |
| Arize Phoenix | Structured JSON trace output per eval run, consumed by a simple Dart report generator |

## What is retained

The **20 mini Flutter apps** with seeded performance issues remain. They are standard Flutter projects under `packages/jankdoc_eval/test_apps/`. The harness runs them via `flutter run --machine`, captures JankDoc's output, applies the suggested fix via `dart fix` or direct source patching, re-runs, and computes the improvement delta.
