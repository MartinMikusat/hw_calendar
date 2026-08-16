package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

@(test)
birthday_date_validation_test :: proc(t: ^testing.T) {
	testing.expect(t, birthday_date_valid(0, 8, 11))
	testing.expect(t, birthday_date_valid(1980, 8, 11))
	testing.expect(t, birthday_date_valid(0, 2, 29))
	testing.expect(t, birthday_date_valid(2025, 2, 28))
	testing.expect(t, !birthday_date_valid(2025, 2, 29))
	testing.expect(t, !birthday_date_valid(0, 4, 31))
	testing.expect(t, !birthday_date_valid(0, 13, 1))
	testing.expect(t, !birthday_date_valid(0, 0, 1))
}

@(test)
birthday_date_parsing_test :: proc(t: ^testing.T) {
	month, day, year: int
	testing.expect(t, birthday_parse_date("08-11", &month, &day, &year))
	testing.expect_value(t, month, 8)
	testing.expect_value(t, day, 11)
	testing.expect_value(t, year, 0)
	testing.expect(t, birthday_parse_date("1815-08-11", &month, &day, &year))
	testing.expect_value(t, year, 1815)
	testing.expect(t, !birthday_parse_date("8-11", &month, &day, &year))
	testing.expect(t, !birthday_parse_date("08/11", &month, &day, &year))
	testing.expect(t, !birthday_parse_date("04-31", &month, &day, &year))
}

@(test)
birthday_next_occurrence_test :: proc(t: ^testing.T) {
	birthday := Birthday{
		month = 8,
		day = 11,
		year = 0,
	}
	today := Agenda_Date_Time{year = 2026, month = 8, day = 11, is_date = true}
	next, days_until := birthday_next_date(&birthday, today)
	testing.expect(t, days_until == 0)
	testing.expect_value(t, next.month, 8)
	testing.expect_value(t, next.day, 11)

	today = Agenda_Date_Time{year = 2026, month = 8, day = 12, is_date = true}
	next, days_until = birthday_next_date(&birthday, today)
	testing.expect_value(t, days_until, 364)

	today = Agenda_Date_Time{year = 2025, month = 12, day = 31, is_date = true}
	next, days_until = birthday_next_date(&birthday, today)
	testing.expect_value(t, days_until, 223)

	leap_birthday := Birthday{month = 2, day = 29, year = 0}
	today = Agenda_Date_Time{year = 2025, month = 3, day = 1, is_date = true}
	next, days_until = birthday_next_date(&leap_birthday, today)
	testing.expect_value(t, next.year, 2026)
	testing.expect_value(t, next.month, 2)
	testing.expect_value(t, next.day, 28)
	testing.expect(t, days_until > 0)
}

@(test)
birthday_database_round_trip_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	if calendar_database != nil {return}
	previous_ui := calendar_ui
	calendar_ui = {width = 900, height = 700}
	defer {calendar_ui = previous_ui}
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	if len(tmp) == 0 {tmp = "/tmp"}
	support := strings.concatenate({
		tmp,
		"/hw_calendar_birthday_test_",
		fmt.tprintf("%d", time.to_unix_nanoseconds(time.now())),
	})
	defer delete(support)
	defer _ = os.remove_all(support)
	if os.set_env("HW_CALENDAR_SUPPORT_DIR", support) != 0 {
		testing.fail_now(t, "could not set the support directory")
	}
	if !calendar_database_open() {
		testing.fail_now(t, "could not open the test database")
	}
	defer calendar_database_close()

	today := agenda_local_today()
	input := Birthday_Input{
		name = "Ada",
		month = today.month,
		day = today.day,
		year = 1815,
		advance_days = 14,
	}
	created, created_ok := birthday_create(&input)
	testing.expect(t, created_ok)
	defer birthday_destroy(&created)
	testing.expect_value(t, created.name, "Ada")
	testing.expect_value(t, created.month, today.month)
	testing.expect_value(t, created.day, today.day)
	testing.expect_value(t, created.year, 1815)
	testing.expect_value(t, created.advance_days, 14)

	got, got_ok := birthday_get(created.id)
	testing.expect(t, got_ok)
	defer birthday_destroy(&got)
	testing.expect_value(t, got.name, "Ada")

	list := birthday_list()
	defer birthdays_destroy(&list)
	testing.expect_value(t, len(list), 1)
	testing.expect_value(t, list[0].name, "Ada")

	upcoming := birthday_upcoming()
	defer birthday_upcoming_destroy(&upcoming)
	found := false
	for &item in upcoming {
		if item.id == created.id {found = true; break}
	}
	testing.expect(t, found)
}
