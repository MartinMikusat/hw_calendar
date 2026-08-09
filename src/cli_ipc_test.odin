package main

import "core:strings"
import "core:testing"
import local_command "local_command:."

@(test)
calendar_cli_ipc_maps_transport_errors_to_structured_results_test :: proc(
	t: ^testing.T,
) {
	cases := [3]struct {
		status: local_command.Read_Status,
		exit_code: int,
		code: string,
	}{
		{.Too_Large, 3, "ipc_request_too_large"},
		{.Timeout, 6, "ipc_request_timeout"},
		{.Invalid_Length, 3, "ipc_invalid_request"},
	}
	for test_case in cases {
		result, handled := calendar_cli_ipc_read_error(test_case.status)
		testing.expect(t, handled)
		if !handled {continue}
		testing.expect_value(t, result.exit_code, test_case.exit_code)
		testing.expect(
			t,
			strings.contains(result.output, test_case.code),
		)
		delete(result.output)
	}
}

@(test)
calendar_cli_ipc_ignores_closed_and_io_error_connections_test :: proc(
	t: ^testing.T,
) {
	statuses := [2]local_command.Read_Status{.Closed, .IO_Error}
	for status in statuses {
		result, handled := calendar_cli_ipc_read_error(status)
		testing.expect(t, !handled)
		testing.expect_value(t, len(result.output), 0)
	}
}
