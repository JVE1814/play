#!/bin/bash
# Fails if app or package sources use networking APIs, or if any third-party dependency
# appears. Run from anywhere: bash ci/audit.sh
cd "$(dirname "$0")/.."
status=0
SOURCES=(App AppTests UITests Packages Games)

echo "Networking APIs in Swift sources:"
PATTERN='URLSession|URLRequest|NSURLConnection|URLSessionWebSocket|import Network\b|NWConnection|NWListener|NWPathMonitor|CFNetwork|CFSocket|CFStream|NSStream|InputStream\(url|OutputStream\(url|import WebKit|WKWebView|SFSafariViewController|import SafariServices|import MultipeerConnectivity|import CloudKit|import GameKit|import StoreKit|import AdSupport|import AppTrackingTransparency|ASIdentifierManager|https?://|socket\(|getaddrinfo|Data\(contentsOf: *URL\(string'
if grep -rnE "$PATTERN" --exclude-dir=.build --include='*.swift' "${SOURCES[@]}"; then
  status=1
else
  echo "  none found"
fi

echo "Remote package dependencies (Package.swift, project.yml):"
if grep -rnE '\.package\((url|name):|url: *"http|github\.com' --exclude-dir=.build --include='Package.swift' "${SOURCES[@]}" || \
   grep -nE '^\s+url:|github\.com' project.yml; then
  status=1
else
  echo "  none found (all packages are local paths)"
fi

echo "Other dependency managers:"
found=$(find . \( -path ./build -o -name .build \) -prune -o \( -name Podfile -o -name Cartfile -o -name 'Package.resolved' -o -name '*.podspec' \) -print)
if [ -n "$found" ]; then
  echo "$found"
  status=1
else
  echo "  none found (no CocoaPods, Carthage or resolved remote packages)"
fi

for engine in KlondikeEngine BubbleEngine ArcheryEngine; do
  echo "Imports used by $engine (must be Foundation only, plus the engine itself in its tool):"
  grep -rhoE '^import [A-Za-z]+' "Packages/$engine/Sources" | sort | uniq -c
  if grep -rhE '^import ' "Packages/$engine/Sources" | grep -vqE "^import (Foundation|$engine)\$"; then
    echo "  $engine imports something other than Foundation"
    status=1
  fi
done

echo "All imports across the app:"
grep -rhoE '^(@testable )?import [A-Za-z]+' --exclude-dir=.build --include='*.swift' "${SOURCES[@]}" | sed 's/@testable //' | sort | uniq -c
exit $status
