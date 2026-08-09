#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/resources/app-icon.svg"
DESTINATION=${1:-"$ROOT/resources/AppIcon.icns"}
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/hw-calendar-icon.XXXXXX")
trap 'find "$TEMP" -depth -delete' EXIT HUP INT TERM

ICONSET="$TEMP/AppIcon.iconset"
mkdir -p "$ICONSET" "$(dirname -- "$DESTINATION")"
qlmanage -t -s 1024 -o "$TEMP" "$SOURCE" >/dev/null
SOURCE_PNG="$TEMP/$(basename "$SOURCE").png"
test -f "$SOURCE_PNG"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE_PNG" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SOURCE_PNG" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$DESTINATION"
printf '[app icon] built %s\n' "$DESTINATION"
