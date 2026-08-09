package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

@(test)
chore_due_and_rolling_completion_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	if calendar_database != nil {return}
	previous_ui := calendar_ui
	calendar_ui = {width = 900, height = 700}
	defer {calendar_ui = previous_ui}
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	if len(tmp) == 0 {tmp = "/tmp"}
	support := strings.concatenate({
		tmp,
		"/hw_calendar_chore_test_",
		fmt.tprintf("%d", time.to_unix_nanoseconds(time.now())),
	})
	defer delete(support)
	defer _ = os.remove_all(support)
	if os.set_env("HW_CALENDAR_SUPPORT_DIR", support) != 0 {
		testing.fail_now(t, "could not set the support directory")
	}
	if !calendar_database_open() {
		testing.fail_now(t, "could not open the test database")
	}
	defer calendar_database_close()

	now_unix := time.to_unix_seconds(time.now())
	created, ok := agenda_entry_create(&Agenda_Entry_Input{
		schema_version = 1,
		original_text = "Vacuum the floors every week",
		due_at = fmt.tprintf("%d", now_unix-86_400),
		recurrence_seconds = 604800,
	})
	defer agenda_entry_destroy(&created)
	if !ok {testing.fail_now(t, "could not create the chore")}

	due := agenda_due_entries(now_unix)
	defer agenda_entries_destroy(&due)
	testing.expect(t, len(due) == 1)
	if len(due) > 0 {
		testing.expect(t, due[0].id == created.id)
		testing.expect(t, due[0].recurrence_seconds == 604800)
	}

	completed, code := agenda_entry_set_state(created.id, created.revision, "completed")
	defer agenda_entry_destroy(&completed)
	testing.expect(t, len(code) == 0)
	if len(code) != 0 {return}
	testing.expect(t, completed.state == "active")

	history, history_found := agenda_completion_recent(completed.id)
	defer if history_found {delete(history)}
	testing.expect(t, history_found)
	if !history_found {return}
	completed_at, parsed := strconv.parse_i64(history)
	testing.expect(t, parsed)
	if parsed {
		expected_due, due_parsed := strconv.parse_i64(completed.due_at)
		testing.expect(t, due_parsed)
		if due_parsed {
			testing.expect(t, expected_due == completed_at+604800)
		}
	}

	due_after := agenda_due_entries(now_unix)
	defer agenda_entries_destroy(&due_after)
	testing.expect(t, len(due_after) == 0)

	normal, normal_ok := agenda_entry_create(&Agenda_Entry_Input{
		schema_version = 1,
		original_text = "One-time task",
		due_at = fmt.tprintf("%d", now_unix-1),
	})
	defer agenda_entry_destroy(&normal)
	if !normal_ok {testing.fail_now(t, "could not create the one-time task")}
	_, code = agenda_chore_complete_at(normal.id, normal.revision, now_unix)
	testing.expect_value(t, code, "not_chore")
	reloaded_normal, normal_found := agenda_entry_get(normal.id)
	defer agenda_entry_destroy(&reloaded_normal)
	testing.expect(t, normal_found)
	testing.expect_value(t, reloaded_normal.state, "active")

	future, future_ok := agenda_entry_create(&Agenda_Entry_Input{
		schema_version = 1,
		original_text = "Future chore",
		due_at = fmt.tprintf("%d", now_unix+60),
		recurrence_seconds = 86_400,
	})
	defer agenda_entry_destroy(&future)
	if !future_ok {testing.fail_now(t, "could not create the future chore")}
	_, code = agenda_chore_complete_at(future.id, future.revision, now_unix)
	testing.expect_value(t, code, "not_due")
	reloaded_future, future_found := agenda_entry_get(future.id)
	defer agenda_entry_destroy(&reloaded_future)
	testing.expect(t, future_found)
	testing.expect_value(t, reloaded_future.revision, future.revision)

	editable, editable_ok := agenda_entry_create(&Agenda_Entry_Input{
		schema_version = 1,
		original_text = "Water the plants",
		start_at = fmt.tprintf("%d", now_unix-120),
		end_at = fmt.tprintf("%d", now_unix-60),
		due_at = fmt.tprintf("%d", now_unix+300),
		location = "Living room",
		source_url = "https://example.test/plants",
		reminder_at = fmt.tprintf("%d", now_unix+240),
		recurrence_seconds = 345600,
	})
	defer agenda_entry_destroy(&editable)
	if !editable_ok {testing.fail_now(t, "could not create the editable chore")}
	due_stamp, update_code := calendar_chore_update_entry(
		editable.id,
		editable.revision,
		"Water all plants",
		259200,
	)
	testing.expect_value(t, update_code, "")
	parsed_due, parsed_due_ok := strconv.parse_i64(editable.due_at)
	testing.expect(t, parsed_due_ok)
	if parsed_due_ok {testing.expect_value(t, due_stamp, parsed_due)}
	reloaded_editable, editable_found := agenda_entry_get(editable.id)
	defer agenda_entry_destroy(&reloaded_editable)
	testing.expect(t, editable_found)
	if editable_found {
		testing.expect_value(t, reloaded_editable.original_text, "Water all plants")
		testing.expect_value(t, reloaded_editable.start_at, editable.start_at)
		testing.expect_value(t, reloaded_editable.end_at, editable.end_at)
		testing.expect_value(t, reloaded_editable.due_at, editable.due_at)
		testing.expect_value(t, reloaded_editable.location, editable.location)
		testing.expect_value(t, reloaded_editable.source_url, editable.source_url)
		testing.expect_value(t, reloaded_editable.reminder_at, editable.reminder_at)
		testing.expect_value(t, reloaded_editable.recurrence_seconds, i64(259200))
		testing.expect_value(t, reloaded_editable.revision, editable.revision+1)
	}
	_, conflict_code := calendar_chore_update_entry(
		editable.id,
		editable.revision,
		"Stale edit",
		86400,
	)
	testing.expect_value(t, conflict_code, "revision_conflict")

	calendar_ui_reload_data()
	editable_index := calendar_ui_event_index_for_entry(editable.id)
	testing.expect(t, editable_index >= 0)
	if editable_index >= 0 {
		testing.expect_value(
			t,
			calendar_ui.entries[editable_index].recurrence_seconds,
			i64(259200),
		)
		calendar_ui.navigation_active = true
		calendar_ui.navigation_kind = .Event
		calendar_ui.navigation_event_index = editable_index
		testing.expect(t, calendar_ui_focused_event_is_chore())
		testing.expect_value(t, calendar_active_modal().kind, Calendar_Modal_Kind.None)
		testing.expect(t, calendar_ui_chore_open(editable_index))
		testing.expect_value(t, calendar_ui.chore_entry_id, editable.id)
		calendar_ui_chore_close()
		calendar_ui_execute_action(Calendar_App_Action{kind = .Action_Edit})
		testing.expect(t, calendar_ui.chore_open)
		testing.expect(t, !calendar_ui.editor_open)
		testing.expect_value(t, calendar_ui.chore_entry_id, editable.id)
		testing.expect_value(t, calendar_ui.chore_expected_revision, editable.revision+1)
		testing.expect_value(t, calendar_ui.chore_name, "Water all plants")
		testing.expect_value(t, calendar_ui.chore_days, "3")
		calendar_ui_chore_close()
	}
	calendar_ui.day_offset += 1
	calendar_ui_reload_data()
	testing.expect(t, calendar_ui_event_index_for_entry(created.id) >= 0)
	calendar_ui.day_offset = 0
	agenda_entries_destroy(&calendar_ui.entries)
	delete(calendar_ui.occurrences)
	agenda_entries_destroy(&calendar_ui.due_entries)
}

agenda_completion_recent :: proc(entry_id: i64, allocator := context.allocator) -> (string, bool) {
	if calendar_database == nil {return "", false}
	statement, prepared := sqlite_prepare(
		calendar_database,
		`SELECT completed_at FROM agenda_completion_history
		 WHERE entry_id=? ORDER BY id DESC LIMIT 1;`,
	)
	if !prepared {return "", false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int64(statement, 1, entry_id) != SQLITE_OK {return "", false}
	if sqlite3_step(statement) != SQLITE_ROW {return "", false}
	return sqlite_column_string(statement, 0, allocator), true
}
