# Curated KB with deterministic rule tier; no crowdsourced pattern learning

JankDoc is a deterministic debugging intelligence platform. Every diagnosis it produces must be traceable to a primary source (flutter/flutter GitHub issue, flutter.dev documentation, or a peer-reviewed benchmark). No pattern enters the KB without a human reviewer verifying the source and a corresponding eval test app demonstrating the pattern.

## What this means in practice

**The Rule Pre-filter is fully deterministic.** Given the same TelemetryBatch, it always produces the same Diagnosis. Temperature, model weights, and inference variance play no part. Rule-tier diagnoses are reproducible in CI.

**The LLM Tier is bounded and reproducible.** Ollama is called with `temperature: 0.0` and `seed: 42`. Combined with JSON-schema-constrained output and a fixed RAG retrieval window (top-5 chunks by cosine similarity, deterministic tie-breaking by KB entry ID), LLM-tier output is as stable as the model weights allow. Not perfectly reproducible across model upgrades, but reproducible within a fixed model version.

**Session History is local-only.** `~/.jankdoc/sessions.db` stores diagnoses for one developer on one machine. It is never uploaded, never aggregated, never used to update the shared KB. It exists for three purposes only: recurring-pattern annotation within a project, CI baseline delta ("this pattern regressed since last week"), and personalised RAG re-ranking (patterns the developer has confirmed or rejected are scored higher/lower in future retrievals).

**KB updates ship with package versions.** The KB is part of `packages/jankdoc_rules/` and is versioned with the package. A user on `jankdoc: ^1.2.0` gets exactly the KB that shipped with 1.2.x. They opt into new patterns by upgrading the package.

**KB entries are deprecated, never silently removed.** When a Flutter version change makes a pattern obsolete, the entry is marked `deprecated_since: '>=3.40.0'` and excluded from retrieval for matching Flutter versions. The entry remains in the repository for historical reference and downgrade compatibility.

## KB contribution model

Adding a KB entry requires:
1. A primary source citation (flutter/flutter issue, flutter.dev doc, or published benchmark with methodology)
2. A minimal Flutter app under `packages/jankdoc_eval/test_apps/` that reproduces the pattern
3. The eval harness passing on the new test app (diagnosis accuracy ≥0.75, fix effectiveness ≥0.65)
4. A maintainer review of the Rule definition and confidence score

Community contributors open a PR to `packages/jankdoc_rules/`. No contribution touches `packages/jankdoc/` (the user-facing pub package) or `packages/jankdoc_extension/` (the UI). This is the only PR surface area for KB additions, keeping the review scope tight.

## What is explicitly not built

- No anonymous telemetry upload to improve the KB
- No "learn from your codebase" LLM fine-tuning
- No cross-user pattern aggregation
- No cloud KB sync
- No "community patterns" tier with lower confidence standards

## Why

Developer trust is the only moat that matters for a local-first tool. The moment JankDoc produces a diagnosis that a senior Flutter engineer cannot trace back to a primary source, trust collapses — and it does not return in the same session. Curated, cited, versioned knowledge is the architecture of trust. Crowdsourced knowledge is the architecture of noise.

The react-scan model confirms this: it won on "one tool, one job, one visceral demo." It did not win on "community-contributed pattern library." Quality over coverage at launch.
