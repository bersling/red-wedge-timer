#!/usr/bin/env bash
# Turns the certificate Apple issued into a usable signing identity on this Mac,
# and installs the provisioning profile.
#
#   ./install-signing.sh [path/to/distribution.key]
#
# Run this yourself: it writes to your login keychain and ~/Library, which the
# agent's sandbox refuses (rightly — those are credential stores).
#
# The private key defaults to the scratchpad it was generated in. That directory
# is temporary, so the script copies the key to ~/Documents/signing first. If the
# scratchpad is already gone, the certificate is dead: revoke it in the developer
# portal and re-run `node asc-provision.mjs certificate`.
set -euo pipefail
cd "$(dirname "$0")"

SCRATCH=/private/tmp/claude-501/-Users-bersling-IT-Projects/75d193ce-5527-4cf2-abff-96ed6c9ebbe1/scratchpad
KEY="${1:-$SCRATCH/distribution.key}"
DEST="$HOME/Documents/signing"
PROFILE_UUID=c75b5392-11e8-4b49-bd08-be7c1d6688ce
PASS="transfer-$$"   # only exists to carry the key into the keychain

# Homebrew's OpenSSL 3 writes PKCS#12 files with AES-256 and a SHA-256 MAC,
# which macOS's Security framework rejects as "MAC verification failed". The
# system LibreSSL writes the older format `security import` understands.
SYS_OPENSSL=/usr/bin/openssl

if [ ! -f "$KEY" ]; then
	echo "No private key at:"
	echo "  $KEY"
	echo "Pass its path as the first argument if you moved it."
	exit 1
fi
if [ ! -f build/distribution.cer ]; then
	echo "Missing build/distribution.cer. Check what the account has with:"
	echo "  node asc-provision.mjs status"
	exit 1
fi

echo "## keeping the private key somewhere permanent"
mkdir -p "$DEST"
cp "$KEY" "$DEST/redwedge-distribution.key"
chmod 600 "$DEST/redwedge-distribution.key"

echo "## converting Apple's DER certificate to PEM"
"$SYS_OPENSSL" x509 -inform DER -in build/distribution.cer -out "$DEST/redwedge-distribution.pem"

echo "## pairing key and certificate into a .p12 (system LibreSSL, for macOS)"
rm -f "$DEST/redwedge-distribution.p12"
"$SYS_OPENSSL" pkcs12 -export \
	-inkey "$DEST/redwedge-distribution.key" \
	-in "$DEST/redwedge-distribution.pem" \
	-name "Red Wedge Timer Distribution" \
	-out "$DEST/redwedge-distribution.p12" \
	-passout "pass:$PASS" \
	-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
chmod 600 "$DEST/redwedge-distribution.p12"

echo "## importing into the login keychain (macOS may ask for your password)"
security import "$DEST/redwedge-distribution.p12" \
	-k "$HOME/Library/Keychains/login.keychain-db" \
	-P "$PASS" -T /usr/bin/codesign -T /usr/bin/security

echo "## installing the provisioning profile"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp build/RedWedgeTimer.mobileprovision \
	"$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

echo
echo "## identities now available"
security find-identity -v -p codesigning

if security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
	echo
	echo "Ready. The key lives in $DEST — back it up; without it the certificate is worthless."
	echo "If a build still says no identity was found, macOS is withholding access to the"
	echo "fresh key. Unlock it with:"
	echo "  security set-key-partition-list -S apple-tool:,apple: -k <login password> ~/Library/Keychains/login.keychain-db"
else
	echo
	echo "The Apple Distribution identity did not appear, so the import failed."
	exit 1
fi
