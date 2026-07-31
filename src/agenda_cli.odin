package main

import "core:encoding/json"
import "core:strconv"

Agenda_CLI_Entry_Data :: struct {entry: Agenda_Entry}
Agenda_CLI_Entries_Data :: struct {entries: []Agenda_Entry}
Agenda_CLI_Proposal_Data :: struct {proposal: Agenda_Proposal}
Agenda_CLI_Entry_Response :: struct {ok: bool, command: string, data: Agenda_CLI_Entry_Data}
Agenda_CLI_Entries_Response :: struct {ok: bool, command: string, data: Agenda_CLI_Entries_Data}
Agenda_CLI_Proposal_Response :: struct {ok: bool, command: string, data: Agenda_CLI_Proposal_Data}

agenda_cli_id :: proc(request: Calendar_CLI_Request) -> (i64, bool) {
	id, ok := strconv.parse_i64(request.id)
	return id, ok && id > 0
}

agenda_cli_entry_result :: proc(command: Calendar_CLI_Command, entry: Agenda_Entry) -> Calendar_CLI_Result {
	encoded := calendar_cli_encode(Agenda_CLI_Entry_Response{
		ok=true, command=calendar_cli_command_name(command), data={entry=entry},
	})
	owned := entry
	agenda_entry_destroy(&owned)
	return {output=encoded}
}

agenda_cli_mutation_error :: proc(command: Calendar_CLI_Command, code: string) -> Calendar_CLI_Result {
	message := "The agenda mutation failed."
	exit_code := 6
	switch code {
	case "not_found": message = "The agenda record was not found."; exit_code = 3
	case "revision_conflict": message = "The entry revision changed."; exit_code = 5
	case "proposal_resolved": message = "The proposal is no longer pending."; exit_code = 5
	case "invalid_entry", "invalid_proposal", "invalid_state": message = "The input document is invalid."; exit_code = 3
	}
	return calendar_cli_error(command, exit_code, code, message)
}

agenda_cli_execute :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	#partial switch request.command {
	case .Entry_Create:
		input: Agenda_Entry_Input
		if error := json.unmarshal(transmute([]u8)request.input, &input); error != nil {
			return agenda_cli_mutation_error(request.command, "invalid_entry")
		}
		entry, created := agenda_entry_create(&input)
		if !created {
			if !agenda_input_valid(&input) {return agenda_cli_mutation_error(request.command, "invalid_entry")}
			return calendar_cli_error(request.command, 6, "storage_failed", sqlite_error(calendar_database))
		}
		return agenda_cli_entry_result(request.command, entry)
	case .Entry_Update:
		id, valid_id := agenda_cli_id(request)
		if !valid_id || request.if_revision < 1 {return calendar_cli_error(request.command, 2, "usage", "entry update requires --id and --if-revision.")}
		input: Agenda_Entry_Input
		if error := json.unmarshal(transmute([]u8)request.input, &input); error != nil {
			return agenda_cli_mutation_error(request.command, "invalid_entry")
		}
		entry, code := agenda_entry_update(id, request.if_revision, &input)
		if len(code) > 0 {return agenda_cli_mutation_error(request.command, code)}
		return agenda_cli_entry_result(request.command, entry)
	case .Entry_Get:
		id, valid_id := agenda_cli_id(request)
		if !valid_id {return calendar_cli_error(request.command, 2, "usage", "entry get requires --id.")}
		entry, found := agenda_entry_get(id)
		if !found {return agenda_cli_mutation_error(request.command, "not_found")}
		return agenda_cli_entry_result(request.command, entry)
	case .Entry_List, .Entry_Search, .Agenda_Query:
		entries := agenda_entries_list(request.from, request.to, request.query)
		encoded := calendar_cli_encode(Agenda_CLI_Entries_Response{
			ok=true, command=calendar_cli_command_name(request.command), data={entries=entries[:]},
		})
		agenda_entries_destroy(&entries)
		return {output=encoded}
	case .Entry_Complete, .Entry_Reopen, .Entry_Dismiss, .Entry_Restore:
		id, valid_id := agenda_cli_id(request)
		if !valid_id || request.if_revision < 1 {return calendar_cli_error(request.command, 2, "usage", "The state change requires --id and --if-revision.")}
		state := "active"
		if request.command == .Entry_Complete {state = "completed"}
		if request.command == .Entry_Dismiss {state = "dismissed"}
		entry, code := agenda_entry_set_state(id, request.if_revision, state)
		if len(code) > 0 {return agenda_cli_mutation_error(request.command, code)}
		return agenda_cli_entry_result(request.command, entry)
	case .Proposal_Submit:
		input: Agenda_Proposal_Input
		if error := json.unmarshal(transmute([]u8)request.input, &input); error != nil {
			return agenda_cli_mutation_error(request.command, "invalid_proposal")
		}
		proposal, code := agenda_proposal_submit(&input)
		if len(code) > 0 {return agenda_cli_mutation_error(request.command, code)}
		encoded := calendar_cli_encode(Agenda_CLI_Proposal_Response{
			ok=true, command=calendar_cli_command_name(request.command), data={proposal=proposal},
		})
		agenda_proposal_destroy(&proposal)
		return {output=encoded}
	case .Proposal_Get:
		id, valid_id := agenda_cli_id(request)
		if !valid_id {return calendar_cli_error(request.command, 2, "usage", "proposal get requires --id.")}
		proposal, found := agenda_proposal_get(id)
		if !found {return agenda_cli_mutation_error(request.command, "not_found")}
		encoded := calendar_cli_encode(Agenda_CLI_Proposal_Response{
			ok=true, command=calendar_cli_command_name(request.command), data={proposal=proposal},
		})
		agenda_proposal_destroy(&proposal)
		return {output=encoded}
	case .Proposal_Confirm, .Proposal_Reject:
		id, valid_id := agenda_cli_id(request)
		if !valid_id {return calendar_cli_error(request.command, 2, "usage", "The proposal decision requires --id.")}
		entry, code := agenda_proposal_resolve(id, request.command == .Proposal_Confirm)
		if len(code) > 0 {return agenda_cli_mutation_error(request.command, code)}
		return agenda_cli_entry_result(request.command, entry)
	case:
	}
	return calendar_cli_error(request.command, 2, "usage", "Unknown agenda command.")
}
