package main

import "core:os"
import "core:testing"

@(test)
agenda_occurrence_projects_confirmed_timed_entry_test :: proc(t: ^testing.T) {
	entry := Agenda_Entry{
		id = 7,
		start_at = "1786182300",
		end_at = "1786185900",
		state = "active",
	}
	occurrence, found := agenda_occurrence_from_entry(&entry, 3)
	testing.expect(t, found)
	testing.expect_value(t, occurrence.entry_index, 3)
	testing.expect_value(t, occurrence.start_stamp, i64(1786182300))
	testing.expect_value(t, occurrence.end_stamp, i64(1786185900))
	testing.expect(t, !occurrence.all_day)
}

@(test)
agenda_occurrence_projects_all_day_and_due_fallback_test :: proc(t: ^testing.T) {
	day := agenda_days_from_civil(2026, 8, 8)*86_400
	all_day := Agenda_Entry{
		start_at = "1786147200",
		end_at = "1786233600",
		state = "active",
	}
	occurrence, found := agenda_occurrence_from_entry(&all_day, 0)
	testing.expect(t, found)
	testing.expect(t, occurrence.all_day)
	testing.expect_value(t, occurrence.start_stamp, day)
	testing.expect_value(t, occurrence.end_stamp, day+86_400)

	due := Agenda_Entry{due_at = "1786182300", state = "active"}
	occurrence, found = agenda_occurrence_from_entry(&due, 1)
	testing.expect(t, found)
	testing.expect(t, occurrence.all_day)
	testing.expect_value(t, occurrence.start_stamp, day)
	testing.expect_value(t, occurrence.end_stamp, occurrence.start_stamp+86_400)
}

@(test)
agenda_occurrence_projects_recurring_entry_from_due_date_test :: proc(t: ^testing.T) {
	due_day := agenda_days_from_civil(2026, 8, 8)*86_400
	entry := Agenda_Entry{
		start_at = "1786182300",
		due_at = "1786147200",
		recurrence_seconds = 86_400,
		state = "active",
	}
	occurrence, found := agenda_occurrence_from_entry(&entry, 0)
	testing.expect(t, found)
	testing.expect(t, occurrence.all_day)
	testing.expect_value(t, occurrence.start_stamp, due_day)
}

@(test)
agenda_occurrence_rejects_inactive_or_undated_entry_test :: proc(t: ^testing.T) {
	inactive := Agenda_Entry{start_at = "1786182300", state = "dismissed"}
	_, found := agenda_occurrence_from_entry(&inactive, 0)
	testing.expect(t, !found)
	undated := Agenda_Entry{state = "active"}
	_, found = agenda_occurrence_from_entry(&undated, 0)
	testing.expect(t, !found)
}

@(test)
agenda_date_time_handles_leap_days_and_weekdays_test :: proc(t: ^testing.T) {
	leap, valid := agenda_parse_date_time("20240229")
	testing.expect(t, valid)
	testing.expect_value(t, agenda_weekday(leap), Agenda_Weekday.Thursday)
	_, valid = agenda_parse_date_time("20230229")
	testing.expect(t, !valid)
	stamp := agenda_date_time_stamp(leap)
	testing.expect_value(t, agenda_date_time_from_stamp(stamp, true), leap)
}

@(test)
agenda_local_date_uses_local_timezone_test :: proc(t: ^testing.T) {
	previous_tz, had_previous_tz := os.lookup_env("TZ", context.temp_allocator)
	defer calendar_cli_test_restore_timezone(previous_tz, had_previous_tz)
	if os.set_env("TZ", "Europe/Bratislava") != 0 {
		testing.fail_now(t, "could not set TZ")
	}
	stamp := agenda_days_from_civil(2026, 8, 10)*86_400+22*3_600+30*60
	local := agenda_local_date_at_unix(stamp)
	testing.expect_value(t, local.year, 2026)
	testing.expect_value(t, local.month, 8)
	testing.expect_value(t, local.day, 11)
}

@(test)
agenda_interval_rejects_reversed_or_incomplete_ranges_test :: proc(t: ^testing.T) {
	testing.expect(t, agenda_interval_valid("100", "100"))
	testing.expect(t, agenda_interval_valid("100", "200"))
	testing.expect(t, !agenda_interval_valid("200", "100"))
	testing.expect(t, !agenda_interval_valid("", "100"))
}
