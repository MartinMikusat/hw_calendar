#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ODIN=$("$ROOT/scripts/dependencies.sh" path odin)
LLVM_BIN=$("$ROOT/scripts/dependencies.sh" path llvm-bin)
MATCH_SORTER_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_matchSorter)
UI_FLASH_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_flash)
COMMAND_PALETTE_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_commandPalette)
COMPONENTS_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_components)
UI_FRAMEWORK_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_framework)
PATH="$(dirname "$ODIN"):$LLVM_BIN:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

APP_PID=
AUTOMATION_ROOT=

cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [ -n "$AUTOMATION_ROOT" ] && [ -d "$AUTOMATION_ROOT" ]; then
    find "$AUTOMATION_ROOT" -depth -delete
  fi
}
trap cleanup EXIT HUP INT TERM

stage() {
  printf '\n[dependency-validation] %s\n' "$1"
}

stage "validate the synchronized lock"
"$ROOT/scripts/dependencies.sh" check
"$ROOT/scripts/dependencies.sh" doctor

stage "test hw_odin_matchSorter"
(cd "$MATCH_SORTER_ROOT" && "$ODIN" test .)

stage "test hw_odin_ui_flash"
(cd "$UI_FLASH_ROOT" && "$ODIN" test .)

stage "test hw_odin_ui_commandPalette"
"$COMMAND_PALETTE_ROOT/test.sh"

stage "test hw_odin_ui_components"
"$COMPONENTS_ROOT/test.sh"

stage "test hw_odin_ui_framework"
"$UI_FRAMEWORK_ROOT/test.sh"

stage "test the calendar and its CLI"
"$ROOT/test.sh"

stage "build the AddressSanitizer application"
"$ROOT/build.sh" asan

stage "launch the isolated AddressSanitizer application"
AUTOMATION_ROOT=$(mktemp -d /tmp/hwc-deps.XXXXXX)
SUPPORT_DIR="$AUTOMATION_ROOT/support"
ASAN_LOG="$AUTOMATION_ROOT/asan.log"
mkdir -p "$SUPPORT_DIR"
env \
  HW_CALENDAR_AUTOMATION=1 \
  HW_CALENDAR_ACTIVATE_ON_LAUNCH=0 \
  HW_CALENDAR_VISIBLE_ON_LAUNCH=0 \
  HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
  "$ROOT/build/asan/hw_calendar.app/Contents/MacOS/hw_calendar" \
  >"$ASAN_LOG" 2>&1 &
APP_PID=$!

attempt=0
while [ "$attempt" -lt 100 ] && [ ! -S "$SUPPORT_DIR/control.sock" ]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    printf '[dependency-validation] ASan application exited before creating its socket\n' >&2
    sed -n '1,160p' "$ASAN_LOG" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
[ -S "$SUPPORT_DIR/control.sock" ] || {
  printf '[dependency-validation] ASan application did not create its socket\n' >&2
  sed -n '1,160p' "$ASAN_LOG" >&2
  exit 1
}

HW_CALENDAR_SUPPORT_DIR="$SUPPORT_DIR" \
  "$ROOT/build/hw_calendar-asan" ui snapshot |
  jq -e '.ok == true' >/dev/null

kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=
if grep -E 'ERROR: AddressSanitizer|LeakSanitizer|runtime error:' "$ASAN_LOG" >/dev/null 2>&1; then
  sed -n '1,160p' "$ASAN_LOG" >&2
  exit 1
fi

stage "build the release application"
"$ROOT/build.sh" release

stage "dependency candidate passed"
