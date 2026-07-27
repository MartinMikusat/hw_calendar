#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/build/test-deps/libical"
BUILD="$ROOT/build/test-deps/libical-build"
ORACLE="$BUILD/hw-calendar-recurrence-oracle"
COMMIT=0a1a1d81304ae63ffe24e43b8d1fb1e9b03c635c

if [ ! -d "$SOURCE/.git" ]; then
  mkdir -p "$ROOT/build/test-deps"
  git clone https://github.com/libical/libical.git "$SOURCE"
fi

if [ "$(git -C "$SOURCE" rev-parse HEAD)" != "$COMMIT" ]; then
  git -C "$SOURCE" checkout --detach "$COMMIT"
fi

cmake -S "$SOURCE" -B "$BUILD" \
  -U SHARED_ONLY -U STATIC_ONLY \
  -DLIBICAL_BUILD_TESTING=OFF \
  -DLIBICAL_JAVA_BINDINGS=OFF \
  -DLIBICAL_GOBJECT_INTROSPECTION=OFF \
  -DLIBICAL_GLIB=OFF \
  -DLIBICAL_GLIB_BUILD_DOCS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel 8

cc "$ROOT/testdata/libical-recurrence-oracle.c" \
  -I"$BUILD/src" \
  -I"$SOURCE/src/libical" \
  -L"$BUILD/lib" \
  -Wl,-rpath,"$BUILD/lib" \
  -lical \
  -o "$ORACLE"

"$ROOT/build.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

check_case() {
  NAME=$1
  RULE=$2
  DTSTART=$3
  FROM=$4
  TO=$5
  "$ORACLE" "$RULE" "$DTSTART" "$FROM" "$TO" > "$TMP/$NAME.libical"
  "$ROOT/build/hw-calendar" recurrence expand \
    --rule "$RULE" \
    --start "$DTSTART" \
    --from "$FROM" \
    --to "$TO" |
    jq -r '.data.occurrences[]' > "$TMP/$NAME.hw"
  diff -u "$TMP/$NAME.libical" "$TMP/$NAME.hw"
}

check_case daily "FREQ=DAILY;INTERVAL=2;COUNT=5" \
  20260727T090000 20260701T000000 20260901T000000
check_case monthly "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=6" \
  20260731T090000 20260701T000000 20270201T000000
check_case yearly "FREQ=YEARLY;BYMONTH=1,2;BYDAY=MO;BYSETPOS=1;COUNT=5" \
  20260105T090000 20260101T000000 20310101T000000
check_case week "FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO;COUNT=4;WKST=MO" \
  20270104T090000 20270101T000000 20320101T000000

printf '[hw_calendar] libical recurrence oracle passed\n'
