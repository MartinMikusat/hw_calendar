package main

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import dt "core:time/datetime"
import "core:time/timezone"

CALENDAR_CLI_PROTOCOL_VERSION :: 2

Calendar_CLI_Command :: enum {
	None,
	Reminder_Status,
	UI_Snapshot,
	UI_Check,
	UI_Modal_State,
	UI_Modal_Dismiss,
	UI_Bridge_Pointer,
	UI_Bridge_Keyboard,
	Entry_Create,
	Entry_Update,
	Entry_Get,
	Entry_List,
	Entry_Search,
	Entry_Complete,
	Entry_Reopen,
	Entry_Dismiss,
	Entry_Restore,
	Agenda_Query,
	Proposal_Submit,
	Proposal_Get,
	Proposal_Confirm,
	Proposal_Reject,
	Chore_Due,
	Chore_Done,
	Birthday_Create,
	Birthday_List,
	Birthday_Due,
	Birthday_Default,
	Archive_Export,
	Archive_Inspect,
	Archive_Import,
	Update_Check,
	// Append patch commands so protocol-1 command values remain stable.
	Entry_Patch,
}

Calendar_CLI_Request :: struct {
	command: Calendar_CLI_Command,
	protocol_version: int,
	input: string,
	use_stdin_input: bool,
	id: string,
	from: string,
	to: string,
	query: string,
	baseline: string,
	target_control: string,
	key: string,
	modifiers: string,
	path: string,
	replace: bool,
	if_revision: int,
	set_text: bool,
	set_start: bool,
	set_end: bool,
	set_due: bool,
	set_location: bool,
	set_source_url: bool,
	set_reminder: bool,
	set_recurrence: bool,
	clear_start: bool,
	clear_end: bool,
	clear_due: bool,
	clear_location: bool,
	clear_source_url: bool,
	clear_reminder: bool,
	clear_recurrence: bool,
	birthday_name: string,
	birthday_date: string,
	birthday_advance_days: int,
}

calendar_cli_command_reads_input :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .Entry_Create ||
	       command == .Entry_Update ||
	       command == .Proposal_Submit
}

calendar_cli_command_mutates_database :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .Entry_Create || command == .Entry_Update ||
	       command == .Entry_Patch ||
	       command == .Entry_Complete || command == .Entry_Reopen ||
	       command == .Entry_Dismiss || command == .Entry_Restore ||
	       command == .Proposal_Submit || command == .Proposal_Confirm ||
	       command == .Proposal_Reject || command == .Chore_Done ||
	       command == .Birthday_Create || command == .Birthday_Default ||
	       command == .Archive_Import
}

calendar_cli_command_requires_gui :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .UI_Snapshot || command == .UI_Check ||
	       command == .UI_Modal_State || command == .UI_Modal_Dismiss ||
	       command == .UI_Bridge_Pointer ||
	       command == .UI_Bridge_Keyboard || command == .Update_Check
}

calendar_cli_command_uses_database :: proc(command: Calendar_CLI_Command) -> bool {
	return command != .Archive_Inspect && command != .Update_Check
}

Calendar_CLI_Result :: struct {
	output: string,
	exit_code: int,
}

Calendar_CLI_Error :: struct {
	code: string,
	message: string,
}

Calendar_CLI_Error_Response :: struct {
	ok: bool,
	command: string,
	error: Calendar_CLI_Error,
}

Calendar_CLI_Help_Response :: struct {
	ok: bool,
	command: string,
	message: string,
}

Calendar_CLI_Modal_Data :: struct {
	kind: string,
	dismissal: string,
	dismissed: bool,
}

Calendar_CLI_Modal_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Modal_Data,
}

Calendar_CLI_Update_Data :: struct {
	checking: bool,
	version: string,
}

Calendar_CLI_Update_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Update_Data,
}

Calendar_CLI_UI_Bridge_Data :: struct {
	control: string `json:"control,omitempty"`,
	key: string `json:"key,omitempty"`,
	modifiers: string `json:"modifiers,omitempty"`,
}

Calendar_CLI_UI_Bridge_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_UI_Bridge_Data,
}

Calendar_CLI_Reminder_Data :: struct {
	authorization: string,
	pending_limit: int,
	executable_action: string,
	snooze_seconds: int,
}

Calendar_CLI_Reminder_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Reminder_Data,
}

calendar_cli_command_name :: proc(command: Calendar_CLI_Command) -> string {
	switch command {
	case .Reminder_Status: return "reminder status"
	case .UI_Snapshot: return "ui snapshot"
	case .UI_Check: return "ui check"
	case .UI_Modal_State: return "ui modal-state"
	case .UI_Modal_Dismiss: return "ui modal-dismiss"
	case .UI_Bridge_Pointer: return "ui bridge-pointer"
	case .UI_Bridge_Keyboard: return "ui bridge-keyboard"
	case .Entry_Create: return "entry create"
	case .Entry_Update: return "entry update"
	case .Entry_Patch: return "entry update"
	case .Entry_Get: return "entry get"
	case .Entry_List: return "entry list"
	case .Entry_Search: return "entry search"
	case .Entry_Complete: return "entry complete"
	case .Entry_Reopen: return "entry reopen"
	case .Entry_Dismiss: return "entry dismiss"
	case .Entry_Restore: return "entry restore"
	case .Agenda_Query: return "agenda query"
	case .Proposal_Submit: return "proposal submit"
	case .Proposal_Get: return "proposal get"
	case .Proposal_Confirm: return "proposal confirm"
	case .Proposal_Reject: return "proposal reject"
	case .Chore_Due: return "chore due"
	case .Chore_Done: return "chore done"
	case .Birthday_Create: return "birthday create"
	case .Birthday_List: return "birthday list"
	case .Birthday_Due: return "birthday due"
	case .Birthday_Default: return "birthday default"
	case .Archive_Export: return "archive export"
	case .Archive_Inspect: return "archive inspect"
	case .Archive_Import: return "archive import"
	case .Update_Check: return "update check"
	case .None: return "unknown"
	}
	return "unknown"
}

calendar_cli_entry_help :: proc(command: Calendar_CLI_Command) -> Calendar_CLI_Result {
	update_help: string = `hw_calendar entry update --id <id> --if-revision <revision> [--text "<text>"] [--start ...] [--end ...] [--due ...] [--location ...] [--source-url ...] [--reminder ...] [--recurrence seconds] [--clear-start] [--clear-end] [--clear-due] [--clear-location] [--clear-source-url] [--clear-reminder] [--clear-recurrence]
Notes:
- Versioned JSON over stdin replaces the full entry document.
- Flag updates preserve fields that the command omits.
- end requires start.
- recurrence requires due.
- Supported datetime formats:
  - Unix timestamp in seconds (e.g. 1750000000)
  - YYYYMMDD
  - YYYYMMDDTHHMMSS
  - YYYY-MM-DD
  - YYYY-MM-DDTHH:MM:SS
  - YYYY-MM-DD HH:MM:SS
- The Z suffix is accepted only for --reminder because entry dates use civil time.
Examples:
- hw_calendar entry update --id 7 --if-revision 3 --text "Water the balcony plants"
- Full replacement: build/hw_calendar entry update --id 7 --if-revision 3 < entry.json`
	create_help: string = `hw_calendar entry create [or entry add] --text "<text>" [--start ...] [--end ...] [--due ...] [--location ...] [--source-url ...] [--reminder ...] [--recurrence seconds]
Notes:
- Input can also be sent as versioned JSON over stdin, as documented below.
- end requires start.
- recurrence requires due.
- Supported datetime formats:
  - Unix timestamp in seconds (e.g. 1750000000)
  - YYYYMMDD
  - YYYYMMDDTHHMMSS
  - YYYY-MM-DD
  - YYYY-MM-DDTHH:MM:SS
  - YYYY-MM-DD HH:MM:SS
- The Z suffix is accepted only for --reminder because entry dates use civil time.
Examples:
- hw_calendar entry create --text "Water the plants" --due 2026-04-27 --recurrence 604800
- hw_calendar entry add --text "Water the plants" --due 20260427 --recurrence 604800
- JSON alternative: build/hw_calendar entry create < entry.json`
	if command == .Entry_Update {
		return {
			output = calendar_cli_encode(Calendar_CLI_Help_Response{
				ok = true,
				command = calendar_cli_command_name(command),
				message = update_help,
			}),
			exit_code = 0,
		}
	}
	return {
		output = calendar_cli_encode(Calendar_CLI_Help_Response{
			ok = true,
			command = calendar_cli_command_name(command),
			message = create_help,
		}),
		exit_code = 0,
	}
}

calendar_cli_parse_entry_recurrence :: proc(value: string) -> (i64, bool) {
	parsed, ok := strconv.parse_i64(value)
	return parsed, ok && parsed >= 0
}

calendar_cli_parse_entry_datetime :: proc(value: string) -> (Agenda_Date_Time, bool) {
	trimmed: string = strings.trim_space(value)
	if len(trimmed) == 0 {return {}, false}
	if parsed, ok := agenda_parse_date_time(trimmed); ok {return parsed, true}
	if len(trimmed) == 10 &&
	   trimmed[4] == '-' && trimmed[7] == '-' {
		result: Agenda_Date_Time
		ok: bool
		result.year, ok = agenda_parse_fixed_int(trimmed, 0, 4)
		if !ok {return {}, false}
		result.month, ok = agenda_parse_fixed_int(trimmed, 5, 2)
		if !ok {return {}, false}
		result.day, ok = agenda_parse_fixed_int(trimmed, 8, 2)
		if !ok {return {}, false}
		result.is_date = true
		return result, agenda_date_time_valid(result)
	}
	if len(trimmed) >= 19 && (trimmed[10] == 'T' || trimmed[10] == ' ') {
		if trimmed[4] == '-' && trimmed[7] == '-' &&
		   trimmed[13] == ':' && trimmed[16] == ':' {
			compact: string
			if len(trimmed) == 19 {
				compact = fmt.tprintf(
					"%s%s%sT%s%s%s",
					trimmed[0:4],
					trimmed[5:7],
					trimmed[8:10],
					trimmed[11:13],
					trimmed[14:16],
					trimmed[17:19],
				)
				return agenda_parse_date_time(compact)
			}
			if len(trimmed) == 20 && trimmed[19] == 'Z' {
				compact = fmt.tprintf(
					"%s%s%sT%s%s%sZ",
					trimmed[0:4],
					trimmed[5:7],
					trimmed[8:10],
					trimmed[11:13],
					trimmed[14:16],
					trimmed[17:19],
				)
				return agenda_parse_date_time(compact)
			}
		}
	}
	return {}, false
}

calendar_cli_datetime_matches :: proc(
	value: Agenda_Date_Time,
	localized: dt.DateTime,
) -> bool {
	return localized.year == i64(value.year) &&
	       i64(localized.month) == i64(value.month) &&
	       i64(localized.day) == i64(value.day) &&
	       i64(localized.hour) == i64(value.hour) &&
	       i64(localized.minute) == i64(value.minute) &&
	       i64(localized.second) == i64(value.second)
}

calendar_cli_datetime_consider_offset :: proc(
	value: Agenda_Date_Time,
	naive_datetime: dt.DateTime,
	region: ^dt.TZ_Region,
	offset: i64,
	best: ^i64,
	found: ^bool,
) {
	candidate_datetime, candidate_error := dt.add(
		naive_datetime,
		dt.Delta{seconds = -offset},
	)
	if candidate_error != .None {return}
	localized, localized_ok := timezone.datetime_to_tz(
		candidate_datetime,
		region,
	)
	if !localized_ok || !calendar_cli_datetime_matches(value, localized) {return}
	candidate_time, candidate_ok := time.datetime_to_time(candidate_datetime)
	if !candidate_ok {return}
	candidate := time.to_unix_seconds(candidate_time)
	if !found^ || candidate < best^ {
		best^ = candidate
		found^ = true
	}
}

calendar_cli_datetime_to_unix :: proc(value: Agenda_Date_Time) -> (i64, bool) {
	if value.utc {return agenda_date_time_stamp(value), true}
	naive_datetime, datetime_error := dt.components_to_datetime(
		i64(value.year),
		i64(value.month),
		i64(value.day),
		i64(value.hour),
		i64(value.minute),
		i64(value.second),
	)
	if datetime_error != .None {return 0, false}
	region, region_ok := timezone.region_load("local")
	if !region_ok {return 0, false}
	defer timezone.region_destroy(region)
	if region == nil {
		stamp_time, stamp_ok := time.datetime_to_time(naive_datetime)
		if !stamp_ok {return 0, false}
		return time.to_unix_seconds(stamp_time), true
	}
	best: i64
	found := false
	// Gaps produce no matching offset. Overlaps produce two matches; keep the
	// smaller Unix value so the reminder uses the earliest occurrence.
	for record in region.records {
		calendar_cli_datetime_consider_offset(
			value,
			naive_datetime,
			region,
			record.utc_offset,
			&best,
			&found,
		)
	}
	calendar_cli_datetime_consider_offset(
		value,
		naive_datetime,
		region,
		region.rrule.std_offset,
		&best,
		&found,
	)
	if region.rrule.has_dst {
		calendar_cli_datetime_consider_offset(
			value,
			naive_datetime,
			region,
			region.rrule.dst_offset,
			&best,
			&found,
		)
	}
	return best, found
}

calendar_cli_parse_entry_timestamp :: proc(value: string) -> (string, bool) {
	trimmed: string = strings.trim_space(value)
	parsed_time, datetime_ok := calendar_cli_parse_entry_datetime(trimmed)
	if datetime_ok {
		if parsed_time.utc {return "", false}
		return fmt.tprintf("%d", agenda_date_time_stamp(parsed_time)), true
	}
	parsed, parse_ok := strconv.parse_i64(trimmed)
	if !parse_ok {return "", false}
	return fmt.tprintf("%d", parsed), true
}

calendar_cli_parse_entry_reminder_timestamp :: proc(value: string) -> (string, bool) {
	trimmed: string = strings.trim_space(value)
	parsed_time, datetime_ok := calendar_cli_parse_entry_datetime(trimmed)
	if datetime_ok {
		parsed, converted := calendar_cli_datetime_to_unix(parsed_time)
		if !converted {return "", false}
		return fmt.tprintf("%d", parsed), true
	}
	parsed, parse_ok := strconv.parse_i64(trimmed)
	if !parse_ok {return "", false}
	return fmt.tprintf("%d", parsed), true
}

calendar_cli_entry_update_has_payload :: proc(request: Calendar_CLI_Request) -> bool {
	return request.set_text || request.set_start || request.set_due || request.set_end ||
		request.set_location || request.set_source_url || request.set_reminder ||
		request.set_recurrence || request.clear_start || request.clear_end ||
		request.clear_due || request.clear_location || request.clear_source_url ||
		request.clear_reminder || request.clear_recurrence
}

calendar_cli_entry_payload_to_json :: proc(input: Agenda_Entry_Input) -> (string, bool) {
	input_json, encode_error := json.marshal(input)
	if encode_error != nil {return "", false}
	defer delete(input_json)
	return strings.clone(string(input_json)), true
}

calendar_cli_encode :: proc(value: $T) -> string {
	bytes, error := json.marshal(value)
	if error != nil {
		return strings.clone(`{"ok":false,"command":"unknown","error":{"code":"encode_failed","message":"The result could not be encoded."}}`)
	}
	defer delete(bytes)
	return strings.clone(string(bytes))
}

calendar_cli_error :: proc(
	command: Calendar_CLI_Command,
	exit_code: int,
	code, message: string,
) -> Calendar_CLI_Result {
	return Calendar_CLI_Result{
		output = calendar_cli_encode(Calendar_CLI_Error_Response{
			ok = false,
			command = calendar_cli_command_name(command),
			error = {code=code, message=message},
		}),
		exit_code = exit_code,
	}
}

calendar_cli_parse :: proc(args: []string) -> (Calendar_CLI_Request, Calendar_CLI_Result, bool) {
	request: Calendar_CLI_Request
	request.protocol_version = CALENDAR_CLI_PROTOCOL_VERSION
	if len(args) < 2 {
		return {}, calendar_cli_error(.None, 2, "usage", "Expected an entry, agenda, proposal, chore, birthday, archive, update, reminder, or UI command."), false
	}
	group, action := args[0], args[1]
	switch {
	case group == "reminder" && action == "status": request.command = .Reminder_Status
	case group == "ui" && action == "snapshot": request.command = .UI_Snapshot
	case group == "ui" && action == "check": request.command = .UI_Check
	case group == "ui" && action == "modal-state": request.command = .UI_Modal_State
	case group == "ui" && action == "modal-dismiss": request.command = .UI_Modal_Dismiss
	case group == "ui" && action == "bridge-pointer": request.command = .UI_Bridge_Pointer
	case group == "ui" && action == "bridge-keyboard": request.command = .UI_Bridge_Keyboard
	case group == "entry" && action == "create": request.command = .Entry_Create
	case group == "entry" && action == "add": request.command = .Entry_Create
	case group == "entry" && action == "update": request.command = .Entry_Update
	case group == "entry" && action == "get": request.command = .Entry_Get
	case group == "entry" && action == "list": request.command = .Entry_List
	case group == "entry" && action == "search": request.command = .Entry_Search
	case group == "entry" && action == "complete": request.command = .Entry_Complete
	case group == "entry" && action == "reopen": request.command = .Entry_Reopen
	case group == "entry" && action == "dismiss": request.command = .Entry_Dismiss
	case group == "entry" && action == "restore": request.command = .Entry_Restore
	case group == "agenda" && action == "query": request.command = .Agenda_Query
	case group == "proposal" && action == "submit": request.command = .Proposal_Submit
	case group == "proposal" && action == "get": request.command = .Proposal_Get
	case group == "proposal" && action == "confirm": request.command = .Proposal_Confirm
	case group == "proposal" && action == "reject": request.command = .Proposal_Reject
	case group == "chore" && action == "due": request.command = .Chore_Due
	case group == "chore" && action == "done": request.command = .Chore_Done
	case group == "birthday" && action == "create": request.command = .Birthday_Create
	case group == "birthday" && action == "add": request.command = .Birthday_Create
	case group == "birthday" && action == "list": request.command = .Birthday_List
	case group == "birthday" && action == "due": request.command = .Birthday_Due
	case group == "birthday" && action == "default": request.command = .Birthday_Default
	case group == "archive" && action == "export": request.command = .Archive_Export
	case group == "archive" && action == "inspect": request.command = .Archive_Inspect
	case group == "archive" && action == "import": request.command = .Archive_Import
	case group == "update" && action == "check": request.command = .Update_Check
	case:
		return {}, calendar_cli_error(.None, 2, "usage", "Unknown command."), false
	}
	if request.command == .Proposal_Submit {
		request.use_stdin_input = true
	}
	build_entry_input := request.command == .Entry_Create || request.command == .Entry_Update
	entry_input: Agenda_Entry_Input
	has_entry_payload := false
	if build_entry_input {
		request.use_stdin_input = true
		entry_input.schema_version = 1
	}
	for index := 2; index < len(args); {
		if args[index] == "--replace" {
			request.replace = true
			index += 1
			continue
		}
		if args[index] == "--help" || args[index] == "-h" {
			if request.command == .Entry_Create || request.command == .Entry_Update {
				return {}, calendar_cli_entry_help(request.command), false
			}
		}
		if args[index] == "--clear-start" {
			if request.command != .Entry_Update {return {}, calendar_cli_error(request.command, 2, "usage", "--clear-start is only available for entry update."), false}
			request.clear_start = true
			request.set_start = false
			has_entry_payload = true
			index += 1
			continue
		}
		if args[index] == "--clear-end" {
			if request.command != .Entry_Update {return {}, calendar_cli_error(request.command, 2, "usage", "--clear-end is only available for entry update."), false}
			request.clear_end = true
			request.set_end = false
			has_entry_payload = true
			index += 1
			continue
		}
		if args[index] == "--clear-due" {
			if request.command != .Entry_Update {return {}, calendar_cli_error(request.command, 2, "usage", "--clear-due is only available for entry update."), false}
			request.clear_due = true
			request.set_due = false
			has_entry_payload = true
			index += 1
			continue
		}
		if args[index] == "--clear-location" {
			if request.command != .Entry_Update {return {}, calendar_cli_error(request.command, 2, "usage", "--clear-location is only available for entry update."), false}
			request.clear_location = true
			request.set_location = false
			has_entry_payload = true
			index += 1
			continue
		}
		if args[index] == "--clear-source-url" {
			if request.command != .Entry_Update {return {}, calendar_cli_error(request.command, 2, "usage", "--clear-source-url is only available for entry update."), false}
			request.clear_source_url = true
			request.set_source_url = false
			has_entry_payload = true
			index += 1
			continue
		}
		if args[index] == "--clear-reminder" {
			if request.command != .Entry_Update {return {}, calendar_cli_error(request.command, 2, "usage", "--clear-reminder is only available for entry update."), false}
			request.clear_reminder = true
			request.set_reminder = false
			has_entry_payload = true
			index += 1
			continue
		}
		if args[index] == "--clear-recurrence" {
			if request.command != .Entry_Update {return {}, calendar_cli_error(request.command, 2, "usage", "--clear-recurrence is only available for entry update."), false}
			request.clear_recurrence = true
			request.set_recurrence = false
			has_entry_payload = true
			index += 1
			continue
		}
		if index+1 >= len(args) {
			return {}, calendar_cli_error(request.command, 2, "usage", fmt.tprintf("Missing value for %s.", args[index])), false
		}
		flag, value := args[index], args[index+1]
		switch flag {
		case "--id": request.id = value
		case "--from": request.from = value
		case "--to": request.to = value
		case "--query": request.query = value
		case "--baseline": request.baseline = value
		case "--control": request.target_control = value
		case "--key": request.key = value
		case "--modifiers": request.modifiers = value
		case "--path": request.path = value
		case "--if-revision":
			parsed, ok := strconv.parse_int(value)
			if !ok || parsed < 1 {return {}, calendar_cli_error(request.command, 2, "usage", "--if-revision must be a positive integer."), false}
			request.if_revision = parsed
		case "--text":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--text is only available for entry create/update."), false}
			entry_input.original_text = value
			request.set_text = true
			has_entry_payload = true
		case "--start":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--start is only available for entry create/update."), false}
			parsed, ok := calendar_cli_parse_entry_timestamp(value)
			if !ok {return {}, calendar_cli_error(request.command, 2, "usage", "--start must be a Unix timestamp or a supported datetime."), false}
			entry_input.start_at = parsed
			request.set_start = true
			request.clear_start = false
			has_entry_payload = true
		case "--end":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--end is only available for entry create/update."), false}
			parsed, ok := calendar_cli_parse_entry_timestamp(value)
			if !ok {return {}, calendar_cli_error(request.command, 2, "usage", "--end must be a Unix timestamp or a supported datetime."), false}
			entry_input.end_at = parsed
			request.set_end = true
			request.clear_end = false
			has_entry_payload = true
		case "--due":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--due is only available for entry create/update."), false}
			parsed, ok := calendar_cli_parse_entry_timestamp(value)
			if !ok {return {}, calendar_cli_error(request.command, 2, "usage", "--due must be a Unix timestamp or a supported datetime."), false}
			entry_input.due_at = parsed
			request.set_due = true
			request.clear_due = false
			has_entry_payload = true
		case "--location":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--location is only available for entry create/update."), false}
			entry_input.location = value
			request.set_location = true
			request.clear_location = false
			has_entry_payload = true
		case "--source-url":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--source-url is only available for entry create/update."), false}
			entry_input.source_url = value
			request.set_source_url = true
			request.clear_source_url = false
			has_entry_payload = true
		case "--reminder":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--reminder is only available for entry create/update."), false}
			parsed, ok := calendar_cli_parse_entry_reminder_timestamp(value)
			if !ok {return {}, calendar_cli_error(request.command, 2, "usage", "--reminder must be a Unix timestamp or a supported datetime."), false}
			entry_input.reminder_at = parsed
			request.set_reminder = true
			request.clear_reminder = false
			has_entry_payload = true
		case "--recurrence":
			if !build_entry_input {return {}, calendar_cli_error(request.command, 2, "usage", "--recurrence is only available for entry create/update."), false}
			parsed, ok := calendar_cli_parse_entry_recurrence(value)
			if !ok {return {}, calendar_cli_error(request.command, 2, "usage", "--recurrence requires a non-negative integer."), false}
			entry_input.recurrence_seconds = parsed
			request.set_recurrence = true
			request.clear_recurrence = false
			has_entry_payload = true
		case "--name":
			if request.command != .Birthday_Create {return {}, calendar_cli_error(request.command, 2, "usage", "--name is only available for birthday create."), false}
			request.birthday_name = value
		case "--date":
			if request.command != .Birthday_Create {return {}, calendar_cli_error(request.command, 2, "usage", "--date is only available for birthday create."), false}
			request.birthday_date = value
		case "--advance-days":
			if request.command != .Birthday_Create {return {}, calendar_cli_error(request.command, 2, "usage", "--advance-days is only available for birthday create."), false}
			parsed, ok := strconv.parse_int(value)
			if !ok || parsed < 0 {return {}, calendar_cli_error(request.command, 2, "usage", "--advance-days requires a non-negative integer."), false}
			request.birthday_advance_days = parsed
		case "--days":
			if request.command != .Birthday_Default {return {}, calendar_cli_error(request.command, 2, "usage", "--days is only available for birthday default."), false}
			parsed, ok := strconv.parse_int(value)
			if !ok || parsed < 1 {return {}, calendar_cli_error(request.command, 2, "usage", "--days requires a positive integer."), false}
			request.birthday_advance_days = parsed
		case:
			return {}, calendar_cli_error(request.command, 2, "usage", fmt.tprintf("Unknown option: %s.", flag)), false
		}
		index += 2
	}
	if build_entry_input && has_entry_payload {
		if request.command == .Entry_Create && len(strings.trim_space(entry_input.original_text)) == 0 {
			return {}, calendar_cli_error(
				request.command,
				2,
				"usage",
				"entry create requires --text.",
			), false
		}
		if request.command == .Entry_Create && len(entry_input.end_at) > 0 && len(entry_input.start_at) == 0 {
			return {}, calendar_cli_error(
				request.command,
				2,
				"usage",
				"entry start is required when end is set.",
			), false
		}
		if request.command == .Entry_Create && entry_input.recurrence_seconds > 0 && len(entry_input.due_at) == 0 {
			return {}, calendar_cli_error(
				request.command,
				2,
				"usage",
				"entry recurrence requires --due.",
			), false
		}
		if request.command == .Entry_Create && !agenda_input_valid(&entry_input) {
			return {}, calendar_cli_error(request.command, 2, "usage", "entry input is invalid."), false
		}
		request.use_stdin_input = false
		input_json, encoded := calendar_cli_entry_payload_to_json(entry_input)
		if !encoded {
			return {}, calendar_cli_error(
				request.command,
				6,
				"internal_error",
				"Could not encode entry payload.",
			), false
		}
		request.input = input_json
		if request.command == .Entry_Update {
			request.command = .Entry_Patch
		}
	}
	if request.command == .Birthday_Create {
		if len(strings.trim_space(request.birthday_name)) == 0 {
			return {}, calendar_cli_error(
				request.command,
				2,
				"usage",
				"birthday create requires --name.",
			), false
		}
		if len(request.birthday_date) == 0 {
			return {}, calendar_cli_error(
				request.command,
				2,
				"usage",
				"birthday create requires --date.",
			), false
		}
	}
	if request.command == .UI_Bridge_Pointer && len(request.target_control) == 0 {
		return {}, calendar_cli_error(
			request.command,
			2,
			"usage",
			"ui bridge-pointer requires --control.",
		), false
	}
	if (request.command == .Archive_Export ||
	    request.command == .Archive_Inspect ||
	    request.command == .Archive_Import) && len(request.path) == 0 {
		return {}, calendar_cli_error(
			request.command,
			2,
			"usage",
			"The archive command requires --path.",
		), false
	}
	if request.command == .Archive_Import && !request.replace {
		return {}, calendar_cli_error(
			request.command,
			2,
			"replacement_not_confirmed",
			"archive import requires --replace.",
		), false
	}
	if request.command == .UI_Bridge_Keyboard {
		if request.key != "up" && request.key != "down" {
			return {}, calendar_cli_error(
				request.command,
				2,
				"usage",
				"ui bridge-keyboard requires --key up or --key down.",
			), false
		}
		if len(request.modifiers) == 0 {request.modifiers = "none"}
		if request.modifiers != "none" && request.modifiers != "command" {
			return {}, calendar_cli_error(
				request.command,
				2,
				"usage",
				"--modifiers must be none or command.",
			), false
		}
	}
	return request, {}, true
}

calendar_cli_execute :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	if request.command == .Archive_Export ||
	   request.command == .Archive_Inspect ||
	   request.command == .Archive_Import {
		return calendar_archive_cli_execute(request)
	}
	if (request.command >= .Entry_Create && request.command <= .Chore_Done) ||
	   request.command == .Entry_Patch {
		return agenda_cli_execute(request)
	}
	if request.command >= .Birthday_Create && request.command <= .Birthday_Default {
		return birthday_cli_execute(request)
	}
	#partial switch request.command {
	case .Reminder_Status:
		return {
			output = calendar_cli_encode(Calendar_CLI_Reminder_Response{
				ok = true,
				command = calendar_cli_command_name(request.command),
				data = {
					authorization = calendar_notification_authorization_name(),
					pending_limit = 48,
					executable_action = "DISPLAY",
					snooze_seconds = 600,
				},
			}),
		}
	case .Update_Check:
		if !calendar_ui_check_for_updates(false) {
			return calendar_cli_error(
				request.command,
				6,
				"updater_unavailable",
				"The release updater is not available in this build.",
			)
		}
		return {
			output = calendar_cli_encode(Calendar_CLI_Update_Response{
				ok = true,
				command = calendar_cli_command_name(request.command),
				data = {
					checking = true,
					version = updater_version_label(),
				},
			}),
		}
	case .UI_Snapshot:
		return calendar_ui_diagnostic_snapshot_command(request)
	case .UI_Check:
		return calendar_ui_diagnostic_check_command(request)
	case .UI_Modal_State, .UI_Modal_Dismiss:
		modal := calendar_active_modal()
		kind := calendar_modal_kind_name(modal.kind)
		dismissal := calendar_modal_dismissal_name(modal.dismissal)
		dismissed := false
		if request.command == .UI_Modal_Dismiss && modal.kind != .None {
			dismissed = calendar_modal_request_dismiss()
		}
		return {
			output = calendar_cli_encode(Calendar_CLI_Modal_Response{
				ok = true,
				command = calendar_cli_command_name(request.command),
				data = {
					kind = kind,
					dismissal = dismissal,
					dismissed = dismissed,
				},
			}),
		}
	case .UI_Bridge_Pointer:
		if pointer_error := calendar_ui_post_pointer_click(request.target_control);
		   len(pointer_error) > 0 {
			return calendar_cli_error(
				request.command,
				3,
				"pointer_failed",
				pointer_error,
			)
		}
		return {
			output = calendar_cli_encode(Calendar_CLI_UI_Bridge_Response{
				ok = true,
				command = calendar_cli_command_name(request.command),
				data = {control=request.target_control},
			}),
		}
	case .UI_Bridge_Keyboard:
		if keyboard_error := calendar_ui_post_keyboard_event(
			request.key,
			request.modifiers,
		); len(keyboard_error) > 0 {
			return calendar_cli_error(
				request.command,
				3,
				"keyboard_failed",
				keyboard_error,
			)
		}
		return {
			output = calendar_cli_encode(Calendar_CLI_UI_Bridge_Response{
				ok = true,
				command = calendar_cli_command_name(request.command),
				data = {key=request.key, modifiers=request.modifiers},
			}),
		}
	case .None:
	}
	return calendar_cli_error(request.command, 2, "usage", "Unknown command.")
}
