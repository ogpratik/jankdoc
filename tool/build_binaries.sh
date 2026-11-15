#!/usr/bin/env bash
# Build pre-compiled daemon binaries for all supported platforms.
#
# Run this script on each target platform before cutting a release:
#
#   macOS arm64:   ./tool/build_binaries.sh
#   macOS x64:     ARCH=macos-x64 ./tool/build_binaries.sh
#   Linux x64:     ./tool/build_binaries.sh  (on a Linux x64 machine)
#
# Each run writes dist/binaries/jankdoc-daemon-<version>-<platform>.tar.gz
# (gitignored). Releases are normally built by .github/workflows/release.yaml;
# this script is for local testing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DAEMON_ENTRYPOINT="$REPO_ROOT/packages/jankdoc/bin/daemon.dart"
OUT_DIR="$REPO_ROOT/dist/binaries"

mkdir -p "$OUT_DIR"

# ── Determine platform string ─────────────────────────────────────────────────
OS="$(uname -s)"
ARCH_RAW="$(uname -m)"

if [[ "$OS" == "Darwin" ]]; then
  if [[ "$ARCH_RAW" == "arm64" ]]; then
    PLATFORM="macos-arm64"
  else
    PLATFORM="macos-x64"
  fi
elif [[ "$OS" == "Linux" ]]; then
  PLATFORM="linux-x64"
else
  echo "Unsupported platform: $OS/$ARCH_RAW" >&2
  exit 1
fi

# Allow override (e.g. ARCH=macos-x64 for cross-compile simulation)
PLATFORM="${ARCH:-$PLATFORM}"

# ── Daemon version (what DaemonLauncher downloads, not the pub version) ──────
VERSION="$(grep -E "^const _kDaemonVersion" "$REPO_ROOT/packages/jankdoc/lib/src/daemon_launcher.dart" | sed -E "s/.*'([^']+)'.*/\1/")"
OUT_PATH="$OUT_DIR/jankdoc-daemon-$VERSION-$PLATFORM.tar.gz"
echo "[build] jankdoc daemon v$VERSION — platform: $PLATFORM"

# ── Ensure workspace deps are resolved ────────────────────────────────────────
# `jankdoc` depends on the Flutter SDK, so a bare `dart pub get` cannot
# resolve the workspace.
echo "[build] resolving dependencies..."
(cd "$REPO_ROOT" && flutter pub get)

# ── Compile ───────────────────────────────────────────────────────────────────
# `dart compile exe` rejects packages with build hooks (objective_c, pulled in
# transitively), so build with `dart build cli` and archive the whole bundle —
# on Linux bin/daemon is the AOT runtime and needs the files beside it.
echo "[build] compiling $DAEMON_ENTRYPOINT → $OUT_PATH"
BUILD_DIR="$(mktemp -d)"
(cd "$REPO_ROOT/packages/jankdoc" && dart build cli -t bin/daemon.dart -o "$BUILD_DIR")
tar -czf "$OUT_PATH" -C "$BUILD_DIR" bundle
rm -rf "$BUILD_DIR"

# ── Checksum ──────────────────────────────────────────────────────────────────
if command -v sha256sum >/dev/null 2>&1; then
  CHECKSUM="$(sha256sum "$OUT_PATH" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  CHECKSUM="$(shasum -a 256 "$OUT_PATH" | awk '{print $1}')"
else
  echo "[build] WARNING: no sha256 tool found, skipping checksum" >&2
  CHECKSUM=""
fi

SIZE="$(du -sh "$OUT_PATH" | awk '{print $1}')"

echo "[build] ✓ $OUT_PATH"
echo "[build]   size:     $SIZE"
echo "[build]   sha256:   $CHECKSUM"
echo ""
echo "[build] Next steps:"
echo "  1. Run this script on other platforms (macOS x64, Linux x64)"
echo "  2. dart run tool/generate_checksums.dart"
echo "  3. git add packages/jankdoc/assets/binary_checksums.json && git commit"
echo "  (Usually: push a daemon-v$VERSION tag and let release.yaml build all"
echo "   platforms, then: dart run tool/generate_checksums.dart --release daemon-v$VERSION)"
