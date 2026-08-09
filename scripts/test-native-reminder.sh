#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP=${1:-}
if [ ! -d "$APP" ]; then
	echo "usage: ./scripts/test-native-reminder.sh /path/to/release.app" >&2
	exit 2
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
	"$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
	"$APP/Contents/Info.plist")
TEST_ROOT=$(mktemp -d /tmp/hwcr.XXXXXX)
SUPPORT_DIR="$TEST_ROOT/support"
APP_PID=

cleanup() {
	if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
		kill "$APP_PID" 2>/dev/null || true
		wait "$APP_PID" 2>/dev/null || true
	fi
	find "$TEST_ROOT" -depth -delete
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$SUPPORT_DIR"
env \
	HW_CALENDAR_ACTIVATE_ON_LAUNCH=1 \
	HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
	"$APP/Contents/MacOS/hw_calendar" \
	>"$TEST_ROOT/app.log" 2>&1 &
APP_PID=$!

attempt=0
while [ "$attempt" -lt 100 ] && [ ! -S "$SUPPORT_DIR/control.sock" ]; do
	if ! kill -0 "$APP_PID" 2>/dev/null; then
		echo "[native reminder] the application exited before it created the control socket" >&2
		sed -n '1,160p' "$TEST_ROOT/app.log" >&2
		exit 1
	fi
	attempt=$((attempt + 1))
	sleep 0.1
done
if [ ! -S "$SUPPORT_DIR/control.sock" ]; then
	echo "[native reminder] the application did not create the control socket" >&2
	exit 1
fi

attempt=0
AUTHORIZATION="not_determined"
while [ "$attempt" -lt 60 ]; do
	AUTHORIZATION=$(HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
		"$APP/Contents/MacOS/hw_calendar" reminder status |
		jq -r '.data.authorization // "unknown"')
	case "$AUTHORIZATION" in
		authorized|provisional|ephemeral) break ;;
		denied)
			echo "[native reminder] macOS notification permission is denied" >&2
			exit 1
			;;
	esac
	attempt=$((attempt + 1))
	sleep 1
done
case "$AUTHORIZATION" in
	authorized|provisional|ephemeral) ;;
	*)
		echo "[native reminder] notification permission was not granted" >&2
		exit 1
		;;
esac

NOW=$(date +%s)
FIRE_AT=$((NOW + 20))
ENTRY_JSON=$(jq -nc \
	--arg due "$FIRE_AT" \
	--arg reminder "$FIRE_AT" \
	'{schema_version:1, original_text:"Release reminder validation", due_at:$due, reminder_at:$reminder}')
printf '%s\n' "$ENTRY_JSON" |
	HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
	"$APP/Contents/MacOS/hw_calendar" entry create |
	jq -e '.ok and .data.entry.original_text == "Release reminder validation"' >/dev/null

sleep 3
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=
if pgrep -f "$APP/Contents/MacOS/hw_calendar" >/dev/null 2>&1; then
	echo "[native reminder] the validation application is still running" >&2
	exit 1
fi

WAIT_SECONDS=$((FIRE_AT - $(date +%s) + 8))
if [ "$WAIT_SECONDS" -gt 0 ]; then
	sleep "$WAIT_SECONDS"
fi

RESULT=$(osascript <<'APPLESCRIPT'
set answer to display dialog "Did the native ‘Release reminder validation’ notification appear while hw_calendar was closed?" buttons {"Not observed", "Observed"} default button "Observed" cancel button "Not observed" with title "hw_calendar release validation"
return button returned of answer
APPLESCRIPT
) || RESULT="Not observed"
if [ "$RESULT" != "Observed" ]; then
	echo "[native reminder] delivery was not confirmed" >&2
	exit 1
fi

RECEIPT="$ROOT/release-output/$VERSION/native-reminder-build-$BUILD.receipt"
mkdir -p "$(dirname "$RECEIPT")"
{
	printf 'version=%s\n' "$VERSION"
	printf 'build=%s\n' "$BUILD"
	printf 'executable_sha256=%s\n' \
		"$(shasum -a 256 "$APP/Contents/MacOS/hw_calendar" | awk '{print $1}')"
	printf 'confirmed_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} >"$RECEIPT"
printf '[native reminder] closed-application delivery confirmed\n'
printf '[native reminder] receipt: %s\n' "$RECEIPT"
