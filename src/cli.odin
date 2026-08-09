package main

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"

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
	Archive_Export,
	Archive_Inspect,
	Archive_Import,
	Update_Check,
}

Calendar_CLI_Request :: struct {
	command: Calendar_CLI_Command,
	input: string,
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
}

calendar_cli_command_reads_input :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .Entry_Create ||
	       command == .Entry_Update ||
	       command == .Proposal_Submit
}

calendar_cli_command_mutates_database :: proc(command: Calendar_CLI_Command) -> bool {
	return command == .Entry_Create || command == .Entry_Update ||
	       command == .Entry_Complete || command == .Entry_Reopen ||
	       command == .Entry_Dismiss || command == .Entry_Restore ||
	       command == .Proposal_Submit || command == .Proposal_Confirm ||
	       command == .Proposal_Reject || command == .Chore_Done ||
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
	case .Archive_Export: return "archive export"
	case .Archive_Inspect: return "archive inspect"
	case .Archive_Import: return "archive import"
	case .Update_Check: return "update check"
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
	request: Calendar_CLI_Request
	if len(args) < 2 {
		return {}, calendar_cli_error(.None, 2, "usage", "Expected an entry, agenda, proposal, chore, archive, update, reminder, or UI command."), false
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
	case group == "archive" && action == "export": request.command = .Archive_Export
	case group == "archive" && action == "inspect": request.command = .Archive_Inspect
	case group == "archive" && action == "import": request.command = .Archive_Import
	case group == "update" && action == "check": request.command = .Update_Check
	case:
		return {}, calendar_cli_error(.None, 2, "usage", "Unknown command."), false
	}
	for index := 2; index < len(args); {
		if args[index] == "--replace" {
			request.replace = true
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
		case:
			return {}, calendar_cli_error(request.command, 2, "usage", fmt.tprintf("Unknown option: %s.", flag)), false
		}
		index += 2
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
	if request.command >= .Entry_Create && request.command <= .Chore_Done {
		return agenda_cli_execute(request)
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
