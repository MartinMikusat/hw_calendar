#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ICON_ROOT="$ROOT/resources/icons/iconoir"
HOLIDAY_ROOT="$ROOT/resources/holidays"

"$ROOT/scripts/dependencies.sh" check
ODIN=$("$ROOT/scripts/dependencies.sh" path odin)
LLVM_BIN=$("$ROOT/scripts/dependencies.sh" path llvm-bin)
PATH="$LLVM_BIN:$PATH"
export PATH
MATCH_SORTER_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_matchSorter)
UI_FLASH_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_flash)
COMMAND_PALETTE_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_commandPalette)
COMPONENTS_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_components)
UI_FRAMEWORK_ROOT=${HW_CALENDAR_UI_FRAMEWORK_ROOT:-$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_framework)}

MODE=${1:-debug}
case "$MODE" in
  debug)
    APP="$ROOT/build/hw_calendar.app"
    CLI="$ROOT/build/hw_calendar"
    set -- -debug -o:none -keep-temp-files
    ;;
  asan)
    APP="$ROOT/build/asan/hw_calendar.app"
    CLI="$ROOT/build/hw_calendar-asan"
    set -- -debug -o:none -keep-temp-files -sanitize:address
    ;;
  release)
    APP="$ROOT/build/release/hw_calendar.app"
    CLI="$ROOT/build/hw_calendar"
    set -- -o:speed
    ;;
  *)
    echo "usage: ./build.sh [debug|asan|release]" >&2
    exit 2
    ;;
esac

rm -rf "$APP/Contents/Resources/Themes" "$APP/Contents/Resources/Fonts"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources/Icons/Iconoir" \
  "$APP/Contents/Resources/Holidays"
if xcrun metal -help >/dev/null 2>&1; then
  "$UI_FRAMEWORK_ROOT/scripts/build-metallib.sh" "$APP/Contents/Resources/ui.metallib"
elif [ "$MODE" = "release" ]; then
  echo "[hw_calendar] release builds require the optional Metal shader toolchain" >&2
  echo "[hw_calendar] install it with: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
else
  rm -f "$APP/Contents/Resources/ui.metallib"
fi
EXECUTABLE="$APP/Contents/MacOS/hw_calendar"
TEMP="$ROOT/build/temp/$MODE"
mkdir -p "$TEMP"
cd "$TEMP"
"$ODIN" build "$ROOT/src" -out:"$EXECUTABLE" "$@" \
  -collection:match_sorter="$MATCH_SORTER_ROOT" \
  -collection:flash="$UI_FLASH_ROOT" \
  -collection:command_palette="$COMMAND_PALETTE_ROOT" \
  -collection:components="$COMPONENTS_ROOT" \
  -collection:ui_framework="$UI_FRAMEWORK_ROOT" \
  -extra-linker-flags:"-framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework UserNotifications"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON_ROOT/xmark.svg" "$APP/Contents/Resources/Icons/Iconoir/xmark.svg"
cp "$ICON_ROOT/minus.svg" "$APP/Contents/Resources/Icons/Iconoir/minus.svg"
cp "$ICON_ROOT/maximize.svg" "$APP/Contents/Resources/Icons/Iconoir/maximize.svg"
cp "$ICON_ROOT/settings.svg" "$APP/Contents/Resources/Icons/Iconoir/settings.svg"
cp "$ICON_ROOT/LICENSE" "$APP/Contents/Resources/Icons/Iconoir/LICENSE"
cp "$HOLIDAY_ROOT/sk.json" "$APP/Contents/Resources/Holidays/sk.json"
cp "$EXECUTABLE" "$CLI"
codesign --force --deep --sign - "$APP"

if [ "$MODE" != "release" ]; then
  xcrun dsymutil "$EXECUTABLE" -o "$APP.dSYM"
fi

printf '[hw_calendar] built %s: %s\n' "$MODE" "${APP#"$ROOT/"}"
