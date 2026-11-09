# Shared by the CI scripts: `source ci/lib.sh` from the repository root.

# Each game's rules engine is a Foundation-only package in Packages/ whose name ends in "Engine".
ENGINES=$(cd Packages && ls -d *Engine)
if [ -z "$ENGINES" ]; then
  echo "ci/lib.sh: no rules engines found under Packages/" >&2
  exit 1
fi

# Runs a command with a time limit (macOS has no `timeout`), so a hang fails one step instead
# of the whole job hitting the workflow timeout before results are published.
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
