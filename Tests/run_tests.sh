#!/usr/bin/env bash
#
# run_tests.sh
# Avro Keyboard
#
# Builds and runs the Foundation-level regression tests with clang directly.
# This avoids needing a full Xcode project/test target and runs in a couple of
# seconds, so it is suitable for pre-commit checks and CI.
#
# Usage:
#   Tests/run_tests.sh
#
# Requirements: Xcode Command Line Tools (clang + macOS SDK).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/avro-tests-$$"
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)"
MIN_VERSION="${AVRO_MIN_OS:-11.0}"

mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ ! -f "$REPO_ROOT/data.json" ]; then
  echo "error: data.json not found in $REPO_ROOT" >&2
  exit 2
fi

# The parsers and database read their data via -[NSBundle mainBundle], so run
# the test binaries from a directory that acts as the bundle root.
cp "$REPO_ROOT/data.json" "$REPO_ROOT/regex.json" "$REPO_ROOT/data/extra-words.tsv" \
   "$REPO_ROOT/autodict.plist" "$REPO_ROOT/database.db3" "$BUILD_DIR/"

INCLUDES=(
  "-I$REPO_ROOT"
  "-I$REPO_ROOT/Tests"
  "-I$REPO_ROOT/Pods/RegexKitLite/RegexKitLite-4.0"
  "-I$REPO_ROOT/Pods/FMDB/src/fmdb"
)

# Third-party sources pulled in by the app's own dependencies.
SOURCES=(
  "$REPO_ROOT/AvroParser.m"
  "$REPO_ROOT/RegexParser.m"
  "$REPO_ROOT/Suggestion.m"
  "$REPO_ROOT/Database.m"
  "$REPO_ROOT/CacheManager.m"
  "$REPO_ROOT/AutoCorrect.m"
  "$REPO_ROOT/AutoCorrectItem.m"
  "$REPO_ROOT/NSString+Levenshtein.m"
  "$REPO_ROOT/SettingsKeys.m"
  "$REPO_ROOT/UserDictionary.m"
  "$REPO_ROOT/TypoCorrections.m"
  "$REPO_ROOT/Pods/RegexKitLite/RegexKitLite-4.0/RegexKitLite.m"
  "$REPO_ROOT/Pods/FMDB/src/fmdb/FMDatabase.m"
  "$REPO_ROOT/Pods/FMDB/src/fmdb/FMDatabaseAdditions.m"
  "$REPO_ROOT/Pods/FMDB/src/fmdb/FMDatabasePool.m"
  "$REPO_ROOT/Pods/FMDB/src/fmdb/FMDatabaseQueue.m"
  "$REPO_ROOT/Pods/FMDB/src/fmdb/FMResultSet.m"
)

TESTS=(
  test_parser
  test_suggestion
  test_storage
  test_controller
  test_user_dictionary
  test_typo_corrections
)

COMMON_FLAGS=(
  -isysroot "$SDK_PATH"
  -fno-objc-arc
  -mmacosx-version-min="$MIN_VERSION"
  -Wno-deprecated-declarations
  -framework Foundation
  -framework AppKit
  -lsqlite3
  -licucore
)

echo "SDK:         $SDK_PATH"
echo "Deployment:  macOS $MIN_VERSION"
echo

for test_name in "${TESTS[@]}"; do
  test_source="$REPO_ROOT/Tests/${test_name}.m"
  binary="$BUILD_DIR/${test_name}"

  if [ ! -f "$test_source" ]; then
    echo "error: missing $test_source" >&2
    exit 2
  fi

  clang "${INCLUDES[@]}" "${COMMON_FLAGS[@]}" \
    -o "$binary" "$test_source" "${SOURCES[@]}" 2> "$BUILD_DIR/${test_name}.log" || {
      echo "error: failed to build ${test_name}" >&2
      grep -E "error:" "$BUILD_DIR/${test_name}.log" | head -20 >&2
      exit 1
    }

  echo "───────────────────────────────────────────────"
  echo "$test_name"
  echo "───────────────────────────────────────────────"
  ( cd "$BUILD_DIR" && "$binary" ) || exit 1
  echo
done

echo "All test suites passed."
