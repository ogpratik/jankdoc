#!/usr/bin/env bash
# Build pre-compiled daemon binaries for all supported platforms.
#
# Run this script on each target platform before cutting a release:
#
#   macOS arm64:   ./tool/build_binaries.sh
#   macOS x64:     ARCH=macos-x64 ./tool/build_binaries.sh
#   Linux x64:     ./tool/build_binaries.sh  (on a Linux x64 machine)
#
# After running on all platforms, run tool/generate_checksums.dart to
# update packages/jankdoc/assets/binary_checksums.json.
#
# The built binaries land in dist/binaries/ (gitignored).
# Upload them as GitHub Release assets when cutting a new release.

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

BINARY_NAME="jankdoc-daemon-$PLATFORM"
OUT_PATH="$OUT_DIR/$BINARY_NAME"

# ── Version from pubspec ──────────────────────────────────────────────────────
VERSION="$(grep '^version:' "$REPO_ROOT/packages/jankdoc/pubspec.yaml" | awk '{print $2}')"
echo "[build] jankdoc v$VERSION — platform: $PLATFORM"

# ── Ensure workspace deps are resolved ────────────────────────────────────────
# `jankdoc` depends on the Flutter SDK, so a bare `dart pub get` cannot
# resolve the workspace.
echo "[build] resolving dependencies..."
(cd "$REPO_ROOT" && flutter pub get)

# ── Compile ───────────────────────────────────────────────────────────────────
# `dart compile exe` rejects packages with build hooks (objective_c, pulled in
# transitively), so build with `dart build cli` and take the executable out of
# its bundle — it runs standalone, as release.yaml ships it.
echo "[build] compiling $DAEMON_ENTRYPOINT → $OUT_PATH"
BUILD_DIR="$(mktemp -d)"
(cd "$REPO_ROOT/packages/jankdoc" && dart build cli -t bin/daemon.dart -o "$BUILD_DIR")
cp "$BUILD_DIR/bundle/bin/daemon" "$OUT_PATH"
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
echo "  4. Prefer the release workflow: git tag daemon-v<version> && git push --tags"
