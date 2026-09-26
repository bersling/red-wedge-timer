#!/usr/bin/env bash
# Archives, exports and uploads the iPhone app to App Store Connect.
#
#   ./release.sh              # archive, export, upload
#   ./release.sh --no-upload  # stop after the .ipa
#
# Reads the App Store Connect credentials from the repo's .env (gitignored), or
# from the environment.
#
# The app record has to exist in App Store Connect first — the API cannot
# create one.
set -euo pipefail
cd "$(dirname "$0")"
if [ -f ../.env ]; then set -a; . ../.env; set +a; fi

UPLOAD=true
[ "${1:-}" = "--no-upload" ] && UPLOAD=false

: "${APPSTORECONNECT_KEY_ID:?set it in .env}"
: "${APPSTORECONNECT_ISSUER_ID:?set it in .env}"

ARCHIVE=build/RedWedgeTimer.xcarchive

echo "## archiving"
xcodebuild -project RedWedgeTimer.xcodeproj -scheme RedWedgeTimer \
	-configuration Release -sdk iphoneos -archivePath "$ARCHIVE" archive

echo "## exporting"
rm -rf build/export
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
	-exportOptionsPlist ExportOptions.plist -exportPath build/export

IPA=$(ls build/export/*.ipa | head -1)
echo "## built $IPA"

if [ "$UPLOAD" = true ]; then
	echo "## uploading"
	# altool wants the key at a fixed location
	KEY=~/.appstoreconnect/private_keys/"AuthKey_${APPSTORECONNECT_KEY_ID}.p8"
	[ -f "$KEY" ] || { mkdir -p "$(dirname "$KEY")"; cp "$APPSTORECONNECT_P8" "$KEY"; }
	xcrun altool --upload-app -f "$IPA" -t ios \
		--apiKey "$APPSTORECONNECT_KEY_ID" --apiIssuer "$APPSTORECONNECT_ISSUER_ID"
	echo "## uploaded; processing takes a few minutes before the build is submittable"
fi
