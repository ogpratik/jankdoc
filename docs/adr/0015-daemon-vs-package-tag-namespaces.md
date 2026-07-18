# ADR-0015: Separate tag namespaces for daemon binaries and pub packages

**Status**: Accepted  
**Date**: 2026-07-12  
**Deciders**: Pratik, Claude  

---

## Context

Public-beta release engineering asked one apparently-trivial question: what
git tag pattern triggers the daemon-binary release workflow?

Two things use versions at release time, and they cadence differently:

1. **Pub packages** — `jankdoc` and `jankdoc_core`. Versions are pub-semver
   (`1.0.0-beta.1`, `1.0.0-beta.2`, `1.0.0-rc.1`, `1.0.0`, `1.0.1`, …). We
   expect frequent beta bumps as we react to feedback.

2. **Daemon binaries** — one native executable per platform, uploaded to
   GitHub Releases and downloaded on first-run by `DaemonLauncher`. The
   compile output is byte-stable across pub-package bumps whenever
   `bin/daemon.dart` and its transitive imports have not changed. Rebuilding
   the binary on every pub-package bump is wasted CI time, wasted download
   bandwidth for the user, and fragments the checksum manifest across
   effectively-identical binaries.

`DaemonLauncher` fetches the binary from the URL:

```
https://github.com/ogpratik/jankdoc/releases/download/<tag>/jankdoc-daemon-<version>-<platform>
```

`<version>` comes from `const _kDaemonVersion` in `daemon_launcher.dart` —
compile-time-constant, currently `1.0.0`. `<tag>` is a git tag we chose to
map cleanly to `<version>`.

If daemon binaries and pub packages share the `v*` tag namespace:

- Pushing `v1.0.0-beta.2` for a pub-package release either has to also
  rebuild binaries (wasteful) or the release workflow must skip them,
  producing an empty release page that confuses users.
- More critically: `DaemonLauncher` would need to know which pub tag its
  daemon binary lives under — a moving target that changes every pub bump.

### Options considered

| Option | Description | Consequence |
|---|---|---|
| A | Share `v*` tags. Every pub-package tag rebuilds binaries. | Wasted CI, duplicate binaries per version, `_kDaemonVersion` must track pub-package version — tight coupling defeats the compile-time-constant model. |
| B | Share `v*` tags. Release workflow only rebuilds binaries when `_kDaemonVersion` changed. | Requires the workflow to inspect prior state; brittle. `_releases/download/v1.0.0-beta.2/jankdoc-daemon-1.0.0-macos-arm64` reads confusingly. |
| C | **Separate `daemon-v*` tag namespace for daemon binaries.** | Two independent version cadences; each has one URL invariant; workflow triggers are clean; the coupling that must not drift (`_kDaemonVersion` vs. filename) is enforced by workflow-time grep and a unit test. |

## Decision

**Option C — Separate namespaces.**

- Pub packages: no git tag required (pub publishes via `dart pub publish`,
  which does not need a tag). If we want a lightweight "history marker" in
  git, we tag as `jankdoc-v<version>` or `jankdoc-core-v<version>` — no
  automation reacts to these.
- Daemon binaries: cut with `daemon-v<version>` tags. Version must equal
  `_kDaemonVersion`. Push triggers `.github/workflows/release.yaml`, which
  builds and uploads binaries.

### Enforcement

Three guardrails prevent the two from drifting:

1. **`_kDaemonVersion`** is a compile-time constant in
   `packages/jankdoc/lib/src/daemon_launcher.dart`. Changing it triggers
   `dart analyze` on the whole workspace.
2. **Release workflow** parses `_kDaemonVersion` out of the source via
   `grep + sed` at build time and refuses to run if the tag version does
   not match.
3. **`daemon_launcher_url_contract_test.dart`** locks all four coupled
   files together (source constant, tag prefix, workflow trigger,
   `binary_checksums.json` platform keys). Silent drift breaks the test.

## Consequences

- **Two release cadences to think about.** Daemon-binary rebuilds are rare
  (typically only when `bin/daemon.dart` or its transitive dependencies
  change). Pub-package publishes happen much more often.
- **When `_kDaemonVersion` bumps** (say to `1.1.0`): (a) update
  `daemon_launcher.dart`, (b) push `daemon-v1.1.0`, (c) release workflow
  builds and uploads all-platform binaries with new checksums, (d) run
  `tool/generate_checksums.dart` to update `assets/binary_checksums.json`,
  (e) publish next `jankdoc` pub package version referencing the new
  daemon.
- **Existing users on `_kDaemonVersion 1.0.0`** are unaffected by pub-only
  bumps — the same cached binary keeps working.
- Documented in `LAUNCH_PLAN.md`'s Blocked-by-external-action table.
