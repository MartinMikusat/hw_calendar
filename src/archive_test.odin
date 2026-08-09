package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

calendar_archive_test_count :: proc(table: string) -> int {
	statement, prepared := sqlite_prepare(
		calendar_database,
		fmt.tprintf("SELECT count(*) FROM %s;", table),
	)
	if !prepared {return -1}
	defer sqlite3_finalize(statement)
	if sqlite3_step(statement) != SQLITE_ROW {return -1}
	return int(sqlite3_column_int(statement, 0))
}

@(test)
calendar_archive_round_trip_replaces_agenda_and_preserves_device_state_test :: proc(
	t: ^testing.T,
) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	if calendar_database != nil {return}
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	if len(tmp) == 0 {tmp = "/tmp"}
	support := strings.concatenate({
		tmp,
		"/hw_calendar_archive_test_",
		fmt.tprintf("%d", time.to_unix_nanoseconds(time.now())),
	})
	defer delete(support)
	defer _ = os.remove_all(support)
	if os.set_env("HW_CALENDAR_SUPPORT_DIR", support) != 0 ||
	   !calendar_database_open() {
		testing.fail_now(t, "could not open the archive test database")
	}
	defer calendar_database_close()

	testing.expect(t, calendar_meta_set("interface_theme", "hw-dark"))
	now := time.to_unix_seconds(time.now())
	entry, created := agenda_entry_create(&Agenda_Entry_Input{
		schema_version = 1,
		original_text = "Take the car for service",
		start_at = fmt.tprintf("%d", now+3_600),
		end_at = fmt.tprintf("%d", now+7_200),
		location = "Garage",
		reminder_at = fmt.tprintf("%d", now+3_000),
	})
	defer agenda_entry_destroy(&entry)
	if !created {testing.fail_now(t, "could not create the archive entry")}
	proposal, proposal_code := agenda_proposal_submit(&Agenda_Proposal_Input{
		schema_version = 1,
		entry_id = entry.id,
		source_revision = entry.revision,
		fields = {
			start_at = entry.start_at,
			end_at = entry.end_at,
			location = entry.location,
			reminder_at = entry.reminder_at,
		},
		uncertainty = "Confirm the time.",
	})
	defer agenda_proposal_destroy(&proposal)
	testing.expect_value(t, proposal_code, "")

	chore, chore_created := agenda_entry_create(&Agenda_Entry_Input{
		schema_version = 1,
		original_text = "Water the plants",
		due_at = fmt.tprintf("%d", now-60),
		recurrence_seconds = 345_600,
	})
	defer agenda_entry_destroy(&chore)
	if !chore_created {testing.fail_now(t, "could not create the archive chore")}
	completed, completion_code := agenda_entry_set_state(
		chore.id,
		chore.revision,
		"completed",
	)
	defer agenda_entry_destroy(&completed)
	testing.expect_value(t, completion_code, "")

	path := fmt.tprintf("%s/test-agenda.hwcalendar.json", support)
	summary, export_error := calendar_archive_export(path)
	testing.expect_value(t, export_error, Calendar_Archive_Error.None)
	testing.expect_value(t, summary.entry_count, 2)
	testing.expect_value(t, summary.proposal_count, 1)
	testing.expect_value(t, summary.completion_count, 1)
	testing.expect(t, os.exists(path))

	archive, inspected, read_error := calendar_archive_read(path)
	defer calendar_archive_destroy(&archive)
	testing.expect_value(t, read_error, Calendar_Archive_Error.None)
	testing.expect_value(t, inspected.entry_count, 2)
	if len(archive.proposals) > 0 {
		original_entry_id := archive.proposals[0].entry_id
		archive.proposals[0].entry_id = 9_999_999
		_, invalid_error := calendar_archive_validate(&archive)
		testing.expect_value(t, invalid_error, Calendar_Archive_Error.Reference)
		archive.proposals[0].entry_id = original_entry_id
	}

	extra, extra_created := agenda_entry_create(&Agenda_Entry_Input{
		schema_version = 1,
		original_text = "This entry must disappear",
	})
	defer agenda_entry_destroy(&extra)
	testing.expect(t, extra_created)
	backup_path, install_error := calendar_archive_install(&archive)
	defer delete(backup_path)
	testing.expect_value(t, install_error, Calendar_Archive_Error.None)
	testing.expect(t, os.exists(backup_path))
	testing.expect(t, calendar_archive_database_valid(backup_path))
	testing.expect_value(t, calendar_archive_test_count("agenda_entries"), 2)
	testing.expect_value(t, calendar_archive_test_count("agenda_proposals"), 1)
	testing.expect_value(
		t,
		calendar_archive_test_count("agenda_completion_history"),
		1,
	)
	_, extra_found := agenda_entry_get(extra.id, context.temp_allocator)
	testing.expect(t, !extra_found)
	theme, theme_found := calendar_meta_get("interface_theme")
	defer delete(theme)
	testing.expect(t, theme_found)
	testing.expect_value(t, theme, "hw-dark")

	second_backup, second_error := calendar_archive_install(&archive)
	defer delete(second_backup)
	testing.expect_value(t, second_error, Calendar_Archive_Error.None)
	testing.expect(t, os.exists(second_backup))
	testing.expect_value(t, calendar_archive_test_count("agenda_entries"), 2)
}
