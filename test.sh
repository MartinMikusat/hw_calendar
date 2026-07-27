#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$ROOT/scripts/dependencies.sh" check

odin test "$ROOT/src" \
  -collection:match_sorter="$ROOT/../hw_odin_matchSorter" \
  -collection:flash="$ROOT/../hw_odin_ui_flash" \
  -collection:command_palette="$ROOT/../hw_odin_ui_commandPalette" \
  -extra-linker-flags:"-framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework UserNotifications"

"$ROOT/build.sh"
"$ROOT/scripts/cli-integration-test.sh"
