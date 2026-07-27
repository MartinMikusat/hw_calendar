package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import match_sorter "match_sorter:."

Calendar_CLI_Command :: enum {
	None,
	ICal_Validate,
	ICal_Import,
	ICal_Export,
	Recurrence_Expand,
	Event_Create,
	Event_Update,
	Event_Delete,
	Event_Get,
	Event_List,
	Event_Search,
	Reminder_Status,
	UI_Snapshot,
	UI_Check,
}

Calendar_CLI_Request :: struct {
	command: Calendar_CLI_Command,
	input: string,
	rule: string,
	start: string,
	uid: string,
	scope: string,
	occurrence: string,
	from: string,
	to: string,
	query: string,
	output: string,
	baseline: string,
	limit: int,
}

calendar_cli_command_reads_input :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .ICal_Validate || command == .ICal_Import ||
	       command == .Event_Create || command == .Event_Update ||
	       command == .Event_Delete
}

calendar_cli_command_mutates_database :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .ICal_Import || command == .Event_Create ||
	       command == .Event_Update || command == .Event_Delete
}

calendar_cli_command_requires_gui :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .UI_Snapshot || command == .UI_Check
}

calendar_cli_command_uses_database :: proc(command: Calendar_CLI_Command) -> bool {
	return command != .ICal_Validate && command != .Recurrence_Expand
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

Calendar_CLI_Diagnostic_Output :: struct {
	severity: string,
	line: int,
	code: string,
	message: string,
}

Calendar_CLI_Validate_Data :: struct {
	valid: bool,
	components: int,
	diagnostics: []Calendar_CLI_Diagnostic_Output,
}

Calendar_CLI_Validate_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Validate_Data,
}

Calendar_CLI_Import_Data :: struct {
	document_id: i64,
	components: int,
	diagnostics: []Calendar_CLI_Diagnostic_Output,
}

Calendar_CLI_Import_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Import_Data,
}

Calendar_CLI_Event_Output :: struct {
	uid: string,
	recurrence_id: string `json:"recurrence_id,omitempty"`,
	summary: string,
	description: string `json:"description,omitempty"`,
	location: string `json:"location,omitempty"`,
	url: string `json:"url,omitempty"`,
	categories: string `json:"categories,omitempty"`,
	important: bool,
	status: string `json:"status,omitempty"`,
	sequence: int,
	start: string,
	end: string,
	rrule: string `json:"rrule,omitempty"`,
}

Calendar_CLI_Event_List_Data :: struct {
	events: []Calendar_CLI_Event_Output,
	truncated: bool,
}

Calendar_CLI_Event_List_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Event_List_Data,
}

Calendar_CLI_Mutation_Data :: struct {
	uid: string,
	recurrence_id: string `json:"recurrence_id,omitempty"`,
	document_id: i64,
	status: string,
}

Calendar_CLI_Mutation_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Mutation_Data,
}

Calendar_CLI_Export_Data :: struct {
	path: string,
	bytes: int,
}

Calendar_CLI_Export_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Export_Data,
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

Calendar_CLI_Recurrence_Data :: struct {
	occurrences: []string,
	truncated: bool,
}

Calendar_CLI_Recurrence_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_Recurrence_Data,
}

Calendar_Event_Input :: struct {
	schema_version: int,
	uid: string,
	recurrence_id: string,
	summary: string,
	description: string,
	location: string,
	url: string,
	categories: []string,
	important: bool,
	dtstart: string,
	dtend: string,
	rrule: string,
	rdates: []string,
	exdates: []string,
	reminder_offsets_seconds: []int,
	sequence: int,
}

calendar_event_input_destroy :: proc(input: ^Calendar_Event_Input) {
	if input == nil {return}
	delete(input.uid)
	delete(input.recurrence_id)
	delete(input.summary)
	delete(input.description)
	delete(input.location)
	delete(input.url)
	for value in input.categories {delete(value)}
	delete(input.categories)
	delete(input.dtstart)
	delete(input.dtend)
	delete(input.rrule)
	for value in input.rdates {delete(value)}
	delete(input.rdates)
	for value in input.exdates {delete(value)}
	delete(input.exdates)
	delete(input.reminder_offsets_seconds)
	input^ = {}
}

calendar_cli_command_name :: proc(command: Calendar_CLI_Command) -> string {
	switch command {
	case .ICal_Validate: return "ical validate"
	case .ICal_Import: return "ical import"
	case .ICal_Export: return "ical export"
	case .Recurrence_Expand: return "recurrence expand"
	case .Event_Create: return "event create"
	case .Event_Update: return "event update"
	case .Event_Delete: return "event delete"
	case .Event_Get: return "event get"
	case .Event_List: return "event list"
	case .Event_Search: return "event search"
	case .Reminder_Status: return "reminder status"
	case .UI_Snapshot: return "ui snapshot"
	case .UI_Check: return "ui check"
	case .None: return "unknown"
	}
	return "unknown"
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
	request := Calendar_CLI_Request{limit=10_000}
	if len(args) < 2 {
		return {}, calendar_cli_error(.None, 2, "usage", "Expected an iCalendar, event, reminder, or UI command."), false
	}
	group, action := args[0], args[1]
	switch {
	case group == "ical" && action == "validate": request.command = .ICal_Validate
	case group == "ical" && action == "import": request.command = .ICal_Import
	case group == "ical" && action == "export": request.command = .ICal_Export
	case group == "recurrence" && action == "expand":
		request.command = .Recurrence_Expand
	case group == "event" && action == "create": request.command = .Event_Create
	case group == "event" && action == "update": request.command = .Event_Update
	case group == "event" && action == "delete": request.command = .Event_Delete
	case group == "event" && action == "get": request.command = .Event_Get
	case group == "event" && action == "list": request.command = .Event_List
	case group == "event" && action == "search": request.command = .Event_Search
	case group == "reminder" && action == "status": request.command = .Reminder_Status
	case group == "ui" && action == "snapshot": request.command = .UI_Snapshot
	case group == "ui" && action == "check": request.command = .UI_Check
	case:
		return {}, calendar_cli_error(.None, 2, "usage", "Unknown command."), false
	}
	for index := 2; index < len(args); {
		if args[index] == "--all" {
			index += 1
			continue
		}
		if index+1 >= len(args) {
			return {}, calendar_cli_error(request.command, 2, "usage", fmt.tprintf("Missing value for %s.", args[index])), false
		}
		flag, value := args[index], args[index+1]
		switch flag {
		case "--rule": request.rule = value
		case "--start": request.start = value
		case "--uid": request.uid = value
		case "--scope": request.scope = value
		case "--occurrence": request.occurrence = value
		case "--from": request.from = value
		case "--to": request.to = value
		case "--query": request.query = value
		case "--output": request.output = value
		case "--baseline": request.baseline = value
		case "--limit":
			parsed, ok := strconv.parse_int(value)
			if !ok || parsed < 1 || parsed > ICAL_MAX_EXPANSION_RESULTS {
				return {}, calendar_cli_error(request.command, 2, "usage", "--limit must be between 1 and 100000."), false
			}
			request.limit = parsed
		case:
			return {}, calendar_cli_error(request.command, 2, "usage", fmt.tprintf("Unknown option: %s.", flag)), false
		}
		index += 2
	}
	return request, {}, true
}

calendar_cli_diagnostics :: proc(
	document: ^ICal_Document,
	allocator := context.allocator,
) -> []Calendar_CLI_Diagnostic_Output {
	result := make([]Calendar_CLI_Diagnostic_Output, len(document.diagnostics), allocator)
	for diagnostic, index in document.diagnostics {
		severity := "info"
		switch diagnostic.severity {
		case .Warning: severity = "warning"
		case .Error: severity = "error"
		case .Info:
		}
		result[index] = {
			severity = severity,
			line = diagnostic.line,
			code = diagnostic.code,
			message = diagnostic.message,
		}
	}
	return result
}

calendar_cli_recurrence_expand :: proc(
	request: Calendar_CLI_Request,
) -> Calendar_CLI_Result {
	rule, parse_error, rule_ok := ical_parse_recurrence(request.rule)
	if !rule_ok {
		defer delete(parse_error)
		return calendar_cli_error(
			request.command,
			3,
			"invalid_recurrence",
			parse_error,
		)
	}
	defer ical_recurrence_destroy(&rule)
	start, start_ok := ical_parse_date_time(request.start)
	range_start, from_ok := calendar_cli_parse_date_input(request.from)
	range_end, to_ok := calendar_cli_parse_date_input(request.to)
	if !start_ok || !from_ok || !to_ok ||
	   ical_date_time_compare(range_start, range_end) >= 0 {
		return calendar_cli_error(
			request.command,
			2,
			"usage",
			"recurrence expand requires valid --rule, --start, --from, and --to values.",
		)
	}
	expansion := ical_expand_recurrence(
		&rule,
		start,
		range_start,
		range_end,
		request.limit,
	)
	defer ical_expansion_destroy(&expansion)
	if len(expansion.error) > 0 {
		return calendar_cli_error(
			request.command,
			3,
			"expansion_failed",
			expansion.error,
		)
	}
	outputs := make([]string, len(expansion.occurrences))
	defer {
		for output in outputs {delete(output)}
		delete(outputs)
	}
	for occurrence, index in expansion.occurrences {
		outputs[index] = ical_format_date_time(occurrence)
	}
	return {
		output = calendar_cli_encode(Calendar_CLI_Recurrence_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {
				occurrences = outputs,
				truncated = expansion.truncated,
			},
		}),
	}
}

calendar_cli_validate :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	if len(request.input) == 0 {
		return calendar_cli_error(request.command, 3, "read_failed", "Standard input could not be read.")
	}
	document := ical_parse(request.input)
	defer ical_document_destroy(&document)
	valid := true
	for diagnostic in document.diagnostics {
		if diagnostic.severity == .Error {valid = false}
	}
	diagnostics := calendar_cli_diagnostics(&document)
	defer delete(diagnostics)
	return {
		output = calendar_cli_encode(Calendar_CLI_Validate_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {
				valid = valid,
				components = len(document.components),
				diagnostics = diagnostics,
			},
		}),
	}
}

calendar_cli_import :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	if len(request.input) == 0 {
		return calendar_cli_error(request.command, 3, "read_failed", "Standard input does not contain iCalendar data.")
	}
	document := ical_parse(request.input)
	defer ical_document_destroy(&document)
	document_id, imported := calendar_import_document(&document)
	if !imported {
		return calendar_cli_error(request.command, 6, "storage_failed", sqlite_error(calendar_database))
	}
	diagnostics := calendar_cli_diagnostics(&document)
	defer delete(diagnostics)
	return {
		output = calendar_cli_encode(Calendar_CLI_Import_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {
				document_id = document_id,
				components = len(document.components),
				diagnostics = diagnostics,
			},
		}),
	}
}

calendar_cli_export :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	if len(request.output) == 0 {
		return calendar_cli_error(request.command, 2, "usage", "ical export requires --output.")
	}
	contents, exported := calendar_export_all()
	if !exported {
		return calendar_cli_error(request.command, 6, "storage_failed", sqlite_error(calendar_database))
	}
	defer delete(contents)
	if !os.write_entire_file(request.output, transmute([]u8)contents) {
		return calendar_cli_error(request.command, 6, "write_failed", "The output file could not be written.")
	}
	return {
		output = calendar_cli_encode(Calendar_CLI_Export_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {path=request.output, bytes=len(contents)},
		}),
	}
}

calendar_cli_event_output :: proc(
	event: ^Calendar_Event,
	start, end: ICal_Date_Time,
	recurrence_id := "",
) -> Calendar_CLI_Event_Output {
	start_text := ical_format_date_time(start, context.temp_allocator)
	end_text := ical_format_date_time(end, context.temp_allocator)
	return {
		uid = ical_clone(event.uid),
		recurrence_id = ical_clone(recurrence_id),
		summary = ical_clone(event.summary),
		description = ical_clone(event.description),
		location = ical_clone(event.location),
		url = ical_clone(event.url),
		categories = ical_clone(event.categories),
		important = event.important,
		status = ical_clone(event.status),
		sequence = event.sequence,
		start = ical_clone(start_text),
		end = ical_clone(end_text),
		rrule = ical_clone(event.rrule),
	}
}

calendar_cli_event_outputs_destroy :: proc(outputs: []Calendar_CLI_Event_Output) {
	for &output in outputs {
		delete(output.uid)
		delete(output.recurrence_id)
		delete(output.summary)
		delete(output.description)
		delete(output.location)
		delete(output.url)
		delete(output.categories)
		delete(output.status)
		delete(output.start)
		delete(output.end)
		delete(output.rrule)
	}
	delete(outputs)
}

calendar_cli_parse_date_input :: proc(value: string) -> (ICal_Date_Time, bool) {
	if len(value) == 10 && value[4] == '-' && value[7] == '-' {
		year, year_ok := strconv.parse_int(value[0:4])
		month, month_ok := strconv.parse_int(value[5:7])
		day, day_ok := strconv.parse_int(value[8:10])
		result := ICal_Date_Time{
			year = year,
			month = month,
			day = day,
			is_date = true,
		}
		return result, year_ok && month_ok && day_ok &&
		               ical_date_time_valid(result)
	}
	return ical_parse_date_time(value)
}

calendar_cli_load_range :: proc(
	request: Calendar_CLI_Request,
) -> (Calendar_CLI_Event_List_Response, bool) {
	range_start, start_ok := calendar_cli_parse_date_input(request.from)
	range_end, end_ok := calendar_cli_parse_date_input(request.to)
	if !start_ok || !end_ok || ical_date_time_compare(range_start, range_end) >= 0 {
		return {}, false
	}
	events, loaded := calendar_events_load()
	if !loaded {return {}, false}
	defer calendar_events_destroy(&events)
	occurrences, truncated := calendar_expand_events(
		events[:],
		range_start,
		range_end,
		request.limit,
	)
	defer calendar_occurrences_destroy(&occurrences)
	outputs := make([]Calendar_CLI_Event_Output, len(occurrences))
	for occurrence, index in occurrences {
		outputs[index] = calendar_cli_event_output(
			&events[occurrence.event_index],
			occurrence.start,
			occurrence.end,
			occurrence.recurrence_id,
		)
	}
	response := Calendar_CLI_Event_List_Response{
		ok = true,
		command = calendar_cli_command_name(request.command),
		data = {events=outputs, truncated=truncated},
	}
	return response, true
}

calendar_event_search_summary :: proc(event: ^Calendar_Event) -> match_sorter.Extracted_Values {
	return match_sorter.single_value(event.summary)
}
calendar_event_search_description :: proc(event: ^Calendar_Event) -> match_sorter.Extracted_Values {
	return match_sorter.single_value(event.description)
}
calendar_event_search_location :: proc(event: ^Calendar_Event) -> match_sorter.Extracted_Values {
	return match_sorter.single_value(event.location)
}
calendar_event_search_url :: proc(event: ^Calendar_Event) -> match_sorter.Extracted_Values {
	return match_sorter.single_value(event.url)
}
calendar_event_search_categories :: proc(event: ^Calendar_Event) -> match_sorter.Extracted_Values {
	return match_sorter.single_value(event.categories)
}
calendar_event_search_uid :: proc(event: ^Calendar_Event) -> match_sorter.Extracted_Values {
	return match_sorter.single_value(event.uid)
}

calendar_cli_event_search :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	if len(strings.trim_space(request.query)) == 0 {
		return calendar_cli_error(request.command, 2, "usage", "event search requires --query.")
	}
	events, loaded := calendar_events_load()
	if !loaded {return calendar_cli_error(request.command, 6, "storage_failed", sqlite_error(calendar_database))}
	defer calendar_events_destroy(&events)
	search: match_sorter.Search_Context
	if error := match_sorter.search_context_init(
		&search,
		reserve_size = 64*1024*1024,
		commit_size = 64*1024,
	); error != nil {
		return calendar_cli_error(request.command, 6, "search_failed", "The search context could not be initialized.")
	}
	defer match_sorter.search_context_destroy(&search)
	keys := []match_sorter.Key(Calendar_Event){
		{getter=calendar_event_search_summary},
		{getter=calendar_event_search_description},
		{getter=calendar_event_search_location},
		{getter=calendar_event_search_url},
		{getter=calendar_event_search_categories},
		{getter=calendar_event_search_uid},
	}
	indices, search_error := match_sorter.match_indices(
		&search,
		events[:],
		request.query,
		match_sorter.Options(Calendar_Event){keys=keys},
	)
	if search_error != .None {
		return calendar_cli_error(
			request.command,
			6,
			"search_failed",
			"Event data or the query contains invalid UTF-8.",
		)
	}
	defer delete(indices)
	valid_total := 0
	for event_index in indices {
		if strings.equal_fold(events[event_index].status, "CANCELLED") {
			continue
		}
		valid_total += 1
	}
	count := min(valid_total, request.limit)
	outputs := make([]Calendar_CLI_Event_Output, count)
	result_index := 0
	for event_index in indices {
		event := &events[event_index]
		if strings.equal_fold(event.status, "CANCELLED") {continue}
		start, _ := ical_parse_date_time(event.dtstart)
		end, end_ok := ical_parse_date_time(event.dtend)
		if !end_ok {end = start}
		outputs[result_index] = calendar_cli_event_output(event, start, end, event.recurrence_id)
		result_index += 1
		if result_index >= count {break}
	}
	response := Calendar_CLI_Event_List_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {events=outputs, truncated=valid_total>count},
		}
	encoded := calendar_cli_encode(response)
	calendar_cli_event_outputs_destroy(outputs)
	return {output=encoded}
}

calendar_cli_event_get :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	if len(request.uid) == 0 {
		return calendar_cli_error(
			request.command,
			2,
			"usage",
			"event get requires --uid.",
		)
	}
	events, loaded := calendar_events_load()
	if !loaded {
		return calendar_cli_error(
			request.command,
			6,
			"storage_failed",
			sqlite_error(calendar_database),
		)
	}
	defer calendar_events_destroy(&events)
	count := 0
	for event in events {
		if event.uid == request.uid &&
		   (len(request.occurrence) == 0 ||
		    event.recurrence_id == request.occurrence) {
			count += 1
		}
	}
	if count == 0 {
		return calendar_cli_error(
			request.command,
			3,
			"not_found",
			"The event was not found.",
		)
	}
	outputs := make([]Calendar_CLI_Event_Output, count)
	output_index := 0
	for &event in events {
		if event.uid != request.uid ||
		   (len(request.occurrence) > 0 &&
		    event.recurrence_id != request.occurrence) {
			continue
		}
		start, _ := ical_parse_date_time(event.dtstart)
		end, end_ok := ical_parse_date_time(event.dtend)
		if !end_ok {end = start}
		outputs[output_index] = calendar_cli_event_output(
			&event,
			start,
			end,
			event.recurrence_id,
		)
		output_index += 1
	}
	response := Calendar_CLI_Event_List_Response{
		ok = true,
		command = calendar_cli_command_name(request.command),
		data = {events=outputs},
	}
	encoded := calendar_cli_encode(response)
	calendar_cli_event_outputs_destroy(outputs)
	return {output=encoded}
}

calendar_cli_generate_uid :: proc() -> string {
	return fmt.tprintf("%d@hw-calendar.local", time.to_unix_nanoseconds(time.now()))
}

calendar_cli_preserved_event_document :: proc(
	input: ^Calendar_Event_Input,
	cancelled, future: bool,
	dtstamp: string,
	allocator := context.allocator,
) -> (string, bool) {
	events, loaded := calendar_events_load()
	if !loaded {return "", false}
	defer calendar_events_destroy(&events)
	base: ^Calendar_Event
	for &event in events {
		if event.uid == input.uid &&
		   event.recurrence_id == input.recurrence_id {
			base = &event
			break
		}
	}
	if base == nil {return "", false}
	document, component, parsed := calendar_event_component(base)
	if !parsed {
		ical_document_destroy(&document)
		return "", false
	}
	defer ical_document_destroy(&document)
	ical_component_set_property(component, "UID", input.uid)
	ical_component_set_property(component, "DTSTAMP", dtstamp)
	ical_component_set_property(
		component,
		"SEQUENCE",
		fmt.tprintf("%d", max(0, input.sequence)),
	)
	ical_component_set_property(component, "LAST-MODIFIED", dtstamp)
	if len(input.recurrence_id) > 0 {
		recurrence := ical_component_set_property(
			component,
			"RECURRENCE-ID",
			input.recurrence_id,
		)
		if future {
			ical_property_set_parameter(
				recurrence,
				"RANGE",
				"THISANDFUTURE",
			)
		} else {
			ical_property_remove_parameter(recurrence, "RANGE")
		}
	} else {
		ical_component_remove_properties(component, "RECURRENCE-ID")
	}
	ical_component_set_property(component, "DTSTART", input.dtstart)
	ical_component_set_property(
		component,
		"DTEND",
		input.dtend,
		true,
	)
	ical_component_set_property(
		component,
		"SUMMARY",
		ical_escape_text(input.summary, context.temp_allocator),
	)
	ical_component_set_property(
		component,
		"DESCRIPTION",
		ical_escape_text(input.description, context.temp_allocator),
		true,
	)
	ical_component_set_property(
		component,
		"LOCATION",
		ical_escape_text(input.location, context.temp_allocator),
		true,
	)
	ical_component_set_property(component, "URL", input.url, true)
	categories := ""
	if len(input.categories) > 0 {
		categories = strings.join(
			input.categories,
			",",
			context.temp_allocator,
		)
	}
	ical_component_set_property(component, "CATEGORIES", categories, true)
	ical_component_set_property(
		component,
		"X-HW-IMPORTANT",
		input.important ? "TRUE" : "",
		true,
	)
	ical_component_set_property(
		component,
		"STATUS",
		cancelled ? "CANCELLED" : "",
		true,
	)
	ical_component_set_property(component, "RRULE", input.rrule, true)
	if input.rdates != nil {
		rdates := ""
		if len(input.rdates) > 0 {
			rdates = strings.join(input.rdates, ",", context.temp_allocator)
		}
		ical_component_set_property(component, "RDATE", rdates, true)
	}
	if input.exdates != nil {
		exdates := ""
		if len(input.exdates) > 0 {
			exdates = strings.join(input.exdates, ",", context.temp_allocator)
		}
		ical_component_set_property(component, "EXDATE", exdates, true)
	}
	if input.reminder_offsets_seconds != nil {
		for index := len(component.children)-1; index >= 0; index -= 1 {
			child := &component.children[index]
			if child.name != "VALARM" ||
			   !strings.equal_fold(
					calendar_property_value(child, "ACTION"),
					"DISPLAY",
			   ) {
				continue
			}
			ical_component_destroy(child)
			for move := index; move+1 < len(component.children); move += 1 {
				component.children[move] = component.children[move+1]
			}
			resize(&component.children, len(component.children)-1)
		}
		for offset in input.reminder_offsets_seconds {
			if offset < 0 {continue}
			append(&component.children, ICal_Component{
				name = ical_clone("VALARM"),
				properties = make([dynamic]ICal_Property),
				children = make([dynamic]ICal_Component),
				dirty = true,
			})
			alarm := &component.children[len(component.children)-1]
			ical_component_set_property(alarm, "ACTION", "DISPLAY")
			ical_component_set_property(
				alarm,
				"TRIGGER",
				fmt.tprintf("-PT%dS", offset),
			)
			ical_component_set_property(
				alarm,
				"DESCRIPTION",
				ical_escape_text(input.summary, context.temp_allocator),
			)
		}
	}
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	strings.write_string(
		&builder,
		"BEGIN:VCALENDAR\r\nPRODID:-//Hal Wayland//HW Calendar 0.1//EN\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\n",
	)
	ical_serialize_component(&builder, component)
	strings.write_string(&builder, "END:VCALENDAR\r\n")
	return strings.to_string(builder), true
}

calendar_cli_event_document :: proc(
	input: ^Calendar_Event_Input,
	cancelled := false,
	future := false,
	preserve_existing := false,
	allocator := context.allocator,
) -> (string, bool) {
	if input.schema_version != 1 || len(strings.trim_space(input.summary)) == 0 ||
	   len(input.dtstart) == 0 {
		return "", false
	}
	if _, ok := ical_parse_date_time(input.dtstart); !ok {return "", false}
	if len(input.dtend) > 0 {
		if _, ok := ical_parse_date_time(input.dtend); !ok {return "", false}
	}
	if len(input.rrule) > 0 {
		rule, error, ok := ical_parse_recurrence(input.rrule, context.temp_allocator)
		if !ok {delete(error, context.temp_allocator); return "", false}
		ical_recurrence_destroy(&rule)
	}
	uid := input.uid
	if len(uid) == 0 {uid = calendar_cli_generate_uid()}
	now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()))
	now.utc = true
	dtstamp := ical_format_date_time(now, context.temp_allocator)
	if preserve_existing && len(input.uid) > 0 {
		if preserved, found := calendar_cli_preserved_event_document(
			input,
			cancelled,
			future,
			dtstamp,
			allocator,
		); found {
			return preserved, true
		}
	}
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	strings.write_string(&builder, "BEGIN:VCALENDAR\r\n")
	strings.write_string(&builder, "PRODID:-//Hal Wayland//HW Calendar 0.1//EN\r\n")
	strings.write_string(&builder, "VERSION:2.0\r\n")
	strings.write_string(&builder, "CALSCALE:GREGORIAN\r\n")
	strings.write_string(&builder, "BEGIN:VEVENT\r\n")
	ical_fold_line(&builder, fmt.tprintf("UID:%s", uid))
	ical_fold_line(&builder, fmt.tprintf("DTSTAMP:%s", dtstamp))
	ical_fold_line(&builder, fmt.tprintf("SEQUENCE:%d", max(0, input.sequence)))
	if len(input.recurrence_id) > 0 {
		if future {
			ical_fold_line(
				&builder,
				fmt.tprintf("RECURRENCE-ID;RANGE=THISANDFUTURE:%s", input.recurrence_id),
			)
		} else {
			ical_fold_line(&builder, fmt.tprintf("RECURRENCE-ID:%s", input.recurrence_id))
		}
	}
	ical_fold_line(&builder, fmt.tprintf("DTSTART:%s", input.dtstart))
	if len(input.dtend) > 0 {ical_fold_line(&builder, fmt.tprintf("DTEND:%s", input.dtend))}
	ical_fold_line(&builder, fmt.tprintf("SUMMARY:%s", ical_escape_text(input.summary, context.temp_allocator)))
	if len(input.description) > 0 {ical_fold_line(&builder, fmt.tprintf("DESCRIPTION:%s", ical_escape_text(input.description, context.temp_allocator)))}
	if len(input.location) > 0 {ical_fold_line(&builder, fmt.tprintf("LOCATION:%s", ical_escape_text(input.location, context.temp_allocator)))}
	if len(input.url) > 0 {ical_fold_line(&builder, fmt.tprintf("URL:%s", input.url))}
	if len(input.categories) > 0 {
		ical_fold_line(&builder, fmt.tprintf("CATEGORIES:%s", strings.join(input.categories, ",")))
	}
	if input.important {strings.write_string(&builder, "X-HW-IMPORTANT:TRUE\r\n")}
	if cancelled {strings.write_string(&builder, "STATUS:CANCELLED\r\n")}
	if len(input.rrule) > 0 {ical_fold_line(&builder, fmt.tprintf("RRULE:%s", input.rrule))}
	if len(input.rdates) > 0 {ical_fold_line(&builder, fmt.tprintf("RDATE:%s", strings.join(input.rdates, ",")))}
	if len(input.exdates) > 0 {ical_fold_line(&builder, fmt.tprintf("EXDATE:%s", strings.join(input.exdates, ",")))}
	for offset in input.reminder_offsets_seconds {
		if offset < 0 {continue}
		strings.write_string(&builder, "BEGIN:VALARM\r\n")
		strings.write_string(&builder, "ACTION:DISPLAY\r\n")
		ical_fold_line(&builder, fmt.tprintf("TRIGGER:-PT%dS", offset))
		ical_fold_line(&builder, fmt.tprintf("DESCRIPTION:%s", ical_escape_text(input.summary, context.temp_allocator)))
		strings.write_string(&builder, "END:VALARM\r\n")
	}
	strings.write_string(&builder, "END:VEVENT\r\nEND:VCALENDAR\r\n")
	return strings.to_string(builder), true
}

calendar_cli_decode_event_input :: proc(input_text: string) -> (Calendar_Event_Input, bool) {
	if len(input_text) == 0 {return {}, false}
	input: Calendar_Event_Input
	if error := json.unmarshal(transmute([]u8)input_text, &input);
	   error != nil {
		return {}, false
	}
	return input, true
}

calendar_cli_event_mutate :: proc(
	request: Calendar_CLI_Request,
	cancelled := false,
) -> Calendar_CLI_Result {
	input, decoded := calendar_cli_decode_event_input(request.input)
	if !decoded {
		return calendar_cli_error(request.command, 3, "invalid_json", "Standard input must contain one versioned event document.")
	}
	defer calendar_event_input_destroy(&input)
	if request.command != .Event_Create {
		if len(request.uid) == 0 {
			return calendar_cli_error(request.command, 2, "usage", "The mutation requires --uid.")
		}
		delete(input.uid)
		input.uid = strings.clone(request.uid)
		scope := request.scope
		if len(scope) == 0 {scope = "all"}
		if scope != "all" && scope != "occurrence" &&
		   scope != "future" {
			return calendar_cli_error(
				request.command,
				2,
				"usage",
				"--scope must be all, occurrence, or future.",
			)
		}
		if scope == "occurrence" || scope == "future" {
			if len(request.occurrence) == 0 {
				return calendar_cli_error(request.command, 2, "usage", "The scope requires --occurrence.")
			}
			delete(input.recurrence_id)
			input.recurrence_id = strings.clone(request.occurrence)
		}
		current_sequence := input.sequence
		if events, loaded := calendar_events_load(); loaded {
			for event in events {
				if event.uid == input.uid &&
				   event.recurrence_id == input.recurrence_id {
					current_sequence = max(current_sequence, event.sequence)
					break
				}
			}
			calendar_events_destroy(&events)
		}
		input.sequence = current_sequence + 1
	}
	contents, valid := calendar_cli_event_document(
		&input,
		cancelled,
		request.scope == "future",
		request.command != .Event_Create,
	)
	if !valid {
		return calendar_cli_error(request.command, 3, "invalid_event", "The event document is incomplete or contains an invalid date or recurrence rule.")
	}
	defer delete(contents)
	document := ical_parse(contents)
	defer ical_document_destroy(&document)
	document_id, imported := calendar_import_document(&document)
	if !imported {
		return calendar_cli_error(request.command, 6, "storage_failed", sqlite_error(calendar_database))
	}
	uid := input.uid
	if len(uid) == 0 {
		event := &document.components[0].children[0]
		uid = calendar_property_value(event, "UID")
	}
	return {
		output = calendar_cli_encode(Calendar_CLI_Mutation_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {
				uid = uid,
				recurrence_id = input.recurrence_id,
				document_id = document_id,
				status = cancelled ? "cancelled" : "saved",
			},
		}),
	}
}

calendar_cli_execute :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	switch request.command {
	case .ICal_Validate: return calendar_cli_validate(request)
	case .ICal_Import: return calendar_cli_import(request)
	case .ICal_Export: return calendar_cli_export(request)
	case .Recurrence_Expand: return calendar_cli_recurrence_expand(request)
	case .Event_Create, .Event_Update: return calendar_cli_event_mutate(request)
	case .Event_Delete: return calendar_cli_event_mutate(request, true)
	case .Event_List:
		response, valid := calendar_cli_load_range(request)
		if !valid {return calendar_cli_error(request.command, 3, "invalid_range", "event list requires valid --from and --to iCalendar values.")}
		encoded := calendar_cli_encode(response)
		calendar_cli_event_outputs_destroy(response.data.events)
		return {output=encoded}
	case .Event_Search: return calendar_cli_event_search(request)
	case .Event_Get:
		return calendar_cli_event_get(request)
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
	case .UI_Snapshot:
		return calendar_ui_diagnostic_snapshot_command(request)
	case .UI_Check:
		return calendar_ui_diagnostic_check_command(request)
	case .None:
	}
	return calendar_cli_error(request.command, 2, "usage", "Unknown command.")
}
