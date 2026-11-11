#!/bin/bash
# Runs each game's rules-engine tests with `swift test` and leaves, for every engine, its log
# (engine-tests-NAME.log) and exit code (engine-tests-NAME.rc) in the output folder given as $1.
# ci/run.sh starts this at low priority alongside the UI tests and reads the results after.
#
# Release mode with testability runs the heavy invariant tests several times faster than a
# debug build.
set -uo pipefail
cd "$(dirname "$0")/.."
source ci/lib.sh
OUT=${1:?output folder}
# Optional: build jobs per engine (run.sh uses 1 so the UI tests keep the other cores).
JOBS=${2:-}
mkdir -p "$OUT"

for engine in $ENGINES; do
  start=$(date +%s)
  (cd "Packages/$engine" && with_timeout 900 swift test -c release -Xswiftc -enable-testing ${JOBS:+--jobs "$JOBS"}) \
    > "$OUT/engine-tests-$engine.log" 2>&1
  echo $? > "$OUT/engine-tests-$engine.rc"
  echo "$engine finished in $(( $(date +%s) - start ))s" >> "$OUT/engine-tests-$engine.log"
done
