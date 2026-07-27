# HW Calendar

An Apple Silicon macOS calendar that renders a continuous list of days through
Metal and stores local calendar data as RFC 5545 iCalendar components.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**

## Current interface

The application shows a continuous vertical day list. Event rows use orange
for the `PERSONAL` category and cyan for the `WORK` category. An important
event contains `X-HW-IMPORTANT:TRUE`, and every date touched by that event uses
a warm background.

Press `/` when no text field has focus to activate Flash labels. Press
`Control-K` to open the command palette. Global event search ranks `SUMMARY`,
`DESCRIPTION`, `LOCATION`, `URL`, `CATEGORIES`, and `UID` through
`hw_odin_matchSorter`.

Select an event or the New Event control to open the Metal event editor. The
editor exposes the same controls to pointer input, Accessibility, and Flash.

## RFC 5545 data

The iCalendar engine parses the complete RFC 5545 component tree. It preserves
unknown IANA and `X-` properties, parameters, property order, and original
content lines for unchanged data. Edited content serializes in canonical
iCalendar form with CRLF line endings and 75-octet folding.

The recurrence engine accepts the complete `RECUR` grammar, including all
frequencies, all `BY*` rules, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`,
`RECURRENCE-ID`, and `RANGE=THISANDFUTURE`.

The GUI edits `VEVENT` components. Raw validate, import, and export commands
accept every component type. Dedicated JSON create, update, delete, list, and
search commands operate on `VEVENT`. Version one does not implement CalDAV or
invitation transport.

## Command-line control

Each command returns one JSON object on standard output. Write operations read
one versioned JSON document from standard input.

```sh
build/hw-calendar event list --from 2026-07-01 --to 2026-08-01
build/hw-calendar event search --query review
build/hw-calendar recurrence expand --rule 'FREQ=WEEKLY;BYDAY=MO' \
  --start 20260727T090000 --from 2026-07-01 --to 2026-09-01
build/hw-calendar ical validate < calendar.ics
build/hw-calendar ical import < calendar.ics
build/hw-calendar ical export --all --output calendar.ics
build/hw-calendar reminder status
build/hw-calendar ui snapshot
build/hw-calendar ui check --baseline /path/to/snapshot.json
```

The GUI owns the SQLite database while it runs. CLI requests use the GUI's
private local socket. When the GUI is closed, the CLI locks and updates the
database directly.

## Native reminders

The application executes RFC `VALARM` components with `ACTION:DISPLAY` through
macOS User Notifications. It preserves `AUDIO` and `EMAIL` alarms without
executing them. Clicking a reminder opens its exact occurrence. The Snooze
action schedules another native reminder ten minutes later.

The application schedules the next 48 reminders at launch, after each calendar
mutation, and once per hour while it runs. macOS can deliver those requests
while the application is not running.

## Development

Install Odin and keep the sibling libraries beside this repository:

```sh
./test.sh
./build.sh
./dev.sh
./scripts/libical-oracle.sh
```

The build pins every sibling origin and commit in
[`dependencies.lock`](dependencies.lock). The test-only differential oracle is
libical 4.0.5 at commit
`0a1a1d81304ae63ffe24e43b8d1fb1e9b03c635c`. It is not linked into the
application.

Bundled font provenance:

- Asset: Iosevka Regular 34.7.0
- Source: <https://github.com/be5invis/Iosevka/releases/download/v34.7.0/PkgTTF-Iosevka-34.7.0.zip>
- SHA-256: `2fe6f742431e66f218b713ecca986370612bc27594a96a8ab45a41e9ebbaf5e3`
- License: [SIL Open Font License, Version 1.1](resources/fonts/IOSEVKA-LICENSE.md)

Test-only oracle provenance:

- Asset: libical 4.0.5 source
- Source: <https://github.com/libical/libical/tree/0a1a1d81304ae63ffe24e43b8d1fb1e9b03c635c>
- License: MPL-2.0 or LGPL-2.1
- License location when fetched: `build/test-deps/libical/LICENSE.txt`

## Release TODO

Produce a Developer ID-signed and notarized application bundle. Verify native
notification delivery from the signed bundle while the application is closed.
