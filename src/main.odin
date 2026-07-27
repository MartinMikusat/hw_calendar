package main

import "core:fmt"
import "core:os"

main :: proc() {
	defer calendar_database_close()
	defer calendar_cli_database_release()
	if len(os.args) > 1 {
		request, parse_result, parsed := calendar_cli_parse(os.args[1:])
		result := parse_result
		if parsed {
			input_bytes: []u8
			if calendar_cli_command_reads_input(request.command) {
				input_bytes, _ = os.read_entire_file(os.stdin)
				request.input = string(input_bytes)
			}
			defer delete(input_bytes)
			if ipc_result, served := calendar_cli_ipc_try_request(request);
			   served {
				result = ipc_result
			} else if calendar_cli_command_requires_gui(request.command) {
				result = calendar_cli_error(
					request.command,
					4,
					"gui_not_running",
					"The UI command requires the running application.",
				)
			} else if calendar_cli_command_uses_database(request.command) &&
			          (!calendar_cli_database_try_acquire() ||
			           !calendar_database_open()) {
				result = calendar_cli_error(
					request.command,
					6,
					"storage_failed",
					"The calendar database is owned by another process or could not be opened.",
				)
			} else {
				result = calendar_cli_execute(request)
			}
		}
		fmt.println(result.output)
		delete(result.output)
		os.exit(result.exit_code)
	}
	if !calendar_cli_database_try_acquire() || !calendar_database_open() {
		fmt.eprintln("HW Calendar could not open its database.")
		return
	}
	run_calendar_gui()
}
