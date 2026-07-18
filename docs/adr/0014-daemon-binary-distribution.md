# ADR-0014: Daemon Binary Distribution Strategy

**Status**: Accepted  
**Date**: 2026-05-23  
**Deciders**: Pratik, Claude  

---

## Context

The JankDoc daemon (`bin/daemon.dart`) must be running before telemetry can flow. Dart
programs can be launched two ways:

- **Compiled binary** (`dart compile exe`) — native AOT, starts in ~50–100 ms, no Dart SDK
  on the user's machine required at runtime.
- **Source run** (`dart run jankdoc:daemon`) — interpreted/JIT, starts in ~3–8 s on cold
  JIT, requires the Dart SDK to be on `PATH`.

`JankDoc.attach()` is called at Flutter app startup. The daemon startup latency directly
affects how quickly the developer sees their first diagnosis. An 8-second cold start
makes the tool feel broken.

### Options considered

| Option | Description | Cold start | Offline |
|--------|-------------|-----------|---------|
| A | Pre-compile + ship per-platform binaries only | ~100 ms | ✗ download required |
| B | Always `dart run` — no binaries | ~5 s | ✓ |
| C | Try cached binary → download → fall back to `dart run` | ~100 ms (warm) / ~10 s (first run) | ✓ (dart run) |

## Decision

**Option C — Hybrid** is adopted.

Resolution order in `DaemonLauncher._resolveDaemonCommand()`:

1. **Cache hit**: look for `~/.jankdoc/bin/jankdoc-daemon-<version>-<platform>`. If it
   exists and its SHA-256 matches `assets/binary_checksums.json`, run it directly.

2. **Download**: fetch the binary for the current version and platform from
   `https://github.com/ogpratik/jankdoc/releases/download/v<version>/jankdoc-daemon-<platform>`,
   verify checksum, chmod +x, write to cache. Log a user-visible progress line during
   the download.

3. **`dart run` fallback**: if cache is cold and download fails for any reason (network
   offline, platform not in release assets, checksum mismatch), fall back to
   `dart run jankdoc:daemon`. Log clearly that this path is slower.

## Consequences

- **First run, online**: daemon is available in <12 s total (including ~10 s download for
  a ~5 MB binary on a slow connection). Subsequent runs are ~100 ms.
- **Network offline or unsupported platform**: `dart run` fallback guarantees the tool
  always works; user sees a clear "running from source" message.
- **Security**: SHA-256 verification prevents corrupted or replaced binaries from running.
  Checksums are committed in `assets/binary_checksums.json` and embedded as a Dart
  constant at compile time.
- **Maintenance**: each jankdoc release must run `tool/build_binaries.sh` on each target
  platform (macOS arm64, macOS x64, Linux x64) and commit the updated checksums. Windows
  support is best-effort for v1 beta.
- **Platforms for beta**: macOS arm64, macOS x64, Linux x64. Windows deferred to v1.1.
