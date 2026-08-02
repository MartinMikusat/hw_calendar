package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"

@(test)
chore_due_and_rolling_completion_test :: proc(t: ^testing.T) {
	if calendar_database != nil {return}
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
