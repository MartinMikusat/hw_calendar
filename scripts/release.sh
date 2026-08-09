#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SITE_ROOT=${HW_CALENDAR_SITE_ROOT:-"$ROOT/../hal_wayland"}
INSTALL=${HW_CALENDAR_RELEASE_CACHE:-"$ROOT/build/release-dependencies"}/install
NOTARY_PROFILE=${HW_CALENDAR_NOTARY_PROFILE:-hw_videoClips-notary}
REPOSITORY=MartinMikusat/hw_calendar
PLIST="$ROOT/Info.plist"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
TAG="v$VERSION"
ASSET="hw_calendar-$VERSION.dmg"
NOTES="$ROOT/releases/$VERSION.md"
OUTPUT="$ROOT/release-output/$VERSION"
APP="$ROOT/build/release/hw_calendar.app"
DMG="$OUTPUT/$ASSET"
APPCAST_STAGE="$OUTPUT/appcast"
SITE_UPDATE_DIR="$SITE_ROOT/static/updates/hw_calendar/stable"
SITE_RELEASE_FILE="$SITE_ROOT/src/features/website/products/hwCalendarRelease.ts"

if ! printf '%s\n' "$VERSION" | grep -Eq '^0\.[0-9]+\.[0-9]+$' ||
   ! printf '%s\n' "$BUILD" | grep -Eq '^[1-9][0-9]*$'; then
	echo "[release] Info.plist contains an invalid version or build" >&2
	exit 1
fi
if [ ! -f "$NOTES" ]; then
	echo "[release] missing release notes: $NOTES" >&2
	exit 1
fi
if [ "$(git -C "$ROOT" branch --show-current)" != main ]; then
	echo "[release] hw_calendar must be on main" >&2
	exit 1
fi
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
	echo "[release] hw_calendar must be clean and committed" >&2
	exit 1
fi
if [ "$(git -C "$SITE_ROOT" branch --show-current)" != staging ]; then
	echo "[release] hal_wayland must be on staging" >&2
	exit 1
fi
if [ -n "$(git -C "$SITE_ROOT" status --porcelain)" ]; then
	echo "[release] hal_wayland must be clean and committed" >&2
	exit 1
fi

git -C "$ROOT" fetch origin --tags
git -C "$SITE_ROOT" fetch origin main staging
test "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse origin/main)" || {
	echo "[release] hw_calendar main must match origin/main" >&2
	exit 1
}
gh auth status >/dev/null

RESUME_PUBLICATION=false
if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
	if [ ! -f "$DMG" ] || [ ! -f "$APPCAST_STAGE/appcast.xml" ]; then
		echo "[release] $TAG exists without matching local release artifacts" >&2
		exit 1
	fi
	VERIFY_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/hw-calendar-release-verify.XXXXXX")
	trap 'find "$VERIFY_STAGE" -depth -delete' EXIT HUP INT TERM
	gh release download "$TAG" --repo "$REPOSITORY" --pattern "$ASSET" --dir "$VERIFY_STAGE"
	cmp -s "$DMG" "$VERIFY_STAGE/$ASSET" || {
		echo "[release] local and published DMG files differ" >&2
		exit 1
	}
	RESUME_PUBLICATION=true
fi

LATEST_APPCAST=$(mktemp "${TMPDIR:-/tmp}/hw-calendar-appcast.XXXXXX")
curl --fail --silent --location \
	"https://www.halwayland.com/updates/hw_calendar/stable/appcast.xml" \
	--output "$LATEST_APPCAST" 2>/dev/null || true
LATEST_BUILD=$(xmllint --xpath \
	'string((//*[local-name()="item"][1]/*[local-name()="version"])[1])' \
	"$LATEST_APPCAST" 2>/dev/null || true)
if [ -n "$LATEST_BUILD" ] && [ "$BUILD" -le "$LATEST_BUILD" ]; then
	echo "[release] build $BUILD must be greater than published build $LATEST_BUILD" >&2
	exit 1
fi

"$ROOT/scripts/dependencies.sh" check
"$ROOT/scripts/setup-release-credentials.sh"
SIGNING_IDENTITY=${HW_CALENDAR_SIGNING_IDENTITY:-$(
	security find-identity -v -p codesigning |
		sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
		head -1
)}
if [ -z "$SIGNING_IDENTITY" ]; then
	echo "[release] no Developer ID Application identity found" >&2
	exit 1
fi

if [ "$RESUME_PUBLICATION" = false ]; then
	mkdir -p "$OUTPUT" "$APPCAST_STAGE"
	"$ROOT/test.sh"
	"$ROOT/build.sh" release

	EXECUTABLE="$APP/Contents/MacOS/hw_calendar"
	if ! file "$EXECUTABLE" | grep -q 'arm64'; then
		echo "[release] executable is not Apple Silicon" >&2
		exit 1
	fi
	if otool -L "$EXECUTABLE" | grep -Eq '/(opt/homebrew|usr/local)/'; then
		echo "[release] executable contains a development-machine library path" >&2
		exit 1
	fi
	if ! otool -l "$EXECUTABLE" |
	   awk '/cmd LC_RPATH/{active=1; next} active && $1 == "path" {print $2; active=0}' |
	   grep -qx '@executable_path/../Frameworks'; then
		echo "[release] executable does not resolve the bundled Sparkle framework" >&2
		exit 1
	fi

	"$ROOT/scripts/sign-release-app.sh" "$APP" "$SIGNING_IDENTITY"

	DMG_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/hw-calendar-dmg.XXXXXX")
	ditto "$APP" "$DMG_STAGE/hw_calendar.app"
	ln -s /Applications "$DMG_STAGE/Applications"
	hdiutil create -quiet -fs HFS+ -volname "hw_calendar $VERSION" \
		-srcfolder "$DMG_STAGE" -format UDZO "$DMG"
	codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
	xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$DMG"
	xcrun stapler validate "$DMG"
	spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

	cp "$DMG" "$APPCAST_STAGE/$ASSET"
	cp "$NOTES" "$APPCAST_STAGE/hw_calendar-$VERSION.md"
	"$INSTALL/Sparkle/generate_appcast" \
		--account hw_calendar \
		--download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
		--release-notes-url-prefix "https://www.halwayland.com/updates/hw_calendar/stable/releases/" \
		--link "https://www.halwayland.com/products/hw_calendar" \
		"$APPCAST_STAGE"
	APPCAST="$APPCAST_STAGE/appcast.xml"
	if [ ! -f "$APPCAST" ] || ! grep -q 'sparkle:edSignature=' "$APPCAST"; then
		echo "[release] Sparkle did not produce a signed appcast" >&2
		exit 1
	fi
else
	APPCAST="$APPCAST_STAGE/appcast.xml"
fi

printf '\nRelease %s (%s)\nAsset: %s\nFeed: https://www.halwayland.com/updates/hw_calendar/stable/appcast.xml\n\n' \
	"$VERSION" "$BUILD" "$DMG"
printf 'Type publish %s to create the public release: ' "$VERSION"
IFS= read -r confirmation
if [ "$confirmation" != "publish $VERSION" ]; then
	echo "[release] publication cancelled; signed artifacts remain in $OUTPUT"
	exit 0
fi

if [ "$RESUME_PUBLICATION" = false ]; then
	gh release create "$TAG" "$DMG" --repo "$REPOSITORY" \
		--target "$(git -C "$ROOT" rev-parse HEAD)" \
		--title "hw_calendar $VERSION" \
		--notes-file "$NOTES"
fi

mkdir -p "$SITE_UPDATE_DIR/releases"
cp "$APPCAST" "$SITE_UPDATE_DIR/appcast.xml"
cp "$APPCAST_STAGE/hw_calendar-$VERSION.md" \
	"$SITE_UPDATE_DIR/releases/hw_calendar-$VERSION.md"
perl -0pi -e \
	"s/version: '[^']+'/version: '$VERSION'/; s/build: '[^']+'/build: '$BUILD'/; s/published: false/published: true/; s#downloadUrl:\\n\\t\\t'[^']*'#downloadUrl:\\n\\t\\t'https://github.com/$REPOSITORY/releases/download/$TAG/$ASSET'#; s#releaseNotesUrl:\\n\\t\\t'[^']*'#releaseNotesUrl:\\n\\t\\t'https://www.halwayland.com/updates/hw_calendar/stable/releases/hw_calendar-$VERSION.md'#" \
	"$SITE_RELEASE_FILE"

(
	cd "$SITE_ROOT"
	npm run test:unit -- --run src/features/website/siteActions.test.ts
	npm run build
	git add \
		static/updates/hw_calendar/stable \
		src/features/website/products/hwCalendarRelease.ts
	git commit -m "chore(release): publish hw_calendar $VERSION"
	git push origin staging
	git switch main
	git merge --ff-only staging
	git push origin main
	git switch staging
)

PUBLISHED_APPCAST=$(mktemp "${TMPDIR:-/tmp}/hw-calendar-published-appcast.XXXXXX")
attempt=0
PUBLISHED_BUILD=""
while [ "$attempt" -lt 24 ]; do
	attempt=$((attempt + 1))
	if curl --fail --silent --location \
	   "https://www.halwayland.com/updates/hw_calendar/stable/appcast.xml" \
	   --output "$PUBLISHED_APPCAST"; then
		PUBLISHED_BUILD=$(xmllint --xpath \
			'string((//*[local-name()="item"][1]/*[local-name()="version"])[1])' \
			"$PUBLISHED_APPCAST" 2>/dev/null || true)
		if [ "$PUBLISHED_BUILD" = "$BUILD" ]; then
			break
		fi
	fi
	sleep 5
done
if [ "$PUBLISHED_BUILD" != "$BUILD" ]; then
	echo "[release] website feed did not deploy build $BUILD within two minutes" >&2
	exit 1
fi
curl --fail --silent --location \
	"https://www.halwayland.com/products/hw_calendar" >/dev/null
printf '[release] published hw_calendar %s (%s)\n' "$VERSION" "$BUILD"
