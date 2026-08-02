package main

import "core:strings"
import "core:testing"

@(test)
calendar_cli_parses_agenda_commands_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"entry", "update", "--id", "7", "--if-revision", "3",
	})
	defer delete(result.output)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.Entry_Update)
	testing.expect_value(t, request.id, "7")
	testing.expect_value(t, request.if_revision, 3)
	testing.expect(t, calendar_cli_command_mutates_database(request.command))
}

@(test)
calendar_cli_rejects_removed_calendar_commands_test :: proc(t: ^testing.T) {
	removed := [4][]string{
		{"ical", "import"},
		{"event", "list"},
		{"calendar", "list"},
		{"recurrence", "expand"},
	}
	for command in removed {
		_, result, parsed := calendar_cli_parse(command)
		testing.expect(t, !parsed)
		testing.expect(t, strings.contains(result.output, "Unknown command"))
		delete(result.output)
	}
}

@(test)
calendar_cli_requires_positive_revision_test :: proc(t: ^testing.T) {
	_, result, parsed := calendar_cli_parse([]string{
		"entry", "complete", "--id", "1", "--if-revision", "0",
	})
	defer delete(result.output)
	testing.expect(t, !parsed)
	testing.expect(t, strings.contains(result.output, "positive integer"))
}

@(test)
calendar_cli_parses_pointer_bridge_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"ui", "bridge-pointer", "--control", "settings",
	})
	defer delete(result.output)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.UI_Bridge_Pointer)
	testing.expect_value(t, request.target_control, "settings")
	testing.expect(t, calendar_cli_command_requires_gui(request.command))
}

@(test)
calendar_cli_requires_pointer_bridge_control_test :: proc(t: ^testing.T) {
	_, result, parsed := calendar_cli_parse([]string{"ui", "bridge-pointer"})
	defer delete(result.output)
	testing.expect(t, !parsed)
	testing.expect(t, strings.contains(result.output, "requires --control"))
}

@(test)
calendar_cli_parses_chore_commands_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{"chore", "due"})
	defer delete(result.output)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.Chore_Due)
	testing.expect(t, !calendar_cli_command_mutates_database(request.command))
	testing.expect(t, calendar_cli_command_uses_database(request.command))

	request, result, parsed = calendar_cli_parse([]string{
		"chore", "done", "--id", "4", "--if-revision", "2",
	})
	defer delete(result.output)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.Chore_Done)
	testing.expect_value(t, request.id, "4")
	testing.expect_value(t, request.if_revision, 2)
	testing.expect(t, calendar_cli_command_mutates_database(request.command))
}

@(test)
calendar_cli_usage_lists_chore_commands_test :: proc(t: ^testing.T) {
	_, result, parsed := calendar_cli_parse(nil)
	defer delete(result.output)
	testing.expect(t, !parsed)
	testing.expect(t, strings.contains(result.output, "chore"))
}
