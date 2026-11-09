#!/bin/bash
# Archives Between Stops and uploads it to App Store Connect (TestFlight), or exports an .ipa.
# Runs on a Mac with Xcode 26+ or on a macOS CI runner (see .github/workflows/testflight.yml).
#
# Required environment:
#   ASC_KEY_ID      App Store Connect API key ID
#   ASC_ISSUER_ID   App Store Connect issuer ID
#   ASC_KEY_PATH    path to the downloaded AuthKey_XXXXXXXXXX.p8 file
#   APP_TEAM_ID     your 10-character Apple Developer Team ID
# Optional:
#   APP_BUNDLE_ID   overrides the value in Config/Signing.xcconfig
#   BUILD_NUMBER    must increase with every upload (default: UTC timestamp)
#   UPLOAD=0        only export build/export/BetweenStops.ipa, do not upload
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
: "${APP_TEAM_ID:?set APP_TEAM_ID}"
BUILD_NUMBER=${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}
DESTINATION=upload
if [ "${UPLOAD:-1}" = "0" ]; then DESTINATION=export; fi

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --spec project.yml
mkdir -p build

OVERRIDES=("APP_DEVELOPMENT_TEAM=$APP_TEAM_ID" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
if [ -n "${APP_BUNDLE_ID:-}" ]; then OVERRIDES+=("APP_BUNDLE_ID=$APP_BUNDLE_ID"); fi
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "Archiving build $BUILD_NUMBER"
rm -rf build/BetweenStops.xcarchive build/export
xcodebuild archive \
  -project BetweenStops.xcodeproj -scheme BetweenStops -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/BetweenStops.xcarchive \
  "${AUTH[@]}" "${OVERRIDES[@]}"

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DESTINATION</string>
	<key>teamID</key><string>$APP_TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "Exporting ($DESTINATION)"
xcodebuild -exportArchive -archivePath build/BetweenStops.xcarchive \
  -exportPath build/export -exportOptionsPlist build/ExportOptions.plist "${AUTH[@]}"
if [ "$DESTINATION" = upload ]; then
  echo "Uploaded build $BUILD_NUMBER. It appears in App Store Connect > TestFlight after processing (5-30 min)."
else
  echo "Exported: $(ls build/export/*.ipa)"
fi
