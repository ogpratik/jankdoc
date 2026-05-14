# KB is versioned with the package; community contributions are PRs to jankdoc_rules

The Knowledge Base ships embedded in the `jankdoc` pub package. KB versions are package versions. There is no separate KB update mechanism in v1.

## KB entry schema

Every KB entry file carries a `flutter_version_range` field. This allows the rule engine to skip entries that do not apply to the target app's Flutter version:

```yaml
---
id: impeller-scroll-jank-ios
category: impeller
severity: high
flutter_version_range: ">=3.27.0"
applicable_platforms: [ios, android]
detection_signals:
  impeller_enabled: true
  scroll_widget: true
  raster_thread_ms: ">8"
sources:
  - https://github.com/flutter/flutter/issues/137992
---
```

## Community contribution flow

All KB contributions are PRs to `packages/jankdoc_rules/lib/kb/`. The PR template requires:
1. A KB entry file with `sources` citing at least one primary source
2. A declarative `Rule` constant in the rules registry
3. A test app in `packages/jankdoc_eval/test_apps/` that demonstrates the issue
4. Passing eval metrics (diagnosis accuracy ≥0.75 on the new test app)

The eval harness runs in CI on every PR. A KB contribution that fails the eval gate is rejected automatically.

## Why not a separate community KB package

A separate `jankdoc_community_kb` package that users add independently is attractive for decoupling contribution velocity from release cadence, but creates a trust problem: community KB entries would not have gone through the eval gate, and users have no way to know which entries are reliable. The monolithic KB with a strict PR gate is the trust moat.

## Versioning cadence

Patch versions (`1.0.x`) for KB-only additions and corrections. Minor versions (`1.x.0`) for new Conditions, Rule combinators, or schema changes. Major versions (`x.0.0`) for breaking API changes to `JankDoc.attach()` or the Diagnosis schema.
