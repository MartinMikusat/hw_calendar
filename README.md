# hw_calendar

`hw_calendar` is a local personal agenda for Apple Silicon macOS. It stores one
unstructured stream of entries and renders confirmed dates in a Metal period
view. The interface uses the terminal catalog language from
`hw_odin_components`: System Monospaced ink on paper, hairline frames,
bracket buttons, and red only for destructive work.

## AI-assisted development disclosure

Models used:

- **gpt-5.6-sol**
- **Cursor Grok 4.6**
- **Cursor Grok 4.5**

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
The focused date stays in the center row and always has a 2-point ink tick,
including when the date has no entries. The current date inverts to ink on
paper.

Each date groups its recurring chores into one distinct `CHORES · count` target.
Regular all-day and timed entries remain separate calendar cards.
The details panel shows every chore, event, and holiday on the selected date as
one day agenda. Selecting a row opens its focused details and actions.

A recurring entry works as a chore. Define it once with an interval, for example
`vacuum every week`, and it becomes due immediately. Marking it done starts the
interval clock from that moment, so the next due date is `completion time +
interval`. An overdue chore stays in the due list until it is marked done; it
does not expire or re-enter the list on a fixed schedule. While the view is on
today, a `DUE TASKS` section is pinned at the top of the details panel. It grows
to show more chores and uses up to two-thirds of the panel. Each chore has a
separate `DONE` control. The section scrolls when more chores are due than fit,
and it disappears when the view moves to another day.

The entry editor keeps natural-language text as its primary field. Each frame
emits framework actions and control boxes directly, then publishes the framework
registry for pointer, numbered keyboard, Accessibility, Flash, command-menu, and
CLI dispatch. A small local binding table maps published action IDs to typed
application payloads, while framework input roots select the topmost modal.

The `NEW CHORE` action (numbered code `21`, also available from the command
palette) opens a chore editor with a name field, a whole-day interval field,
and interval presets. Saving a new chore creates a recurring entry that is due
immediately. The `EDIT` action opens the same editor for a focused chore.
Changing its interval preserves its current due date and applies the new
interval after its next completion.

Use Up and Down to move the selected date by one day. Use `Command` with Up or
Down to jump to the previous or next date that contains an entry, chore, or
holiday. Each jump occurs once per occupied date. The selected date moves to
the center row.

Use `[set]` or `Command-,` to open Settings. Settings contains Styling,
Data, Shortcuts, and Updates. Styling is one Dark toggle. Data exports and
imports the portable agenda archive. Updates starts a signed update check. The
application stores interface preferences in its local database.

Each modal uses a hairline frame over a 45-percent dim. Escape, Cancel, and a
backdrop click dismiss ordinary modals. An edited form requests confirmation
before it discards unsaved changes.

## Structured commands

Each command writes one JSON result to standard output. Entry creation, full
entry replacement, and proposal submission accept a versioned JSON document
from standard input. Entry creation and updates also accept first-class flags.
An update read from standard input replaces the full entry document; a flag
update preserves omitted fields.

```sh
build/hw_calendar entry create < entry.json
build/hw_calendar entry add --text "Water the plants" --due 2026-04-27 --recurrence 604800
build/hw_calendar entry create --help
build/hw_calendar entry get --id 1
build/hw_calendar entry list
build/hw_calendar entry search --query bathroom
build/hw_calendar entry update --id 1 --if-revision 2 < entry.json
build/hw_calendar entry update --id 1 --if-revision 2 --text "Water the balcony plants"
build/hw_calendar entry complete --id 1 --if-revision 2
build/hw_calendar entry reopen --id 1 --if-revision 3
build/hw_calendar entry dismiss --id 1 --if-revision 3
build/hw_calendar entry restore --id 1 --if-revision 4
build/hw_calendar agenda query --from 1767225600 --to 1767830400
build/hw_calendar proposal submit < proposal.json
build/hw_calendar proposal get --id 1
build/hw_calendar proposal confirm --id 1
build/hw_calendar proposal reject --id 1
build/hw_calendar chore due
build/hw_calendar chore done --id 1 --if-revision 2
build/hw_calendar archive export --path /path/to/agenda.hwcalendar.json
build/hw_calendar archive inspect --path /path/to/agenda.hwcalendar.json
build/hw_calendar archive import --path /path/to/agenda.hwcalendar.json --replace
build/hw_calendar update check
build/hw_calendar reminder status
build/hw_calendar ui snapshot
build/hw_calendar ui check --baseline /path/to/snapshot.json
build/hw_calendar ui modal-state
build/hw_calendar ui modal-dismiss
build/hw_calendar ui bridge-pointer --control "settings"
build/hw_calendar ui bridge-keyboard --key down --modifiers command
```

Every entry mutation uses an expected revision. A proposal also records its
source revision. The application rejects stale mutations and stale proposals.

`chore due` lists every currently-due recurring entry as JSON, so an external
local agent can answer `what tasks are due today` directly. Each result includes
the revision required by `chore done`. This command marks a due chore done and
advances its next due date. Both commands work through the running application's
socket or directly against the database.

The GUI owns the SQLite database while it runs. Commands use the GUI's private
local socket in that state. When the GUI is closed, a command locks and opens
the database directly.

The archive is readable, versioned JSON. It contains agenda entries, pending
and resolved proposals, and chore completion history. It excludes interface
preferences, operational notifications, and transient interface state. Import
validates all records, creates a verified SQLite backup, and replaces only the
agenda tables. The application retains the newest ten pre-import backups in
the Application Support `Backups` directory.

The pointer bridge resolves a live control by its functional name. It sends
AppKit mouse events through the same view callback as physical pointer input.
It does not activate or raise the application window.

The keyboard bridge sends AppKit Up or Down key events through the live view.
Use `--modifiers none` or `--modifiers command`. The command defaults to `none`.

The agenda uses `agenda.sqlite3`. On the first agenda launch, the application
renames an unused `calendar.sqlite3` file to `calendar-unused.sqlite3`. It does
not read or migrate records from that file.

## Development

Install the Xcode command-line tools, Homebrew LLVM, and the workspace-global
compiler through `hw_odin_toolchain`. Install the optional Metal toolchain for
release builds. The dependency script creates isolated sibling checkouts in
the user cache. Each build verifies the active global compiler, LLVM version,
and the checksums of Clang and the AddressSanitizer runtime.
The build rejects a repository or bundled icon that differs from
[`dependencies.lock`](dependencies.lock).

```sh
./scripts/dependencies.sh sync
./scripts/dependencies.sh doctor
./test.sh
./build.sh
./dev.sh
./dev.sh asan
```

Normal builds invoke `hw-odin`. Run `sync` after a lock change or on a new
machine. Run `brew upgrade llvm` when an update report requires a new locked
LLVM version. Set `HW_CALENDAR_DEPS_DIR` to relocate the cache.

Run the complete update gate manually with:

```sh
./scripts/dependencies.sh update-candidate
```

The updater checks the newest official Odin monthly release, Homebrew LLVM,
sibling `main` branches, and stable Iconoir release. It validates candidates
only when every sibling branch resolves from its locked remote URL. Validation uses an isolated worktree.
A passing update creates a local
`chore/dependency-update-YYYY-MM-DD` branch. A failed update preserves `main`
and writes its report below the dependency cache.

Install the daily 06:00 local update with:

```sh
./scripts/dependency-schedule.sh install
./scripts/dependency-schedule.sh status
./scripts/dependency-schedule.sh uninstall
```

The application emits base content, the modal backdrop, and modal content into
one ordered draw stream. `hw_odin_ui_framework` caches CoreText glyphs in an
atlas and encodes that stream through one Metal pipeline. This order keeps
background content below the backdrop and modal content above it.

`src/ui_registry.odin` owns a persistent framework registry. Each frame resets
the builder, publishes only controls in the active input scope, and validates
the complete cross-surface contract. Pointer, Accessibility, Flash, and
numbered activation resolve through this registry before the application
executes a typed action.

Debug and ASan builds compile Metal source at runtime when the optional shader
compiler is unavailable. Release builds require a bundled `ui.metallib`; use
`xcodebuild -downloadComponent MetalToolchain` to install its compiler.

The development watcher rebuilds the complete executable. It replaces the
running process only after a successful build. A replacement restores the
previous process's frontmost state. A background replacement does not put its
window onscreen. A failed build leaves the current process running.

Launch isolated automation with these environment values:

```sh
HW_CALENDAR_AUTOMATION=1
HW_CALENDAR_ACTIVATE_ON_LAUNCH=0
HW_CALENDAR_VISIBLE_ON_LAUNCH=0
```

This policy keeps the window hidden and removes its Dock item. Remove each
temporary automation process and launch job after the check.

The interface requests AppKit's system monospaced font. It does not hard-code
or bundle the concrete font family.

Bundled icons:

- App icon only: Iconoir Regular `calendar.svg` 7.11.1 at commit `3497016dcb93122b5a64a2df1221598a14ecf4f3`
- Window controls use bracket labels (`[x]` `[-]` `[+]` `[set]`) instead of Iconoir glyphs
- Source: <https://github.com/iconoir-icons/iconoir/tree/v7.11.1/icons/regular>
- Archive SHA-256: `6a22cb1c3eaa49485a5f40cf276c0d063af0792d7bfed8b4bec4fbfc8866e5b2`
- Bundled file checksums: [dependencies.lock](dependencies.lock)
- License: [MIT](resources/icons/iconoir/LICENSE)

Bundled holiday data:

- Slovak holidays from 2026 onward
- Source: <https://static.slov-lex.sk/static/SK/ZZ/1993/241/20251101.print.html>
- SHA-256: `3555b57422a8bc6aa11d7f861fdfca106bc5eb1c423148a13b5a2f7574c5452f`
- Data: [resources/holidays/sk.json](resources/holidays/sk.json)

## Release details

Release builds embed Sparkle 2.9.5. The application checks the signed stable
feed once each day. It downloads and installs an update only after a person
starts or confirms that action.

- Sparkle version: 2.9.5
- Source: <https://github.com/sparkle-project/Sparkle/releases/tag/2.9.5>
- Archive SHA-256: `015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc`
- License: `Contents/Resources/Licenses/Sparkle/LICENSE` in each release bundle

Prepare one release machine with a Developer ID Application certificate, the
`hw_videoClips-notary` Keychain profile, the `hw_calendar` Sparkle signing key,
and authenticated GitHub CLI access. Run `./scripts/setup-release-credentials.sh`
to verify these inputs.

Run `./scripts/release.sh` from clean and synchronized `hw_calendar` `main` and
`hal_wayland` `staging` branches. The command executes the tests, signs and
notarizes the DMG, installs exact build 2 over private build 1 through Sparkle,
and schedules a native reminder before it closes the test application. The
release continues after the observed reminder is confirmed. Publication creates
the GitHub Release, signs the stable appcast, enables the product page, and
fast-forwards the website from `staging` to `main`.

The current release task is tracked in [TODO.md](TODO.md). Mark it complete only
after the closed-application reminder delivery is observed.
