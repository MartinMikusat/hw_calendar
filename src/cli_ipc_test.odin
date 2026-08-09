package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import "core:time"

calendar_cli_ipc_test_socket_pair :: proc(
	t: ^testing.T,
) -> ([2]posix.FD, bool) {
	sockets: [2]posix.FD
	result := posix.socketpair(.UNIX, .STREAM, .IP, &sockets)
	testing.expect_value(t, result, posix.result(.OK))
	return sockets, result == .OK
}

calendar_cli_ipc_test_response :: proc(
	t: ^testing.T,
	fd: posix.FD,
) -> (Calendar_CLI_IPC_Response, bool) {
	bytes, read_ok := calendar_cli_socket_receive_response(fd)
	testing.expect(t, read_ok)
	if !read_ok {return {}, false}
	defer delete(bytes)
	response: Calendar_CLI_IPC_Response
	decode_error := json.unmarshal(bytes, &response)
	testing.expect_value(t, decode_error, nil)
	return response, decode_error == nil
}

@(test)
calendar_cli_ipc_rejects_oversized_request_before_body_allocation_test :: proc(
	t: ^testing.T,
) {
	sockets, sockets_ok := calendar_cli_ipc_test_socket_pair(t)
	if !sockets_ok {return}
	defer posix.close(sockets[0])
	defer posix.close(sockets[1])

	length := u32(CALENDAR_CLI_IPC_MAX_REQUEST_BYTES+1)
	header := [CALENDAR_CLI_IPC_REQUEST_HEADER_SIZE]u8{
		u8(length >> 24),
		u8(length >> 16),
		u8(length >> 8),
		u8(length),
	}
	testing.expect(t, calendar_cli_socket_send_all(sockets[1], header[:]))
	calendar_cli_ipc_serve_connection(sockets[0], 20*time.Millisecond)
	_ = posix.shutdown(sockets[0], .WR)

	response, response_ok := calendar_cli_ipc_test_response(t, sockets[1])
	if !response_ok {return}
	defer delete(response.output)
	testing.expect_value(t, response.exit_code, 3)
	testing.expect(
		t,
		strings.contains(response.output, `"code":"ipc_request_too_large"`),
	)
}

@(test)
calendar_cli_ipc_times_out_incomplete_request_with_structured_error_test :: proc(
	t: ^testing.T,
) {
	sockets, sockets_ok := calendar_cli_ipc_test_socket_pair(t)
	if !sockets_ok {return}
	defer posix.close(sockets[0])
	defer posix.close(sockets[1])

	testing.expect(t, calendar_cli_socket_send_all(sockets[1], []u8{0}))
	started := time.tick_now()
	calendar_cli_ipc_serve_connection(sockets[0], 20*time.Millisecond)
	elapsed := time.tick_since(started)
	_ = posix.shutdown(sockets[0], .WR)

	response, response_ok := calendar_cli_ipc_test_response(t, sockets[1])
	if !response_ok {return}
	defer delete(response.output)
	testing.expect(t, elapsed < 250*time.Millisecond)
	testing.expect_value(t, response.exit_code, 6)
	testing.expect(
		t,
		strings.contains(response.output, `"code":"ipc_request_timeout"`),
	)
}

@(test)
calendar_cli_ipc_reads_valid_length_prefixed_request_test :: proc(t: ^testing.T) {
	sockets, sockets_ok := calendar_cli_ipc_test_socket_pair(t)
	if !sockets_ok {return}
	defer posix.close(sockets[0])
	defer posix.close(sockets[1])

	request := Calendar_CLI_Request{command=.Entry_List}
	bytes, encode_error := json.marshal(request)
	testing.expect_value(t, encode_error, nil)
	if encode_error != nil {return}
	defer delete(bytes)
	testing.expect(t, calendar_cli_socket_send_request(sockets[1], bytes))

	received, read_status := calendar_cli_socket_receive_request(
		sockets[0],
		20*time.Millisecond,
	)
	testing.expect_value(t, read_status, Calendar_CLI_IPC_Read_Status.Success)
	if read_status != .Success {return}
	defer delete(received)
	decoded: Calendar_CLI_Request
	decode_error := json.unmarshal(received, &decoded)
	testing.expect_value(t, decode_error, nil)
	testing.expect_value(t, decoded.command, Calendar_CLI_Command.Entry_List)
}

@(test)
calendar_cli_ipc_rejects_invalid_json_with_structured_error_test :: proc(
	t: ^testing.T,
) {
	sockets, sockets_ok := calendar_cli_ipc_test_socket_pair(t)
	if !sockets_ok {return}
	defer posix.close(sockets[0])
	defer posix.close(sockets[1])

	testing.expect(
		t,
		calendar_cli_socket_send_request(sockets[1], []u8{'{'}),
	)
	calendar_cli_ipc_serve_connection(sockets[0], 20*time.Millisecond)
	_ = posix.shutdown(sockets[0], .WR)

	response, response_ok := calendar_cli_ipc_test_response(t, sockets[1])
	if !response_ok {return}
	defer delete(response.output)
	testing.expect_value(t, response.exit_code, 3)
	testing.expect(
		t,
		strings.contains(response.output, `"code":"ipc_invalid_request"`),
	)
}

calendar_cli_ipc_test_support_directory :: proc(t: ^testing.T) -> (string, bool) {
	support := strings.concatenate({
		"/tmp/hwc-ipc-",
		fmt.tprintf("%d", time.to_unix_nanoseconds(time.now())),
	})
	if os.make_directory(support) != nil {
		delete(support)
		testing.fail_now(t, "could not create the IPC test support directory")
	}
	if os.set_env("HW_CALENDAR_SUPPORT_DIR", support) != 0 {
		_ = os.remove_all(support)
		delete(support)
		testing.fail_now(t, "could not set the IPC test support directory")
	}
	return support, true
}

@(test)
calendar_cli_ipc_server_stop_interrupts_incomplete_active_client_test :: proc(
	t: ^testing.T,
) {
	support, support_ok := calendar_cli_ipc_test_support_directory(t)
	if !support_ok {return}
	defer delete(support)
	defer _ = os.remove_all(support)
	defer _ = os.unset_env("HW_CALENDAR_SUPPORT_DIR")

	calendar_cli_ipc_server_stop()
	testing.expect(t, calendar_cli_ipc_server_start())
	if !calendar_cli_ipc_server_is_running() {return}
	defer calendar_cli_ipc_server_stop()

	path := calendar_cli_socket_path()
	address, address_ok := calendar_cli_socket_address(path)
	testing.expect(t, address_ok)
	if !address_ok {return}
	client := posix.socket(.UNIX, .STREAM)
	testing.expect(t, client >= 0)
	if client < 0 {return}
	defer posix.close(client)
	connected := posix.connect(
		client,
		cast(^posix.sockaddr)&address,
		posix.socklen_t(size_of(address)),
	) == .OK
	testing.expect(t, connected)
	if !connected {return}
	testing.expect(t, calendar_cli_socket_send_all(client, []u8{0}))

	active := false
	for _ in 0..<100 {
		if calendar_cli_ipc_server_has_active_client() {
			active = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, active)
	if !active {return}

	started := time.tick_now()
	calendar_cli_ipc_server_stop()
	elapsed := time.tick_since(started)
	testing.expect(t, elapsed < 250*time.Millisecond)
	testing.expect(t, !calendar_cli_ipc_server_is_running())
	testing.expect(t, !calendar_cli_ipc_server_has_active_client())
	testing.expect(t, !os.exists(path))
}

@(test)
calendar_cli_ipc_server_stop_handles_client_completion_race_test :: proc(
	t: ^testing.T,
) {
	support, support_ok := calendar_cli_ipc_test_support_directory(t)
	if !support_ok {return}
	defer delete(support)
	defer _ = os.remove_all(support)
	defer _ = os.unset_env("HW_CALENDAR_SUPPORT_DIR")

	calendar_cli_ipc_server_stop()
	testing.expect(t, calendar_cli_ipc_server_start())
	if !calendar_cli_ipc_server_is_running() {return}
	defer calendar_cli_ipc_server_stop()

	path := calendar_cli_socket_path()
	address, address_ok := calendar_cli_socket_address(path)
	testing.expect(t, address_ok)
	if !address_ok {return}
	client := posix.socket(.UNIX, .STREAM)
	testing.expect(t, client >= 0)
	if client < 0 {return}
	defer posix.close(client)
	connected := posix.connect(
		client,
		cast(^posix.sockaddr)&address,
		posix.socklen_t(size_of(address)),
	) == .OK
	testing.expect(t, connected)
	if !connected {return}

	testing.expect(t, calendar_cli_socket_send_all(client, []u8{0}))
	active := false
	for _ in 0..<100 {
		if calendar_cli_ipc_server_has_active_client() {
			active = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, active)
	if !active {return}

	testing.expect(t, calendar_cli_socket_send_all(client, []u8{1, 0, 1}))
	started := time.tick_now()
	calendar_cli_ipc_server_stop()
	elapsed := time.tick_since(started)
	testing.expect(t, elapsed < 250*time.Millisecond)
	testing.expect(t, !calendar_cli_ipc_server_is_running())
	testing.expect(t, !calendar_cli_ipc_server_has_active_client())
	testing.expect(t, !os.exists(path))
}
