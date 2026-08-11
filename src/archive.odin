package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

CALENDAR_ARCHIVE_FORMAT :: "hw-calendar-agenda"
CALENDAR_ARCHIVE_VERSION :: 1
CALENDAR_ARCHIVE_MAX_BYTES :: 64 * 1024 * 1024
CALENDAR_ARCHIVE_BACKUP_RETENTION :: 10

Calendar_Archive_Entry :: struct {
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

Calendar_Archive_Proposal :: struct {
	id: i64,
	entry_id: i64,
	source_revision: int,
	fields_json: string,
	uncertainty: string,
	state: string,
	created_at_ms: i64,
}

Calendar_Archive_Completion :: struct {
	id: i64,
	entry_id: i64,
	completed_at: string,
	previous_due_at: string,
}

Calendar_Archive :: struct {
	format: string,
	version: int,
	exported_at_unix: i64,
	entries: [dynamic]Calendar_Archive_Entry,
	proposals: [dynamic]Calendar_Archive_Proposal,
	completion_history: [dynamic]Calendar_Archive_Completion,
}

Calendar_Archive_Summary :: struct {
	exported_at_unix: i64,
	entry_count: int,
	proposal_count: int,
	completion_count: int,
	earliest_date: i64,
	latest_date: i64,
}

Calendar_Archive_Error :: enum {
	None,
	Read,
	Too_Large,
	Decode,
	Format,
	Version,
	Invalid_Record,
	Duplicate,
	Reference,
	Encode,
	Write,
	Backup,
	Database,
	Activation,
}

calendar_archive_error_code :: proc(value: Calendar_Archive_Error) -> string {
	switch value {
	case .None: return ""
	case .Read: return "read_failed"
	case .Too_Large: return "archive_too_large"
	case .Decode: return "invalid_json"
	case .Format: return "invalid_format"
	case .Version: return "unsupported_version"
	case .Invalid_Record: return "invalid_record"
	case .Duplicate: return "duplicate_record"
	case .Reference: return "broken_reference"
	case .Encode: return "encode_failed"
	case .Write: return "write_failed"
	case .Backup: return "backup_failed"
	case .Database: return "storage_failed"
	case .Activation: return "activation_failed"
	}
	return "archive_failed"
}

calendar_archive_error_text :: proc(value: Calendar_Archive_Error) -> string {
	switch value {
	case .None: return ""
	case .Read: return "The agenda archive could not be read."
	case .Too_Large: return "The agenda archive exceeds the 64 MiB limit."
	case .Decode: return "The agenda archive is not valid JSON."
	case .Format: return "The selected file is not a hw_calendar agenda archive."
	case .Version: return "This agenda archive version is not supported."
	case .Invalid_Record: return "The agenda archive contains an invalid record."
	case .Duplicate: return "The agenda archive contains duplicate identifiers."
	case .Reference: return "The agenda archive contains a broken record reference."
	case .Encode: return "The agenda archive could not be encoded."
	case .Write: return "The agenda archive could not be written."
	case .Backup: return "The current agenda could not be backed up."
	case .Database: return "The agenda database could not be replaced."
	case .Activation: return "The imported agenda could not be reopened. The previous database was restored."
	}
	return "The agenda archive operation failed."
}

calendar_archive_destroy :: proc(
	archive: ^Calendar_Archive,
	allocator := context.allocator,
) {
	if archive == nil {return}
	delete(archive.format, allocator)
	for &entry in archive.entries {
		delete(entry.original_text, allocator)
		delete(entry.start_at, allocator)
		delete(entry.end_at, allocator)
		delete(entry.due_at, allocator)
		delete(entry.location, allocator)
		delete(entry.source_url, allocator)
		delete(entry.reminder_at, allocator)
		delete(entry.state, allocator)
	}
	delete(archive.entries)
	for &proposal in archive.proposals {
		delete(proposal.fields_json, allocator)
		delete(proposal.uncertainty, allocator)
		delete(proposal.state, allocator)
	}
	delete(archive.proposals)
	for &completion in archive.completion_history {
		delete(completion.completed_at, allocator)
		delete(completion.previous_due_at, allocator)
	}
	delete(archive.completion_history)
	archive^ = {}
}

calendar_archive_collect :: proc(
	allocator := context.allocator,
) -> (Calendar_Archive, bool) {
	archive := Calendar_Archive{
		format = strings.clone(CALENDAR_ARCHIVE_FORMAT, allocator),
		version = CALENDAR_ARCHIVE_VERSION,
		exported_at_unix = time.to_unix_seconds(time.now()),
		entries = make([dynamic]Calendar_Archive_Entry, allocator),
		proposals = make([dynamic]Calendar_Archive_Proposal, allocator),
		completion_history = make([dynamic]Calendar_Archive_Completion, allocator),
	}
	loaded := false
	defer if !loaded {calendar_archive_destroy(&archive, allocator)}

	entry_statement, prepared := sqlite_prepare(
		calendar_database,
		AGENDA_ENTRY_SELECT+" ORDER BY id;",
	)
	if !prepared {return {}, false}
	for {
		step := sqlite3_step(entry_statement)
		if step == SQLITE_DONE {break}
		if step != SQLITE_ROW {
			sqlite3_finalize(entry_statement)
			return {}, false
		}
		entry := agenda_entry_from_statement(entry_statement, allocator)
		append(&archive.entries, Calendar_Archive_Entry{
			id = entry.id,
			original_text = entry.original_text,
			start_at = entry.start_at,
			end_at = entry.end_at,
			due_at = entry.due_at,
			location = entry.location,
			source_url = entry.source_url,
			reminder_at = entry.reminder_at,
			recurrence_seconds = entry.recurrence_seconds,
			state = entry.state,
			revision = entry.revision,
			created_at_ms = entry.created_at_ms,
			updated_at_ms = entry.updated_at_ms,
		})
	}
	sqlite3_finalize(entry_statement)

	proposal_statement, proposals_prepared := sqlite_prepare(calendar_database, `
		SELECT id, entry_id, source_revision, fields_json, uncertainty, state,
		       created_at_ms
		FROM agenda_proposals ORDER BY id;
	`)
	if !proposals_prepared {return {}, false}
	for {
		step := sqlite3_step(proposal_statement)
		if step == SQLITE_DONE {break}
		if step != SQLITE_ROW {
			sqlite3_finalize(proposal_statement)
			return {}, false
		}
		append(&archive.proposals, Calendar_Archive_Proposal{
			id = sqlite3_column_int64(proposal_statement, 0),
			entry_id = sqlite3_column_int64(proposal_statement, 1),
			source_revision = int(sqlite3_column_int(proposal_statement, 2)),
			fields_json = sqlite_column_string(proposal_statement, 3, allocator),
			uncertainty = sqlite_column_string(proposal_statement, 4, allocator),
			state = sqlite_column_string(proposal_statement, 5, allocator),
			created_at_ms = sqlite3_column_int64(proposal_statement, 6),
		})
	}
	sqlite3_finalize(proposal_statement)

	history_statement, history_prepared := sqlite_prepare(calendar_database, `
		SELECT id, entry_id, completed_at, previous_due_at
		FROM agenda_completion_history ORDER BY id;
	`)
	if !history_prepared {return {}, false}
	for {
		step := sqlite3_step(history_statement)
		if step == SQLITE_DONE {break}
		if step != SQLITE_ROW {
			sqlite3_finalize(history_statement)
			return {}, false
		}
		append(&archive.completion_history, Calendar_Archive_Completion{
			id = sqlite3_column_int64(history_statement, 0),
			entry_id = sqlite3_column_int64(history_statement, 1),
			completed_at = sqlite_column_string(history_statement, 2, allocator),
			previous_due_at = sqlite_column_string(history_statement, 3, allocator),
		})
	}
	sqlite3_finalize(history_statement)
	loaded = true
	return archive, true
}

calendar_archive_timestamp_valid :: proc(value: string, optional := true) -> bool {
	if len(value) == 0 {return optional}
	_, parsed := strconv.parse_i64(value)
	return parsed
}

calendar_archive_proposal_state_valid :: proc(value: string) -> bool {
	return value == "pending" || value == "confirmed" || value == "rejected"
}

calendar_archive_validate :: proc(
	archive: ^Calendar_Archive,
) -> (Calendar_Archive_Summary, Calendar_Archive_Error) {
	if archive == nil || archive.format != CALENDAR_ARCHIVE_FORMAT {
		return {}, .Format
	}
	if archive.version != CALENDAR_ARCHIVE_VERSION {return {}, .Version}
	if archive.exported_at_unix < 0 {return {}, .Invalid_Record}

	entry_ids := make(map[i64]bool, context.temp_allocator)
	proposal_ids := make(map[i64]bool, context.temp_allocator)
	history_ids := make(map[i64]bool, context.temp_allocator)
	entry_revisions := make(map[i64]int, context.temp_allocator)
	earliest, latest := i64(0), i64(0)
	for entry in archive.entries {
		if entry.id <= 0 || entry_ids[entry.id] {return {}, .Duplicate}
		entry_ids[entry.id] = true
		entry_revisions[entry.id] = entry.revision
		if len(strings.trim_space(entry.original_text)) == 0 ||
		   !agenda_state_valid(entry.state) || entry.revision < 1 ||
		   entry.recurrence_seconds < 0 || entry.created_at_ms < 0 ||
		   entry.updated_at_ms < entry.created_at_ms ||
		   !calendar_archive_timestamp_valid(entry.start_at) ||
		   !calendar_archive_timestamp_valid(entry.end_at) ||
		   !calendar_archive_timestamp_valid(entry.due_at) ||
		   !calendar_archive_timestamp_valid(entry.reminder_at) ||
		   !agenda_interval_valid(entry.start_at, entry.end_at) ||
		   entry.recurrence_seconds > 0 && len(entry.due_at) == 0 {
			return {}, .Invalid_Record
		}
		date_values := [2]string{entry.start_at, entry.due_at}
		for value in date_values {
			if len(value) == 0 {continue}
			stamp, _ := strconv.parse_i64(value)
			if earliest == 0 || stamp < earliest {earliest = stamp}
			if latest == 0 || stamp > latest {latest = stamp}
		}
	}
	for proposal in archive.proposals {
		if proposal.id <= 0 || proposal_ids[proposal.id] {return {}, .Duplicate}
		proposal_ids[proposal.id] = true
		if !entry_ids[proposal.entry_id] {return {}, .Reference}
		if proposal.source_revision < 1 ||
		   proposal.source_revision > entry_revisions[proposal.entry_id] ||
		   !calendar_archive_proposal_state_valid(proposal.state) ||
		   proposal.created_at_ms < 0 {
			return {}, .Invalid_Record
		}
		fields: Agenda_Proposal_Fields
		if error := json.unmarshal(
			transmute([]u8)proposal.fields_json,
			&fields,
		); error != nil {
			return {}, .Invalid_Record
		}
		valid := fields.recurrence_seconds >= 0 &&
		         calendar_archive_timestamp_valid(fields.start_at) &&
		         calendar_archive_timestamp_valid(fields.end_at) &&
		         calendar_archive_timestamp_valid(fields.due_at) &&
		         calendar_archive_timestamp_valid(fields.reminder_at) &&
		         agenda_interval_valid(fields.start_at, fields.end_at) &&
		         !(fields.recurrence_seconds > 0 && len(fields.due_at) == 0)
		delete(fields.start_at)
		delete(fields.end_at)
		delete(fields.due_at)
		delete(fields.location)
		delete(fields.source_url)
		delete(fields.reminder_at)
		if !valid {return {}, .Invalid_Record}
	}
	for completion in archive.completion_history {
		if completion.id <= 0 || history_ids[completion.id] {
			return {}, .Duplicate
		}
		history_ids[completion.id] = true
		if !entry_ids[completion.entry_id] {return {}, .Reference}
		if !calendar_archive_timestamp_valid(completion.completed_at, false) ||
		   !calendar_archive_timestamp_valid(completion.previous_due_at) {
			return {}, .Invalid_Record
		}
	}
	return {
		exported_at_unix = archive.exported_at_unix,
		entry_count = len(archive.entries),
		proposal_count = len(archive.proposals),
		completion_count = len(archive.completion_history),
		earliest_date = earliest,
		latest_date = latest,
	}, .None
}

calendar_archive_read :: proc(
	path: string,
	allocator := context.allocator,
) -> (Calendar_Archive, Calendar_Archive_Summary, Calendar_Archive_Error) {
	file_info, stat_error := os.stat(path, context.temp_allocator)
	if stat_error != nil {return {}, {}, .Read}
	defer os.file_info_delete(file_info, context.temp_allocator)
	if file_info.size > CALENDAR_ARCHIVE_MAX_BYTES {return {}, {}, .Too_Large}
	bytes, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {return {}, {}, .Read}
	defer delete(bytes, allocator)
	if len(bytes) > CALENDAR_ARCHIVE_MAX_BYTES {return {}, {}, .Too_Large}
	archive: Calendar_Archive
	if decode_error := json.unmarshal(bytes, &archive, .JSON, allocator);
	   decode_error != nil {
		return {}, {}, .Decode
	}
	summary, validation_error := calendar_archive_validate(&archive)
	if validation_error != .None {
		calendar_archive_destroy(&archive, allocator)
		return {}, {}, validation_error
	}
	return archive, summary, .None
}

calendar_archive_export :: proc(path: string) -> (Calendar_Archive_Summary, Calendar_Archive_Error) {
	if len(path) == 0 {return {}, .Write}
	archive, collected := calendar_archive_collect()
	if !collected {return {}, .Database}
	defer calendar_archive_destroy(&archive)
	summary, validation_error := calendar_archive_validate(&archive)
	if validation_error != .None {return {}, validation_error}
	bytes, encode_error := json.marshal(
		archive,
		{pretty=true, use_spaces=true, spaces=2},
	)
	if encode_error != nil {return {}, .Encode}
	defer delete(bytes)
	temporary := fmt.tprintf(
		"%s.tmp-%d",
		path,
		time.to_unix_nanoseconds(time.now()),
	)
	defer _ = os.remove(temporary)
	if write_error := os.write_entire_file(temporary, bytes); write_error != nil {
		return {}, .Write
	}
	if rename_error := os.rename(temporary, path); rename_error != nil {
		return {}, .Write
	}
	return summary, .None
}

calendar_archive_database_copy :: proc(source_path, destination_path: string) -> bool {
	source_c := strings.clone_to_cstring(source_path, context.temp_allocator)
	destination_c := strings.clone_to_cstring(destination_path, context.temp_allocator)
	source: ^SQLite_DB
	destination: ^SQLite_DB
	if sqlite3_open_v2(source_c, &source, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
		if source != nil {sqlite3_close(source)}
		return false
	}
	defer sqlite3_close(source)
	if sqlite3_open_v2(
		destination_c,
		&destination,
		SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
		nil,
	) != SQLITE_OK {
		if destination != nil {sqlite3_close(destination)}
		return false
	}
	defer sqlite3_close(destination)
	backup := sqlite3_backup_init(destination, "main", source, "main")
	if backup == nil {
		fmt.eprintf("[hw_calendar] backup initialization failed: %s\n", sqlite_error(destination))
		return false
	}
	step := sqlite3_backup_step(backup, -1)
	finished := sqlite3_backup_finish(backup)
	if step != SQLITE_DONE || finished != SQLITE_OK {
		fmt.eprintf(
			"[hw_calendar] backup copy failed: step=%d finish=%d error=%s\n",
			step,
			finished,
			sqlite_error(destination),
		)
	}
	return step == SQLITE_DONE && finished == SQLITE_OK
}

calendar_archive_database_valid :: proc(path: string) -> bool {
	path_c := strings.clone_to_cstring(path, context.temp_allocator)
	database: ^SQLite_DB
	if sqlite3_open_v2(path_c, &database, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
		if database != nil {
			fmt.eprintf(
				"[hw_calendar] backup reopen failed: %s path=%s\n",
				sqlite_error(database),
				path,
			)
		}
		if database != nil {sqlite3_close(database)}
		return false
	}
	defer sqlite3_close(database)
	check, prepared := sqlite_prepare(database, "PRAGMA quick_check;")
	if !prepared {return false}
	quick_ok := sqlite3_step(check) == SQLITE_ROW &&
	            sqlite_column_string(check, 0, context.temp_allocator) == "ok"
	sqlite3_finalize(check)
	if !quick_ok {
		fmt.eprintf("[hw_calendar] backup quick_check failed: %s\n", path)
		return false
	}
	foreign_check, foreign_prepared := sqlite_prepare(database, "PRAGMA foreign_key_check;")
	if !foreign_prepared {return false}
	foreign_ok := sqlite3_step(foreign_check) == SQLITE_DONE
	sqlite3_finalize(foreign_check)
	if !foreign_ok {
		fmt.eprintf("[hw_calendar] backup foreign_key_check failed: %s\n", path)
	}
	return foreign_ok
}

Calendar_Archive_Backup_File :: struct {
	path: string,
	modified_nano: i64,
}

calendar_archive_prune_backups :: proc(directory: string) {
	handle, open_error := os.open(directory)
	if open_error != nil {return}
	entries, read_error := os.read_dir(handle, -1, context.temp_allocator)
	os.close(handle)
	if read_error != nil {return}
	files := make([dynamic]Calendar_Archive_Backup_File, context.temp_allocator)
	for entry in entries {
		if entry.type == .Directory ||
		   !strings.has_prefix(entry.name, "agenda-before-import-v") ||
		   !strings.has_suffix(entry.name, ".sqlite3") {
			continue
		}
		append(&files, Calendar_Archive_Backup_File{
			path = entry.fullpath,
			modified_nano = time.time_to_unix_nano(entry.modification_time),
		})
	}
	if len(files) <= CALENDAR_ARCHIVE_BACKUP_RETENTION {return}
	slice.sort_by(
		files[:],
		proc(a, b: Calendar_Archive_Backup_File) -> bool {
			return a.modified_nano < b.modified_nano
		},
	)
	for index in 0..<len(files)-CALENDAR_ARCHIVE_BACKUP_RETENTION {
		_ = os.remove(files[index].path)
	}
}

calendar_archive_create_backup :: proc(
	allocator := context.allocator,
) -> (string, bool) {
	directory := fmt.tprintf("%s/Backups", calendar_support_dir())
	if os.make_directory(directory) != nil && !os.exists(directory) {
		return "", false
	}
	path := fmt.aprintf(
		"%s/agenda-before-import-v%d-%d.sqlite3",
		directory,
		CALENDAR_SCHEMA_VERSION,
		time.to_unix_nanoseconds(time.now()),
		allocator = allocator,
	)
	copied := calendar_archive_database_copy(calendar_database_path(), path)
	valid := copied && calendar_archive_database_valid(path)
	if !copied || !valid {
		fmt.eprintf(
			"[hw_calendar] import backup verification failed: copied=%v valid=%v path=%s\n",
			copied,
			valid,
			path,
		)
		_ = os.remove(path)
		delete(path, allocator)
		return "", false
	}
	calendar_archive_prune_backups(directory)
	return path, true
}

calendar_archive_foreign_keys_valid :: proc(database: ^SQLite_DB) -> bool {
	statement, prepared := sqlite_prepare(database, "PRAGMA foreign_key_check;")
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite3_step(statement) == SQLITE_DONE
}

calendar_archive_insert_entry :: proc(entry: ^Calendar_Archive_Entry) -> bool {
	statement, prepared := sqlite_prepare(calendar_database, `
		INSERT INTO agenda_entries (
			id, original_text, start_at, end_at, due_at, location, source_url,
			reminder_at, recurrence_seconds, state, revision, created_at_ms,
			updated_at_ms
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
	`)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite3_bind_int64(statement, 1, entry.id) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 2, entry.original_text) &&
	       sqlite_bind_text_value(statement, 3, entry.start_at) &&
	       sqlite_bind_text_value(statement, 4, entry.end_at) &&
	       sqlite_bind_text_value(statement, 5, entry.due_at) &&
	       sqlite_bind_text_value(statement, 6, entry.location) &&
	       sqlite_bind_text_value(statement, 7, entry.source_url) &&
	       sqlite_bind_text_value(statement, 8, entry.reminder_at) &&
	       sqlite3_bind_int64(statement, 9, entry.recurrence_seconds) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 10, entry.state) &&
	       sqlite3_bind_int(statement, 11, i32(entry.revision)) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 12, entry.created_at_ms) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 13, entry.updated_at_ms) == SQLITE_OK &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_archive_insert_proposal :: proc(proposal: ^Calendar_Archive_Proposal) -> bool {
	statement, prepared := sqlite_prepare(calendar_database, `
		INSERT INTO agenda_proposals (
			id, entry_id, source_revision, fields_json, uncertainty, state,
			created_at_ms
		) VALUES (?, ?, ?, ?, ?, ?, ?);
	`)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite3_bind_int64(statement, 1, proposal.id) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 2, proposal.entry_id) == SQLITE_OK &&
	       sqlite3_bind_int(statement, 3, i32(proposal.source_revision)) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 4, proposal.fields_json) &&
	       sqlite_bind_text_value(statement, 5, proposal.uncertainty) &&
	       sqlite_bind_text_value(statement, 6, proposal.state) &&
	       sqlite3_bind_int64(statement, 7, proposal.created_at_ms) == SQLITE_OK &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_archive_insert_completion :: proc(
	completion: ^Calendar_Archive_Completion,
) -> bool {
	statement, prepared := sqlite_prepare(calendar_database, `
		INSERT INTO agenda_completion_history (
			id, entry_id, completed_at, previous_due_at
		) VALUES (?, ?, ?, ?);
	`)
	if !prepared {return false}
	defer sqlite3_finalize(statement)
	return sqlite3_bind_int64(statement, 1, completion.id) == SQLITE_OK &&
	       sqlite3_bind_int64(statement, 2, completion.entry_id) == SQLITE_OK &&
	       sqlite_bind_text_value(statement, 3, completion.completed_at) &&
	       sqlite_bind_text_value(statement, 4, completion.previous_due_at) &&
	       sqlite3_step(statement) == SQLITE_DONE
}

calendar_archive_restore_backup :: proc(path: string) -> bool {
	calendar_database_close()
	active := calendar_database_path()
	_ = os.remove(fmt.tprintf("%s-wal", active))
	_ = os.remove(fmt.tprintf("%s-shm", active))
	if !calendar_archive_database_copy(path, active) {return false}
	return calendar_database_open()
}

calendar_archive_install :: proc(
	archive: ^Calendar_Archive,
) -> (string, Calendar_Archive_Error) {
	_, validation_error := calendar_archive_validate(archive)
	if validation_error != .None {return "", validation_error}
	backup_path, backed_up := calendar_archive_create_backup()
	if !backed_up {return "", .Backup}
	installed := false
	defer if !installed {delete(backup_path)}
	if !sqlite_execute(calendar_database, "BEGIN IMMEDIATE;") {
		return "", .Database
	}
	committed := false
	defer if !committed {_ = sqlite_execute(calendar_database, "ROLLBACK;")}
	if !sqlite_execute(calendar_database, "DELETE FROM agenda_completion_history;") ||
	   !sqlite_execute(calendar_database, "DELETE FROM agenda_proposals;") ||
	   !sqlite_execute(calendar_database, "DELETE FROM agenda_entries;") {
		return "", .Database
	}
	for &entry in archive.entries {
		if !calendar_archive_insert_entry(&entry) {return "", .Database}
	}
	for &proposal in archive.proposals {
		if !calendar_archive_insert_proposal(&proposal) {return "", .Database}
	}
	for &completion in archive.completion_history {
		if !calendar_archive_insert_completion(&completion) {return "", .Database}
	}
	if !calendar_archive_foreign_keys_valid(calendar_database) ||
	   !sqlite_execute(calendar_database, "COMMIT;") {
		return "", .Database
	}
	committed = true
	calendar_database_close()
	if !calendar_database_open() ||
	   !calendar_archive_database_valid(calendar_database_path()) {
		if calendar_database != nil {calendar_database_close()}
		if !calendar_archive_restore_backup(backup_path) {return "", .Activation}
		return "", .Activation
	}
	installed = true
	return backup_path, .None
}

Calendar_CLI_Archive_Data :: struct {
	path: string,
	backup_path: string `json:"backup_path,omitempty"`,
	replaced: bool,
	summary: Calendar_Archive_Summary,
}

Calendar_CLI_Archive_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Archive_Data,
}

calendar_archive_cli_error :: proc(
	request: Calendar_CLI_Request,
	error: Calendar_Archive_Error,
) -> Calendar_CLI_Result {
	return calendar_cli_error(
		request.command,
		error == .Format || error == .Version || error == .Invalid_Record ||
		error == .Duplicate || error == .Reference || error == .Decode ||
		error == .Too_Large ? 3 : 6,
		calendar_archive_error_code(error),
		calendar_archive_error_text(error),
	)
}

calendar_archive_cli_execute :: proc(
	request: Calendar_CLI_Request,
) -> Calendar_CLI_Result {
	#partial switch request.command {
	case .Archive_Export:
		summary, archive_error := calendar_archive_export(request.path)
		if archive_error != .None {
			return calendar_archive_cli_error(request, archive_error)
		}
		return {output=calendar_cli_encode(Calendar_CLI_Archive_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {path=request.path, summary=summary},
		})}
	case .Archive_Inspect, .Archive_Import:
		archive, summary, archive_error := calendar_archive_read(request.path)
		if archive_error != .None {
			return calendar_archive_cli_error(request, archive_error)
		}
		defer calendar_archive_destroy(&archive)
		if request.command == .Archive_Inspect {
			return {output=calendar_cli_encode(Calendar_CLI_Archive_Response{
				ok = true,
				command = calendar_cli_command_name(request.command),
				data = {path=request.path, summary=summary},
			})}
		}
		backup_path, install_error := calendar_archive_install(&archive)
		if install_error != .None {
			return calendar_archive_cli_error(request, install_error)
		}
		defer delete(backup_path)
		return {output=calendar_cli_encode(Calendar_CLI_Archive_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {
				path = request.path,
				backup_path = backup_path,
				replaced = true,
				summary = summary,
			},
		})}
	case:
	}
	return calendar_cli_error(
		request.command,
		2,
		"usage",
		"Unknown archive command.",
	)
}
