#!/bin/bash
# Probe script: records the runner environment so the real pipeline can be tuned.
set -uo pipefail
OUT="ci-output"
mkdir -p "$OUT"
{
  echo "== date"; date -u
  echo "== sw_vers"; sw_vers
  echo "== xcode"; xcodebuild -version; xcode-select -p
  echo "== installed xcodes"; ls -d /Applications/Xcode*.app
  echo "== sdks"; xcodebuild -showsdks
  echo "== swift"; swift --version
  echo "== runtimes"; xcrun simctl list runtimes
  echo "== devices"; xcrun simctl list devices available
  echo "== tools"; command -v xcodegen brew python3 xcbeautify jq || true
  python3 --version
  echo "== disk"; df -h .
  echo "== cpu"; sysctl -n hw.ncpu machdep.cpu.brand_string
} > "$OUT/env.txt" 2>&1
cat "$OUT/env.txt"
start=$(date +%s)
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install xcodegen > "$OUT/brew.txt" 2>&1
echo "brew install xcodegen exit=$? seconds=$(( $(date +%s) - start ))"
xcodegen --version || true
echo "probe complete"
