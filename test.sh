#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
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

"$ODIN" test "$ROOT/src" \
	-define:ODIN_TEST_THREADS=1 \
  -collection:match_sorter="$MATCH_SORTER_ROOT" \
  -collection:local_command="$LOCAL_COMMAND_ROOT" \
  -collection:flash="$UI_FLASH_ROOT" \
  -collection:command_palette="$COMMAND_PALETTE_ROOT" \
  -collection:components="$COMPONENTS_ROOT" \
  -collection:ui_framework="$UI_FRAMEWORK_ROOT" \
  -extra-linker-flags:"-framework AppKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreText -framework CoreGraphics -framework UserNotifications"

"$ROOT/build.sh"
"$ROOT/scripts/cli-integration-test.sh"
