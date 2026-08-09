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
calendar_cli_parses_keyboard_bridge_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"ui", "bridge-keyboard", "--key", "down", "--modifiers", "command",
	})
	defer delete(result.output)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.UI_Bridge_Keyboard)
	testing.expect_value(t, request.key, "down")
	testing.expect_value(t, request.modifiers, "command")
	testing.expect(t, calendar_cli_command_requires_gui(request.command))
}

@(test)
calendar_cli_keyboard_bridge_defaults_to_no_modifiers_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"ui", "bridge-keyboard", "--key", "up",
	})
	defer delete(result.output)
	testing.expect(t, parsed)
	testing.expect_value(t, request.modifiers, "none")
}

@(test)
calendar_cli_rejects_invalid_keyboard_bridge_input_test :: proc(t: ^testing.T) {
	_, key_result, key_parsed := calendar_cli_parse([]string{
		"ui", "bridge-keyboard", "--key", "left",
	})
	defer delete(key_result.output)
	testing.expect(t, !key_parsed)
	testing.expect(t, strings.contains(key_result.output, "--key up or --key down"))
	_, modifier_result, modifier_parsed := calendar_cli_parse([]string{
		"ui", "bridge-keyboard", "--key", "down", "--modifiers", "shift",
	})
	defer delete(modifier_result.output)
	testing.expect(t, !modifier_parsed)
	testing.expect(t, strings.contains(modifier_result.output, "none or command"))
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

@(test)
calendar_cli_parses_archive_commands_test :: proc(t: ^testing.T) {
	export_request, export_result, export_parsed := calendar_cli_parse([]string{
		"archive", "export", "--path", "/tmp/calendar.json",
	})
	defer delete(export_result.output)
	testing.expect(t, export_parsed)
	testing.expect_value(t, export_request.command, Calendar_CLI_Command.Archive_Export)
	testing.expect_value(t, export_request.path, "/tmp/calendar.json")
	testing.expect(t, calendar_cli_command_uses_database(export_request.command))
	testing.expect(t, !calendar_cli_command_mutates_database(export_request.command))

	inspect_request, inspect_result, inspect_parsed := calendar_cli_parse([]string{
		"archive", "inspect", "--path", "/tmp/calendar.json",
	})
	defer delete(inspect_result.output)
	testing.expect(t, inspect_parsed)
	testing.expect_value(t, inspect_request.command, Calendar_CLI_Command.Archive_Inspect)
	testing.expect(t, !calendar_cli_command_uses_database(inspect_request.command))

	import_request, import_result, import_parsed := calendar_cli_parse([]string{
		"archive", "import", "--path", "/tmp/calendar.json", "--replace",
	})
	defer delete(import_result.output)
	testing.expect(t, import_parsed)
	testing.expect_value(t, import_request.command, Calendar_CLI_Command.Archive_Import)
	testing.expect(t, import_request.replace)
	testing.expect(t, calendar_cli_command_mutates_database(import_request.command))
}

@(test)
calendar_cli_requires_archive_path_and_import_confirmation_test :: proc(t: ^testing.T) {
	_, path_result, path_parsed := calendar_cli_parse([]string{"archive", "export"})
	defer delete(path_result.output)
	testing.expect(t, !path_parsed)
	testing.expect(t, strings.contains(path_result.output, "requires --path"))

	_, replace_result, replace_parsed := calendar_cli_parse([]string{
		"archive", "import", "--path", "/tmp/calendar.json",
	})
	defer delete(replace_result.output)
	testing.expect(t, !replace_parsed)
	testing.expect(t, strings.contains(replace_result.output, "requires --replace"))
}

@(test)
calendar_cli_parses_update_check_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{"update", "check"})
	defer delete(result.output)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.Update_Check)
	testing.expect(t, calendar_cli_command_requires_gui(request.command))
	testing.expect(t, !calendar_cli_command_uses_database(request.command))
}
