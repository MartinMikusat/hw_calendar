#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PLIST="$ROOT/Info.plist"
VERSION=${1:-}
BUILD=${2:-}

if ! printf '%s\n' "$VERSION" | grep -Eq '^0\.[0-9]+\.[0-9]+$'; then
	echo "usage: ./scripts/set-version.sh 0.x.y positive-build-number" >&2
	exit 2
fi
if ! printf '%s\n' "$BUILD" | grep -Eq '^[1-9][0-9]*$'; then
	echo "usage: ./scripts/set-version.sh 0.x.y positive-build-number" >&2
	exit 2
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
plutil -lint "$PLIST" >/dev/null
printf '[version] prepared %s (%s)\n' "$VERSION" "$BUILD"
