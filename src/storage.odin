package main

import "core:fmt"
import "core:os"
import "core:strings"

CALENDAR_SCHEMA_VERSION :: 1

calendar_database: ^SQLite_DB

calendar_support_dir :: proc() -> string {
	if override := os.get_env("HW_CALENDAR_SUPPORT_DIR", context.temp_allocator);
	   len(override) > 0 {
		return override
	}
	home := os.get_env("HOME", context.temp_allocator)
	return fmt.tprintf("%s/Library/Application Support/hw_calendar", home)
}

calendar_database_path :: proc() -> string {
	return fmt.tprintf("%s/agenda.sqlite3", calendar_support_dir())
}

calendar_database_open :: proc() -> bool {
	if calendar_database != nil {return true}
	support := calendar_support_dir()
	if os.make_directory(support) != nil && !os.exists(support) {return false}
	calendar_archive_unused_database(support)
	path := calendar_database_path()
	path_c := strings.clone_to_cstring(path, context.temp_allocator)
	if sqlite3_open_v2(
		path_c,
		&calendar_database,
		SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
		nil,
	) != SQLITE_OK {
		if calendar_database != nil {sqlite3_close(calendar_database)}
		calendar_database = nil
		return false
	}
	return calendar_database_create_schema()
}

calendar_archive_unused_database :: proc(support: string) {
	legacy := fmt.tprintf("%s/calendar.sqlite3", support)
	if !os.exists(legacy) {return}
	archived := fmt.tprintf("%s/calendar-unused.sqlite3", support)
	if os.exists(archived) {return}
	_ = os.rename(legacy, archived)
	sidecar_suffixes := [2]string{"-wal", "-shm"}
	for suffix in sidecar_suffixes {
		legacy_sidecar := fmt.tprintf("%s%s", legacy, suffix)
		if os.exists(legacy_sidecar) {
			_ = os.rename(legacy_sidecar, fmt.tprintf("%s%s", archived, suffix))
		}
	}
}

calendar_database_close :: proc() {
	if calendar_database != nil {sqlite3_close(calendar_database)}
	calendar_database = nil
}

calendar_database_create_schema :: proc() -> bool {
	if calendar_database == nil {return false}
	return sqlite_execute(calendar_database, "PRAGMA journal_mode=WAL;") &&
	       sqlite_execute(calendar_database, "PRAGMA foreign_keys=ON;") &&
	       sqlite_execute(calendar_database, `
		CREATE TABLE IF NOT EXISTS agenda_entries (
			id INTEGER PRIMARY KEY,
			original_text TEXT NOT NULL,
			start_at TEXT NOT NULL DEFAULT '',
			end_at TEXT NOT NULL DEFAULT '',
			due_at TEXT NOT NULL DEFAULT '',
			location TEXT NOT NULL DEFAULT '',
			source_url TEXT NOT NULL DEFAULT '',
			reminder_at TEXT NOT NULL DEFAULT '',
			recurrence_seconds INTEGER NOT NULL DEFAULT 0,
			state TEXT NOT NULL DEFAULT 'active',
			revision INTEGER NOT NULL DEFAULT 1,
			created_at_ms INTEGER NOT NULL,
			updated_at_ms INTEGER NOT NULL
		);
		CREATE INDEX IF NOT EXISTS agenda_entries_period ON agenda_entries(start_at, due_at);
		CREATE TABLE IF NOT EXISTS agenda_proposals (
			id INTEGER PRIMARY KEY,
			entry_id INTEGER NOT NULL REFERENCES agenda_entries(id) ON DELETE CASCADE,
			source_revision INTEGER NOT NULL,
			fields_json TEXT NOT NULL,
			uncertainty TEXT NOT NULL DEFAULT '',
			state TEXT NOT NULL DEFAULT 'pending',
			created_at_ms INTEGER NOT NULL
		);
		CREATE INDEX IF NOT EXISTS agenda_proposals_entry ON agenda_proposals(entry_id, state);
		CREATE TABLE IF NOT EXISTS agenda_completion_history (
			id INTEGER PRIMARY KEY,
			entry_id INTEGER NOT NULL REFERENCES agenda_entries(id) ON DELETE CASCADE,
			completed_at TEXT NOT NULL,
			previous_due_at TEXT NOT NULL DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS activity_notifications (
			id INTEGER PRIMARY KEY,
			created_at_ms INTEGER NOT NULL,
			severity INTEGER NOT NULL,
			summary TEXT NOT NULL,
			detail TEXT NOT NULL
		);
		CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
		CREATE TABLE IF NOT EXISTS calendar_preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL);
		CREATE TABLE IF NOT EXISTS birthdays (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			month INTEGER NOT NULL,
			day INTEGER NOT NULL,
			year INTEGER NOT NULL DEFAULT 0,
			advance_days INTEGER NOT NULL DEFAULT 0,
			created_at_ms INTEGER NOT NULL,
			updated_at_ms INTEGER NOT NULL
		);
		PRAGMA user_version=1;
	`)
}

calendar_meta_get :: proc(
	key: string,
	allocator := context.allocator,
) -> (string, bool) {
	if calendar_database == nil {return "", false}
	statement, prepared := sqlite_prepare(
		calendar_database,
		"SELECT value FROM app_meta WHERE key = ?;",
	)
	if !prepared {return "", false}
	defer sqlite3_finalize(statement)
	if !sqlite_bind_text_value(statement, 1, key) {return "", false}
	if sqlite3_step(statement) != SQLITE_ROW {return "", false}
	return sqlite_column_string(statement, 0, allocator), true
}

calendar_meta_set :: proc(key, value: string) -> bool {
	if calendar_database == nil {return false}
	statement, prepared := sqlite_prepare(
		calendar_database,
		`INSERT INTO app_meta (key, value) VALUES (?, ?)
		 ON CONFLICT(key) DO UPDATE SET value = excluded.value;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite_bind_text_value(statement, 1, key) &&
	       sqlite_bind_text_value(statement, 2, value) &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_preference_get :: proc(
	key: string,
	allocator := context.allocator,
) -> (string, bool) {
	if calendar_database == nil {return "", false}
	statement, prepared := sqlite_prepare(
		calendar_database,
		"SELECT value FROM calendar_preferences WHERE key = ?;",
	)
	if !prepared {return "", false}
	defer sqlite3_finalize(statement)
	if !sqlite_bind_text_value(statement, 1, key) {return "", false}
	if sqlite3_step(statement) != SQLITE_ROW {return "", false}
	return sqlite_column_string(statement, 0, allocator), true
}

calendar_preference_set :: proc(key, value: string) -> bool {
	if calendar_database == nil {return false}
	statement, prepared := sqlite_prepare(
		calendar_database,
		`INSERT INTO calendar_preferences(key, value) VALUES (?, ?)
		 ON CONFLICT(key) DO UPDATE SET value = excluded.value;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite_bind_text_value(statement, 1, key) &&
	       sqlite_bind_text_value(statement, 2, value) &&
	       sqlite3_step(statement) == SQLITE_DONE
}
