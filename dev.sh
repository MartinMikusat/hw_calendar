#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

MODE=${1:-debug}
case "$MODE" in
  debug) APP="$ROOT/build/HWCalendar.app" ;;
  asan|release) APP="$ROOT/build/$MODE/HWCalendar.app" ;;
  *)
    echo "usage: ./dev.sh [debug|asan|release]" >&2
    exit 2
    ;;
esac

EXECUTABLE="$APP/Contents/MacOS/HWCalendar"
MODULE="$ROOT/build/hot-reload/$MODE/calendar.dylib"
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

legacy_fingerprint() {
  stat -f '%m:%z:%N' \
    src/*.odin ./*.sh scripts/*.sh Info.plist dependencies.lock \
    resources/fonts/* resources/icons/iconoir/* resources/holidays/* \
    resources/themes/*/* \
    2>/dev/null | shasum | cut -d' ' -f1
}

module_fingerprint() {
  stat -f '%m:%z:%N' src/*.odin dependencies.lock 2>/dev/null |
    shasum | cut -d' ' -f1
}

host_fingerprint() {
  find dev -type f -name '*.odin' -exec stat -f '%m:%z:%N' {} + 2>/dev/null
  stat -f '%m:%z:%N' \
    Info.plist scripts/hot-reload-build.sh \
    resources/fonts/* resources/icons/iconoir/* resources/holidays/* \
    resources/themes/*/* \
    2>/dev/null
}

hot_reload_fingerprint() {
  host_fingerprint | shasum | cut -d' ' -f1
}

stop_app() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
}

cleanup() {
  status=$?
  trap - INT TERM EXIT
  stop_app
  rm -f "$LOCK_PID"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  exit "$status"
}

check_app() {
  if [ -z "$APP_PID" ] || kill -0 "$APP_PID" 2>/dev/null; then
    return
  fi

  if wait "$APP_PID"; then
    status=0
  else
    status=$?
  fi
  exited_pid=$APP_PID
  APP_PID=""
  printf '[hw_calendar] app pid %s exited with status %s\n' "$exited_pid" "$status"
  if [ "$MODE" != "release" ] && [ "$status" -eq 75 ]; then
    launch_app
  fi
}

launch_app() {
  if [ "$MODE" = "release" ]; then
    env \
      HW_CALENDAR_ACTIVATE_ON_LAUNCH=0 \
      MTL_DEBUG_LAYER=1 \
      "$EXECUTABLE" &
  else
    env \
      HW_CALENDAR_ACTIVATE_ON_LAUNCH=0 \
      HW_HOT_RELOAD_MODULE="$MODULE" \
      MTL_DEBUG_LAYER=1 \
      "$EXECUTABLE" &
  fi
  APP_PID=$!
  printf '[hw_calendar] launched pid %s (%s)\n' "$APP_PID" "$MODE"
}

legacy_rebuild_and_launch() {
  printf '\n[hw_calendar] rebuilding %s...\n' "$MODE"
  if ! "$ROOT/build.sh" "$MODE"; then
    printf '[hw_calendar] build failed; keeping the current app running\n'
    return 1
  fi

  stop_app
  launch_app
}

hot_rebuild_and_launch() {
  printf '\n[hw_calendar] rebuilding hot-reload %s host and module...\n' "$MODE"
  if ! "$ROOT/scripts/hot-reload-build.sh" "$MODE" all; then
    printf '[hw_calendar] build failed; keeping the current app running\n'
    return 1
  fi

  stop_app
  launch_app
}

hot_rebuild_module() {
  printf '\n[hw_calendar] rebuilding hot-reload %s module...\n' "$MODE"
  if ! "$ROOT/scripts/hot-reload-build.sh" "$MODE" module; then
    printf '[hw_calendar] module build failed; the current module remains active\n'
  fi
}

acquire_lock
trap cleanup INT TERM EXIT

if [ "$MODE" = "release" ]; then
  legacy_rebuild_and_launch || exit 1
  LAST_FINGERPRINT=$(legacy_fingerprint)
else
  hot_rebuild_and_launch || exit 1
  LAST_MODULE_FINGERPRINT=$(module_fingerprint)
  LAST_HOST_FINGERPRINT=$(hot_reload_fingerprint)
fi

while :; do
  sleep 0.5
  check_app
  if [ "$MODE" = "release" ]; then
    CURRENT_FINGERPRINT=$(legacy_fingerprint)
    if [ "$CURRENT_FINGERPRINT" != "$LAST_FINGERPRINT" ]; then
      LAST_FINGERPRINT=$CURRENT_FINGERPRINT
      legacy_rebuild_and_launch
    fi
    continue
  fi

  CURRENT_HOST_FINGERPRINT=$(hot_reload_fingerprint)
  CURRENT_MODULE_FINGERPRINT=$(module_fingerprint)
  if [ "$CURRENT_HOST_FINGERPRINT" != "$LAST_HOST_FINGERPRINT" ]; then
    LAST_HOST_FINGERPRINT=$CURRENT_HOST_FINGERPRINT
    LAST_MODULE_FINGERPRINT=$CURRENT_MODULE_FINGERPRINT
    hot_rebuild_and_launch
  elif [ "$CURRENT_MODULE_FINGERPRINT" != "$LAST_MODULE_FINGERPRINT" ]; then
    LAST_MODULE_FINGERPRINT=$CURRENT_MODULE_FINGERPRINT
    hot_rebuild_module
  fi
done
