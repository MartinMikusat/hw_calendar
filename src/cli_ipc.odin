package main

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import os2 "core:os/os2"
import "core:strings"
import "core:sys/posix"
import "core:thread"

foreign import calendar_cli_libc "system:System.framework"
foreign calendar_cli_libc {
	flock :: proc "c" (fd, operation: c.int) -> c.int ---
	close :: proc "c" (fd: c.int) -> c.int ---
}

CALENDAR_CLI_LOCK_EX :: 2
CALENDAR_CLI_LOCK_NB :: 4
CALENDAR_CLI_LOCK_UN :: 8
CALENDAR_CLI_MODE_USER_READ_WRITE :: posix.mode_t{.IRUSR, .IWUSR}

Calendar_CLI_Database_Owner :: struct {
	file: ^os2.File,
	held: bool,
}

Calendar_CLI_IPC_Response :: struct {
	exit_code: int,
	output: string,
}

Calendar_CLI_IPC_Work :: struct {
	request: Calendar_CLI_Request,
	result: Calendar_CLI_Result,
}

Calendar_CLI_IPC_State :: struct {
	thread: ^thread.Thread,
	listen_fd: posix.FD,
	running: bool,
}

calendar_cli_database_owner: Calendar_CLI_Database_Owner
calendar_cli_ipc_state: Calendar_CLI_IPC_State
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
	file, open_error := os2.open(
		calendar_cli_lock_path(),
		{.Read, .Write, .Create},
	)
	if open_error != nil {return false}
	if posix.fchmod(
		posix.FD(os2.fd(file)),
		CALENDAR_CLI_MODE_USER_READ_WRITE,
	) != .OK {
		_ = os2.close(file)
		return false
	}
	fd := c.int(os2.fd(file))
	if flock(fd, CALENDAR_CLI_LOCK_EX|CALENDAR_CLI_LOCK_NB) != 0 {
		_ = os2.close(file)
		return false
	}
	calendar_cli_database_owner = {file=file, held=true}
	return true
}

calendar_cli_database_release :: proc() {
	if !calendar_cli_database_owner.held {return}
	_ = flock(
		c.int(os2.fd(calendar_cli_database_owner.file)),
		CALENDAR_CLI_LOCK_UN,
	)
	_ = os2.close(calendar_cli_database_owner.file)
	calendar_cli_database_owner = {}
}

calendar_cli_socket_address :: proc(path: string) -> (posix.sockaddr_un, bool) {
	address: posix.sockaddr_un
	if len(path) == 0 || len(path) >= len(address.sun_path) {
		return address, false
	}
	address.sun_len = u8(size_of(address))
	address.sun_family = .UNIX
	for byte, index in path {address.sun_path[index] = c.char(byte)}
	return address, true
}

calendar_cli_socket_send_all :: proc(fd: posix.FD, bytes: []u8) -> bool {
	sent := 0
	for sent < len(bytes) {
		count := posix.send(
			fd,
			raw_data(bytes[sent:]),
			c.size_t(len(bytes))-c.size_t(sent),
			{.NOSIGNAL},
		)
		if count <= 0 {return false}
		sent += int(count)
	}
	return true
}

calendar_cli_socket_receive_all :: proc(
	fd: posix.FD,
	allocator := context.allocator,
) -> ([]u8, bool) {
	contents := make([dynamic]u8, allocator)
	success := false
	defer if !success {delete(contents)}
	buffer: [16*1024]u8
	for {
		count := posix.recv(
			fd,
			raw_data(buffer[:]),
			c.size_t(len(buffer)),
			{},
		)
		if count < 0 {return nil, false}
		if count == 0 {break}
		append(&contents, ..buffer[:int(count)])
	}
	success = true
	return contents[:], true
}

calendar_cli_ipc_request_destroy :: proc(request: ^Calendar_CLI_Request) {
	if request == nil {return}
	delete(request.input)
	delete(request.rule)
	delete(request.start)
	delete(request.uid)
	delete(request.id)
	delete(request.source)
	delete(request.calendar)
	delete(request.if_version)
	delete(request.scope)
	delete(request.occurrence)
	delete(request.from)
	delete(request.to)
	delete(request.query)
	delete(request.output)
	delete(request.baseline)
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
	if calendar_cli_command_mutates_database(
		calendar_cli_ipc_work.request.command,
	) {
		calendar_ui_reload_data()
		calendar_notification_reconcile()
		calendar_ui.needs_redraw = true
	}
}

calendar_cli_ipc_serve_connection :: proc(fd: posix.FD) {
	request_bytes, read_ok := calendar_cli_socket_receive_all(
		fd,
		context.temp_allocator,
	)
	if !read_ok {return}
	request: Calendar_CLI_Request
	if decode_error := json.unmarshal(request_bytes, &request);
	   decode_error != nil {
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
	wire_bytes, encode_error := json.marshal(Calendar_CLI_IPC_Response{
		exit_code = work.result.exit_code,
		output = work.result.output,
	})
	if encode_error != nil {return}
	defer delete(wire_bytes)
	_ = calendar_cli_socket_send_all(fd, wire_bytes)
}

calendar_cli_ipc_server_worker :: proc(t: ^thread.Thread) {
	context = runtime.default_context()
	for calendar_cli_ipc_state.running {
		client := posix.accept(calendar_cli_ipc_state.listen_fd, nil, nil)
		if client < 0 {
			if !calendar_cli_ipc_state.running {break}
			continue
		}
		{
			runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
			calendar_cli_ipc_serve_connection(client)
		}
		_ = close(c.int(client))
	}
}

calendar_cli_ipc_server_start :: proc() -> bool {
	if calendar_cli_ipc_state.running {return true}
	path := calendar_cli_socket_path()
	address, address_ok := calendar_cli_socket_address(path)
	if !address_ok {return false}
	fd := posix.socket(.UNIX, .STREAM)
	if fd < 0 {return false}
	started := false
	defer if !started {
		_ = close(c.int(fd))
		_ = os.remove(path)
	}
	_ = os.remove(path)
	if posix.bind(
		fd,
		cast(^posix.sockaddr)&address,
		posix.socklen_t(size_of(address)),
	) != .OK {
		return false
	}
	c_path := strings.clone_to_cstring(path)
	mode_set := posix.chmod(
		c_path,
		CALENDAR_CLI_MODE_USER_READ_WRITE,
	) == .OK
	delete(c_path)
	if !mode_set || posix.listen(fd, 4) != .OK {return false}
	worker := thread.create(calendar_cli_ipc_server_worker)
	if worker == nil {return false}
	calendar_cli_ipc_state = {
		thread = worker,
		listen_fd = fd,
		running = true,
	}
	thread.start(worker)
	started = true
	return true
}

calendar_cli_ipc_server_stop :: proc() {
	if !calendar_cli_ipc_state.running {return}
	calendar_cli_ipc_state.running = false
	_ = posix.shutdown(calendar_cli_ipc_state.listen_fd, .RDWR)
	_ = close(c.int(calendar_cli_ipc_state.listen_fd))
	if calendar_cli_ipc_state.thread != nil {
		thread.join(calendar_cli_ipc_state.thread)
		thread.destroy(calendar_cli_ipc_state.thread)
	}
	_ = os.remove(calendar_cli_socket_path())
	calendar_cli_ipc_state = {}
}

calendar_cli_ipc_try_request :: proc(
	request: Calendar_CLI_Request,
) -> (Calendar_CLI_Result, bool) {
	path := calendar_cli_socket_path()
	address, address_ok := calendar_cli_socket_address(path)
	if !address_ok {return {}, false}
	fd := posix.socket(.UNIX, .STREAM)
	if fd < 0 {return {}, false}
	defer close(c.int(fd))
	if posix.connect(
		fd,
		cast(^posix.sockaddr)&address,
		posix.socklen_t(size_of(address)),
	) != .OK {
		return {}, false
	}
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
	if !calendar_cli_socket_send_all(fd, request_bytes) {
		return calendar_cli_error(
			request.command,
			6,
			"ipc_failed",
			"The CLI request could not reach the running application.",
		), true
	}
	_ = posix.shutdown(fd, .WR)
	response_bytes, read_ok := calendar_cli_socket_receive_all(
		fd,
		context.temp_allocator,
	)
	if !read_ok {
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
