# KB entries move through promotion channels: canary → beta → stable

status: extends ADR-0011

The KB has three promotion channels. Every entry starts in `canary`. Promotion is
explicit — a maintainer decision, not automatic. Each channel has its own CI gate.
Stable blocks. Beta and canary do not.

This is the architecture used by Debian (unstable → testing → stable), Chrome (Canary →
Dev → Beta → Stable), and Flutter itself (master → beta → stable). It separates the
velocity of knowledge discovery from the reliability guarantee of production diagnoses.

---

## Channels

### `canary`
New entries land here. The gate is structural only: is the YAML schema valid? Does the
entry have a primary source citation? CI runs in <30 seconds.

- **CI gate**: schema validation + primary source field present. **Advisory only** — PRs
  may merge with warnings on non-structural issues.
- **Who uses it**: maintainers and contributors dogfooding new patterns.
- **Opt-in**: `kb_channel: canary` in `jankdoc.yaml`.
- **Typical entries**: patterns found in open GitHub issues, patterns from conference
  talks, Impeller regressions spotted in the wild before they have authoritative fixes.

### `beta`
Entries promoted from canary by a maintainer after initial review. An eval test app is
required. The accuracy gate is enforced but soft enough to allow iteration.

- **CI gate**:
  - Eval test app exists under `test_apps/`
  - Diagnosis accuracy on that test app ≥ 0.60
  - Fix compiles without error
  - **Advisory** on accuracy 0.60–0.75; **blocks** on missing test app or compile failure.
- **Who uses it**: developers who want early access to new patterns with reasonable
  confidence; teams willing to act as a validation audience.
- **Opt-in**: `kb_channel: beta` in `jankdoc.yaml`.
- **Typical entries**: patterns with a test app and a working rule, but not yet validated
  on diverse real-world codebases.

### `stable`
The default channel. Every entry here has passed the full eval suite, has primary source
citations, and has not caused regressions in any existing stable test app. **CI blocks
unconditionally on any failure.**

- **CI gate** (all required, all blocking):
  - Schema valid, primary source cited
  - Eval test app exists
  - Diagnosis accuracy ≥ 0.75 on the entry's test app
  - Fix effectiveness ≥ 0.65 on the entry's test app (frame time reduction ≥ 20%)
  - Fix compiles without error
  - **No regression** on all existing stable test apps (full suite re-run)
  - Confidence score defensible: rule-tier entries ≥ 0.85, LLM-tier fallback entries ≤ 0.80
- **Who uses it**: everyone. This is the default, requiring no configuration.
- **Typical entries**: patterns that have been in beta, exercised by real users, and
  confirmed correct against multiple Flutter versions.

---

## Promotion flow

```
PR opened → canary (schema gate, advisory)
               │
               ▼  maintainer: reviews source, confirms pattern is real
            beta (eval gate, partially blocking)
               │
               ▼  maintainer: confirms real-world validity, stable flutter versions tested
           stable (full gate, fully blocking)
```

Promotion is a PR from the entry's branch into the `stable` or `beta` branch of the
`jankdoc-kb` repository. The CI gate runs on the promotion PR. If it fails, the PR is
blocked. No exceptions.

**Promotion is never automatic.** Telemetry-based auto-promotion is explicitly rejected
(ADR-0010: no crowdsourcing, no usage data). A human decision sits at every channel
boundary.

---

## KB Bundle composition per channel

A channel bundle contains entries AT or BELOW its channel:

| Bundle | Contains |
|--------|----------|
| `stable` (default) | stable entries only |
| `beta` | stable + beta entries |
| `canary` | stable + beta + canary entries |

This means stable users never see an unvalidated entry. Canary users see everything.
Deprecations propagate downward: an entry deprecated in stable is excluded from all
channel bundles.

---

## Bundle versioning per channel

```
1.4.2            → stable
1.4.2-beta.3     → beta
1.4.2-canary.11  → canary
```

The daemon resolves bundles by channel. Pinning in `jankdoc.yaml`:
```yaml
jankdoc:
  kb_channel: stable      # default — omit for same effect
  kb_version: "1.4.x"    # pin minor, float patches within stable
```

CI reproducibility: `kb_version: "1.4.2"` pins exact stable version. The SARIF report
embeds the KB version, making delta analysis between runs meaningful.

---

## CI environment per channel

| Channel | Trigger | Duration | Gate |
|---------|---------|----------|------|
| canary  | PR to canary branch | <30s | Advisory |
| beta    | PR to beta branch | ~2 min (new test app only) | Partial block |
| stable  | PR to stable branch | ~10 min (full suite) | Full block |

The full stable suite runs all existing stable test apps plus the new entry's test app.
This is what prevents a new rule from breaking diagnosis accuracy on an existing pattern —
the regression gate.

---

## Considered options

- **Single universal CI gate** — rejected. Forces a choice between moving too slowly
  (if the gate is strict) or shipping low-quality entries (if the gate is loose). The
  Flutter release cycle demands fast knowledge discovery; production users demand
  reliability. A single gate cannot serve both.
- **Confidence tiers within a single channel** — rejected. Mixing high-confidence and
  experimental entries in one bundle with a confidence flag makes the user experience
  ambiguous. "Why is this diagnosis marked 0.4?" is worse UX than "you're on the canary
  channel and this entry hasn't been fully validated."
- **Canary → beta → stable promotion channels** — selected. Proven at scale (Debian,
  Chrome, Flutter). Separates the velocity of knowledge capture from the reliability
  guarantee of production diagnoses. Each channel makes a different promise to users,
  and those promises are kept by CI.
