#!/bin/bash
# Runs each game's rules-engine tests with `swift test` and leaves, for every engine, its log
# (engine-tests-NAME.log) and exit code (engine-tests-NAME.rc) in the output folder given as $1.
# ci/run.sh starts this at low priority alongside the UI tests and reads the results after.
#
# Release mode with testability runs the heavy invariant tests several times faster than a
# debug build.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?output folder}
mkdir -p "$OUT"

# A time limit (macOS has no `timeout`), so a hang fails one engine instead of the whole job.
with_timeout() {
  local limit=$1; shift
  "$@" &
  local pid=$!
  # `&&`: when the command finishes first, its `sleep` is killed and nothing is reported.
  ( sleep "$limit" && { echo "TIMEOUT: killed after ${limit}s: $*"; kill -TERM "$pid" 2>/dev/null; sleep 15; kill -KILL "$pid" 2>/dev/null; } ) &
  local watchdog=$!
  wait "$pid"
  local rc=$?
  pkill -P "$watchdog" 2>/dev/null
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return $rc
}

for engine in KlondikeEngine BubbleEngine ArcheryEngine; do
  start=$(date +%s)
  (cd "Packages/$engine" && with_timeout 900 swift test -c release -Xswiftc -enable-testing) > "$OUT/engine-tests-$engine.log" 2>&1
  echo $? > "$OUT/engine-tests-$engine.rc"
  echo "$engine finished in $(( $(date +%s) - start ))s" >> "$OUT/engine-tests-$engine.log"
done
