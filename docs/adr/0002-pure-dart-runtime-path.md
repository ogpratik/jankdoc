# Pure Dart in the entire runtime path; Python is CI-only

The analysis daemon is compiled to a native binary with `dart compile exe`. No Python, no Rust, no native FFI extensions appear in the user-facing distribution. Python is used only in the eval harness (CI), which users never touch.

This eliminates the cross-language boundary that complicates distribution (pub packages cannot ship Python or Rust binaries), increases first-run friction, and multiplies failure modes. A pure-Dart binary distributed via pub's `executables:` mechanism installs with a single command and produces a self-contained native executable on macOS, Linux, and Windows.

## Considered options

- **Python/FastAPI analysis engine** — rejected. pub packages cannot ship Python binaries. Cross-language boundary adds process management complexity and multiplies failure modes on Windows.
- **Rust daemon with Dart FFI** — correct long-term for performance-critical workloads, wrong at v1. Requires Rust toolchain at build time, no first-class Dart FFI generation for arbitrary Rust crates, and adds a cross-compilation CI matrix.
- **Pure Dart native binary** — ships with `dart compile exe`, produces a single self-contained executable per platform, zero external runtime dependencies beyond Ollama (user-managed).
