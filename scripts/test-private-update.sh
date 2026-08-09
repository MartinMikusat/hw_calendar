#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TARGET_APP=${1:-}
IDENTITY=${2:-}
INSTALL=${HW_CALENDAR_RELEASE_CACHE:-"$ROOT/build/release-dependencies"}/install
PLIST="$ROOT/Info.plist"

if [ ! -d "$TARGET_APP" ] || [ -z "$IDENTITY" ]; then
	echo "usage: ./scripts/test-private-update.sh /path/to/build-2.app 'Developer ID Application: ...'" >&2
	exit 2
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
	"$TARGET_APP/Contents/Info.plist")
TARGET_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
	"$TARGET_APP/Contents/Info.plist")
if [ "$TARGET_BUILD" -ne 2 ]; then
	echo "[private update] the 0.1.0 validation requires target build 2" >&2
	exit 1
fi

TEST_ROOT=$(mktemp -d /tmp/hwcu.XXXXXX)
TARGET_COPY="$TEST_ROOT/target/hw_calendar.app"
SOURCE_APP="$TEST_ROOT/source/hw_calendar.app"
SUPPORT_DIR="$TEST_ROOT/support"
FEED_DIR="$TEST_ROOT/feed"
SOURCE_PLIST="$TEST_ROOT/Info-build-1.plist"
SERVER_PID=
SOURCE_PID=

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
	if [ -d "$TARGET_COPY" ]; then
		if [ -d "$TARGET_APP" ]; then
			find "$TARGET_APP" -depth -delete
		fi
		ditto "$TARGET_COPY" "$TARGET_APP"
	fi
	find "$TEST_ROOT" -depth -delete
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TEST_ROOT/target" "$TEST_ROOT/source" "$SUPPORT_DIR" "$FEED_DIR"
ditto "$TARGET_APP" "$TARGET_COPY"
cp "$PLIST" "$SOURCE_PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$SOURCE_PLIST"

PYTHON=$(xcrun --find python3 2>/dev/null || command -v python3 || true)
if [ -z "$PYTHON" ]; then
	echo "[private update] Python 3 is required for the loopback feed" >&2
	exit 1
fi
PORT=$(
	"$PYTHON" -c \
		'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
)
FEED_URL="http://127.0.0.1:$PORT/appcast.xml"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $FEED_URL" "$SOURCE_PLIST"
/usr/libexec/PlistBuddy -c 'Add :SUAllowsInsecureUpdates bool true' "$SOURCE_PLIST"

HW_CALENDAR_INFO_PLIST="$SOURCE_PLIST" "$ROOT/build.sh" release
ditto "$ROOT/build/release/hw_calendar.app" "$SOURCE_APP"
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
	echo "[private update] the private appcast is not signed" >&2
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
		echo "[private update] build 1 exited before it created the control socket" >&2
		sed -n '1,160p' "$TEST_ROOT/source.log" >&2
		exit 1
	fi
	attempt=$((attempt + 1))
	sleep 0.1
done
if [ ! -S "$SUPPORT_DIR/control.sock" ]; then
	echo "[private update] build 1 did not create the control socket" >&2
	exit 1
fi

HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
	"$SOURCE_APP/Contents/MacOS/hw_calendar" update check |
	jq -e '.ok and .data.version == "0.1.0 (1)"' >/dev/null

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
	echo "[private update] Sparkle did not install target build $TARGET_BUILD" >&2
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
	echo "[private update] installed build differs from the signed target bundle" >&2
	diff -u "$TEST_ROOT/target.manifest" "$TEST_ROOT/installed.manifest" >&2 || true
	exit 1
fi

RECEIPT="$ROOT/release-output/$VERSION/private-update-build-$TARGET_BUILD.receipt"
mkdir -p "$(dirname "$RECEIPT")"
{
	printf 'version=%s\n' "$VERSION"
	printf 'source_build=1\n'
	printf 'target_build=%s\n' "$TARGET_BUILD"
	printf 'target_executable_sha256=%s\n' \
		"$(shasum -a 256 "$TARGET_COPY/Contents/MacOS/hw_calendar" | awk '{print $1}')"
	printf 'validated_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} >"$RECEIPT"
printf '[private update] Sparkle installed exact build 2 from build 1\n'
printf '[private update] receipt: %s\n' "$RECEIPT"
