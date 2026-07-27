#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HW_CALENDAR_SUPPORT_DIR="$TMP/support"
CLI="$ROOT/build/hw-calendar"

"$CLI" ical import < "$ROOT/testdata/calendar.ics" |
  jq -e '.ok and .data.document_id == 1' >/dev/null

"$CLI" event list --from 2026-07-01 --to 2026-09-01 |
  jq -e '.ok and (.data.events | length) == 8' >/dev/null

"$CLI" event search --query review |
  jq -e '.ok and .data.events[0].uid == "review-series@hw-calendar.test"' >/dev/null

CREATED=$(
  "$CLI" event create <<'EOF'
{"schema_version":1,"summary":"CLI integration","dtstart":"20260801T140000","dtend":"20260801T150000","categories":["PERSONAL"],"important":true,"reminder_offsets_seconds":[600]}
EOF
)
EVENT_UID=$(printf '%s' "$CREATED" | jq -r '.data.uid')
test -n "$EVENT_UID"

"$CLI" event get --uid "$EVENT_UID" |
  jq -e '.ok and .data.events[0].summary == "CLI integration"' >/dev/null

"$CLI" event update --uid "$EVENT_UID" --scope all <<'EOF' |
{"schema_version":1,"summary":"CLI integration updated","dtstart":"20260801T140000","dtend":"20260801T153000","categories":["WORK"],"important":false}
EOF
  jq -e '.ok and .data.status == "saved"' >/dev/null

"$CLI" event get --uid "$EVENT_UID" |
  jq -e '.ok and .data.events[0].summary == "CLI integration updated" and .data.events[0].sequence == 1' >/dev/null

"$CLI" event delete --uid "$EVENT_UID" --scope all <<'EOF' |
{"schema_version":1,"summary":"CLI integration updated","dtstart":"20260801T140000","dtend":"20260801T153000","categories":["WORK"],"important":false}
EOF
  jq -e '.ok and .data.status == "cancelled"' >/dev/null

"$CLI" event search --query "CLI integration" |
  jq -e '.ok and (.data.events | length) == 0' >/dev/null

"$CLI" ical export --all --output "$TMP/export.ics" |
  jq -e '.ok and .data.bytes > 0' >/dev/null
"$CLI" ical validate < "$TMP/export.ics" |
  jq -e '.ok and .data.valid' >/dev/null

"$CLI" recurrence expand \
  --rule "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3" \
  --start 20260731T090000 \
  --from 2026-07-01 \
  --to 2027-01-01 |
  jq -e '.ok and (.data.occurrences | length) == 3' >/dev/null

printf '[hw_calendar] CLI integration passed\n'
