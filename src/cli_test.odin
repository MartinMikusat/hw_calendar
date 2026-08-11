package main

import "core:strings"
import "core:testing"
import "core:fmt"
import "core:os"

calendar_cli_test_restore_timezone :: proc(value: string, was_set: bool) {
	if was_set {
		_ = os.set_env("TZ", value)
	} else {
		_ = os.unset_env("TZ")
	}
}

@(test)
calendar_cli_parses_agenda_commands_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"entry", "update", "--id", "7", "--if-revision", "3",
	})
	defer delete(result.output)
	defer delete(request.input)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.Entry_Update)
	testing.expect_value(t, request.id, "7")
	testing.expect_value(t, request.if_revision, 3)
	testing.expect(t, request.use_stdin_input)
	testing.expect(t, calendar_cli_command_mutates_database(request.command))
}

@(test)
calendar_cli_parses_entry_update_patch_flags_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"entry", "update", "--id", "7", "--if-revision", "3",
		"--location", "Kitchen",
	})
	defer delete(result.output)
	defer delete(request.input)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.Entry_Patch)
	testing.expect_value(t, request.protocol_version, CALENDAR_CLI_PROTOCOL_VERSION)
	testing.expect(t, !request.use_stdin_input)
	testing.expect(t, request.set_location)
	testing.expect(t, !request.set_text)
	testing.expect(t, strings.contains(request.input, `"location":"Kitchen"`))
	testing.expect(t, calendar_cli_command_mutates_database(request.command))
}

@(test)
calendar_cli_parses_entry_add_flags_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"entry", "add", "--text", "Water the plants",
		"--due", "2026-04-27",
		"--recurrence", "604800",
	})
	defer delete(result.output)
	defer delete(request.input)
	testing.expect(t, parsed)
	testing.expect_value(t, request.command, Calendar_CLI_Command.Entry_Create)
	testing.expect(t, !request.use_stdin_input)
	testing.expect(t, strings.contains(request.input, `"original_text"`))
	due_stamp, due_ok := calendar_cli_parse_entry_timestamp("2026-04-27")
	testing.expect(t, due_ok)
	testing.expect(t, strings.contains(request.input, fmt.tprintf(`"due_at":"%s"`, due_stamp)))
	testing.expect(t, strings.contains(request.input, `"recurrence_seconds":604800`))
}

@(test)
calendar_cli_parses_compact_date_timestamp_test :: proc(t: ^testing.T) {
	request, result, parsed := calendar_cli_parse([]string{
		"entry", "create", "--text", "Compact date", "--due", "20260427",
		"--recurrence", "86400",
	})
	defer delete(result.output)
	defer delete(request.input)
	testing.expect(t, parsed)
	parsed_date, date_ok := agenda_parse_date_time("20260427")
	testing.expect(t, date_ok)
	if date_ok {
		expected := fmt.tprintf("%d", agenda_date_time_stamp(parsed_date))
		testing.expect(t, strings.contains(request.input, fmt.tprintf(`"due_at":"%s"`, expected)))
	}
}

@(test)
calendar_cli_parses_entry_datetime_as_civil_time_test :: proc(t: ^testing.T) {
	previous_tz, had_previous_tz := os.lookup_env("TZ", context.temp_allocator)
	defer calendar_cli_test_restore_timezone(previous_tz, had_previous_tz)
	if os.set_env("TZ", "America/New_York") != 0 {
		testing.fail_now(t, "could not set TZ")
	}
	unzoned_timestamp, parse_ok := calendar_cli_parse_entry_timestamp("20260630T120000")
	testing.expect(t, parse_ok)
	parsed_datetime, datetime_ok := agenda_parse_date_time("20260630T120000")
	testing.expect(t, datetime_ok)
	if !parse_ok || !datetime_ok {return}
	expected_timestamp := fmt.tprintf("%d", agenda_date_time_stamp(parsed_datetime))
	testing.expect_value(t, unzoned_timestamp, expected_timestamp)
}

@(test)
calendar_cli_rejects_zoned_entry_timestamp_test :: proc(t: ^testing.T) {
	_, parsed := calendar_cli_parse_entry_timestamp("20260630T120000Z")
	testing.expect(t, !parsed)
	_, parsed = calendar_cli_parse_entry_timestamp("2026-06-30T12:00:00Z")
	testing.expect(t, !parsed)
}

@(test)
calendar_cli_parses_reminder_datetime_with_local_timezone_test :: proc(t: ^testing.T) {
	previous_tz, had_previous_tz := os.lookup_env("TZ", context.temp_allocator)
	defer calendar_cli_test_restore_timezone(previous_tz, had_previous_tz)
	if os.set_env("TZ", "America/New_York") != 0 {
		testing.fail_now(t, "could not set TZ")
	}
	cases := []struct {
		value: string,
		expected: string,
		valid: bool,
	}{
		{"20260630T120000", "1782835200", true},
		{"20260630T120000Z", "1782820800", true},
		{"2026-03-08T03:30:00", "1772955000", true},
		{"2026-11-01T01:30:00", "1793511000", true},
		{"2026-03-08T02:30:00", "", false},
	}
	for test_case in cases {
		actual, parsed := calendar_cli_parse_entry_reminder_timestamp(
			test_case.value,
		)
		testing.expect_value(t, parsed, test_case.valid)
		if parsed {
			testing.expect_value(t, actual, test_case.expected)
		}
	}
}

@(test)
calendar_cli_entry_help_test :: proc(t: ^testing.T) {
	_, result, parsed := calendar_cli_parse([]string{
		"entry", "create", "--help",
	})
	defer delete(result.output)
	testing.expect(t, !parsed)
	testing.expect(t, strings.contains(result.output, "hw_calendar entry create"))
	testing.expect(t, strings.contains(result.output, `"ok":true`))
}

@(test)
calendar_cli_entry_update_help_test :: proc(t: ^testing.T) {
	_, result, parsed := calendar_cli_parse([]string{
		"entry", "update", "--id", "7", "--if-revision", "3", "--help",
	})
	defer delete(result.output)
	testing.expect(t, !parsed)
	testing.expect(t, strings.contains(result.output, "hw_calendar entry update"))
	testing.expect(t, strings.contains(result.output, `"ok":true`))
}

@(test)
calendar_cli_rejects_invalid_entry_payload_test :: proc(t: ^testing.T) {
	_, result, parsed := calendar_cli_parse([]string{
		"entry", "create", "--text", "Water the plants", "--recurrence", "yearly",
	})
	defer delete(result.output)
	testing.expect(t, !parsed)
	testing.expect(t, strings.contains(result.output, "non-negative integer"))
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
