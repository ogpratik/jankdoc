#!/usr/bin/env bash
# Run tests with coverage for all packages and report coverage for critical-path files.
#
# Usage:
#   ./tool/coverage.sh                  # all packages
#   ./tool/coverage.sh --package jankdoc  # single package
#
# Requirements:
#   dart pub global activate coverage  (run once)
#
# Output:
#   coverage/<package>/lcov.info       — LCOV data
#   coverage/<package>/html/           — HTML report (if genhtml available)
#   A summary table printed to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COVERAGE_DIR="$REPO_ROOT/coverage"

SINGLE_PACKAGE="${1:-}"

# Critical-path files to report on specifically.
declare -A CRITICAL_FILES=(
  ["jankdoc"]="lib/src/analysis/diagnosis_pipeline.dart lib/src/session/session_repository.dart lib/src/kb/kb_bundle_loader.dart lib/src/kb/kb_manager.dart lib/src/kb/github_releases_kb_registry.dart lib/src/analysis/output_validator.dart"
  ["jankdoc_core"]="lib/src/rules/rule_engine.dart lib/src/kb/kb_bundle.dart lib/src/kb/kb_entry.dart"
)

PACKAGES=("jankdoc_core" "jankdoc" "jankdoc_eval")
if [[ -n "$SINGLE_PACKAGE" && "$SINGLE_PACKAGE" != "--all" ]]; then
  PACKAGES=("$SINGLE_PACKAGE")
fi

mkdir -p "$COVERAGE_DIR"

echo "══════════════════════════════════════════════════════════"
echo " JankDoc Coverage Report"
echo "══════════════════════════════════════════════════════════"

OVERALL_PASS=true

for PKG in "${PACKAGES[@]}"; do
  PKG_DIR="$REPO_ROOT/packages/$PKG"
  if [[ ! -d "$PKG_DIR/test" ]]; then
    echo ""
    echo "[$PKG] No test/ directory — skipping"
    continue
  fi

  echo ""
  echo "── $PKG ──────────────────────────────────────────────────"

  PKG_COV_DIR="$COVERAGE_DIR/$PKG"
  mkdir -p "$PKG_COV_DIR"

  # Run tests with coverage
  (cd "$REPO_ROOT" && dart test "packages/$PKG/test/" \
    --coverage="$PKG_COV_DIR/raw" \
    --reporter=compact \
    2>&1) || {
    echo "[$PKG] ✗ tests failed"
    OVERALL_PASS=false
    continue
  }

  # Convert to LCOV
  if command -v dart >/dev/null 2>&1; then
    dart pub global run coverage:format_coverage \
      --packages="$PKG_DIR/.dart_tool/package_config.json" \
      --in="$PKG_COV_DIR/raw" \
      --out="$PKG_COV_DIR/lcov.info" \
      --lcov \
      --report-on="$PKG_DIR/lib/" \
      2>/dev/null || true
  fi

  # Report on critical-path files
  CRITICAL="${CRITICAL_FILES[$PKG]:-}"
  if [[ -n "$CRITICAL" && -f "$PKG_COV_DIR/lcov.info" ]]; then
    echo "  Critical-path coverage:"
    for FILE in $CRITICAL; do
      # Extract coverage for this file from lcov.info
      COVERAGE=$(awk -v file="$FILE" '
        /^SF:.*'"$FILE"'$/ { in_file=1 }
        in_file && /^DA:/ {
          split($0, a, ",")
          total++
          if (a[2] > 0) covered++
        }
        in_file && /^end_of_record/ { in_file=0 }
        END {
          if (total > 0) printf "%.0f", (covered/total)*100
          else print "n/a"
        }
      ' "$PKG_COV_DIR/lcov.info")

      # Pass/fail based on threshold
      if [[ "$COVERAGE" == "n/a" ]]; then
        STATUS="⚠"
      elif [[ "$COVERAGE" -ge 80 ]]; then
        STATUS="✓"
      else
        STATUS="✗"
        OVERALL_PASS=false
      fi

      printf "    %s %-55s %s%%\n" "$STATUS" "$FILE" "$COVERAGE"
    done
  fi

  # Generate HTML if genhtml is available
  if command -v genhtml >/dev/null 2>&1 && [[ -f "$PKG_COV_DIR/lcov.info" ]]; then
    genhtml "$PKG_COV_DIR/lcov.info" \
      --output-directory="$PKG_COV_DIR/html" \
      --quiet
    echo "  HTML report: $PKG_COV_DIR/html/index.html"
  fi
done

echo ""
echo "══════════════════════════════════════════════════════════"
if $OVERALL_PASS; then
  echo " PASS — all critical-path files ≥80% coverage"
  exit 0
else
  echo " FAIL — one or more critical-path files below 80%"
  exit 1
fi
