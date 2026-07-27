#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MATCH_SORTER_ROOT="$ROOT/../hw_odin_matchSorter"
UI_FLASH_ROOT="$ROOT/../hw_odin_ui_flash"
COMMAND_PALETTE_ROOT="$ROOT/../hw_odin_ui_commandPalette"
FONT_ROOT="$ROOT/resources/fonts"

"$ROOT/scripts/dependencies.sh" check

MODE=${1:-debug}
case "$MODE" in
  debug)
    APP="$ROOT/build/HWCalendar.app"
    CLI="$ROOT/build/hw-calendar"
    set -- -debug -o:none -keep-temp-files
    ;;
  asan)
    APP="$ROOT/build/asan/HWCalendar.app"
    CLI="$ROOT/build/hw-calendar-asan"
    set -- -debug -o:none -keep-temp-files -sanitize:address
    ;;
  release)
    APP="$ROOT/build/release/HWCalendar.app"
    CLI="$ROOT/build/hw-calendar"
    set -- -o:speed
    ;;
  *)
    echo "usage: ./build.sh [debug|asan|release]" >&2
    exit 2
    ;;
esac

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
EXECUTABLE="$APP/Contents/MacOS/HWCalendar"
TEMP="$ROOT/build/temp/$MODE"
mkdir -p "$TEMP"
cd "$TEMP"
odin build "$ROOT/src" -out:"$EXECUTABLE" "$@" \
  -collection:match_sorter="$MATCH_SORTER_ROOT" \
  -collection:flash="$UI_FLASH_ROOT" \
  -collection:command_palette="$COMMAND_PALETTE_ROOT" \
  -extra-linker-flags:"-framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework UserNotifications"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$FONT_ROOT/Iosevka-Regular.ttf" "$APP/Contents/Resources/Fonts/Iosevka-Regular.ttf"
cp "$FONT_ROOT/IOSEVKA-LICENSE.md" "$APP/Contents/Resources/Fonts/IOSEVKA-LICENSE.md"
cp "$EXECUTABLE" "$CLI"
codesign --force --deep --sign - "$APP"

if [ "$MODE" != "release" ]; then
  xcrun dsymutil "$EXECUTABLE" -o "$APP.dSYM"
fi

printf '[hw_calendar] built %s: %s\n' "$MODE" "${APP#"$ROOT/"}"
