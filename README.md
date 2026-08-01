# hw_calendar

`hw_calendar` is a local personal agenda for Apple Silicon macOS. It stores one
unstructured stream of entries and renders confirmed dates in a Metal period
view.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**

## Product contract

The original entry text is authoritative. An entry can also contain confirmed
start, end, due, location, source URL, reminder, and recurrence values. These
values support deterministic display and scheduling. They do not create
user-facing entry types.

An external local agent can list entries and submit an interpretation proposal.
The proposal cannot change the entry. A person must confirm the proposal before
the application stores its temporal fields or schedules its reminder.

The application has no calendar-account integration. It does not implement
EventKit synchronization, CalDAV, iCalendar import, iCalendar export, or
invitation transport. Automatic discovery of city events is also outside the
current product boundary.

## Interface

The main interface shows a chronological period. Dated entries, due recurring
work, and enabled holidays share this view. An entry without a confirmed date
remains available through search and the structured command interface.

The entry editor keeps natural-language text as its primary field. The shared
control registry routes pointer, numbered keyboard, Accessibility, Flash, and
command-menu activation through typed application actions.

Use the gear control or `Command-,` to open Settings. Settings contains theme
and Flash shortcut configuration. The application stores these preferences in
its local database.

## Structured commands

Each command writes one JSON result to standard output. A mutation reads one
versioned JSON document from standard input.

```sh
build/hw_calendar entry create < entry.json
build/hw_calendar entry get --id 1
build/hw_calendar entry list
build/hw_calendar entry search --query bathroom
build/hw_calendar entry update --id 1 --if-revision 2 < entry.json
build/hw_calendar entry complete --id 1 --if-revision 2
build/hw_calendar entry reopen --id 1 --if-revision 3
build/hw_calendar entry dismiss --id 1 --if-revision 3
build/hw_calendar entry restore --id 1 --if-revision 4
build/hw_calendar agenda query --from 1767225600 --to 1767830400
build/hw_calendar proposal submit < proposal.json
build/hw_calendar proposal get --id 1
build/hw_calendar proposal confirm --id 1
build/hw_calendar proposal reject --id 1
build/hw_calendar reminder status
build/hw_calendar ui snapshot
build/hw_calendar ui check --baseline /path/to/snapshot.json
```

Every entry mutation uses an expected revision. A proposal also records its
source revision. The application rejects stale mutations and stale proposals.

The GUI owns the SQLite database while it runs. Commands use the GUI's private
local socket in that state. When the GUI is closed, a command locks and opens
the database directly.

The agenda uses `agenda.sqlite3`. On the first agenda launch, the application
renames an unused `calendar.sqlite3` file to `calendar-unused.sqlite3`. It does
not read or migrate records from that file.

## Development

Install Odin and keep the pinned sibling libraries beside this repository.

```sh
./test.sh
./build.sh
./dev.sh
./dev.sh asan
```

The development watcher rebuilds the complete executable. It replaces the
running process only after a successful build. A replacement restores the
previous process's frontmost state. A background replacement does not put its
window onscreen. A failed build leaves the current process running.

The interface requests AppKit's system monospaced font. It does not hard-code
or bundle the concrete font family.

Bundled icons:

- Iconoir Regular 7.11.1 at commit `59e3d5d969c59b3fb652a556795e08c1b3371c5b`
- Source: <https://github.com/iconoir-icons/iconoir/tree/v7.11.1/icons/regular>
- License: [MIT](resources/icons/iconoir/LICENSE)

Bundled holiday data:

- Slovak holidays from 2026 onward
- Source: <https://static.slov-lex.sk/static/SK/ZZ/1993/241/20251101.print.html>
- SHA-256: `3555b57422a8bc6aa11d7f861fdfca106bc5eb1c423148a13b5a2f7574c5452f`
- Data: [resources/holidays/sk.json](resources/holidays/sk.json)

## Release TODO

Produce a Developer ID-signed and notarized build. Verify confirmed native
reminder delivery while the application is closed.
