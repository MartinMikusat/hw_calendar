#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALL=${HW_CALENDAR_RELEASE_CACHE:-"$ROOT/build/release-dependencies"}/install
NOTARY_PROFILE=${HW_CALENDAR_NOTARY_PROFILE:-hw_videoClips-notary}

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
	echo "[release setup] no Developer ID Application identity is installed" >&2
	exit 1
fi

"$ROOT/scripts/prepare-release-dependencies.sh"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
	echo "[release setup] notarization profile is unavailable: $NOTARY_PROFILE" >&2
	echo "Set HW_CALENDAR_NOTARY_PROFILE or store credentials with notarytool." >&2
	exit 1
fi

if /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Info.plist" |
   grep -q '^REPLACE_WITH_'; then
	echo "[release setup] generate the Sparkle Ed25519 key:" >&2
	echo "$INSTALL/Sparkle/generate_keys --account hw_calendar" >&2
	echo "Copy the public key into Info.plist and retain the Keychain private key." >&2
	exit 1
fi

printf '[release setup] signing, notarization, dependencies, and Sparkle key are available\n'
