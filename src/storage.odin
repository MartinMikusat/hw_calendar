package main

import "core:fmt"
import "core:hash"
import "core:os"
import os2 "core:os/os2"
import "core:strings"
import "core:time"

CALENDAR_SCHEMA_VERSION :: 1

calendar_database: ^SQLite_DB

Calendar_Event_Source :: enum {
	Local,
	EventKit,
}

Calendar_Event :: struct {
	source: Calendar_Event_Source,
	row_id: i64,
	document_id: i64,
	opaque_id: string,
	event_identifier: string,
	calendar_item_identifier: string,
	external_identifier: string,
	calendar_identifier: string,
	source_identifier: string,
	source_title: string,
	calendar_title: string,
	version: string,
	time_zone: string,
	alarms: string,
	alarm_offsets: string,
	organizer: string,
	attendees: string,
	participation_status: string,
	writable: bool,
	all_day: bool,
	connected_recurring: bool,
	connected_detached: bool,
	has_attendees: bool,
	uid: string,
	recurrence_id: string,
	summary: string,
	description: string,
	location: string,
	url: string,
	categories: string,
	important: bool,
	archived: bool,
	status: string,
	dtstart: string,
	dtend: string,
	rrule: string,
	raw_component: string,
	sequence: int,
	last_modified: string,
	dtstamp: string,
}

calendar_event_destroy :: proc(event: ^Calendar_Event) {
	if event == nil {return}
	delete(event.opaque_id)
	delete(event.event_identifier)
	delete(event.calendar_item_identifier)
	delete(event.external_identifier)
	delete(event.calendar_identifier)
	delete(event.source_identifier)
	delete(event.source_title)
	delete(event.calendar_title)
	delete(event.version)
	delete(event.time_zone)
	delete(event.alarms)
	delete(event.alarm_offsets)
	delete(event.organizer)
	delete(event.attendees)
	delete(event.participation_status)
	delete(event.uid)
	delete(event.recurrence_id)
	delete(event.summary)
	delete(event.description)
	delete(event.location)
	delete(event.url)
	delete(event.categories)
	delete(event.status)
	delete(event.dtstart)
	delete(event.dtend)
	delete(event.rrule)
	delete(event.raw_component)
	delete(event.last_modified)
	delete(event.dtstamp)
	event^ = {}
}

calendar_event_clone :: proc(
	event: ^Calendar_Event,
	allocator := context.allocator,
) -> Calendar_Event {
	if event == nil {return {}}
	result := event^
	result.opaque_id = strings.clone(event.opaque_id, allocator)
	result.event_identifier = strings.clone(event.event_identifier, allocator)
	result.calendar_item_identifier = strings.clone(
		event.calendar_item_identifier,
		allocator,
	)
	result.external_identifier = strings.clone(event.external_identifier, allocator)
	result.calendar_identifier = strings.clone(event.calendar_identifier, allocator)
	result.source_identifier = strings.clone(event.source_identifier, allocator)
	result.source_title = strings.clone(event.source_title, allocator)
	result.calendar_title = strings.clone(event.calendar_title, allocator)
	result.version = strings.clone(event.version, allocator)
	result.time_zone = strings.clone(event.time_zone, allocator)
	result.alarms = strings.clone(event.alarms, allocator)
	result.alarm_offsets = strings.clone(event.alarm_offsets, allocator)
	result.organizer = strings.clone(event.organizer, allocator)
	result.attendees = strings.clone(event.attendees, allocator)
	result.participation_status = strings.clone(
		event.participation_status,
		allocator,
	)
	result.uid = strings.clone(event.uid, allocator)
	result.recurrence_id = strings.clone(event.recurrence_id, allocator)
	result.summary = strings.clone(event.summary, allocator)
	result.description = strings.clone(event.description, allocator)
	result.location = strings.clone(event.location, allocator)
	result.url = strings.clone(event.url, allocator)
	result.categories = strings.clone(event.categories, allocator)
	result.status = strings.clone(event.status, allocator)
	result.dtstart = strings.clone(event.dtstart, allocator)
	result.dtend = strings.clone(event.dtend, allocator)
	result.rrule = strings.clone(event.rrule, allocator)
	result.raw_component = strings.clone(event.raw_component, allocator)
	result.last_modified = strings.clone(event.last_modified, allocator)
	result.dtstamp = strings.clone(event.dtstamp, allocator)
	return result
}

calendar_events_destroy :: proc(events: ^[dynamic]Calendar_Event) {
	for &event in events^ {calendar_event_destroy(&event)}
	delete(events^)
	events^ = nil
}

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
	if os2.make_directory(support) != nil && !os.exists(support) {return false}
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
		PRAGMA user_version=1;
	`)
}

calendar_database_create_schema_legacy :: proc() -> bool {
	if calendar_database == nil {return false}
	if !sqlite_execute(calendar_database, "PRAGMA journal_mode=WAL;") ||
	   !sqlite_execute(calendar_database, "PRAGMA foreign_keys=ON;") ||
	   !sqlite_execute(calendar_database, `
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
			CREATE INDEX IF NOT EXISTS agenda_entries_period
				ON agenda_entries(start_at, due_at);
			CREATE TABLE IF NOT EXISTS agenda_proposals (
				id INTEGER PRIMARY KEY,
				entry_id INTEGER NOT NULL REFERENCES agenda_entries(id) ON DELETE CASCADE,
				source_revision INTEGER NOT NULL,
				fields_json TEXT NOT NULL,
				uncertainty TEXT NOT NULL DEFAULT '',
				state TEXT NOT NULL DEFAULT 'pending',
				created_at_ms INTEGER NOT NULL
			);
			CREATE INDEX IF NOT EXISTS agenda_proposals_entry
				ON agenda_proposals(entry_id, state);
			CREATE TABLE IF NOT EXISTS agenda_completion_history (
				id INTEGER PRIMARY KEY,
				entry_id INTEGER NOT NULL REFERENCES agenda_entries(id) ON DELETE CASCADE,
				completed_at TEXT NOT NULL,
				previous_due_at TEXT NOT NULL DEFAULT ''
			);
			CREATE TABLE IF NOT EXISTS documents (
				id INTEGER PRIMARY KEY,
				source TEXT NOT NULL,
				imported_at_ms INTEGER NOT NULL,
				diagnostic_count INTEGER NOT NULL DEFAULT 0
			);
			CREATE TABLE IF NOT EXISTS events (
				id INTEGER PRIMARY KEY,
				document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
				uid TEXT NOT NULL,
				recurrence_id TEXT NOT NULL DEFAULT '',
				summary TEXT NOT NULL DEFAULT '',
				description TEXT NOT NULL DEFAULT '',
				location TEXT NOT NULL DEFAULT '',
				url TEXT NOT NULL DEFAULT '',
				categories TEXT NOT NULL DEFAULT '',
				important INTEGER NOT NULL DEFAULT 0,
				archived INTEGER NOT NULL DEFAULT 0,
				status TEXT NOT NULL DEFAULT '',
				dtstart TEXT NOT NULL DEFAULT '',
				dtend TEXT NOT NULL DEFAULT '',
				rrule TEXT NOT NULL DEFAULT '',
				raw_component TEXT NOT NULL,
				sequence INTEGER NOT NULL DEFAULT 0,
				last_modified TEXT NOT NULL DEFAULT '',
				dtstamp TEXT NOT NULL DEFAULT '',
				UNIQUE(uid, recurrence_id)
			);
			CREATE INDEX IF NOT EXISTS events_document ON events(document_id);
			CREATE INDEX IF NOT EXISTS events_uid ON events(uid);
			CREATE TABLE IF NOT EXISTS activity_notifications (
				id INTEGER PRIMARY KEY,
				created_at_ms INTEGER NOT NULL,
				severity INTEGER NOT NULL,
				summary TEXT NOT NULL,
				detail TEXT NOT NULL
			);
			CREATE TABLE IF NOT EXISTS snoozes (
				request_id TEXT PRIMARY KEY,
				uid TEXT NOT NULL,
				recurrence_id TEXT NOT NULL,
				fire_at_unix INTEGER NOT NULL
			);
			CREATE TABLE IF NOT EXISTS app_meta (
				key TEXT PRIMARY KEY,
				value TEXT NOT NULL
			);
			CREATE TABLE IF NOT EXISTS calendar_preferences (
				key TEXT PRIMARY KEY,
				value TEXT NOT NULL
			);
			CREATE TABLE IF NOT EXISTS connected_event_metadata (
				opaque_id TEXT PRIMARY KEY,
				important INTEGER NOT NULL DEFAULT 0,
				categories TEXT NOT NULL DEFAULT '',
				updated_at_ms INTEGER NOT NULL
			);
			CREATE TABLE IF NOT EXISTS eventkit_identity_aliases (
				alias_key TEXT PRIMARY KEY,
				opaque_id TEXT NOT NULL
			);
			CREATE INDEX IF NOT EXISTS eventkit_identity_opaque
				ON eventkit_identity_aliases(opaque_id);
			CREATE TABLE IF NOT EXISTS eventkit_search_cache (
				opaque_id TEXT NOT NULL,
				start_unix INTEGER NOT NULL,
				end_unix INTEGER NOT NULL,
				event_identifier TEXT NOT NULL DEFAULT '',
				calendar_item_identifier TEXT NOT NULL DEFAULT '',
				external_identifier TEXT NOT NULL DEFAULT '',
				summary TEXT NOT NULL DEFAULT '',
				description TEXT NOT NULL DEFAULT '',
				location TEXT NOT NULL DEFAULT '',
				url TEXT NOT NULL DEFAULT '',
				calendar_identifier TEXT NOT NULL,
				source_identifier TEXT NOT NULL DEFAULT '',
				source_title TEXT NOT NULL DEFAULT '',
				calendar_title TEXT NOT NULL DEFAULT '',
				writable INTEGER NOT NULL DEFAULT 0,
				all_day INTEGER NOT NULL DEFAULT 0,
				time_zone TEXT NOT NULL DEFAULT '',
				alarms TEXT NOT NULL DEFAULT '',
				alarm_offsets TEXT NOT NULL DEFAULT '',
				organizer TEXT NOT NULL DEFAULT '',
				attendees TEXT NOT NULL DEFAULT '',
				participation_status TEXT NOT NULL DEFAULT '',
				has_attendees INTEGER NOT NULL DEFAULT 0,
				connected_recurring INTEGER NOT NULL DEFAULT 0,
				connected_detached INTEGER NOT NULL DEFAULT 0,
				status TEXT NOT NULL DEFAULT '',
				rrule TEXT NOT NULL DEFAULT '',
				version TEXT NOT NULL,
				last_seen_ms INTEGER NOT NULL,
				PRIMARY KEY(opaque_id, start_unix)
			);
			CREATE INDEX IF NOT EXISTS eventkit_search_text
				ON eventkit_search_cache(summary, description, location);
			CREATE TABLE IF NOT EXISTS eventkit_search_windows (
				start_unix INTEGER NOT NULL,
				end_unix INTEGER NOT NULL,
				refreshed_at_ms INTEGER NOT NULL,
				PRIMARY KEY(start_unix, end_unix)
			);
		`) {
		return false
	}
	has_dtstamp := false
	has_archived := false
	statement, prepared := sqlite_prepare(
		calendar_database,
		"PRAGMA table_info(events);",
	)
	if !prepared {return false}
	for sqlite3_step(statement) == SQLITE_ROW {
		name := sqlite3_column_text(statement, 1)
		if name != nil && string(name) == "dtstamp" {
			has_dtstamp = true
		}
		if name != nil && string(name) == "archived" {
			has_archived = true
		}
	}
	sqlite3_finalize(statement)
	if !has_dtstamp && !sqlite_execute(
		calendar_database,
		"ALTER TABLE events ADD COLUMN dtstamp TEXT NOT NULL DEFAULT '';",
	) {
		return false
	}
	if !has_archived && !sqlite_execute(
		calendar_database,
		"ALTER TABLE events ADD COLUMN archived INTEGER NOT NULL DEFAULT 0;",
	) {
		return false
	}
	cache_columns := [18][2]string{
		{"event_identifier", "TEXT NOT NULL DEFAULT ''"},
		{"calendar_item_identifier", "TEXT NOT NULL DEFAULT ''"},
		{"external_identifier", "TEXT NOT NULL DEFAULT ''"},
		{"source_identifier", "TEXT NOT NULL DEFAULT ''"},
		{"source_title", "TEXT NOT NULL DEFAULT ''"},
		{"writable", "INTEGER NOT NULL DEFAULT 0"},
		{"all_day", "INTEGER NOT NULL DEFAULT 0"},
		{"time_zone", "TEXT NOT NULL DEFAULT ''"},
		{"alarms", "TEXT NOT NULL DEFAULT ''"},
		{"alarm_offsets", "TEXT NOT NULL DEFAULT ''"},
		{"organizer", "TEXT NOT NULL DEFAULT ''"},
		{"attendees", "TEXT NOT NULL DEFAULT ''"},
		{"participation_status", "TEXT NOT NULL DEFAULT ''"},
		{"has_attendees", "INTEGER NOT NULL DEFAULT 0"},
		{"connected_recurring", "INTEGER NOT NULL DEFAULT 0"},
		{"connected_detached", "INTEGER NOT NULL DEFAULT 0"},
		{"status", "TEXT NOT NULL DEFAULT ''"},
		{"rrule", "TEXT NOT NULL DEFAULT ''"},
	}
	for column in cache_columns {
		found := false
		cache_statement, cache_prepared := sqlite_prepare(
			calendar_database,
			"PRAGMA table_info(eventkit_search_cache);",
		)
		if !cache_prepared {return false}
		for sqlite3_step(cache_statement) == SQLITE_ROW {
			name := sqlite3_column_text(cache_statement, 1)
			if name != nil && string(name) == column[0] {
				found = true
				break
			}
		}
		sqlite3_finalize(cache_statement)
		if !found && !sqlite_execute(
			calendar_database,
			fmt.tprintf(
				"ALTER TABLE eventkit_search_cache ADD COLUMN %s %s;",
				column[0],
				column[1],
			),
		) {
			return false
		}
	}
	return sqlite_execute(
		calendar_database,
		fmt.tprintf("PRAGMA user_version=%d;", CALENDAR_SCHEMA_VERSION),
	)
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

calendar_connected_calendar_visible :: proc(identifier: string) -> bool {
	key := fmt.tprintf("eventkit_visible:%s", identifier)
	value, found := calendar_preference_get(key, context.temp_allocator)
	return !found || value != "0"
}

calendar_connected_calendar_set_visible :: proc(
	identifier: string,
	visible: bool,
) -> bool {
	return calendar_preference_set(
		fmt.tprintf("eventkit_visible:%s", identifier),
		visible ? "1" : "0",
	)
}

calendar_connected_default_calendar :: proc(
	allocator := context.allocator,
) -> (string, bool) {
	return calendar_preference_get("eventkit_default_calendar", allocator)
}

calendar_connected_set_default_calendar :: proc(identifier: string) -> bool {
	return calendar_preference_set("eventkit_default_calendar", identifier)
}

calendar_connected_alias_lookup :: proc(
	alias_key: string,
	allocator := context.allocator,
) -> (string, bool) {
	statement, prepared := sqlite_prepare(
		calendar_database,
		"SELECT opaque_id FROM eventkit_identity_aliases WHERE alias_key = ?;",
	)
	if !prepared {return "", false}
	defer sqlite3_finalize(statement)
	if !sqlite_bind_text_value(statement, 1, alias_key) {return "", false}
	if sqlite3_step(statement) != SQLITE_ROW {return "", false}
	return sqlite_column_string(statement, 0, allocator), true
}

calendar_connected_alias_set :: proc(alias_key, opaque_id: string) -> bool {
	if len(alias_key) == 0 || len(opaque_id) == 0 {return false}
	statement, prepared := sqlite_prepare(
		calendar_database,
		`INSERT INTO eventkit_identity_aliases(alias_key, opaque_id)
		 VALUES (?, ?)
		 ON CONFLICT(alias_key) DO UPDATE SET opaque_id = excluded.opaque_id;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite_bind_text_value(statement, 1, alias_key) &&
	       sqlite_bind_text_value(statement, 2, opaque_id) &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_connected_identity_keys :: proc(
	event: ^Calendar_Event,
) -> ([3]string, int) {
	keys: [3]string
	count := 0
	if len(event.external_identifier) > 0 {
		keys[count] = fmt.tprintf(
			"external:%s:%s",
			event.source_identifier,
			event.external_identifier,
		)
		count += 1
	}
	if len(event.calendar_item_identifier) > 0 {
		keys[count] = fmt.tprintf(
			"item:%s",
			event.calendar_item_identifier,
		)
		count += 1
	}
	if len(event.event_identifier) > 0 {
		keys[count] = fmt.tprintf("event:%s", event.event_identifier)
		count += 1
	}
	return keys, count
}

calendar_connected_resolve_opaque_id :: proc(
	event: ^Calendar_Event,
	allocator := context.allocator,
) -> (string, bool) {
	if event == nil || event.source != .EventKit {return "", false}
	keys, count := calendar_connected_identity_keys(event)
	if count == 0 {return "", false}
	opaque_id := ""
	for key in keys[:count] {
		if existing, found := calendar_connected_alias_lookup(key, allocator);
		   found {
			opaque_id = existing
			break
		}
	}
	if len(opaque_id) == 0 {
		sum := hash.fnv64a(transmute([]u8)keys[0])
		opaque_id = fmt.aprintf(
			"ek-%016x",
			sum,
			allocator = allocator,
		)
	}
	for key in keys[:count] {
		if !calendar_connected_alias_set(key, opaque_id) {
			delete(opaque_id, allocator)
			return "", false
		}
	}
	return opaque_id, true
}

calendar_connected_metadata_apply :: proc(event: ^Calendar_Event) {
	if event == nil || len(event.opaque_id) == 0 {return}
	statement, prepared := sqlite_prepare(
		calendar_database,
		`SELECT important, categories
		 FROM connected_event_metadata
		 WHERE opaque_id = ?;`,
	)
	if !prepared {return}
	defer sqlite3_finalize(statement)
	if !sqlite_bind_text_value(statement, 1, event.opaque_id) {return}
	if sqlite3_step(statement) != SQLITE_ROW {return}
	event.important = sqlite3_column_int(statement, 0) != 0
	delete(event.categories)
	event.categories = sqlite_column_string(statement, 1)
}

calendar_connected_metadata_set :: proc(
	opaque_id: string,
	important: bool,
	categories: string,
) -> bool {
	if len(opaque_id) == 0 {return false}
	statement, prepared := sqlite_prepare(
		calendar_database,
		`INSERT INTO connected_event_metadata(
			opaque_id, important, categories, updated_at_ms
		 ) VALUES (?, ?, ?, ?)
		 ON CONFLICT(opaque_id) DO UPDATE SET
			important = excluded.important,
			categories = excluded.categories,
			updated_at_ms = excluded.updated_at_ms;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	now_ms := time.to_unix_nanoseconds(time.now()) / 1_000_000
	return sqlite_bind_text_value(statement, 1, opaque_id) &&
	       sqlite3_bind_int(statement, 2, important ? 1 : 0) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 3, categories) &&
	       sqlite3_bind_int64(statement, 4, now_ms) == SQLITE_OK &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_connected_cache_event :: proc(event: ^Calendar_Event) -> bool {
	if event == nil || len(event.opaque_id) == 0 {return false}
	start, start_ok := ical_parse_date_time(event.dtstart)
	end, end_ok := ical_parse_date_time(event.dtend)
	if !start_ok {return false}
	if !end_ok {end = start}
	statement, prepared := sqlite_prepare(
		calendar_database,
		`INSERT INTO eventkit_search_cache(
			opaque_id, start_unix, end_unix, event_identifier,
			calendar_item_identifier, external_identifier, summary, description,
			location, url, calendar_identifier, source_identifier, source_title,
			calendar_title, writable, all_day, time_zone, alarms, alarm_offsets,
			organizer, attendees, participation_status, has_attendees, version,
			connected_recurring, connected_detached, status, rrule, last_seen_ms
		 ) VALUES (
			?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
			?, ?, ?, ?, ?, ?, ?, ?, ?
		 )
		 ON CONFLICT(opaque_id, start_unix) DO UPDATE SET
			end_unix = excluded.end_unix,
			event_identifier = excluded.event_identifier,
			calendar_item_identifier = excluded.calendar_item_identifier,
			external_identifier = excluded.external_identifier,
			summary = excluded.summary,
			description = excluded.description,
			location = excluded.location,
			url = excluded.url,
			calendar_identifier = excluded.calendar_identifier,
			source_identifier = excluded.source_identifier,
			source_title = excluded.source_title,
			calendar_title = excluded.calendar_title,
			writable = excluded.writable,
			all_day = excluded.all_day,
			time_zone = excluded.time_zone,
			alarms = excluded.alarms,
			alarm_offsets = excluded.alarm_offsets,
			organizer = excluded.organizer,
			attendees = excluded.attendees,
			participation_status = excluded.participation_status,
			has_attendees = excluded.has_attendees,
			connected_recurring = excluded.connected_recurring,
			connected_detached = excluded.connected_detached,
			status = excluded.status,
			rrule = excluded.rrule,
			version = excluded.version,
			last_seen_ms = excluded.last_seen_ms;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	now_ms := time.to_unix_nanoseconds(time.now()) / 1_000_000
	return sqlite_bind_text_value(statement, 1, event.opaque_id) &&
	       sqlite3_bind_int64(
			statement,
			2,
			ical_date_time_stamp(start),
	       ) == SQLITE_OK &&
	       sqlite3_bind_int64(
			statement,
			3,
			ical_date_time_stamp(end),
	       ) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 4, event.event_identifier) &&
	       sqlite_bind_text_value(
			statement,
			5,
			event.calendar_item_identifier,
	       ) &&
	       sqlite_bind_text_value(statement, 6, event.external_identifier) &&
	       sqlite_bind_text_value(statement, 7, event.summary) &&
	       sqlite_bind_text_value(statement, 8, event.description) &&
	       sqlite_bind_text_value(statement, 9, event.location) &&
	       sqlite_bind_text_value(statement, 10, event.url) &&
	       sqlite_bind_text_value(statement, 11, event.calendar_identifier) &&
	       sqlite_bind_text_value(statement, 12, event.source_identifier) &&
	       sqlite_bind_text_value(statement, 13, event.source_title) &&
	       sqlite_bind_text_value(statement, 14, event.calendar_title) &&
	       sqlite3_bind_int(statement, 15, event.writable ? 1 : 0) == SQLITE_OK &&
	       sqlite3_bind_int(statement, 16, event.all_day ? 1 : 0) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 17, event.time_zone) &&
	       sqlite_bind_text_value(statement, 18, event.alarms) &&
	       sqlite_bind_text_value(statement, 19, event.alarm_offsets) &&
	       sqlite_bind_text_value(statement, 20, event.organizer) &&
	       sqlite_bind_text_value(statement, 21, event.attendees) &&
	       sqlite_bind_text_value(statement, 22, event.participation_status) &&
	       sqlite3_bind_int(
			statement,
			23,
			event.has_attendees ? 1 : 0,
	       ) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 24, event.version) &&
	       sqlite3_bind_int(
			statement,
			25,
			event.connected_recurring ? 1 : 0,
	       ) == SQLITE_OK &&
	       sqlite3_bind_int(
			statement,
			26,
			event.connected_detached ? 1 : 0,
	       ) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 27, event.status) &&
	       sqlite_bind_text_value(statement, 28, event.rrule) &&
	       sqlite3_bind_int64(statement, 29, now_ms) == SQLITE_OK &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_connected_cached_events_load :: proc(
	allocator := context.allocator,
) -> ([dynamic]Calendar_Event, bool) {
	events := make([dynamic]Calendar_Event, allocator)
	statement, prepared := sqlite_prepare(
		calendar_database,
		`SELECT opaque_id, start_unix, end_unix, event_identifier,
		        calendar_item_identifier, external_identifier, summary,
		        description, location, url, calendar_identifier,
		        source_identifier, source_title, calendar_title, writable,
		        all_day, time_zone, alarms, alarm_offsets, organizer,
		        attendees, participation_status, has_attendees, version,
		        connected_recurring, connected_detached, status, rrule
		 FROM eventkit_search_cache
		 ORDER BY start_unix, opaque_id;`,
	)
	if !prepared {return events, false}
	defer sqlite3_finalize(statement)
	for {
		step := sqlite3_step(statement)
		if step == SQLITE_DONE {break}
		if step != SQLITE_ROW {
			calendar_events_destroy(&events)
			return nil, false
		}
		start_unix := sqlite3_column_int64(statement, 1)
		end_unix := sqlite3_column_int64(statement, 2)
		all_day := sqlite3_column_int(statement, 15) != 0
		append(&events, Calendar_Event{
			source = .EventKit,
			opaque_id = sqlite_column_string(statement, 0, allocator),
			event_identifier = sqlite_column_string(statement, 3, allocator),
			calendar_item_identifier = sqlite_column_string(
				statement,
				4,
				allocator,
			),
			external_identifier = sqlite_column_string(
				statement,
				5,
				allocator,
			),
			summary = sqlite_column_string(statement, 6, allocator),
			description = sqlite_column_string(statement, 7, allocator),
			location = sqlite_column_string(statement, 8, allocator),
			url = sqlite_column_string(statement, 9, allocator),
			calendar_identifier = sqlite_column_string(
				statement,
				10,
				allocator,
			),
			source_identifier = sqlite_column_string(statement, 11, allocator),
			source_title = sqlite_column_string(statement, 12, allocator),
			calendar_title = sqlite_column_string(statement, 13, allocator),
			writable = sqlite3_column_int(statement, 14) != 0,
			all_day = all_day,
			time_zone = sqlite_column_string(statement, 16, allocator),
			alarms = sqlite_column_string(statement, 17, allocator),
			alarm_offsets = sqlite_column_string(statement, 18, allocator),
			organizer = sqlite_column_string(statement, 19, allocator),
			attendees = sqlite_column_string(statement, 20, allocator),
			participation_status = sqlite_column_string(
				statement,
				21,
				allocator,
			),
			has_attendees = sqlite3_column_int(statement, 22) != 0,
			version = sqlite_column_string(statement, 23, allocator),
			connected_recurring = sqlite3_column_int(statement, 24) != 0,
			connected_detached = sqlite3_column_int(statement, 25) != 0,
			status = sqlite_column_string(statement, 26, allocator),
			rrule = sqlite_column_string(statement, 27, allocator),
			uid = sqlite_column_string(statement, 0, allocator),
			dtstart = ical_format_date_time(
				ical_date_time_from_stamp(start_unix, all_day),
				allocator,
			),
			dtend = ical_format_date_time(
				ical_date_time_from_stamp(end_unix, all_day),
				allocator,
			),
		})
		calendar_connected_metadata_apply(&events[len(events)-1])
	}
	return events, true
}

calendar_connected_cache_window :: proc(start_unix, end_unix: i64) -> bool {
	statement, prepared := sqlite_prepare(
		calendar_database,
		`INSERT INTO eventkit_search_windows(
			start_unix, end_unix, refreshed_at_ms
		 ) VALUES (?, ?, ?)
		 ON CONFLICT(start_unix, end_unix) DO UPDATE SET
			refreshed_at_ms = excluded.refreshed_at_ms;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	now_ms := time.to_unix_nanoseconds(time.now()) / 1_000_000
	return sqlite3_bind_int64(statement, 1, start_unix) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 2, end_unix) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 3, now_ms) == SQLITE_OK &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_connected_cache_clear_window :: proc(
	start_unix, end_unix: i64,
) -> bool {
	statement, prepared := sqlite_prepare(
		calendar_database,
		`DELETE FROM eventkit_search_cache
		 WHERE start_unix >= ? AND start_unix < ?;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite3_bind_int64(statement, 1, start_unix) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 2, end_unix) == SQLITE_OK &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_connected_cache_covers :: proc(
	start_unix, end_unix: i64,
) -> bool {
	statement, prepared := sqlite_prepare(
		calendar_database,
		`SELECT 1
		 FROM eventkit_search_windows
		 WHERE start_unix <= ? AND end_unix >= ?
		 LIMIT 1;`,
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite3_bind_int64(statement, 1, start_unix) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 2, end_unix) == SQLITE_OK &&
	       sqlite3_step(statement) == SQLITE_ROW
}

calendar_component_string :: proc(
	component: ^ICal_Component,
	allocator := context.allocator,
) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	ical_serialize_component(&builder, component)
	return strings.to_string(builder)
}

calendar_property_value :: proc(component: ^ICal_Component, name: string) -> string {
	property := ical_component_property(component, name)
	if property == nil {return ""}
	return property.value
}

calendar_project_event :: proc(
	document_id: i64,
	component: ^ICal_Component,
) -> bool {
	statement, prepared := sqlite_prepare(calendar_database, `
		INSERT INTO events (
			document_id, uid, recurrence_id, summary, description, location,
			url, categories, important, status, dtstart, dtend, rrule, raw_component,
			sequence, last_modified, dtstamp
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(uid, recurrence_id) DO UPDATE SET
			document_id=excluded.document_id,
			summary=excluded.summary,
			description=excluded.description,
			location=excluded.location,
			url=excluded.url,
			categories=excluded.categories,
			important=excluded.important,
			status=excluded.status,
			dtstart=excluded.dtstart,
			dtend=excluded.dtend,
			rrule=excluded.rrule,
			raw_component=excluded.raw_component,
			sequence=excluded.sequence,
			last_modified=excluded.last_modified,
			dtstamp=excluded.dtstamp
		WHERE excluded.sequence > events.sequence
		   OR (
				excluded.sequence = events.sequence AND
				excluded.dtstamp > events.dtstamp
		   )
		   OR (
				excluded.sequence = events.sequence AND
				excluded.dtstamp = events.dtstamp AND
				excluded.last_modified > events.last_modified
		   );
	`)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	raw := calendar_component_string(component, context.temp_allocator)
	sequence := 0
	if value := calendar_property_value(component, "SEQUENCE"); len(value) > 0 {
		sequence, _ = ical_parse_int(value)
	}
	important := strings.to_upper(
		calendar_property_value(component, "X-HW-IMPORTANT"),
		context.temp_allocator,
	) == "TRUE"
	values := [12]string{
		calendar_property_value(component, "UID"),
		calendar_property_value(component, "RECURRENCE-ID"),
		ical_unescape_text(calendar_property_value(component, "SUMMARY"), context.temp_allocator),
		ical_unescape_text(calendar_property_value(component, "DESCRIPTION"), context.temp_allocator),
		ical_unescape_text(calendar_property_value(component, "LOCATION"), context.temp_allocator),
		calendar_property_value(component, "URL"),
		ical_unescape_text(calendar_property_value(component, "CATEGORIES"), context.temp_allocator),
		calendar_property_value(component, "STATUS"),
		calendar_property_value(component, "DTSTART"),
		calendar_property_value(component, "DTEND"),
		calendar_property_value(component, "RRULE"),
		raw,
	}
	if sqlite3_bind_int64(statement, 1, document_id) != SQLITE_OK {return false}
	for value, index in values {
		bind_index := index + 2
		if index >= 7 {bind_index += 1}
		if !sqlite_bind_text_value(statement, bind_index, value) {return false}
	}
	if sqlite3_bind_int(statement, 9, important ? 1 : 0) != SQLITE_OK ||
	   sqlite3_bind_int(statement, 15, i32(sequence)) != SQLITE_OK ||
	   !sqlite_bind_text_value(
			statement,
			16,
			calendar_property_value(component, "LAST-MODIFIED"),
		) ||
	   !sqlite_bind_text_value(
			statement,
			17,
			calendar_property_value(component, "DTSTAMP"),
		) {
		return false
	}
	return sqlite3_step(statement) == SQLITE_DONE
}

calendar_project_components :: proc(
	document_id: i64,
	component: ^ICal_Component,
) -> bool {
	if component.name == "VEVENT" {
		if len(calendar_property_value(component, "UID")) == 0 {return false}
		if !calendar_project_event(document_id, component) {return false}
	}
	for &child in component.children {
		if !calendar_project_components(document_id, &child) {return false}
	}
	return true
}

calendar_import_document :: proc(document: ^ICal_Document) -> (i64, bool) {
	if document == nil || calendar_database == nil {return 0, false}
	if !sqlite_execute(calendar_database, "BEGIN IMMEDIATE;") {return 0, false}
	committed := false
	defer {
		if !committed {_ = sqlite_execute(calendar_database, "ROLLBACK;")}
	}
	statement, prepared := sqlite_prepare(
		calendar_database,
		"INSERT INTO documents(source, imported_at_ms, diagnostic_count) VALUES (?, ?, ?);",
	)
	if !prepared {return 0, false}
	now_ms := time.to_unix_nanoseconds(time.now()) / 1_000_000
	bound := sqlite_bind_text_value(statement, 1, document.source) &&
	         sqlite3_bind_int64(statement, 2, now_ms) == SQLITE_OK &&
	         sqlite3_bind_int(statement, 3, i32(len(document.diagnostics))) == SQLITE_OK
	inserted := bound && sqlite3_step(statement) == SQLITE_DONE
	sqlite3_finalize(statement)
	if !inserted {return 0, false}
	document_id := sqlite3_last_insert_rowid(calendar_database)
	for &component in document.components {
		if !calendar_project_components(document_id, &component) {return 0, false}
	}
	if !sqlite_execute(calendar_database, "COMMIT;") {return 0, false}
	committed = true
	return document_id, true
}

calendar_events_load :: proc(
	allocator := context.allocator,
) -> ([dynamic]Calendar_Event, bool) {
	events := make([dynamic]Calendar_Event, allocator)
	statement, prepared := sqlite_prepare(calendar_database, `
		SELECT id, document_id, uid, recurrence_id, summary, description,
		       location, url, categories, important, archived, status, dtstart,
		       dtend, rrule, raw_component, sequence, last_modified, dtstamp
		FROM events
		ORDER BY dtstart, uid, recurrence_id;
	`)
	if !prepared {return events, false}
	defer sqlite3_finalize(statement)
	for {
		step := sqlite3_step(statement)
		if step == SQLITE_DONE {break}
		if step != SQLITE_ROW {
			calendar_events_destroy(&events)
			return nil, false
		}
		append(&events, Calendar_Event{
			row_id = sqlite3_column_int64(statement, 0),
			document_id = sqlite3_column_int64(statement, 1),
			uid = sqlite_column_string(statement, 2, allocator),
			recurrence_id = sqlite_column_string(statement, 3, allocator),
			summary = sqlite_column_string(statement, 4, allocator),
			description = sqlite_column_string(statement, 5, allocator),
			location = sqlite_column_string(statement, 6, allocator),
			url = sqlite_column_string(statement, 7, allocator),
			categories = sqlite_column_string(statement, 8, allocator),
			important = sqlite3_column_int(statement, 9) != 0,
			archived = sqlite3_column_int(statement, 10) != 0,
			status = sqlite_column_string(statement, 11, allocator),
			dtstart = sqlite_column_string(statement, 12, allocator),
			dtend = sqlite_column_string(statement, 13, allocator),
			rrule = sqlite_column_string(statement, 14, allocator),
			raw_component = sqlite_column_string(statement, 15, allocator),
			sequence = int(sqlite3_column_int(statement, 16)),
			last_modified = sqlite_column_string(statement, 17, allocator),
			dtstamp = sqlite_column_string(statement, 18, allocator),
		})
	}
	return events, true
}

calendar_event_set_archived :: proc(row_id: i64, archived: bool) -> bool {
	statement, prepared := sqlite_prepare(
		calendar_database,
		"UPDATE events SET archived=? WHERE id=?;",
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int(statement, 1, archived ? 1 : 0) != SQLITE_OK ||
	   sqlite3_bind_int64(statement, 2, row_id) != SQLITE_OK {
		return false
	}
	return sqlite3_step(statement) == SQLITE_DONE &&
	       sqlite3_changes(calendar_database) == 1
}

calendar_event_series_set_archived :: proc(uid: string, archived: bool) -> bool {
	statement, prepared := sqlite_prepare(
		calendar_database,
		"UPDATE events SET archived=? WHERE uid=?;",
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int(statement, 1, archived ? 1 : 0) != SQLITE_OK ||
	   !sqlite_bind_text_value(statement, 2, uid) {
		return false
	}
	return sqlite3_step(statement) == SQLITE_DONE &&
	       sqlite3_changes(calendar_database) > 0
}

calendar_event_identity_set_archived :: proc(
	uid, recurrence_id: string,
	archived: bool,
) -> bool {
	statement, prepared := sqlite_prepare(
		calendar_database,
		"UPDATE events SET archived=? WHERE uid=? AND recurrence_id=?;",
	)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int(statement, 1, archived ? 1 : 0) != SQLITE_OK ||
	   !sqlite_bind_text_value(statement, 2, uid) ||
	   !sqlite_bind_text_value(statement, 3, recurrence_id) {
		return false
	}
	return sqlite3_step(statement) == SQLITE_DONE &&
	       sqlite3_changes(calendar_database) == 1
}

calendar_export_all :: proc(allocator := context.allocator) -> (string, bool) {
	statement, prepared := sqlite_prepare(
		calendar_database,
		"SELECT source FROM documents ORDER BY id;",
	)
	if !prepared {return "", false}
	defer sqlite3_finalize(statement)
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	found := false
	for {
		step := sqlite3_step(statement)
		if step == SQLITE_DONE {break}
		if step != SQLITE_ROW {return "", false}
		value := sqlite3_column_text(statement, 0)
		if value != nil {
			strings.write_string(&builder, string(value))
			if !strings.has_suffix(string(value), "\n") {
				strings.write_string(&builder, "\r\n")
			}
			found = true
		}
	}
	if !found {
		strings.write_string(
			&builder,
			"BEGIN:VCALENDAR\r\nPRODID:-//Hal Wayland//hw_calendar 0.1//EN\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nEND:VCALENDAR\r\n",
		)
	}
	return strings.to_string(builder), true
}
