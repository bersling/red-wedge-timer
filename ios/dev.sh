#!/usr/bin/env bash
# Builds and installs the app straight onto the paired iPhone, bypassing the
# App Store entirely. Use this while a release sits in review.
#
#   ./dev.sh          # build, install, launch
#   ./dev.sh --build  # stop after the build
#
# The device has to be reachable: plugged in, or paired over Wi-Fi via
# Xcode > Window > Devices and Simulators > "Connect via network".
set -euo pipefail
cd "$(dirname "$0")"

SCHEME=RedWedgeTimer
DEVICE=${DEVICE:-B3C1FA12-2E34-575F-9533-1526CF34A119}

# The device name contains spaces, so key off the identifier and take the
# next column rather than counting fields.
state=$(xcrun devicectl list devices 2>/dev/null |
	sed -n "s/.*$DEVICE[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p")
if [ "$state" != "connected" ]; then
	echo "device $DEVICE is '${state:-not paired}' — plug the phone in and unlock it" >&2
	exit 1
fi

echo "## building"
xcodebuild -quiet -project "$SCHEME.xcodeproj" -scheme "$SCHEME" \
	-configuration Debug -destination "id=$DEVICE" \
	-derivedDataPath build/dev -allowProvisioningUpdates build

APP=$(ls -d build/dev/Build/Products/Debug-iphoneos/*.app | head -1)
[ "${1:-}" = "--build" ] && { echo "## built $APP"; exit 0; }

echo "## installing"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" com.bersling.redwedgetimer
