#!/bin/sh
set -eu

APP=${1:-}
IDENTITY=${2:-}

if [ ! -d "$APP" ] || [ -z "$IDENTITY" ]; then
	echo "usage: ./scripts/sign-release-app.sh /path/to/app 'Developer ID Application: ...'" >&2
	exit 2
fi

FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for component in \
	"$FRAMEWORK/XPCServices/Downloader.xpc" \
	"$FRAMEWORK/XPCServices/Installer.xpc" \
	"$FRAMEWORK/Updater.app" \
	"$FRAMEWORK/Autoupdate"
do
	if [ -e "$component" ]; then
		codesign --force --timestamp --options runtime \
			--preserve-metadata=identifier,entitlements \
			--sign "$IDENTITY" "$component"
	fi
done
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
	"$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
