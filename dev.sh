#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

MODE=${1:-debug}
case "$MODE" in
  debug) APP="$ROOT/build/HWCalendar.app" ;;
  asan) APP="$ROOT/build/asan/HWCalendar.app" ;;
  release)
    "$ROOT/build.sh" release
    exec "$ROOT/build/release/HWCalendar.app/Contents/MacOS/HWCalendar"
    ;;
  *)
    echo "usage: ./dev.sh [debug|asan|release]" >&2
    exit 2
    ;;
esac

EXECUTABLE="$APP/Contents/MacOS/HWCalendar"
LOCK_DIR="$ROOT/build/dev-watcher.lock"
LOCK_PID="$LOCK_DIR/pid"
APP_PID=""

acquire_lock() {
  mkdir -p "$ROOT/build"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_PID"
    return
  fi
  existing_pid=$(sed -n '1p' "$LOCK_PID" 2>/dev/null || true)
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    printf '[hw_calendar] dev watcher already running as pid %s\n' "$existing_pid"
    exit 0
  fi
  rm -f "$LOCK_PID"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "[hw_calendar] could not acquire the dev watcher lock" >&2
    exit 1
  fi
  printf '%s\n' "$$" > "$LOCK_PID"
}

fingerprint() {
  stat -f '%m:%z:%N' \
    "$ROOT"/src/*.odin \
    "$ROOT"/*.sh \
    "$ROOT"/scripts/*.sh \
    "$ROOT"/Info.plist \
    "$ROOT"/dependencies.lock \
    "$ROOT"/resources/icons/iconoir/* \
    "$ROOT"/resources/holidays/* \
    2>/dev/null | shasum | cut -d' ' -f1
}

stop_app() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
}

cleanup() {
  exit_status=$?
  trap - INT TERM EXIT
  stop_app
  rm -f "$LOCK_PID"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  exit "$exit_status"
}

check_app() {
  if [ -z "$APP_PID" ] || kill -0 "$APP_PID" 2>/dev/null; then
    return
  fi
  if wait "$APP_PID"; then
    exit_status=0
  else
    exit_status=$?
  fi
  exited_pid=$APP_PID
  APP_PID=""
  printf '[hw_calendar] app pid %s exited with status %s\n' \
    "$exited_pid" "$exit_status"
}

launch_app() {
  env \
    HW_CALENDAR_ACTIVATE_ON_LAUNCH=0 \
    MTL_DEBUG_LAYER=1 \
    "$EXECUTABLE" &
  APP_PID=$!
  printf '[hw_calendar] launched pid %s (%s)\n' "$APP_PID" "$MODE"
}

rebuild_and_launch() {
  printf '\n[hw_calendar] rebuilding %s...\n' "$MODE"
  if ! "$ROOT/build.sh" "$MODE"; then
    printf '[hw_calendar] build failed; keeping the current app running\n'
    return 1
  fi
  stop_app
  launch_app
}

acquire_lock
trap cleanup INT TERM EXIT
rebuild_and_launch || exit 1
LAST_FINGERPRINT=$(fingerprint)

while :; do
  sleep 0.5
  check_app
  CURRENT_FINGERPRINT=$(fingerprint)
  if [ "$CURRENT_FINGERPRINT" != "$LAST_FINGERPRINT" ]; then
    LAST_FINGERPRINT=$CURRENT_FINGERPRINT
    rebuild_and_launch
  fi
done
