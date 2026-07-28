#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

check_one() {
  NAME=$1
  EXPECTED_ORIGIN=$2
  EXPECTED_COMMIT=$3
  REPOSITORY="$ROOT/../$NAME"

  if [ ! -d "$REPOSITORY/.git" ]; then
    echo "[hw_calendar] missing sibling repository: $REPOSITORY" >&2
    exit 1
  fi
  ACTUAL_ORIGIN=$(git -C "$REPOSITORY" remote get-url origin)
  ACTUAL_COMMIT=$(git -C "$REPOSITORY" rev-parse HEAD)
  if [ "$ACTUAL_ORIGIN" != "$EXPECTED_ORIGIN" ]; then
    echo "[hw_calendar] $NAME origin mismatch" >&2
    exit 1
  fi
  if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
    echo "[hw_calendar] $NAME commit mismatch: expected $EXPECTED_COMMIT, found $ACTUAL_COMMIT" >&2
    exit 1
  fi
  if [ -n "$(git -C "$REPOSITORY" status --porcelain)" ]; then
    echo "[hw_calendar] $NAME has uncommitted changes" >&2
    exit 1
  fi
}

check_one hw_odin_matchSorter https://github.com/MartinMikusat/hw_odin_matchSorter.git 52bbe319503752881ebd777e0f3340fce027e017
check_one hw_odin_ui_flash https://github.com/MartinMikusat/hw_odin_ui_flash.git d06e98a40640b13eea5b979319022aad0a470d72
check_one hw_odin_ui_commandPalette https://github.com/MartinMikusat/hw_odin_ui_commandPalette.git 72312d2f67cfc3d2ebc6a62fdbb1ba5bbc4e335f

if [ ! -f "$ROOT/resources/fonts/Iosevka-Regular.ttf" ]; then
  echo "[hw_calendar] missing bundled Iosevka font" >&2
  exit 1
fi

if [ ! -f "$ROOT/resources/holidays/sk.json" ]; then
  echo "[hw_calendar] missing bundled Slovak holiday data" >&2
  exit 1
fi
