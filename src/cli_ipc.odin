package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import local_command "local_command:."

Calendar_CLI_IPC_Response :: struct {
	exit_code: int,
	output: string,
}

Calendar_CLI_IPC_Work :: struct {
	request: Calendar_CLI_Request,
	result: Calendar_CLI_Result,
}

calendar_cli_database_owner: local_command.Owner_Lock
calendar_cli_ipc_server: local_command.Server
calendar_cli_ipc_work: ^Calendar_CLI_IPC_Work

calendar_cli_lock_path :: proc() -> string {
	return fmt.tprintf("%s/calendar.lock", calendar_support_dir())
}

calendar_cli_socket_path :: proc() -> string {
	return fmt.tprintf("%s/control.sock", calendar_support_dir())
}

calendar_cli_database_try_acquire :: proc() -> bool {
	if calendar_cli_database_owner.held {return true}
	_ = os.make_directory(calendar_support_dir())
	return local_command.owner_lock_try_acquire(
		&calendar_cli_database_owner,
		calendar_cli_lock_path(),
	)
}

calendar_cli_database_release :: proc() {
	local_command.owner_lock_release(&calendar_cli_database_owner)
}

calendar_cli_ipc_request_destroy :: proc(request: ^Calendar_CLI_Request) {
	if request == nil {return}
	delete(request.input)
	delete(request.id)
	delete(request.from)
	delete(request.to)
	delete(request.query)
	delete(request.baseline)
	delete(request.target_control)
	delete(request.key)
	delete(request.modifiers)
	delete(request.path)
	request^ = {}
}

calendar_cli_msg_void_sel_id_bool :: proc(
	receiver: Id,
	selector, action: Sel,
	object: Id,
	wait: bool,
) {
	p := transmute(proc "c" (Id, Sel, Sel, Id, bool))objc_send_address
	p(receiver, selector, action, object, wait)
}

calendar_on_cli_ipc_request :: proc "c" (
	self: Id,
	command: Sel,
	sender: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if calendar_cli_ipc_work == nil {return}
	calendar_cli_ipc_work.result = calendar_cli_execute(
		calendar_cli_ipc_work.request,
	)
	if calendar_cli_ipc_work.result.exit_code == 0 &&
	   calendar_cli_command_mutates_database(
		calendar_cli_ipc_work.request.command,
	) {
		calendar_ui_reload_data()
		calendar_notification_reconcile()
		calendar_ui.needs_redraw = true
	}
}

calendar_cli_ipc_send_result :: proc(
	connection: local_command.Connection,
	result: Calendar_CLI_Result,
) -> bool {
	wire_bytes, encode_error := json.marshal(Calendar_CLI_IPC_Response{
		exit_code = result.exit_code,
		output = result.output,
	})
	if encode_error != nil {return false}
	defer delete(wire_bytes)
	return local_command.connection_send_response(connection, wire_bytes)
}

calendar_cli_ipc_read_error :: proc(
	status: local_command.Read_Status,
) -> (Calendar_CLI_Result, bool) {
	switch status {
	case .Too_Large:
		return calendar_cli_error(
			.None,
			3,
			"ipc_request_too_large",
			"The app request exceeds the 64 KiB limit.",
		), true
	case .Timeout:
		return calendar_cli_error(
			.None,
			6,
			"ipc_request_timeout",
			"The app request was not received before the deadline.",
		), true
	case .Invalid_Length:
		return calendar_cli_error(
			.None,
			3,
			"ipc_invalid_request",
			"The app request has an invalid length.",
		), true
	case .Success, .Closed, .IO_Error:
	}
	return {}, false
}

calendar_cli_ipc_handle_request :: proc(
	user_data: rawptr,
	connection: local_command.Connection,
	status: local_command.Read_Status,
	request_bytes: []u8,
) {
	if result, handled := calendar_cli_ipc_read_error(status); handled {
		defer delete(result.output)
		_ = calendar_cli_ipc_send_result(connection, result)
		return
	}
	if status != .Success {return}

	request: Calendar_CLI_Request
	if decode_error := json.unmarshal(request_bytes, &request);
	   decode_error != nil {
		result := calendar_cli_error(
			.None,
			3,
			"ipc_invalid_request",
			"The app request is not valid JSON.",
		)
		defer delete(result.output)
		_ = calendar_cli_ipc_send_result(connection, result)
		return
	}
	defer calendar_cli_ipc_request_destroy(&request)
	work := Calendar_CLI_IPC_Work{request=request}
	calendar_cli_ipc_work = &work
	calendar_cli_msg_void_sel_id_bool(
		calendar_ui.delegate,
		sel_registerName(
			"performSelectorOnMainThread:withObject:waitUntilDone:",
		),
		sel_registerName("calendarCLIRequest:"),
		nil,
		true,
	)
	calendar_cli_ipc_work = nil
	defer delete(work.result.output)
	_ = calendar_cli_ipc_send_result(connection, work.result)
}

calendar_cli_ipc_server_start :: proc() -> bool {
	return local_command.server_start(&calendar_cli_ipc_server, {
		path = calendar_cli_socket_path(),
		handler = calendar_cli_ipc_handle_request,
	}) == .None
}

calendar_cli_ipc_server_stop :: proc() {
	local_command.server_stop(&calendar_cli_ipc_server)
}

calendar_cli_ipc_try_request :: proc(
	request: Calendar_CLI_Request,
) -> (Calendar_CLI_Result, bool) {
	request_bytes, encode_error := json.marshal(request)
	if encode_error != nil {
		return calendar_cli_error(
			request.command,
			6,
			"internal_error",
			"The CLI request could not be encoded.",
		), true
	}
	defer delete(request_bytes)
	response_bytes, client_status := local_command.client_exchange(
		calendar_cli_socket_path(),
		request_bytes,
		context.temp_allocator,
	)
	switch client_status {
	case .Success:
	case .Invalid_Path, .Socket_Failed, .Connect_Failed:
		return {}, false
	case .Request_Too_Large:
		return calendar_cli_error(
			request.command,
			3,
			"ipc_request_too_large",
			"The app request exceeds the 64 KiB limit.",
		), true
	case .Send_Failed:
		return calendar_cli_error(
			request.command,
			6,
			"ipc_failed",
			"The CLI request could not reach the running application.",
		), true
	case .Read_Failed:
		return calendar_cli_error(
			request.command,
			6,
			"ipc_failed",
			"The running application did not return a response.",
		), true
	}
	response: Calendar_CLI_IPC_Response
	if decode_error := json.unmarshal(response_bytes, &response);
	   decode_error != nil {
		return calendar_cli_error(
			request.command,
			6,
			"ipc_failed",
			"The running application returned an invalid response.",
		), true
	}
	return {output=response.output, exit_code=response.exit_code}, true
}
