package main

import "core:fmt"
import "core:strconv"

Agenda_Weekday :: enum int {
	Sunday,
	Monday,
	Tuesday,
	Wednesday,
	Thursday,
	Friday,
	Saturday,
}

Agenda_Date_Time :: struct {
	year: int,
	month: int,
	day: int,
	hour: int,
	minute: int,
	second: int,
	is_date: bool,
	utc: bool,
}

agenda_is_leap_year :: proc(year: int) -> bool {
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

agenda_days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 1, 3, 5, 7, 8, 10, 12: return 31
	case 4, 6, 9, 11: return 30
	case 2: return 29 if agenda_is_leap_year(year) else 28
	}
	return 0
}

agenda_date_time_valid :: proc(value: Agenda_Date_Time) -> bool {
	if value.year < 0 || value.month < 1 || value.month > 12 ||
	   value.day < 1 || value.day > agenda_days_in_month(value.year, value.month) {
		return false
	}
	if value.is_date {
		return value.hour == 0 && value.minute == 0 && value.second == 0
	}
	return value.hour >= 0 && value.hour <= 23 &&
	       value.minute >= 0 && value.minute <= 59 &&
	       value.second >= 0 && value.second <= 60
}

agenda_parse_fixed_int :: proc(value: string, start, count: int) -> (int, bool) {
	if start < 0 || count <= 0 || start + count > len(value) {return 0, false}
	for index in start..<start+count {
		if value[index] < '0' || value[index] > '9' {return 0, false}
	}
	parsed, ok := strconv.parse_int(value[start:start+count])
	return parsed, ok
}

agenda_parse_date_time :: proc(value: string) -> (Agenda_Date_Time, bool) {
	result: Agenda_Date_Time
	if len(value) == 8 {
		result.year, _ = agenda_parse_fixed_int(value, 0, 4)
		result.month, _ = agenda_parse_fixed_int(value, 4, 2)
		result.day, _ = agenda_parse_fixed_int(value, 6, 2)
		result.is_date = true
		return result, agenda_date_time_valid(result)
	}
	if len(value) == 16 && value[15] == 'Z' {
		result.utc = true
	} else if len(value) != 15 {
		return {}, false
	}
	if value[8] != 'T' {return {}, false}
	result.year, _ = agenda_parse_fixed_int(value, 0, 4)
	result.month, _ = agenda_parse_fixed_int(value, 4, 2)
	result.day, _ = agenda_parse_fixed_int(value, 6, 2)
	result.hour, _ = agenda_parse_fixed_int(value, 9, 2)
	result.minute, _ = agenda_parse_fixed_int(value, 11, 2)
	result.second, _ = agenda_parse_fixed_int(value, 13, 2)
	return result, agenda_date_time_valid(result)
}

agenda_format_date_time :: proc(
	value: Agenda_Date_Time,
	allocator := context.allocator,
) -> string {
	if value.is_date {
		return fmt.aprintf(
			"%04d%02d%02d",
			value.year,
			value.month,
			value.day,
			allocator = allocator,
		)
	}
	return fmt.aprintf(
		"%04d%02d%02dT%02d%02d%02d%s",
		value.year,
		value.month,
		value.day,
		value.hour,
		value.minute,
		value.second,
		value.utc ? "Z" : "",
		allocator = allocator,
	)
}

agenda_days_from_civil :: proc(year, month, day: int) -> i64 {
	y := i64(year)
	m := i64(month)
	d := i64(day)
	if m <= 2 {y -= 1}
	era := (y >= 0 ? y : y - 399) / 400
	yoe := y - era * 400
	adjusted_month := m + (m > 2 ? -3 : 9)
	doy := (153 * adjusted_month + 2) / 5 + d - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

agenda_civil_from_days :: proc(days: i64) -> (year, month, day: int) {
	z := days + 719468
	era := (z >= 0 ? z : z - 146096) / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	y := yoe + era * 400
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	d := doy - (153 * mp + 2) / 5 + 1
	m := mp + (mp < 10 ? 3 : -9)
	if m <= 2 {y += 1}
	return int(y), int(m), int(d)
}

agenda_date_time_stamp :: proc(value: Agenda_Date_Time) -> i64 {
	return agenda_days_from_civil(value.year, value.month, value.day) * 86400 +
	       i64(value.hour * 3600 + value.minute * 60 + min(value.second, 59))
}

agenda_date_time_from_stamp :: proc(stamp: i64, is_date := false) -> Agenda_Date_Time {
	days := stamp / 86400
	seconds := stamp % 86400
	if seconds < 0 {
		seconds += 86400
		days -= 1
	}
	year, month, day := agenda_civil_from_days(days)
	result := Agenda_Date_Time{year=year, month=month, day=day, is_date=is_date}
	if !is_date {
		result.hour = int(seconds / 3600)
		result.minute = int(seconds % 3600 / 60)
		result.second = int(seconds % 60)
	}
	return result
}

agenda_weekday :: proc(value: Agenda_Date_Time) -> Agenda_Weekday {
	days := agenda_days_from_civil(value.year, value.month, value.day)
	index := int((days + 4) % 7)
	if index < 0 {index += 7}
	return Agenda_Weekday(index)
}
