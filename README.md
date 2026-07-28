# HW Calendar

An Apple Silicon macOS calendar that renders a continuous list of days through
Metal and stores local calendar data as RFC 5545 iCalendar components.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**

## Current interface

The application shows a continuous vertical day list. Event rows use Ochre for
the `PERSONAL` category and Forest for the `WORK` category. An important event
contains `X-HW-IMPORTANT:TRUE`, and every date touched by that event uses a
Coffee background.

Use the `DARK` or `LIGHT` header control to switch the interface theme. The
application stores the selected theme in its local database.

Press `/` when no text field has focus to activate Flash labels. Press
`Control-K` to open the command palette. Global event search ranks `SUMMARY`,
`DESCRIPTION`, `LOCATION`, `URL`, `CATEGORIES`, and `UID` through
`hw_odin_matchSorter`.

Select an event or the New Event control to open the Metal event editor. The
editor exposes the same controls to pointer input, Accessibility, and Flash.

The application uses a square borderless window by product requirement. Its
project-drawn close, minimize, and zoom controls call the corresponding AppKit
operations and use the shared pointer, Accessibility, and Flash registry.

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

`./dev.sh` builds a stable AppKit host and loads the application from a
generation-specific dylib. A source edit builds a new dylib. The host swaps it
at a frame boundary and preserves the window, current view, editor state,
database connection, and UI allocations. It defers the swap while CLI or
notification work is active.

Changes to the host contract, application metadata, or bundled resources
rebuild and restart the host. An incompatible state layout also requests a
controlled restart with exit status 75. A failed module build leaves the
current generation active. `./dev.sh asan` uses the same reload path with
AddressSanitizer instrumentation. Release mode keeps the full rebuild path.
Every `./dev.sh` launch orders the window behind active applications. Launch
the app directly when it must activate and move to the front.
A watcher lock prevents a second `./dev.sh` invocation from opening another
application instance.

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

Bundled icon provenance:

- Assets: Iconoir regular `xmark`, `minus`, and `maximize`
- Version: 7.11.1, commit `59e3d5d969c59b3fb652a556795e08c1b3371c5b`
- Source files: <https://github.com/iconoir-icons/iconoir/tree/v7.11.1/icons/regular>
- SHA-256 (`xmark.svg`): `61aa0a4913a440aaafcc45064a87e24fe8eb22ba4abc4c5ef020530928ed8daf`
- SHA-256 (`minus.svg`): `babb05bca016bffdd38cbd1dcaeef6ccdf42fc8654124dee169a412eeed6d425`
- SHA-256 (`maximize.svg`): `3a3048cdc0e8e4aef5d68353b5434f0c0e074dc672b6c0abf25a5a64bc5cc8f4`
- License: [MIT](resources/icons/iconoir/LICENSE)

Test-only oracle provenance:

- Asset: libical 4.0.5 source
- Source: <https://github.com/libical/libical/tree/0a1a1d81304ae63ffe24e43b8d1fb1e9b03c635c>
- License: MPL-2.0 or LGPL-2.1
- License location when fetched: `build/test-deps/libical/LICENSE.txt`

## Release TODO

Produce a Developer ID-signed and notarized application bundle. Verify native
notification delivery from the signed bundle while the application is closed.
