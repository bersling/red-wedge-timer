#!/usr/bin/env bash
# Archives, exports and uploads the iPhone app to App Store Connect.
#
#   ./release.sh              # archive, export, upload
#   ./release.sh --no-upload  # stop after the .ipa
#
# Needs the App Store Connect credentials in the environment; the toddler-games
# .env holds them:
#   set -a; . ~/IT-Projects/toddler-games/.env; set +a
#
# The app record has to exist in App Store Connect first — the API cannot
# create one.
set -euo pipefail
cd "$(dirname "$0")"

UPLOAD=true
[ "${1:-}" = "--no-upload" ] && UPLOAD=false

: "${APPSTORECONNECT_KEY_ID:?set it, or source the toddler-games .env}"
: "${APPSTORECONNECT_ISSUER_ID:?set it, or source the toddler-games .env}"

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
	mkdir -p ~/.appstoreconnect/private_keys
	cp "${APPSTORECONNECT_P8:-$HOME/IT-Projects/toddler-games/AuthKey_${APPSTORECONNECT_KEY_ID}.p8}" \
		~/.appstoreconnect/private_keys/"AuthKey_${APPSTORECONNECT_KEY_ID}.p8"
	xcrun altool --upload-app -f "$IPA" -t ios \
		--apiKey "$APPSTORECONNECT_KEY_ID" --apiIssuer "$APPSTORECONNECT_ISSUER_ID"
	echo "## uploaded; processing takes a few minutes before the build is submittable"
fi
