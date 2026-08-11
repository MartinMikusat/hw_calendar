# TODO — hw_calendar

## Active

- [ ] Replace the first-release build-1 updater test with a public old-to-new test before 0.1.1. Install the latest stable release through its public feed, update it to the signed candidate, and verify the installed bundle matches that candidate.

## Completed

- [x] Release Developer ID-signed and notarized 0.1.0 build 2, then confirm native reminder delivery while the application is closed. Completed 2026-08-09.
- [x] Fix `hw_calendar` CLI command discoverability and usage in-app: implement a dedicated `--help`/subcommand help path for `entry add/create/update` and replace opaque `unknown command`/JSON-only input failures with actionable guidance.
  - Detailed scope: [`src/agenda_cli.odin`](src/agenda_cli.odin), [`src/cli.odin`](src/cli.odin), [`src/cli_test.odin`](src/cli_test.odin), and [`scripts/cli-integration-test.sh`](scripts/cli-integration-test.sh).
  - Completion: `entry create`/`entry add` usage is discoverable without trial-and-error, interval-based recurring chores can be created with first-class flags (including date/time and recurrence) without requiring raw stdin JSON guessing, and invalid payloads emit targeted error messages instead of generic parser errors.
  - Completed: 2026-08-11.

## Deferred

Cross-project Apple-platform interaction work is tracked in the [workspace
TODO](../TODO.md).
