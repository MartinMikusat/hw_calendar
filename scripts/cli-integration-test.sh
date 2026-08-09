#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HW_CALENDAR_SUPPORT_DIR="$TMP/support"
CLI="$ROOT/build/hw_calendar"

mkdir -p "$HW_CALENDAR_SUPPORT_DIR"
sqlite3 "$HW_CALENDAR_SUPPORT_DIR/calendar.sqlite3" 'CREATE TABLE obsolete_events(id INTEGER);'

CREATED=$(
  "$CLI" entry create <<'EOF'
{"schema_version":1,"original_text":"Clean the bathroom every month"}
EOF
)
ENTRY_ID=$(printf '%s' "$CREATED" | jq -r '.data.entry.id')
test "$ENTRY_ID" = 1
test -f "$HW_CALENDAR_SUPPORT_DIR/calendar-unused.sqlite3"
test ! -f "$HW_CALENDAR_SUPPORT_DIR/calendar.sqlite3"

"$CLI" entry get --id "$ENTRY_ID" |
  jq -e '.ok and .data.entry.original_text == "Clean the bathroom every month" and .data.entry.revision == 1' >/dev/null

"$CLI" proposal submit <<'EOF' |
{"schema_version":1,"entry_id":1,"source_revision":1,"fields":{"due_at":"1767225600","reminder_at":"1767222000","recurrence_seconds":2592000},"uncertainty":"A month is represented as 30 days."}
EOF
  jq -e '.ok and .data.proposal.state == "pending" and .data.proposal.source_revision == 1' >/dev/null

"$CLI" entry get --id "$ENTRY_ID" |
  jq -e '.data.entry.due_at == "" and .data.entry.revision == 1' >/dev/null

"$CLI" proposal confirm --id 1 |
  jq -e '.ok and .data.entry.due_at == "1767225600" and .data.entry.revision == 2' >/dev/null

if "$CLI" entry update --id "$ENTRY_ID" --if-revision 1 <<'EOF' >/dev/null 2>&1
{"schema_version":1,"original_text":"stale update"}
EOF
then
  exit 1
fi

"$CLI" entry complete --id "$ENTRY_ID" --if-revision 2 |
  jq -e '.ok and .data.entry.state == "active" and .data.entry.revision == 3' >/dev/null
COMPLETED_AT=$(sqlite3 "$HW_CALENDAR_SUPPORT_DIR/agenda.sqlite3" \
  "SELECT completed_at FROM agenda_completion_history WHERE entry_id=$ENTRY_ID ORDER BY id DESC LIMIT 1;")
EXPECTED_DUE=$((COMPLETED_AT + 2592000))
ACTUAL_DUE=$(sqlite3 "$HW_CALENDAR_SUPPORT_DIR/agenda.sqlite3" \
  "SELECT due_at FROM agenda_entries WHERE id=$ENTRY_ID;")
test "$ACTUAL_DUE" = "$EXPECTED_DUE"

"$CLI" agenda query --from 1700000000 --to 1900000000 |
  jq -e '.ok and (.data.entries | length) == 1' >/dev/null

"$CLI" entry dismiss --id "$ENTRY_ID" --if-revision 3 |
  jq -e '.ok and .data.entry.state == "dismissed" and .data.entry.revision == 4' >/dev/null
"$CLI" entry restore --id "$ENTRY_ID" --if-revision 4 |
  jq -e '.ok and .data.entry.state == "active" and .data.entry.revision == 5' >/dev/null

if "$CLI" chore done --id "$ENTRY_ID" --if-revision 5 >/dev/null 2>&1
then
  exit 1
fi
"$CLI" entry get --id "$ENTRY_ID" |
  jq -e '.data.entry.state == "active" and .data.entry.revision == 5' >/dev/null

test "$(sqlite3 "$HW_CALENDAR_SUPPORT_DIR/agenda.sqlite3" 'PRAGMA foreign_key_check;')" = ""
test "$(sqlite3 "$HW_CALENDAR_SUPPORT_DIR/agenda.sqlite3" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('events','documents');")" = 0
"$CLI" entry list >/dev/null
test "$(find "$HW_CALENDAR_SUPPORT_DIR" -name 'calendar-unused.sqlite3' | wc -l | tr -d ' ')" = 1

VACUUM=$(
  "$CLI" entry create <<'EOF'
{"schema_version":1,"original_text":"Vacuum the floors every week","due_at":"1000000000","recurrence_seconds":604800}
EOF
)
VACUUM_ID=$(printf '%s' "$VACUUM" | jq -r '.data.entry.id')
test "$VACUUM_ID" = 2

"$CLI" chore due |
  jq -e '.ok and (.data.chores | length) == 1 and .data.chores[0].name == "Vacuum the floors every week" and .data.chores[0].interval_seconds == 604800 and .data.chores[0].overdue_seconds > 0 and .data.chores[0].revision == 1' >/dev/null

"$CLI" chore done --id "$VACUUM_ID" --if-revision 1 |
  jq -e '.ok and .data.entry.state == "active" and .data.entry.recurrence_seconds == 604800 and .data.entry.revision == 2' >/dev/null

"$CLI" chore due |
  jq -e '.ok and (.data.chores | length) == 0' >/dev/null

NOTE=$(
  "$CLI" entry create <<'EOF'
{"schema_version":1,"original_text":"Review the calendar notes"}
EOF
)
NOTE_ID=$(printf '%s' "$NOTE" | jq -r '.data.entry.id')
test "$NOTE_ID" = 3

if "$CLI" chore done --id "$NOTE_ID" --if-revision 1 >/dev/null 2>&1
then
  exit 1
fi
"$CLI" entry get --id "$NOTE_ID" |
  jq -e '.data.entry.state == "active" and .data.entry.revision == 1' >/dev/null

ARCHIVE="$TMP/agenda.hwcalendar.json"
"$CLI" archive export --path "$ARCHIVE" |
  jq -e '.ok and .data.summary.entry_count == 3 and .data.summary.completion_count == 2' >/dev/null
test -f "$ARCHIVE"

"$CLI" archive inspect --path "$ARCHIVE" |
  jq -e '.ok and .data.summary.entry_count == 3 and .data.summary.completion_count == 2' >/dev/null

EXTRA=$(
  "$CLI" entry create <<'EOF'
{"schema_version":1,"original_text":"Temporary entry after export"}
EOF
)
EXTRA_ID=$(printf '%s' "$EXTRA" | jq -r '.data.entry.id')
test "$EXTRA_ID" = 4

if "$CLI" archive import --path "$ARCHIVE" >/dev/null 2>&1
then
  exit 1
fi

"$CLI" archive import --path "$ARCHIVE" --replace |
  jq -e '.ok and .data.replaced and .data.backup_path != "" and .data.summary.entry_count == 3' >/dev/null

if "$CLI" entry get --id "$EXTRA_ID" >/dev/null 2>&1
then
  exit 1
fi
test "$(sqlite3 "$HW_CALENDAR_SUPPORT_DIR/agenda.sqlite3" 'PRAGMA foreign_key_check;')" = ""
test "$(find "$HW_CALENDAR_SUPPORT_DIR/Backups" -name 'agenda-before-import-v1-*.sqlite3' | wc -l | tr -d ' ')" = 1

printf '[hw_calendar] agenda CLI integration passed\n'
