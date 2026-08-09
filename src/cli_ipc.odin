package main

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:thread"
import "core:time"

foreign import calendar_cli_libc "system:System.framework"
foreign calendar_cli_libc {
	flock :: proc "c" (fd, operation: c.int) -> c.int ---
	close :: proc "c" (fd: c.int) -> c.int ---
}

CALENDAR_CLI_LOCK_EX :: 2
CALENDAR_CLI_LOCK_NB :: 4
CALENDAR_CLI_LOCK_UN :: 8
CALENDAR_CLI_MODE_USER_READ_WRITE :: posix.mode_t{.IRUSR, .IWUSR}
CALENDAR_CLI_IPC_REQUEST_HEADER_SIZE :: 4
CALENDAR_CLI_IPC_MAX_REQUEST_BYTES :: 64*1024
CALENDAR_CLI_IPC_REQUEST_TIMEOUT :: 1*time.Second

Calendar_CLI_IPC_Read_Status :: enum {
	Success,
	Closed,
	Timeout,
	Too_Large,
	Invalid_Length,
	IO_Error,
}

Calendar_CLI_Database_Owner :: struct {
	file: ^os.File,
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
	active_client_fd: posix.FD,
	running: bool,
}

calendar_cli_database_owner: Calendar_CLI_Database_Owner
calendar_cli_ipc_state := Calendar_CLI_IPC_State{
	listen_fd = -1,
	active_client_fd = -1,
}
calendar_cli_ipc_state_mutex: sync.Mutex
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
	file, open_error := os.open(
		calendar_cli_lock_path(),
		{.Read, .Write, .Create},
	)
	if open_error != nil {return false}
	if posix.fchmod(
		posix.FD(os.fd(file)),
		CALENDAR_CLI_MODE_USER_READ_WRITE,
	) != .OK {
		_ = os.close(file)
		return false
	}
	fd := c.int(os.fd(file))
	if flock(fd, CALENDAR_CLI_LOCK_EX|CALENDAR_CLI_LOCK_NB) != 0 {
		_ = os.close(file)
		return false
	}
	calendar_cli_database_owner = {file=file, held=true}
	return true
}

calendar_cli_database_release :: proc() {
	if !calendar_cli_database_owner.held {return}
	_ = flock(
		c.int(os.fd(calendar_cli_database_owner.file)),
		CALENDAR_CLI_LOCK_UN,
	)
	_ = os.close(calendar_cli_database_owner.file)
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

calendar_cli_socket_send_request :: proc(fd: posix.FD, bytes: []u8) -> bool {
	if len(bytes) == 0 || len(bytes) > CALENDAR_CLI_IPC_MAX_REQUEST_BYTES {
		return false
	}
	length := u32(len(bytes))
	header := [CALENDAR_CLI_IPC_REQUEST_HEADER_SIZE]u8{
		u8(length >> 24),
		u8(length >> 16),
		u8(length >> 8),
		u8(length),
	}
	return calendar_cli_socket_send_all(fd, header[:]) &&
	       calendar_cli_socket_send_all(fd, bytes)
}

calendar_cli_socket_receive_exact_until :: proc(
	fd: posix.FD,
	bytes: []u8,
	deadline: time.Tick,
) -> Calendar_CLI_IPC_Read_Status {
	received := 0
	for received < len(bytes) {
		remaining_ns := i64(time.tick_diff(time.tick_now(), deadline))
		if remaining_ns <= 0 {return .Timeout}
		timeout_ms := c.int(
			(remaining_ns+i64(time.Millisecond)-1)/i64(time.Millisecond),
		)
		poll_fd := posix.pollfd{fd=fd, events={.IN}}
		poll_result := posix.poll(&poll_fd, 1, timeout_ms)
		if poll_result == 0 {return .Timeout}
		if poll_result < 0 {return .IO_Error}
		count := posix.recv(
			fd,
			raw_data(bytes[received:]),
			c.size_t(int(len(bytes))-received),
			{},
		)
		if count == 0 {return .Closed}
		if count < 0 {return .IO_Error}
		received += int(count)
	}
	return .Success
}

calendar_cli_socket_receive_request :: proc(
	fd: posix.FD,
	timeout := CALENDAR_CLI_IPC_REQUEST_TIMEOUT,
	allocator := context.allocator,
) -> ([]u8, Calendar_CLI_IPC_Read_Status) {
	deadline := time.tick_add(time.tick_now(), timeout)
	header: [CALENDAR_CLI_IPC_REQUEST_HEADER_SIZE]u8
	status := calendar_cli_socket_receive_exact_until(fd, header[:], deadline)
	if status != .Success {return nil, status}
	length := int(
		u32(header[0]) << 24 |
		u32(header[1]) << 16 |
		u32(header[2]) << 8 |
		u32(header[3]),
	)
	if length == 0 {return nil, .Invalid_Length}
	if length > CALENDAR_CLI_IPC_MAX_REQUEST_BYTES {return nil, .Too_Large}
	contents := make([]u8, length, allocator)
	status = calendar_cli_socket_receive_exact_until(fd, contents, deadline)
	if status != .Success {
		delete(contents, allocator)
		return nil, status
	}
	return contents, .Success
}

calendar_cli_socket_receive_response :: proc(
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
	delete(request.target_control)
	delete(request.key)
	delete(request.modifiers)
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

calendar_cli_ipc_send_result :: proc(
	fd: posix.FD,
	result: Calendar_CLI_Result,
) -> bool {
	wire_bytes, encode_error := json.marshal(Calendar_CLI_IPC_Response{
		exit_code = result.exit_code,
		output = result.output,
	})
	if encode_error != nil {return false}
	defer delete(wire_bytes)
	return calendar_cli_socket_send_all(fd, wire_bytes)
}

calendar_cli_ipc_send_protocol_error :: proc(
	fd: posix.FD,
	exit_code: int,
	code, message: string,
) {
	result := calendar_cli_error(.None, exit_code, code, message)
	defer delete(result.output)
	_ = calendar_cli_ipc_send_result(fd, result)
}

calendar_cli_ipc_serve_connection :: proc(
	fd: posix.FD,
	timeout := CALENDAR_CLI_IPC_REQUEST_TIMEOUT,
) {
	request_bytes, read_status := calendar_cli_socket_receive_request(
		fd,
		timeout,
		context.temp_allocator,
	)
	switch read_status {
	case .Success:
	case .Too_Large:
		calendar_cli_ipc_send_protocol_error(
			fd,
			3,
			"ipc_request_too_large",
			"The app request exceeds the 64 KiB limit.",
		)
		return
	case .Timeout:
		calendar_cli_ipc_send_protocol_error(
			fd,
			6,
			"ipc_request_timeout",
			"The app request was not received before the deadline.",
		)
		return
	case .Invalid_Length:
		calendar_cli_ipc_send_protocol_error(
			fd,
			3,
			"ipc_invalid_request",
			"The app request has an invalid length.",
		)
		return
	case .Closed, .IO_Error:
		return
	}
	request: Calendar_CLI_Request
	if decode_error := json.unmarshal(request_bytes, &request);
	   decode_error != nil {
		calendar_cli_ipc_send_protocol_error(
			fd,
			3,
			"ipc_invalid_request",
			"The app request is not valid JSON.",
		)
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
	_ = calendar_cli_ipc_send_result(fd, work.result)
}

calendar_cli_ipc_server_is_running :: proc() -> bool {
	sync.mutex_lock(&calendar_cli_ipc_state_mutex)
	running := calendar_cli_ipc_state.running
	sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
	return running
}

calendar_cli_ipc_server_set_active_client :: proc(fd: posix.FD) -> bool {
	sync.mutex_lock(&calendar_cli_ipc_state_mutex)
	running := calendar_cli_ipc_state.running
	if running {calendar_cli_ipc_state.active_client_fd = fd}
	sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
	return running
}

calendar_cli_ipc_server_clear_active_client :: proc(fd: posix.FD) {
	sync.mutex_lock(&calendar_cli_ipc_state_mutex)
	if calendar_cli_ipc_state.active_client_fd == fd {
		calendar_cli_ipc_state.active_client_fd = -1
	}
	sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
}

calendar_cli_ipc_server_has_active_client :: proc() -> bool {
	sync.mutex_lock(&calendar_cli_ipc_state_mutex)
	active := calendar_cli_ipc_state.active_client_fd >= 0
	sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
	return active
}

calendar_cli_ipc_server_worker :: proc(t: ^thread.Thread) {
	context = runtime.default_context()
	for calendar_cli_ipc_server_is_running() {
		sync.mutex_lock(&calendar_cli_ipc_state_mutex)
		listen_fd := calendar_cli_ipc_state.listen_fd
		sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
		client := posix.accept(listen_fd, nil, nil)
		if client < 0 {
			if !calendar_cli_ipc_server_is_running() {break}
			continue
		}
		if !calendar_cli_ipc_server_set_active_client(client) {
			_ = close(c.int(client))
			break
		}
		{
			runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
			calendar_cli_ipc_serve_connection(client)
		}
		calendar_cli_ipc_server_clear_active_client(client)
		_ = close(c.int(client))
	}
}

calendar_cli_ipc_server_start :: proc() -> bool {
	if calendar_cli_ipc_server_is_running() {return true}
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
	sync.mutex_lock(&calendar_cli_ipc_state_mutex)
	calendar_cli_ipc_state = {
		thread = worker,
		listen_fd = fd,
		active_client_fd = -1,
		running = true,
	}
	sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
	thread.start(worker)
	started = true
	return true
}

calendar_cli_ipc_server_stop :: proc() {
	sync.mutex_lock(&calendar_cli_ipc_state_mutex)
	if !calendar_cli_ipc_state.running {
		sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
		return
	}
	calendar_cli_ipc_state.running = false
	listen_fd := calendar_cli_ipc_state.listen_fd
	active_client_fd := calendar_cli_ipc_state.active_client_fd
	worker := calendar_cli_ipc_state.thread
	if active_client_fd >= 0 {
		_ = posix.shutdown(active_client_fd, .RDWR)
	}
	sync.mutex_unlock(&calendar_cli_ipc_state_mutex)

	_ = posix.shutdown(listen_fd, .RDWR)
	_ = close(c.int(listen_fd))
	if worker != nil {
		thread.join(worker)
		thread.destroy(worker)
	}
	_ = os.remove(calendar_cli_socket_path())
	sync.mutex_lock(&calendar_cli_ipc_state_mutex)
	calendar_cli_ipc_state = {
		listen_fd = -1,
		active_client_fd = -1,
	}
	sync.mutex_unlock(&calendar_cli_ipc_state_mutex)
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
	if len(request_bytes) > CALENDAR_CLI_IPC_MAX_REQUEST_BYTES {
		return calendar_cli_error(
			request.command,
			3,
			"ipc_request_too_large",
			"The app request exceeds the 64 KiB limit.",
		), true
	}
	if !calendar_cli_socket_send_request(fd, request_bytes) {
		return calendar_cli_error(
			request.command,
			6,
			"ipc_failed",
			"The CLI request could not reach the running application.",
		), true
	}
	_ = posix.shutdown(fd, .WR)
	response_bytes, read_ok := calendar_cli_socket_receive_response(
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
