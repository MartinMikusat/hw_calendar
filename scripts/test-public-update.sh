#!/bin/sh
set -eu

# Install the latest published stable app, then Sparkle-update it to the signed
# release candidate and verify the installed bundle matches that candidate.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TARGET_APP=${1:-}
IDENTITY=${2:-}
INSTALL=${HW_CALENDAR_RELEASE_CACHE:-"$ROOT/build/release-dependencies"}/install
PUBLIC_APPCAST_URL=https://www.halwayland.com/updates/hw_calendar/stable/appcast.xml

if [ ! -d "$TARGET_APP" ] || [ -z "$IDENTITY" ]; then
	echo "usage: ./scripts/test-public-update.sh /path/to/candidate.app 'Developer ID Application: ...'" >&2
	exit 2
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
	"$TARGET_APP/Contents/Info.plist")
TARGET_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
	"$TARGET_APP/Contents/Info.plist")
if ! printf '%s\n' "$TARGET_BUILD" | grep -Eq '^[1-9][0-9]*$'; then
	echo "[public update] candidate build is invalid" >&2
	exit 1
fi

PUBLIC_APPCAST=$(mktemp "${TMPDIR:-/tmp}/hw-calendar-public-appcast.XXXXXX")
curl --fail --silent --show-error --location \
	"$PUBLIC_APPCAST_URL" --output "$PUBLIC_APPCAST"
PUBLIC_BUILD=$(xmllint --xpath \
	'string((//*[local-name()="item"][1]/*[local-name()="version"])[1])' \
	"$PUBLIC_APPCAST")
PUBLIC_VERSION=$(xmllint --xpath \
	'string((//*[local-name()="item"][1]/*[local-name()="shortVersionString"])[1])' \
	"$PUBLIC_APPCAST")
PUBLIC_DMG_URL=$(xmllint --xpath \
	'string((//*[local-name()="item"][1]/*[local-name()="enclosure"]/@url)[1])' \
	"$PUBLIC_APPCAST")
if ! printf '%s\n' "$PUBLIC_BUILD" | grep -Eq '^[1-9][0-9]*$' ||
   [ -z "$PUBLIC_VERSION" ] || [ -z "$PUBLIC_DMG_URL" ]; then
	echo "[public update] published appcast has no usable release" >&2
	exit 1
fi
if [ "$TARGET_BUILD" -le "$PUBLIC_BUILD" ]; then
	echo "[public update] candidate build $TARGET_BUILD must be greater than published build $PUBLIC_BUILD" >&2
	exit 1
fi

TEST_ROOT=$(mktemp -d /tmp/hwcu.XXXXXX)
TARGET_COPY="$TEST_ROOT/target/hw_calendar.app"
SOURCE_APP="$TEST_ROOT/source/hw_calendar.app"
SUPPORT_DIR="$TEST_ROOT/support"
FEED_DIR="$TEST_ROOT/feed"
DMG_PATH="$TEST_ROOT/public.dmg"
MOUNT_POINT="$TEST_ROOT/mnt"
SERVER_PID=
SOURCE_PID=
ATTACHED=

cleanup() {
	if [ -n "$SOURCE_PID" ] && kill -0 "$SOURCE_PID" 2>/dev/null; then
		kill "$SOURCE_PID" 2>/dev/null || true
		wait "$SOURCE_PID" 2>/dev/null || true
	fi
	if [ -d "$SOURCE_APP" ]; then
		for process in $(pgrep -f "$SOURCE_APP/Contents/MacOS/hw_calendar" 2>/dev/null || true); do
			kill "$process" 2>/dev/null || true
		done
	fi
	if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
		kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
	if [ -n "$ATTACHED" ]; then
		hdiutil detach "$MOUNT_POINT" -quiet -force 2>/dev/null || true
	fi
	if [ -d "$TARGET_COPY" ]; then
		if [ -d "$TARGET_APP" ]; then
			find "$TARGET_APP" -depth -delete
		fi
		ditto "$TARGET_COPY" "$TARGET_APP"
	fi
	find "$TEST_ROOT" -depth -delete
	rm -f "$PUBLIC_APPCAST"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TEST_ROOT/target" "$TEST_ROOT/source" "$SUPPORT_DIR" "$FEED_DIR" "$MOUNT_POINT"
ditto "$TARGET_APP" "$TARGET_COPY"

printf '[public update] downloading published %s (build %s)\n' \
	"$PUBLIC_VERSION" "$PUBLIC_BUILD"
curl --fail --silent --show-error --location \
	"$PUBLIC_DMG_URL" --output "$DMG_PATH"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet
ATTACHED=1
if [ ! -d "$MOUNT_POINT/hw_calendar.app" ]; then
	echo "[public update] published DMG does not contain hw_calendar.app" >&2
	exit 1
fi
ditto "$MOUNT_POINT/hw_calendar.app" "$SOURCE_APP"
hdiutil detach "$MOUNT_POINT" -quiet -force
ATTACHED=

SOURCE_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
	"$SOURCE_APP/Contents/Info.plist")
SOURCE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
	"$SOURCE_APP/Contents/Info.plist")
if [ "$SOURCE_BUILD" != "$PUBLIC_BUILD" ] ||
   [ "$SOURCE_VERSION" != "$PUBLIC_VERSION" ]; then
	echo "[public update] downloaded app does not match the published appcast" >&2
	exit 1
fi

PYTHON=$(xcrun --find python3 2>/dev/null || command -v python3 || true)
if [ -z "$PYTHON" ]; then
	echo "[public update] Python 3 is required for the loopback feed" >&2
	exit 1
fi
PORT=$(
	"$PYTHON" -c \
		'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
)
FEED_URL="http://127.0.0.1:$PORT/appcast.xml"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $FEED_URL" \
	"$SOURCE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUAllowsInsecureUpdates bool true' \
	"$SOURCE_APP/Contents/Info.plist" 2>/dev/null ||
	/usr/libexec/PlistBuddy -c 'Set :SUAllowsInsecureUpdates true' \
		"$SOURCE_APP/Contents/Info.plist"
"$ROOT/scripts/sign-release-app.sh" "$SOURCE_APP" "$IDENTITY"

TARGET_ARCHIVE="$FEED_DIR/hw_calendar-$VERSION-build-$TARGET_BUILD.zip"
ditto -c -k --sequesterRsrc --keepParent "$TARGET_COPY" "$TARGET_ARCHIVE"
"$INSTALL/Sparkle/generate_appcast" \
	--account hw_calendar \
	--download-url-prefix "http://127.0.0.1:$PORT/" \
	--embed-release-notes \
	"$FEED_DIR"
if [ ! -f "$FEED_DIR/appcast.xml" ] ||
   ! grep -q 'sparkle:edSignature=' "$FEED_DIR/appcast.xml"; then
	echo "[public update] the candidate appcast is not signed" >&2
	exit 1
fi

(
	cd "$FEED_DIR"
	exec "$PYTHON" -m http.server "$PORT" --bind 127.0.0.1
) >"$TEST_ROOT/server.log" 2>&1 &
SERVER_PID=$!
sleep 1
curl --fail --silent "$FEED_URL" >/dev/null

env \
	HW_CALENDAR_ACTIVATE_ON_LAUNCH=1 \
	HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
	"$SOURCE_APP/Contents/MacOS/hw_calendar" \
	>"$TEST_ROOT/source.log" 2>&1 &
SOURCE_PID=$!

attempt=0
while [ "$attempt" -lt 100 ] && [ ! -S "$SUPPORT_DIR/control.sock" ]; do
	if ! kill -0 "$SOURCE_PID" 2>/dev/null; then
		echo "[public update] published app exited before it created the control socket" >&2
		sed -n '1,160p' "$TEST_ROOT/source.log" >&2
		exit 1
	fi
	attempt=$((attempt + 1))
	sleep 0.1
done
if [ ! -S "$SUPPORT_DIR/control.sock" ]; then
	echo "[public update] published app did not create the control socket" >&2
	exit 1
fi

HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
	"$SOURCE_APP/Contents/MacOS/hw_calendar" update check |
	jq -e --arg version "$SOURCE_VERSION ($SOURCE_BUILD)" \
		'.ok and .data.version == $version' >/dev/null

attempt=0
while [ "$attempt" -lt 180 ]; do
	INSTALLED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
		"$SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)
	if [ "$INSTALLED_BUILD" = "$TARGET_BUILD" ]; then
		break
	fi
	if kill -0 "$SOURCE_PID" 2>/dev/null; then
		osascript - "$SOURCE_PID" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
    set targetPid to item 1 of argv as integer
    tell application "System Events"
        if exists (first application process whose unix id is targetPid) then
            tell first application process whose unix id is targetPid
                set frontmost to true
                repeat with currentWindow in windows
                    if exists button "Install Update" of currentWindow then
                        click button "Install Update" of currentWindow
                        return
                    end if
                    if exists button "Install and Relaunch" of currentWindow then
                        click button "Install and Relaunch" of currentWindow
                        return
                    end if
                end repeat
            end tell
        end if
    end tell
end run
APPLESCRIPT
	fi
	attempt=$((attempt + 1))
	sleep 1
done

INSTALLED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
	"$SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)
if [ "$INSTALLED_BUILD" != "$TARGET_BUILD" ]; then
	echo "[public update] Sparkle did not install candidate build $TARGET_BUILD" >&2
	sed -n '1,200p' "$TEST_ROOT/source.log" >&2
	exit 1
fi

codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"
manifest() {
	app=$1
	output=$2
	(
		cd "$app"
		find . -type f -print | LC_ALL=C sort | while IFS= read -r path; do
			shasum -a 256 "$path"
		done
		find . -type l -print | LC_ALL=C sort | while IFS= read -r path; do
			printf 'link %s -> %s\n' "$path" "$(readlink "$path")"
		done
	) >"$output"
}
manifest "$TARGET_COPY" "$TEST_ROOT/target.manifest"
manifest "$SOURCE_APP" "$TEST_ROOT/installed.manifest"
if ! cmp -s "$TEST_ROOT/target.manifest" "$TEST_ROOT/installed.manifest"; then
	echo "[public update] installed build differs from the signed candidate bundle" >&2
	diff -u "$TEST_ROOT/target.manifest" "$TEST_ROOT/installed.manifest" >&2 || true
	exit 1
fi

RECEIPT="$ROOT/release-output/$VERSION/public-update-build-$TARGET_BUILD.receipt"
mkdir -p "$(dirname "$RECEIPT")"
{
	printf 'version=%s\n' "$VERSION"
	printf 'source_version=%s\n' "$SOURCE_VERSION"
	printf 'source_build=%s\n' "$SOURCE_BUILD"
	printf 'target_build=%s\n' "$TARGET_BUILD"
	printf 'public_dmg_url=%s\n' "$PUBLIC_DMG_URL"
	printf 'target_executable_sha256=%s\n' \
		"$(shasum -a 256 "$TARGET_COPY/Contents/MacOS/hw_calendar" | awk '{print $1}')"
	printf 'validated_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} >"$RECEIPT"
printf '[public update] Sparkle installed candidate build %s from published %s (%s)\n' \
	"$TARGET_BUILD" "$PUBLIC_VERSION" "$PUBLIC_BUILD"
printf '[public update] receipt: %s\n' "$RECEIPT"
