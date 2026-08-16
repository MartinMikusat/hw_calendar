package main

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"

Birthday_CLI_Birthday :: struct {
	id: i64,
	name: string,
	month: int,
	day: int,
	year: int,
	advance_days: int,
	created_at_ms: i64,
	updated_at_ms: i64,
}

Birthday_CLI_Birthdays_Data :: struct {birthdays: []Birthday_CLI_Birthday}
Birthday_CLI_Birthday_Data :: struct {birthday: Birthday_CLI_Birthday}

Birthday_CLI_Upcoming :: struct {
	id: i64,
	name: string,
	month: int,
	day: int,
	year: int,
	next_at: i64,
	days_until: int,
	advance_days: int,
}

Birthday_CLI_Upcoming_Data :: struct {upcoming: []Birthday_CLI_Upcoming}

Birthday_CLI_Default_Data :: struct {advance_days: int}

Birthday_CLI_Birthday_Response :: struct {
	ok: bool,
	command: string,
	data: Birthday_CLI_Birthday_Data,
}

Birthday_CLI_Birthdays_Response :: struct {
	ok: bool,
	command: string,
	data: Birthday_CLI_Birthdays_Data,
}

Birthday_CLI_Upcoming_Response :: struct {
	ok: bool,
	command: string,
	data: Birthday_CLI_Upcoming_Data,
}

Birthday_CLI_Default_Response :: struct {
	ok: bool,
	command: string,
	data: Birthday_CLI_Default_Data,
}

birthday_cli_birthday_outputs_destroy :: proc(
	birthdays: []Birthday_CLI_Birthday,
) {
	for &birthday in birthdays {
		delete(birthday.name)
	}
	delete(birthdays)
}

birthday_cli_upcoming_destroy :: proc(upcoming: []Birthday_CLI_Upcoming) {
	for &item in upcoming {
		delete(item.name)
	}
	delete(upcoming)
}

birthday_cli_to_output :: proc(
	birthday: Birthday,
	allocator := context.allocator,
) -> Birthday_CLI_Birthday {
	return {
		id = birthday.id,
		name = strings.clone(birthday.name, allocator),
		month = birthday.month,
		day = birthday.day,
		year = birthday.year,
		advance_days = birthday.advance_days,
		created_at_ms = birthday.created_at_ms,
		updated_at_ms = birthday.updated_at_ms,
	}
}

birthday_cli_mutation_error :: proc(
	command: Calendar_CLI_Command,
	code: string,
) -> Calendar_CLI_Result {
	message := "The birthday mutation failed."
	exit_code := 6
	switch code {
	case "invalid_birthday":
		message = "The birthday input is invalid."
		exit_code = 3
	case "storage_failed":
		message = sqlite_error(calendar_database)
		exit_code = 6
	}
	return calendar_cli_error(command, exit_code, code, message)
}

birthday_cli_execute :: proc(request: Calendar_CLI_Request) -> Calendar_CLI_Result {
	#partial switch request.command {
	case .Birthday_Create:
		month, day, year: int
		if !birthday_parse_date(request.birthday_date, &month, &day, &year) {
			return calendar_cli_error(
				request.command,
				2,
				"usage",
				"--date must be MM-DD or YYYY-MM-DD.",
			)
		}
		input := Birthday_Input{
			name = request.birthday_name,
			month = month,
			day = day,
			year = year,
			advance_days = request.birthday_advance_days,
		}
		if !birthday_input_valid(&input) {
			return birthday_cli_mutation_error(request.command, "invalid_birthday")
		}
		birthday, created := birthday_create(&input)
		if !created {
			return birthday_cli_mutation_error(request.command, "storage_failed")
		}
		defer birthday_destroy(&birthday)
		output := birthday_cli_to_output(birthday)
		defer delete(output.name)
		encoded := calendar_cli_encode(Birthday_CLI_Birthday_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {birthday = output},
		})
		return {output = encoded}
	case .Birthday_List:
		birthdays := birthday_list()
		defer birthdays_destroy(&birthdays)
		outputs := make([]Birthday_CLI_Birthday, len(birthdays))
		for &birthday, index in birthdays {
			outputs[index] = birthday_cli_to_output(birthday)
		}
		encoded := calendar_cli_encode(Birthday_CLI_Birthdays_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {birthdays = outputs[:]},
		})
		defer birthday_cli_birthday_outputs_destroy(outputs)
		return {output = encoded}
	case .Birthday_Due:
		upcoming := birthday_upcoming()
		defer birthday_upcoming_destroy(&upcoming)
		outputs := make([]Birthday_CLI_Upcoming, len(upcoming))
		for &item, index in upcoming {
			outputs[index] = {
				id = item.id,
				name = strings.clone(item.name),
				month = item.month,
				day = item.day,
				year = item.year,
				next_at = item.next_at,
				days_until = item.days_until,
				advance_days = item.advance_days,
			}
		}
		encoded := calendar_cli_encode(Birthday_CLI_Upcoming_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {upcoming = outputs[:]},
		})
		defer birthday_cli_upcoming_destroy(outputs)
		return {output = encoded}
	case .Birthday_Default:
		if request.birthday_advance_days > 0 {
			if !birthday_set_default_advance_days(request.birthday_advance_days) {
				return birthday_cli_mutation_error(request.command, "storage_failed")
			}
		}
		encoded := calendar_cli_encode(Birthday_CLI_Default_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {advance_days = birthday_default_advance_days()},
		})
		return {output = encoded}
	case:
	}
	return calendar_cli_error(request.command, 2, "usage", "Unknown birthday command.")
}
