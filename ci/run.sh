#!/bin/bash
# Builds and tests Between Stops on a macOS runner with the newest installed Xcode.
#
# Called by .github/workflows/ci.yml, which then publishes ci-output/ to the ci-results branch
# (even when this script fails). Everything worth reading ends up in ci-output/:
#   totals.txt         test totals per suite and overall (the line to check: RESULT)
#   failures.txt       every failure, empty when green
#   test-results.txt   each test case with its result
#   screenshots/       PNGs captured by the UI tests (light, dark, large text)
#   *.log              full logs of each step
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/ci-output"
BUILD="$ROOT/build"
mkdir -p "$OUT/screenshots" "$BUILD"
: > "$OUT/failures.txt"
STATUS=0
START=$(date +%s)
PROJECT=BetweenStops.xcodeproj
SCHEME=BetweenStops

step() { echo; echo "=== [$(( $(date +%s) - START ))s] $*"; }
fail() { echo "FAIL: $*" | tee -a "$OUT/failures.txt"; STATUS=1; }

# Runs a command with a time limit (macOS has no `timeout`), so a hang fails this step instead
# of the whole job hitting the workflow timeout before results are published.
with_timeout() {
  local limit=$1; shift
  "$@" &
  local pid=$!
  ( sleep "$limit"; echo "TIMEOUT: killed after ${limit}s: $*"; kill -TERM "$pid" 2>/dev/null; sleep 15; kill -KILL "$pid" 2>/dev/null ) &
  local watchdog=$!
  wait "$pid"
  local rc=$?
  pkill -P "$watchdog" 2>/dev/null
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return $rc
}

step "Environment"
{
  sw_vers
  xcodebuild -version
  xcode-select -p
  swift --version 2>&1 | head -1
  sysctl -n machdep.cpu.brand_string hw.ncpu
} | tee "$OUT/environment.txt"

step "Source audit (networking APIs, third-party dependencies)"
bash ci/audit.sh | tee "$OUT/source-audit.txt"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then fail "source audit found networking APIs or third-party dependencies"; fi

step "Create and boot a simulator (it finishes booting while the engine tests and build run)"
RUNTIME_ID=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"]
       if r.get("isAvailable") and (r.get("platform") == "iOS" or ".iOS-" in r["identifier"])]
rts.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rts[-1]["identifier"] if rts else "")')
DEVICE_TYPE_ID=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
types = {t["name"]: t["identifier"] for t in json.load(sys.stdin)["devicetypes"]}
# 6.9-inch first: its screenshots are the size App Store Connect requires.
for name in ["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 17 Pro", "iPhone 16 Pro", "iPhone 17", "iPhone 16"]:
    if name in types:
        print(types[name]); break')
echo "runtime: $RUNTIME_ID"
echo "device type: $DEVICE_TYPE_ID"
UDID=$(xcrun simctl create "CI iPhone" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
echo "simulator: $UDID"
xcrun simctl boot "$UDID"
DESTINATION="platform=iOS Simulator,id=$UDID"

# Each game's rules engine is a Foundation-only package tested with `swift test`. Release mode
# with testability runs the heavy invariant tests several times faster than a debug build.
ENGINE_TOTAL=0
ENGINE_FAILED=0
ENGINE_SUMMARY=""
for engine in KlondikeEngine BubbleEngine; do
  step "Engine tests: swift test in Packages/$engine"
  log="$OUT/engine-tests-$engine.log"
  (cd "Packages/$engine" && with_timeout 900 swift test -c release -Xswiftc -enable-testing) > "$log" 2>&1
  rc=$?
  line=$(grep -E "Executed [0-9]+ tests?, with [0-9]+ failures?" "$log" | tail -1 | sed -E 's/^[[:space:]]+//')
  echo "${line:-no XCTest summary found} (exit $rc)"
  total=$(echo "$line" | sed -nE 's/.*Executed ([0-9]+) tests?.*/\1/p')
  failed=$(echo "$line" | sed -nE 's/.*with ([0-9]+) failures?.*/\1/p')
  ENGINE_TOTAL=$(( ENGINE_TOTAL + ${total:-0} ))
  ENGINE_FAILED=$(( ENGINE_FAILED + ${failed:-0} ))
  ENGINE_SUMMARY="$ENGINE_SUMMARY $engine ${total:-?}/${failed:-?}"
  if [ "$rc" -ne 0 ] || [ -z "$total" ] || [ "${failed:-1}" != "0" ]; then
    fail "$engine tests (exit $rc)"
    ENGINE_FAILED=$(( ENGINE_FAILED + (${failed:-0} == 0 ? 1 : 0) ))
    grep -E "error:|failed" "$log" | head -50 | tee -a "$OUT/failures.txt"
  fi
done

step "Generate Xcode project with XcodeGen"
if ! command -v xcodegen >/dev/null; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcodegen > "$OUT/brew.log" 2>&1
fi
xcodegen --version
if ! xcodegen generate --spec project.yml > "$OUT/xcodegen.log" 2>&1; then
  cat "$OUT/xcodegen.log"
  fail "xcodegen generate"
fi

step "Build for testing"
with_timeout 1200 xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  -derivedDataPath "$BUILD/DerivedData" \
  -skipPackagePluginValidation -skipMacroValidation \
  COMPILER_INDEX_STORE_ENABLE=NO > "$OUT/build.log" 2>&1
BUILD_RC=$?
grep -E "(error|warning): " "$OUT/build.log" | grep -v "^ld: warning" | sort -u > "$OUT/build-diagnostics.txt"
grep -E "error: " "$OUT/build-diagnostics.txt" > "$OUT/build-errors.txt"
echo "build exit $BUILD_RC, $(wc -l < "$OUT/build-errors.txt" | tr -d ' ') errors, $(grep -c 'warning: ' "$OUT/build-diagnostics.txt") warnings"
if [ "$BUILD_RC" -ne 0 ]; then
  fail "build-for-testing (exit $BUILD_RC)"
  head -80 "$OUT/build-errors.txt" | tee -a "$OUT/failures.txt"
  tail -40 "$OUT/build.log"
fi

if [ "$BUILD_RC" -eq 0 ]; then
  step "Prepare simulator"
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
  xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100 || true

  step "Unit and UI tests"
  rm -rf "$BUILD/Tests.xcresult"
  TEST_RUNNER_SCREENSHOT_DIR="$OUT/screenshots" with_timeout 1200 xcodebuild test-without-building \
    -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
    -derivedDataPath "$BUILD/DerivedData" \
    -resultBundlePath "$BUILD/Tests.xcresult" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
    -maximum-test-execution-time-allowance 600 > "$OUT/test.log" 2>&1
  TEST_RC=$?
  echo "xcodebuild test exit $TEST_RC"
  grep -E "Executed [0-9]+ tests?, with" "$OUT/test.log" | tail -5

  step "Collect results"
  python3 ci/xcresult_summary.py "$BUILD/Tests.xcresult" "$OUT" "$OUT/test.log"
  SUMMARY_RC=$?
  if [ "$TEST_RC" -ne 0 ] || [ "$SUMMARY_RC" -ne 0 ]; then
    fail "unit/UI tests (xcodebuild exit $TEST_RC)"
  fi

  # Screenshots normally arrive straight from the test runner; fall back to the result bundle.
  if [ -z "$(ls -A "$OUT/screenshots" 2>/dev/null)" ]; then
    echo "exporting screenshots from the result bundle"
    rm -rf "$BUILD/attachments"
    xcrun xcresulttool export attachments --path "$BUILD/Tests.xcresult" --output-path "$BUILD/attachments" > /dev/null 2>&1
    python3 ci/xcresult_summary.py --rename-attachments "$BUILD/attachments" "$OUT/screenshots"
  fi
  echo "screenshots: $(ls "$OUT/screenshots" | wc -l | tr -d ' ')"
fi

step "Totals"
{
  echo "engines (swift test): ${ENGINE_TOTAL} tests, ${ENGINE_FAILED} failures (tests/failures:${ENGINE_SUMMARY})"
  if [ -f "$OUT/app-totals.txt" ]; then cat "$OUT/app-totals.txt"; else echo "app (xcodebuild): not run"; fi
  APP_TOTAL=$(sed -nE 's/.* ([0-9]+) tests,.*/\1/p' "$OUT/app-totals.txt" 2>/dev/null | head -1)
  APP_FAILED=$(sed -nE 's/.* ([0-9]+) failed.*/\1/p' "$OUT/app-totals.txt" 2>/dev/null | head -1)
  echo "TOTAL: $(( ${ENGINE_TOTAL:-0} + ${APP_TOTAL:-0} )) tests, $(( ${ENGINE_FAILED:-0} + ${APP_FAILED:-0} )) failures"
  if [ "$STATUS" -eq 0 ]; then echo "RESULT: PASSED"; else echo "RESULT: FAILED"; fi
} | tee "$OUT/totals.txt"

if [ -s "$OUT/failures.txt" ]; then
  step "Failures"
  cat "$OUT/failures.txt"
fi
xcrun simctl shutdown "$UDID" > /dev/null 2>&1 || true
echo "finished in $(( $(date +%s) - START ))s"
exit $STATUS
