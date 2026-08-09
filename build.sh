#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INFO_PLIST_SOURCE=${HW_CALENDAR_INFO_PLIST:-"$ROOT/Info.plist"}
ICON_ROOT="$ROOT/resources/icons/iconoir"
HOLIDAY_ROOT="$ROOT/resources/holidays"

"$ROOT/scripts/dependencies.sh" check
ODIN=$("$ROOT/scripts/dependencies.sh" path odin)
LLVM_BIN=$("$ROOT/scripts/dependencies.sh" path llvm-bin)
PATH="$LLVM_BIN:$PATH"
export PATH
MATCH_SORTER_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_matchSorter)
LOCAL_COMMAND_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ipc_localCommand)
UI_FLASH_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_flash)
COMMAND_PALETTE_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_commandPalette)
COMPONENTS_ROOT=$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_components)
UI_FRAMEWORK_ROOT=${HW_CALENDAR_UI_FRAMEWORK_ROOT:-$("$ROOT/scripts/dependencies.sh" path repo hw_odin_ui_framework)}

MODE=${1:-debug}
UPDATER_DEFINE=""
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
    UPDATER_DEFINE="-define:HW_CALENDAR_UPDATER=true"
    set -- -o:speed "$UPDATER_DEFINE"
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
UPDATER_LINK=""
if [ "$MODE" = "release" ]; then
  RELEASE_INSTALL=${HW_CALENDAR_RELEASE_CACHE:-"$ROOT/build/release-dependencies"}/install
  SPARKLE_ROOT="$RELEASE_INSTALL/Sparkle"
  if [ ! -d "$SPARKLE_ROOT/Sparkle.framework" ]; then
    echo "[hw_calendar] release dependencies are not prepared" >&2
    echo "[hw_calendar] run: ./scripts/prepare-release-dependencies.sh" >&2
    exit 1
  fi
  if /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST_SOURCE" |
     grep -q '^REPLACE_WITH_'; then
    echo "[hw_calendar] replace SUPublicEDKey before a release build" >&2
    exit 1
  fi
  UPDATER_OBJECT="$TEMP/updater.o"
  xcrun clang \
    -fobjc-arc \
    -fblocks \
    -mmacosx-version-min=14.0 \
    -Wall -Wextra -Werror -Wpedantic \
    -F"$SPARKLE_ROOT" \
    -c "$ROOT/src/updater.m" \
    -o "$UPDATER_OBJECT"
  UPDATER_LINK=" $UPDATER_OBJECT -F$SPARKLE_ROOT -framework Sparkle -Wl,-rpath,@executable_path/../Frameworks"
fi
cd "$TEMP"
"$ODIN" build "$ROOT/src" -out:"$EXECUTABLE" "$@" \
  -collection:match_sorter="$MATCH_SORTER_ROOT" \
  -collection:local_command="$LOCAL_COMMAND_ROOT" \
  -collection:flash="$UI_FLASH_ROOT" \
  -collection:command_palette="$COMMAND_PALETTE_ROOT" \
  -collection:components="$COMPONENTS_ROOT" \
  -collection:ui_framework="$UI_FRAMEWORK_ROOT" \
  -extra-linker-flags:"$UPDATER_LINK -framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework UserNotifications"
cp "$INFO_PLIST_SOURCE" "$APP/Contents/Info.plist"
cp "$ROOT/resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ICON_ROOT/calendar.svg" "$APP/Contents/Resources/Icons/Iconoir/calendar.svg"
cp "$ICON_ROOT/xmark.svg" "$APP/Contents/Resources/Icons/Iconoir/xmark.svg"
cp "$ICON_ROOT/minus.svg" "$APP/Contents/Resources/Icons/Iconoir/minus.svg"
cp "$ICON_ROOT/maximize.svg" "$APP/Contents/Resources/Icons/Iconoir/maximize.svg"
cp "$ICON_ROOT/settings.svg" "$APP/Contents/Resources/Icons/Iconoir/settings.svg"
cp "$ICON_ROOT/LICENSE" "$APP/Contents/Resources/Icons/Iconoir/LICENSE"
cp "$HOLIDAY_ROOT/sk.json" "$APP/Contents/Resources/Holidays/sk.json"
if [ "$MODE" = "release" ]; then
  mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources/Licenses/Sparkle"
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
  ditto "$SPARKLE_ROOT/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  cp "$SPARKLE_ROOT/LICENSE" "$APP/Contents/Resources/Licenses/Sparkle/LICENSE"
  cp "$RELEASE_INSTALL/release-dependencies.lock" \
    "$APP/Contents/Resources/Licenses/release-dependencies.lock"
fi
CLI_STAGING="$ROOT/build/.hw_calendar-$MODE.tmp"
cp "$EXECUTABLE" "$CLI_STAGING"
mv -f "$CLI_STAGING" "$CLI"
if [ "$MODE" != "release" ]; then
  codesign --force --deep --sign - "$APP"
fi

if [ "$MODE" != "release" ]; then
  xcrun dsymutil "$EXECUTABLE" -o "$APP.dSYM"
fi

printf '[hw_calendar] built %s: %s\n' "$MODE" "${APP#"$ROOT/"}"
