#!/bin/bash
# Fails if app or package sources use networking APIs, or if any third-party dependency
# appears. Run from anywhere: bash ci/audit.sh
cd "$(dirname "$0")/.."
source ci/lib.sh
status=0
# Every Swift file in the repository, wherever it lives. Git lists them, so this needs a checkout.
swift_files() { git ls-files -z -- "$@"; }
if [ -z "$(git ls-files -- '*.swift')" ]; then
  echo "audit: git lists no Swift files here, so there is nothing to check"
  exit 1
fi

echo "Networking APIs in Swift sources:"
PATTERN='URLSession|URLRequest|NSURLConnection|URLSessionWebSocket|import Network\b|NWConnection|NWListener|NWPathMonitor|CFNetwork|CFSocket|CFStream|NSStream|InputStream\(url|OutputStream\(url|import WebKit|WKWebView|SFSafariViewController|import SafariServices|import MultipeerConnectivity|import CloudKit|import GameKit|import StoreKit|import AdSupport|import AppTrackingTransparency|ASIdentifierManager|https?://|socket\(|getaddrinfo|Data\(contentsOf: *URL\(string'
if swift_files '*.swift' | xargs -0 grep -nE "$PATTERN"; then
  status=1
else
  echo "  none found"
fi

echo "Remote package dependencies (Package.swift, project.yml):"
if swift_files '*Package.swift' | xargs -0 grep -nE '\.package\((url|name):|url: *"http|github\.com' || \
   grep -nE '^\s+url:|github\.com' project.yml; then
  status=1
else
  echo "  none found (all packages are local paths)"
fi

echo "Other dependency managers:"
found=$(git ls-files -- Podfile '*/Podfile' Cartfile '*/Cartfile' Package.resolved '*/Package.resolved' '*.podspec')
if [ -n "$found" ]; then
  echo "$found"
  status=1
else
  echo "  none found (no CocoaPods, Carthage or resolved remote packages)"
fi

for engine in $ENGINES; do
  echo "Imports used by $engine (must be Foundation only, plus the engine itself in its tool):"
  grep -rhoE '^import [A-Za-z]+' "Packages/$engine/Sources" | sort | uniq -c
  if grep -rhE '^import ' "Packages/$engine/Sources" | grep -vqE "^import (Foundation|$engine)\$"; then
    echo "  $engine imports something other than Foundation"
    status=1
  fi
done

echo "All imports across the app:"
swift_files '*.swift' | xargs -0 grep -hoE '^(@testable )?import [A-Za-z]+' | sed 's/@testable //' | sort | uniq -c
exit $status
