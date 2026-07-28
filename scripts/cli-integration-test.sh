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

sqlite3 "$HW_CALENDAR_SUPPORT_DIR/calendar.sqlite3" \
  "UPDATE events SET archived=1 WHERE uid='review-series@hw-calendar.test';"
"$CLI" event search --query review |
  jq -e '.ok and (.data.events | length) == 0' >/dev/null
"$CLI" event get --uid "review-series@hw-calendar.test" |
  jq -e '.ok and .data.events[0].archived' >/dev/null
"$CLI" ical import < "$ROOT/testdata/calendar.ics" |
  jq -e '.ok' >/dev/null
"$CLI" event get --uid "review-series@hw-calendar.test" |
  jq -e '.ok and .data.events[0].archived' >/dev/null

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

MIGRATION_SUPPORT="$TMP/migration-support"
mkdir -p "$MIGRATION_SUPPORT"
sqlite3 "$MIGRATION_SUPPORT/calendar.sqlite3" <<'SQL'
PRAGMA user_version=2;
CREATE TABLE documents (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  imported_at_ms INTEGER NOT NULL,
  diagnostic_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE events (
  id INTEGER PRIMARY KEY,
  document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  uid TEXT NOT NULL,
  recurrence_id TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL DEFAULT '',
  categories TEXT NOT NULL DEFAULT '',
  important INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT '',
  dtstart TEXT NOT NULL DEFAULT '',
  dtend TEXT NOT NULL DEFAULT '',
  rrule TEXT NOT NULL DEFAULT '',
  raw_component TEXT NOT NULL,
  sequence INTEGER NOT NULL DEFAULT 0,
  last_modified TEXT NOT NULL DEFAULT '',
  dtstamp TEXT NOT NULL DEFAULT '',
  UNIQUE(uid, recurrence_id)
);
INSERT INTO documents VALUES (1, 'migration-test', 0, 0);
INSERT INTO events (
  document_id, uid, summary, dtstart, dtend, raw_component
) VALUES (
  1, 'legacy@hw-calendar.test', 'Legacy event',
  '20260728T090000', '20260728T100000',
  'BEGIN:VEVENT
UID:legacy@hw-calendar.test
DTSTART:20260728T090000
DTEND:20260728T100000
END:VEVENT'
);
SQL
HW_CALENDAR_SUPPORT_DIR="$MIGRATION_SUPPORT" \
  "$CLI" event get --uid "legacy@hw-calendar.test" |
  jq -e '.ok and (.data.events[0].archived | not)' >/dev/null
test "$(sqlite3 "$MIGRATION_SUPPORT/calendar.sqlite3" 'PRAGMA user_version;')" = 3
test "$(sqlite3 "$MIGRATION_SUPPORT/calendar.sqlite3" \
  "SELECT count(*) FROM pragma_table_info('events') WHERE name='archived';")" = 1

printf '[hw_calendar] CLI integration passed\n'
