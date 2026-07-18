# Four-channel KB governance: experimental → candidate → stable + local

status: supersedes ADR-0012

Four promotion channels with distinct CI contracts. Three public channels govern
the shared KB in `jankdoc-kb`. One private channel lives on the developer's machine,
unrestricted, and is never shared.

---

## Channels

### `experimental`
Knowledge discovery. A pattern exists and has a citation. Nothing more is required.
CI is fast and advisory — it validates structure, not correctness.

- **CI gate**: YAML schema valid + `sources` field non-empty. Advisory. Never blocks.
- **CI duration**: <30 seconds.
- **Promise to users**: "This pattern is real and cited. The rule may be wrong."
- **Opt-in**: `kb_channel: experimental` in `jankdoc.yaml`.
- **Use case**: Impeller regression spotted in a GitHub issue. A conference talk pattern.
  A production issue you've just diagnosed manually and want to document before writing
  the test app.

### `candidate`
Validation in progress. A test app exists. The rule works in a controlled environment.
CI is threshold-based — it runs the eval harness on the new entry only and enforces
minimum bars, blocking on hard failures and allowing soft failures through with
annotation.

- **CI gate**:
  - Schema valid, source cited. **Blocks** if missing.
  - Eval test app exists. **Blocks** if missing.
  - Fix compiles without error. **Blocks** if not.
  - Diagnosis accuracy on test app ≥ 0.60. **Blocks** if below.
  - Fix effectiveness ≥ 0.50. **Advisory** — annotated in CI output, does not block.
  - No regression on existing candidate + stable test apps. **Advisory**.
- **CI duration**: ~2–3 minutes (new test app only).
- **Promise to users**: "This rule works on a known reproduction case. May not generalise."
- **Opt-in**: `kb_channel: candidate` in `jankdoc.yaml`.
- **Use case**: Entry has a test app and a working rule but hasn't been exercised on
  diverse real-world Flutter versions or device classes.

### `stable`
Production. Every entry here has passed the full eval suite, has no regressions, and
has been explicitly promoted by a maintainer. **CI blocks unconditionally on any
failure. No exceptions.**

- **CI gate** (all blocking, no advisory exceptions):
  - Schema valid, primary source cited (flutter.dev, flutter/flutter GitHub issue, or
    peer-reviewed benchmark).
  - Eval test app exists and is self-contained.
  - Diagnosis accuracy ≥ 0.75.
  - Fix effectiveness ≥ 0.65 (frame time reduction ≥ 20% measured).
  - Fix compiles without error.
  - Full regression suite passes: all existing stable test apps re-run, no accuracy
    drop > 0.02 on any existing entry.
  - Confidence score within declared bounds (rule-tier ≥ 0.85, LLM-fallback ≤ 0.80).
- **CI duration**: ~10–15 minutes (full stable suite).
- **Promise to users**: "This rule has been validated. It has no known regressions.
  It is the default."
- **Default**: No configuration needed. All users receive stable unless they opt in
  to a higher channel.

### `local`
Developer-owned. Unrestricted. Entries live in the project repository under
`.jankdoc/local-kb/`. They never leave the developer's machine. No CI gate exists
because no CI runs them — they are the developer's own knowledge.

- **CI gate**: None. No schema enforcement. No accuracy threshold. No source requirement.
- **Promise to users**: None. This is your knowledge. You own it.
- **Use case**:
  - Company-specific patterns: "At Razorpay, the checkout widget always rebuilds
    because of this specific state management mistake."
  - Pre-contribution staging: write a local entry, validate it on your codebase,
    then open a PR to `experimental` when you're confident.
  - Permanent private entries: patterns too specific to the codebase to ever belong
    in the public KB.
  - Airgapped environments: teams that cannot reach the KB Registry at all.
- **Override semantics**: Local entries take precedence over all channel entries for
  the same `id`. A local entry with `id: raster-overdraw` overrides the stable entry
  with the same ID. This enables local calibration of upstream confidence scores.
- **Configuration**: no `jankdoc.yaml` entry needed. Any YAML file under
  `.jankdoc/local-kb/` is automatically loaded.

---

## Promotion flow

```
                  .jankdoc/local-kb/
                  (developer's machine,
                   never shared)
                        │
                        │  optional: PR to experimental
                        ▼
[PR] ──► experimental  (schema gate, advisory)
              │
              │  maintainer promotes
              ▼
          candidate  (threshold gate, partial block)
              │
              │  maintainer promotes
              ▼
           stable  (full gate, full block)
```

Promotion is always an explicit maintainer PR. Never automatic.
A local entry can become an experimental entry via a PR to `jankdoc-kb` — this is
the intended contribution path for new community patterns.

---

## Bundle composition

Each channel bundle is a superset of the channel below it:

| Bundle | Contains |
|--------|----------|
| `stable` (default) | stable entries |
| `candidate` | stable + candidate |
| `experimental` | stable + candidate + experimental |
| `local` | whichever public channel the user is on + all local entries |

`local` is always additive on top of the configured public channel. Local entries
with the same `id` as a public entry override the public entry.

---

## Bundle versioning

```
2.1.0              → stable
2.1.0-candidate.4  → candidate
2.1.0-exp.17       → experimental
```

Local entries carry no version — they are loaded directly from disk at daemon startup.

---

## CI environment per channel

| Channel | Trigger | Suite scope | Gate type |
|---------|---------|-------------|-----------|
| experimental | PR to `exp` branch | Schema only | Advisory |
| candidate | PR to `candidate` branch | New test app only | Threshold (partial block) |
| stable | PR to `stable` branch | Full suite | Strict (full block) |
| local | None | None | None |

---

## Why four channels, not three

The three-channel model (ADR-0012) lacked a distinction between:

- **"I have a rule that works"** (candidate) and
- **"I have a pattern I want to document before I write the rule"** (experimental)

Collapsing these two states forces contributors to write both the rule and the test app
before getting any KB entry into users' hands. This creates a contribution cliff: the
first thing you publish has to be fully formed. Experimental removes that cliff — you
document the pattern immediately, the test app follows.

The `local` channel solves a different problem: enterprise teams and power users have
patterns that will never belong in the public KB. Without a local channel, they either
fork jankdoc or go without. The local channel keeps them in the ecosystem while
preserving the curation integrity of the public KB.

This four-channel model directly mirrors:
- **Linux kernel**: mainline / stable / longterm / vendor (additive, increasing trust)
- **Nix**: unstable / staging / stable / local overlay (composable, local takes precedence)
- **Chrome**: Canary / Dev / Beta / Stable (different CI contracts per channel)
