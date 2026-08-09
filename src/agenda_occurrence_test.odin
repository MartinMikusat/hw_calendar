package main

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
