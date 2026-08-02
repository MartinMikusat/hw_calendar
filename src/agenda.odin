package main

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"

Agenda_Entry :: struct {
	id: i64,
	original_text: string,
	start_at: string,
	end_at: string,
	due_at: string,
	location: string,
	source_url: string,
	reminder_at: string,
	recurrence_seconds: i64,
	state: string,
	revision: int,
	created_at_ms: i64,
	updated_at_ms: i64,
}

Agenda_Entry_Input :: struct {
	schema_version: int `json:"schema_version"`,
	original_text: string `json:"original_text"`,
	start_at: string `json:"start_at"`,
	end_at: string `json:"end_at"`,
	due_at: string `json:"due_at"`,
	location: string,
	source_url: string `json:"source_url"`,
	reminder_at: string `json:"reminder_at"`,
	recurrence_seconds: i64 `json:"recurrence_seconds"`,
}

Agenda_Proposal_Fields :: struct {
	start_at: string,
	end_at: string,
	due_at: string,
	location: string,
	source_url: string,
	reminder_at: string,
	recurrence_seconds: i64,
}

Agenda_Proposal_Input :: struct {
	schema_version: int `json:"schema_version"`,
	entry_id: i64 `json:"entry_id"`,
	source_revision: int `json:"source_revision"`,
	fields: Agenda_Proposal_Fields,
	uncertainty: string,
}

Agenda_Proposal :: struct {
	id: i64,
	entry_id: i64,
	source_revision: int,
	fields: Agenda_Proposal_Fields,
	uncertainty: string,
	state: string,
	created_at_ms: i64,
}

agenda_entry_destroy :: proc(entry: ^Agenda_Entry, allocator := context.allocator) {
	if entry == nil {return}
	delete(entry.original_text, allocator)
	delete(entry.start_at, allocator)
	delete(entry.end_at, allocator)
	delete(entry.due_at, allocator)
	delete(entry.location, allocator)
	delete(entry.source_url, allocator)
	delete(entry.reminder_at, allocator)
	delete(entry.state, allocator)
	entry^ = {}
}

agenda_entries_destroy :: proc(entries: ^[dynamic]Agenda_Entry) {
	for &entry in entries^ {agenda_entry_destroy(&entry)}
	delete(entries^)
	entries^ = nil
}

agenda_now_ms :: proc() -> i64 {
	return time.to_unix_nanoseconds(time.now()) / 1_000_000
}

agenda_state_valid :: proc(state: string) -> bool {
	return state == "active" || state == "completed" || state == "dismissed"
}

agenda_input_valid :: proc(input: ^Agenda_Entry_Input) -> bool {
	if input == nil || input.schema_version != 1 ||
	   len(strings.trim_space(input.original_text)) == 0 ||
	   input.recurrence_seconds < 0 {
		return false
	}
	if len(input.end_at) > 0 && len(input.start_at) == 0 {return false}
	if input.recurrence_seconds > 0 && len(input.due_at) == 0 {return false}
	timestamps := [4]string{input.start_at, input.end_at, input.due_at, input.reminder_at}
	for value in timestamps {
		if len(value) > 0 {if _, ok := strconv.parse_i64(value); !ok {return false}}
	}
	return true
}

agenda_entry_from_statement :: proc(
	statement: ^SQLite_Statement,
	allocator := context.allocator,
) -> Agenda_Entry {
	return {
		id = sqlite3_column_int64(statement, 0),
		original_text = sqlite_column_string(statement, 1, allocator),
		start_at = sqlite_column_string(statement, 2, allocator),
		end_at = sqlite_column_string(statement, 3, allocator),
		due_at = sqlite_column_string(statement, 4, allocator),
		location = sqlite_column_string(statement, 5, allocator),
		source_url = sqlite_column_string(statement, 6, allocator),
		reminder_at = sqlite_column_string(statement, 7, allocator),
		recurrence_seconds = sqlite3_column_int64(statement, 8),
		state = sqlite_column_string(statement, 9, allocator),
		revision = int(sqlite3_column_int(statement, 10)),
		created_at_ms = sqlite3_column_int64(statement, 11),
		updated_at_ms = sqlite3_column_int64(statement, 12),
	}
}

AGENDA_ENTRY_SELECT :: `SELECT id, original_text, start_at, end_at, due_at,
	location, source_url, reminder_at, recurrence_seconds, state, revision,
	created_at_ms, updated_at_ms FROM agenda_entries`

agenda_entry_get :: proc(id: i64, allocator := context.allocator) -> (Agenda_Entry, bool) {
	statement, prepared := sqlite_prepare(calendar_database, AGENDA_ENTRY_SELECT+" WHERE id = ?;")
	if !prepared {return {}, false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int64(statement, 1, id) != SQLITE_OK ||
	   sqlite3_step(statement) != SQLITE_ROW {return {}, false}
	return agenda_entry_from_statement(statement, allocator), true
}

agenda_entry_create :: proc(input: ^Agenda_Entry_Input) -> (Agenda_Entry, bool) {
	if !agenda_input_valid(input) {return {}, false}
	statement, prepared := sqlite_prepare(calendar_database, `INSERT INTO agenda_entries
		(original_text, start_at, end_at, due_at, location, source_url, reminder_at,
		 recurrence_seconds, state, revision, created_at_ms, updated_at_ms)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', 1, ?, ?);`)
	if !prepared {return {}, false}
	defer sqlite3_finalize(statement)
	now := agenda_now_ms()
	ok := sqlite_bind_text_value(statement, 1, strings.trim_space(input.original_text)) &&
	      sqlite_bind_text_value(statement, 2, input.start_at) &&
	      sqlite_bind_text_value(statement, 3, input.end_at) &&
	      sqlite_bind_text_value(statement, 4, input.due_at) &&
	      sqlite_bind_text_value(statement, 5, input.location) &&
	      sqlite_bind_text_value(statement, 6, input.source_url) &&
	      sqlite_bind_text_value(statement, 7, input.reminder_at) &&
	      sqlite3_bind_int64(statement, 8, input.recurrence_seconds) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 9, now) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 10, now) == SQLITE_OK &&
	      sqlite3_step(statement) == SQLITE_DONE
	if !ok {return {}, false}
	return agenda_entry_get(sqlite3_last_insert_rowid(calendar_database))
}

agenda_entry_update :: proc(id: i64, expected_revision: int, input: ^Agenda_Entry_Input) -> (Agenda_Entry, string) {
	if !agenda_input_valid(input) {return {}, "invalid_entry"}
	statement, prepared := sqlite_prepare(calendar_database, `UPDATE agenda_entries SET
		original_text=?, start_at=?, end_at=?, due_at=?, location=?, source_url=?,
		reminder_at=?, recurrence_seconds=?, revision=revision+1, updated_at_ms=?
		WHERE id=? AND revision=?;`)
	if !prepared {return {}, "storage_failed"}
	defer sqlite3_finalize(statement)
	ok := sqlite_bind_text_value(statement, 1, strings.trim_space(input.original_text)) &&
	      sqlite_bind_text_value(statement, 2, input.start_at) &&
	      sqlite_bind_text_value(statement, 3, input.end_at) &&
	      sqlite_bind_text_value(statement, 4, input.due_at) &&
	      sqlite_bind_text_value(statement, 5, input.location) &&
	      sqlite_bind_text_value(statement, 6, input.source_url) &&
	      sqlite_bind_text_value(statement, 7, input.reminder_at) &&
	      sqlite3_bind_int64(statement, 8, input.recurrence_seconds) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 9, agenda_now_ms()) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 10, id) == SQLITE_OK &&
	      sqlite3_bind_int(statement, 11, i32(expected_revision)) == SQLITE_OK &&
	      sqlite3_step(statement) == SQLITE_DONE
	if !ok {return {}, "storage_failed"}
	if sqlite3_changes(calendar_database) == 0 {return {}, "revision_conflict"}
	entry, found := agenda_entry_get(id)
	if !found {return {}, "storage_failed"}
	return entry, ""
}

agenda_entries_list :: proc(from, to, query: string, allocator := context.allocator) -> [dynamic]Agenda_Entry {
	result := make([dynamic]Agenda_Entry, allocator)
	statement, prepared := sqlite_prepare(calendar_database, AGENDA_ENTRY_SELECT+
		` WHERE (? = '' OR start_at = '' OR start_at >= ? OR due_at >= ?)
		AND (? = '' OR start_at = '' OR start_at < ? OR due_at < ?)
		AND (? = '' OR original_text LIKE '%' || ? || '%' OR location LIKE '%' || ? || '%')
		ORDER BY CASE WHEN due_at != '' THEN due_at WHEN start_at != '' THEN start_at ELSE '9999' END, id;`)
	if !prepared {return result}
	defer sqlite3_finalize(statement)
	values := [9]string{from, from, from, to, to, to, query, query, query}
	for value, index in values {if !sqlite_bind_text_value(statement, index+1, value) {return result}}
	for sqlite3_step(statement) == SQLITE_ROW {append(&result, agenda_entry_from_statement(statement, allocator))}
	return result
}

agenda_due_entries :: proc(now_unix: i64, allocator := context.allocator) -> [dynamic]Agenda_Entry {
	result := make([dynamic]Agenda_Entry, allocator)
	statement, prepared := sqlite_prepare(calendar_database, AGENDA_ENTRY_SELECT+
		` WHERE state='active' AND recurrence_seconds > 0 AND due_at != ''
		AND CAST(due_at AS INTEGER) <= ?
		ORDER BY CAST(due_at AS INTEGER), id;`)
	if !prepared {return result}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int64(statement, 1, now_unix) != SQLITE_OK {return result}
	for sqlite3_step(statement) == SQLITE_ROW {append(&result, agenda_entry_from_statement(statement, allocator))}
	return result
}

agenda_chore_complete_at :: proc(
	id: i64,
	expected_revision: int,
	now_unix: i64,
) -> (Agenda_Entry, string) {
	entry, found := agenda_entry_get(id, context.temp_allocator)
	if !found {return {}, "not_found"}
	defer agenda_entry_destroy(&entry, context.temp_allocator)
	if entry.revision != expected_revision {return {}, "revision_conflict"}
	if entry.state != "active" || entry.recurrence_seconds <= 0 {
		return {}, "not_chore"
	}
	due_at, parsed := strconv.parse_i64(entry.due_at)
	if !parsed || due_at > now_unix {return {}, "not_due"}
	return agenda_entry_set_state(id, expected_revision, "completed")
}

agenda_entry_set_state :: proc(id: i64, expected_revision: int, state: string) -> (Agenda_Entry, string) {
	if !agenda_state_valid(state) {return {}, "invalid_state"}
	if state == "completed" {
		if !sqlite_execute(calendar_database, "BEGIN IMMEDIATE;") {return {}, "storage_failed"}
		entry, found := agenda_entry_get(id, context.temp_allocator)
		if !found || entry.revision != expected_revision {
		agenda_entry_destroy(&entry, context.temp_allocator)
			_ = sqlite_execute(calendar_database, "ROLLBACK;")
			return {}, "revision_conflict"
		}
		defer agenda_entry_destroy(&entry, context.temp_allocator)
		history, ready := sqlite_prepare(calendar_database, `INSERT INTO agenda_completion_history
			(entry_id, completed_at, previous_due_at) VALUES (?, ?, ?);`)
		if !ready {_ = sqlite_execute(calendar_database, "ROLLBACK;"); return {}, "storage_failed"}
		now_seconds := time.to_unix_seconds(time.now())
		now_text := fmt.tprintf("%d", now_seconds)
		ok := sqlite3_bind_int64(history, 1, id) == SQLITE_OK &&
		      sqlite_bind_text_value(history, 2, now_text) &&
		      sqlite_bind_text_value(history, 3, entry.due_at) &&
		      sqlite3_step(history) == SQLITE_DONE
		sqlite3_finalize(history)
		if !ok {_ = sqlite_execute(calendar_database, "ROLLBACK;"); return {}, "storage_failed"}
		if entry.recurrence_seconds > 0 {
			next_due := fmt.tprintf("%d", now_seconds+entry.recurrence_seconds)
			statement, ready := sqlite_prepare(calendar_database, `UPDATE agenda_entries SET
				due_at=?, state='active', revision=revision+1, updated_at_ms=? WHERE id=? AND revision=?;`)
			if ready {
				ok = sqlite_bind_text_value(statement, 1, next_due) &&
				     sqlite3_bind_int64(statement, 2, agenda_now_ms()) == SQLITE_OK &&
				     sqlite3_bind_int64(statement, 3, id) == SQLITE_OK &&
				     sqlite3_bind_int(statement, 4, i32(expected_revision)) == SQLITE_OK &&
				     sqlite3_step(statement) == SQLITE_DONE
				sqlite3_finalize(statement)
			}
		} else {
			statement, ready := sqlite_prepare(calendar_database, `UPDATE agenda_entries SET
				state='completed', revision=revision+1, updated_at_ms=? WHERE id=? AND revision=?;`)
			if ready {
				ok = sqlite3_bind_int64(statement, 1, agenda_now_ms()) == SQLITE_OK &&
				     sqlite3_bind_int64(statement, 2, id) == SQLITE_OK &&
				     sqlite3_bind_int(statement, 3, i32(expected_revision)) == SQLITE_OK &&
				     sqlite3_step(statement) == SQLITE_DONE
				sqlite3_finalize(statement)
			} else {ok = false}
		}
		if !ok {_ = sqlite_execute(calendar_database, "ROLLBACK;"); return {}, "storage_failed"}
		if sqlite3_changes(calendar_database) == 0 {_ = sqlite_execute(calendar_database, "ROLLBACK;"); return {}, "revision_conflict"}
		if !sqlite_execute(calendar_database, "COMMIT;") {return {}, "storage_failed"}
		result, result_found := agenda_entry_get(id)
		if !result_found {return {}, "storage_failed"}
		return result, ""
	}
	statement, prepared := sqlite_prepare(calendar_database, `UPDATE agenda_entries SET state=?,
		revision=revision+1, updated_at_ms=? WHERE id=? AND revision=?;`)
	if !prepared {return {}, "storage_failed"}
	defer sqlite3_finalize(statement)
	ok := sqlite_bind_text_value(statement, 1, state) &&
	      sqlite3_bind_int64(statement, 2, agenda_now_ms()) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 3, id) == SQLITE_OK &&
	      sqlite3_bind_int(statement, 4, i32(expected_revision)) == SQLITE_OK &&
	      sqlite3_step(statement) == SQLITE_DONE
	if !ok {return {}, "storage_failed"}
	if sqlite3_changes(calendar_database) == 0 {return {}, "revision_conflict"}
	entry, found := agenda_entry_get(id)
	if !found {return {}, "storage_failed"}
	return entry, ""
}

agenda_proposal_submit :: proc(input: ^Agenda_Proposal_Input) -> (Agenda_Proposal, string) {
	if input == nil || input.schema_version != 1 || input.entry_id <= 0 || input.source_revision <= 0 || input.fields.recurrence_seconds < 0 {
		return {}, "invalid_proposal"
	}
	if input.fields.recurrence_seconds > 0 && len(input.fields.due_at) == 0 {return {}, "invalid_proposal"}
	timestamps := [4]string{input.fields.start_at, input.fields.end_at, input.fields.due_at, input.fields.reminder_at}
	for value in timestamps {
		if len(value) > 0 {if _, ok := strconv.parse_i64(value); !ok {return {}, "invalid_proposal"}}
	}
	entry, found := agenda_entry_get(input.entry_id, context.temp_allocator)
	if !found {return {}, "not_found"}
	defer agenda_entry_destroy(&entry, context.temp_allocator)
	if entry.revision != input.source_revision {return {}, "revision_conflict"}
	bytes, error := json.marshal(input.fields)
	if error != nil {return {}, "invalid_proposal"}
	defer delete(bytes)
	statement, prepared := sqlite_prepare(calendar_database, `INSERT INTO agenda_proposals
		(entry_id, source_revision, fields_json, uncertainty, state, created_at_ms)
		VALUES (?, ?, ?, ?, 'pending', ?);`)
	if !prepared {return {}, "storage_failed"}
	defer sqlite3_finalize(statement)
	ok := sqlite3_bind_int64(statement, 1, input.entry_id) == SQLITE_OK &&
	      sqlite3_bind_int(statement, 2, i32(input.source_revision)) == SQLITE_OK &&
	      sqlite_bind_text_value(statement, 3, string(bytes)) &&
	      sqlite_bind_text_value(statement, 4, input.uncertainty) &&
	      sqlite3_bind_int64(statement, 5, agenda_now_ms()) == SQLITE_OK &&
	      sqlite3_step(statement) == SQLITE_DONE
	if !ok {return {}, "storage_failed"}
	return {id=sqlite3_last_insert_rowid(calendar_database), entry_id=input.entry_id,
		source_revision=input.source_revision, fields=input.fields,
		uncertainty=strings.clone(input.uncertainty), state=strings.clone("pending"),
		created_at_ms=agenda_now_ms()}, ""
}

agenda_proposal_destroy :: proc(proposal: ^Agenda_Proposal, allocator := context.allocator) {
	if proposal == nil {return}
	delete(proposal.fields.start_at, allocator)
	delete(proposal.fields.end_at, allocator)
	delete(proposal.fields.due_at, allocator)
	delete(proposal.fields.location, allocator)
	delete(proposal.fields.source_url, allocator)
	delete(proposal.fields.reminder_at, allocator)
	delete(proposal.uncertainty, allocator)
	delete(proposal.state, allocator)
	proposal^ = {}
}

agenda_proposal_get :: proc(id: i64, allocator := context.allocator) -> (Agenda_Proposal, bool) {
	statement, prepared := sqlite_prepare(calendar_database, `SELECT id, entry_id,
		source_revision, fields_json, uncertainty, state, created_at_ms
		FROM agenda_proposals WHERE id=?;`)
	if !prepared {return {}, false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int64(statement, 1, id) != SQLITE_OK ||
	   sqlite3_step(statement) != SQLITE_ROW {return {}, false}
	proposal := Agenda_Proposal{
		id = sqlite3_column_int64(statement, 0),
		entry_id = sqlite3_column_int64(statement, 1),
		source_revision = int(sqlite3_column_int(statement, 2)),
		uncertainty = sqlite_column_string(statement, 4, allocator),
		state = sqlite_column_string(statement, 5, allocator),
		created_at_ms = sqlite3_column_int64(statement, 6),
	}
	fields_json := sqlite_column_string(statement, 3, context.temp_allocator)
	if error := json.unmarshal(transmute([]u8)fields_json, &proposal.fields);
	   error != nil {
		agenda_proposal_destroy(&proposal, allocator)
		return {}, false
	}
	return proposal, true
}

agenda_proposal_pending_for_entry :: proc(entry_id: i64, allocator := context.allocator) -> (Agenda_Proposal, bool) {
	statement, prepared := sqlite_prepare(calendar_database, `SELECT id FROM agenda_proposals
		WHERE entry_id=? AND state='pending' ORDER BY id DESC LIMIT 1;`)
	if !prepared {return {}, false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int64(statement, 1, entry_id) != SQLITE_OK ||
	   sqlite3_step(statement) != SQLITE_ROW {return {}, false}
	return agenda_proposal_get(sqlite3_column_int64(statement, 0), allocator)
}

agenda_proposal_resolve :: proc(id: i64, confirm: bool) -> (Agenda_Entry, string) {
	proposal, found := agenda_proposal_get(id, context.temp_allocator)
	if !found {return {}, "not_found"}
	defer agenda_proposal_destroy(&proposal, context.temp_allocator)
	if proposal.state != "pending" {return {}, "proposal_resolved"}
	entry, entry_found := agenda_entry_get(proposal.entry_id, context.temp_allocator)
	if !entry_found {return {}, "not_found"}
	defer agenda_entry_destroy(&entry, context.temp_allocator)
	if entry.revision != proposal.source_revision {return {}, "revision_conflict"}
	if !sqlite_execute(calendar_database, "BEGIN IMMEDIATE;") {return {}, "storage_failed"}
	if confirm {
		input := Agenda_Entry_Input{
			schema_version = 1,
			original_text = entry.original_text,
			start_at = proposal.fields.start_at,
			end_at = proposal.fields.end_at,
			due_at = proposal.fields.due_at,
			location = proposal.fields.location,
			source_url = proposal.fields.source_url,
			reminder_at = proposal.fields.reminder_at,
			recurrence_seconds = proposal.fields.recurrence_seconds,
		}
		updated, update_error := agenda_entry_update(entry.id, entry.revision, &input)
		if len(update_error) > 0 {
			_ = sqlite_execute(calendar_database, "ROLLBACK;")
			return {}, update_error
		}
		agenda_entry_destroy(&updated)
	}
	state := "confirmed" if confirm else "rejected"
	statement, prepared := sqlite_prepare(calendar_database,
		"UPDATE agenda_proposals SET state=? WHERE id=? AND state='pending';")
	if !prepared {_ = sqlite_execute(calendar_database, "ROLLBACK;"); return {}, "storage_failed"}
	ok := sqlite_bind_text_value(statement, 1, state) &&
	      sqlite3_bind_int64(statement, 2, id) == SQLITE_OK &&
	      sqlite3_step(statement) == SQLITE_DONE
	sqlite3_finalize(statement)
	if !ok || sqlite3_changes(calendar_database) == 0 {
		_ = sqlite_execute(calendar_database, "ROLLBACK;")
		return {}, "storage_failed"
	}
	if !sqlite_execute(calendar_database, "COMMIT;") {return {}, "storage_failed"}
	result, result_found := agenda_entry_get(entry.id)
	if !result_found {return {}, "storage_failed"}
	return result, ""
}
