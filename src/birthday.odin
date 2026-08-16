package main

import "core:fmt"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:time"

BIRTHDAY_DEFAULT_ADVANCE_DAYS :: 7
BIRTHDAY_DEFAULT_ADVANCE_DAYS_KEY :: "birthday.default_advance_days"

Birthday :: struct {
	id: i64,
	name: string,
	month: int,
	day: int,
	year: int,
	advance_days: int,
	created_at_ms: i64,
	updated_at_ms: i64,
}

Birthday_Input :: struct {
	name: string,
	month: int,
	day: int,
	year: int,
	advance_days: int,
}

Birthday_Upcoming :: struct {
	id: i64,
	name: string,
	month: int,
	day: int,
	year: int,
	next_at: i64,
	days_until: int,
	advance_days: int,
}

birthday_default_advance_days :: proc() -> int {
	value, found := calendar_preference_get(
		BIRTHDAY_DEFAULT_ADVANCE_DAYS_KEY,
		context.temp_allocator,
	)
	if !found {return BIRTHDAY_DEFAULT_ADVANCE_DAYS}
	parsed, ok := strconv.parse_int(value)
	if !ok || parsed < 1 {return BIRTHDAY_DEFAULT_ADVANCE_DAYS}
	return parsed
}

birthday_set_default_advance_days :: proc(days: int) -> bool {
	if days < 1 {return false}
	return calendar_preference_set(
		BIRTHDAY_DEFAULT_ADVANCE_DAYS_KEY,
		fmt.tprintf("%d", days),
	)
}

birthday_date_valid :: proc(year, month, day: int) -> bool {
	check_year := year if year > 0 else 2024
	return agenda_date_time_valid(
		Agenda_Date_Time{year=check_year, month=month, day=day, is_date=true},
	)
}

birthday_input_valid :: proc(input: ^Birthday_Input) -> bool {
	if input == nil ||
	   len(strings.trim_space(input.name)) == 0 ||
	   !birthday_date_valid(input.year, input.month, input.day) ||
	   input.advance_days < 0 {
		return false
	}
	return true
}

birthday_destroy :: proc(birthday: ^Birthday, allocator := context.allocator) {
	if birthday == nil {return}
	delete(birthday.name, allocator)
	birthday^ = {}
}

birthdays_destroy :: proc(
	birthdays: ^[dynamic]Birthday,
	allocator := context.allocator,
) {
	for &birthday in birthdays^ {birthday_destroy(&birthday, allocator)}
	delete(birthdays^)
	birthdays^ = nil
}

birthday_upcoming_destroy :: proc(
	upcoming: ^[dynamic]Birthday_Upcoming,
	allocator := context.allocator,
) {
	for &item in upcoming^ {delete(item.name, allocator)}
	delete(upcoming^)
	upcoming^ = nil
}

BIRTHDAY_SELECT :: `SELECT id, name, month, day, year, advance_days,
	created_at_ms, updated_at_ms FROM birthdays`

birthday_from_statement :: proc(
	statement: ^SQLite_Statement,
	allocator := context.allocator,
) -> Birthday {
	return {
		id = sqlite3_column_int64(statement, 0),
		name = sqlite_column_string(statement, 1, allocator),
		month = int(sqlite3_column_int(statement, 2)),
		day = int(sqlite3_column_int(statement, 3)),
		year = int(sqlite3_column_int(statement, 4)),
		advance_days = int(sqlite3_column_int(statement, 5)),
		created_at_ms = sqlite3_column_int64(statement, 6),
		updated_at_ms = sqlite3_column_int64(statement, 7),
	}
}

birthday_create :: proc(input: ^Birthday_Input) -> (Birthday, bool) {
	if !birthday_input_valid(input) {return {}, false}
	statement, prepared := sqlite_prepare(calendar_database, `INSERT INTO birthdays
		(name, month, day, year, advance_days, created_at_ms, updated_at_ms)
		VALUES (?, ?, ?, ?, ?, ?, ?);`)
	if !prepared {return {}, false}
	defer sqlite3_finalize(statement)
	now := agenda_now_ms()
	ok := sqlite_bind_text_value(statement, 1, strings.trim_space(input.name)) &&
	      sqlite3_bind_int64(statement, 2, i64(input.month)) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 3, i64(input.day)) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 4, i64(input.year)) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 5, i64(input.advance_days)) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 6, now) == SQLITE_OK &&
	      sqlite3_bind_int64(statement, 7, now) == SQLITE_OK &&
	      sqlite3_step(statement) == SQLITE_DONE
	if !ok {return {}, false}
	return birthday_get(sqlite3_last_insert_rowid(calendar_database))
}

birthday_get :: proc(id: i64, allocator := context.allocator) -> (Birthday, bool) {
	statement, prepared := sqlite_prepare(
		calendar_database,
		BIRTHDAY_SELECT+" WHERE id = ?;",
	)
	if !prepared {return {}, false}
	defer sqlite3_finalize(statement)
	if sqlite3_bind_int64(statement, 1, id) != SQLITE_OK ||
	   sqlite3_step(statement) != SQLITE_ROW {return {}, false}
	return birthday_from_statement(statement, allocator), true
}

birthday_list :: proc(allocator := context.allocator) -> [dynamic]Birthday {
	result := make([dynamic]Birthday, allocator)
	statement, prepared := sqlite_prepare(
		calendar_database,
		BIRTHDAY_SELECT+" ORDER BY month, day, id;",
	)
	if !prepared {return result}
	defer sqlite3_finalize(statement)
	for sqlite3_step(statement) == SQLITE_ROW {
		append(&result, birthday_from_statement(statement, allocator))
	}
	return result
}

birthday_effective_advance_days :: proc(birthday: ^Birthday) -> int {
	if birthday == nil {return birthday_default_advance_days()}
	if birthday.advance_days > 0 {return birthday.advance_days}
	return birthday_default_advance_days()
}

birthday_adjusted_day :: proc(month, day, year: int) -> int {
	if agenda_date_time_valid(
		Agenda_Date_Time{year=year, month=month, day=day, is_date=true},
	) {
		return day
	}
	if month == 2 {return 28}
	return day
}

birthday_next_date :: proc(
	birthday: ^Birthday,
	today: Agenda_Date_Time,
) -> (Agenda_Date_Time, int) {
	if birthday == nil {return {}, -1}
	year := today.year
	for _ in 0..<2 {
		day := birthday_adjusted_day(birthday.month, birthday.day, year)
		candidate := Agenda_Date_Time{
			year = year,
			month = birthday.month,
			day = day,
			is_date = true,
		}
		candidate_days := agenda_days_from_civil(
			candidate.year,
			candidate.month,
			candidate.day,
		)
		today_days := agenda_days_from_civil(today.year, today.month, today.day)
		if candidate_days >= today_days {
			return candidate, int(candidate_days - today_days)
		}
		year += 1
	}
	return {}, -1
}

birthday_upcoming :: proc(
	allocator := context.allocator,
) -> [dynamic]Birthday_Upcoming {
	result := make([dynamic]Birthday_Upcoming, allocator)
	today := agenda_local_today()
	birthdays := birthday_list(context.temp_allocator)
	defer birthdays_destroy(&birthdays, context.temp_allocator)
	for &birthday in birthdays {
		next_date, days_until := birthday_next_date(&birthday, today)
		if days_until < 0 {continue}
		advance := birthday_effective_advance_days(&birthday)
		if days_until > advance {continue}
		append(&result, Birthday_Upcoming{
			id = birthday.id,
			name = strings.clone(birthday.name, allocator),
			month = birthday.month,
			day = birthday.day,
			year = birthday.year,
			next_at = agenda_date_time_stamp(next_date),
			days_until = days_until,
			advance_days = advance,
		})
	}
	sort.merge_sort_proc(result[:], proc(a, b: Birthday_Upcoming) -> int {
		if a.days_until < b.days_until {return -1}
		if a.days_until > b.days_until {return 1}
		if a.id < b.id {return -1}
		if a.id > b.id {return 1}
		return 0
	})
	return result
}

birthday_parse_date :: proc(
	value: string,
	month, day, year: ^int,
) -> bool {
	trimmed := strings.trim_space(value)
	month^ = 0
	day^ = 0
	year^ = 0
	if len(trimmed) == 5 && trimmed[2] == '-' {
		month_parsed, month_ok := agenda_parse_fixed_int(trimmed, 0, 2)
		day_parsed, day_ok := agenda_parse_fixed_int(trimmed, 3, 2)
		if !month_ok || !day_ok {return false}
		month^ = month_parsed
		day^ = day_parsed
		return birthday_date_valid(0, month^, day^)
	}
	if len(trimmed) == 10 && trimmed[4] == '-' && trimmed[7] == '-' {
		year_parsed, year_ok := agenda_parse_fixed_int(trimmed, 0, 4)
		month_parsed, month_ok := agenda_parse_fixed_int(trimmed, 5, 2)
		day_parsed, day_ok := agenda_parse_fixed_int(trimmed, 8, 2)
		if !year_ok || !month_ok || !day_ok {return false}
		month^ = month_parsed
		day^ = day_parsed
		year^ = year_parsed
		return birthday_date_valid(year^, month^, day^)
	}
	return false
}
