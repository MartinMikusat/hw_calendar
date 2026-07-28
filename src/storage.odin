package main

import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:strings"
import "core:time"

CALENDAR_SCHEMA_VERSION :: 2

calendar_database: ^SQLite_DB

Calendar_Event :: struct {
	row_id: i64,
	document_id: i64,
	uid: string,
	recurrence_id: string,
	summary: string,
	description: string,
	location: string,
	url: string,
	categories: string,
	important: bool,
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
	return fmt.tprintf("%s/Library/Application Support/HWCalendar", home)
}

calendar_database_path :: proc() -> string {
	return fmt.tprintf("%s/calendar.sqlite3", calendar_support_dir())
}

calendar_database_open :: proc() -> bool {
	if calendar_database != nil {return true}
	support := calendar_support_dir()
	if os2.make_directory(support) != nil && !os.exists(support) {return false}
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

calendar_database_close :: proc() {
	if calendar_database != nil {sqlite3_close(calendar_database)}
	calendar_database = nil
}

calendar_database_create_schema :: proc() -> bool {
	if calendar_database == nil {return false}
	if !sqlite_execute(calendar_database, "PRAGMA journal_mode=WAL;") ||
	   !sqlite_execute(calendar_database, "PRAGMA foreign_keys=ON;") ||
	   !sqlite_execute(calendar_database, `
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
		`) {
		return false
	}
	has_dtstamp := false
	statement, prepared := sqlite_prepare(
		calendar_database,
		"PRAGMA table_info(events);",
	)
	if !prepared {return false}
	for sqlite3_step(statement) == SQLITE_ROW {
		name := sqlite3_column_text(statement, 1)
		if name != nil && string(name) == "dtstamp" {
			has_dtstamp = true
			break
		}
	}
	sqlite3_finalize(statement)
	if !has_dtstamp && !sqlite_execute(
		calendar_database,
		"ALTER TABLE events ADD COLUMN dtstamp TEXT NOT NULL DEFAULT '';",
	) {
		return false
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
		       location, url, categories, important, status, dtstart, dtend, rrule,
		       raw_component, sequence, last_modified, dtstamp
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
			status = sqlite_column_string(statement, 10, allocator),
			dtstart = sqlite_column_string(statement, 11, allocator),
			dtend = sqlite_column_string(statement, 12, allocator),
			rrule = sqlite_column_string(statement, 13, allocator),
			raw_component = sqlite_column_string(statement, 14, allocator),
			sequence = int(sqlite3_column_int(statement, 15)),
			last_modified = sqlite_column_string(statement, 16, allocator),
			dtstamp = sqlite_column_string(statement, 17, allocator),
		})
	}
	return events, true
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
			"BEGIN:VCALENDAR\r\nPRODID:-//Hal Wayland//HW Calendar 0.1//EN\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nEND:VCALENDAR\r\n",
		)
	}
	return strings.to_string(builder), true
}
