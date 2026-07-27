package main

import "core:fmt"
import "core:sort"
import "core:strconv"
import "core:strings"

ICal_Frequency :: enum {
	None,
	Secondly,
	Minutely,
	Hourly,
	Daily,
	Weekly,
	Monthly,
	Yearly,
}

ICal_Weekday :: enum int {
	Sunday,
	Monday,
	Tuesday,
	Wednesday,
	Thursday,
	Friday,
	Saturday,
}

ICal_By_Day :: struct {
	ordinal: int,
	weekday: ICal_Weekday,
}

ICal_Date_Time :: struct {
	year: int,
	month: int,
	day: int,
	hour: int,
	minute: int,
	second: int,
	is_date: bool,
	utc: bool,
}

ICal_Recurrence_Rule :: struct {
	frequency: ICal_Frequency,
	until: ICal_Date_Time,
	has_until: bool,
	count: int,
	has_count: bool,
	interval: int,
	by_seconds: [dynamic]int,
	by_minutes: [dynamic]int,
	by_hours: [dynamic]int,
	by_days: [dynamic]ICal_By_Day,
	by_month_days: [dynamic]int,
	by_year_days: [dynamic]int,
	by_week_numbers: [dynamic]int,
	by_months: [dynamic]int,
	by_set_positions: [dynamic]int,
	week_start: ICal_Weekday,
}

ICal_Expansion :: struct {
	occurrences: [dynamic]ICal_Date_Time,
	truncated: bool,
	error: string,
}

ical_recurrence_destroy :: proc(rule: ^ICal_Recurrence_Rule) {
	if rule == nil {return}
	delete(rule.by_seconds)
	delete(rule.by_minutes)
	delete(rule.by_hours)
	delete(rule.by_days)
	delete(rule.by_month_days)
	delete(rule.by_year_days)
	delete(rule.by_week_numbers)
	delete(rule.by_months)
	delete(rule.by_set_positions)
	rule^ = {}
}

ical_expansion_destroy :: proc(expansion: ^ICal_Expansion) {
	if expansion == nil {return}
	delete(expansion.occurrences)
	delete(expansion.error)
	expansion^ = {}
}

ical_is_leap_year :: proc(year: int) -> bool {
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

ical_days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 1, 3, 5, 7, 8, 10, 12: return 31
	case 4, 6, 9, 11: return 30
	case 2: return 29 if ical_is_leap_year(year) else 28
	}
	return 0
}

ical_date_time_valid :: proc(value: ICal_Date_Time) -> bool {
	if value.year < 0 || value.month < 1 || value.month > 12 ||
	   value.day < 1 || value.day > ical_days_in_month(value.year, value.month) {
		return false
	}
	if value.is_date {
		return value.hour == 0 && value.minute == 0 && value.second == 0
	}
	return value.hour >= 0 && value.hour <= 23 &&
	       value.minute >= 0 && value.minute <= 59 &&
	       value.second >= 0 && value.second <= 60
}

ical_parse_fixed_int :: proc(value: string, start, count: int) -> (int, bool) {
	if start < 0 || count <= 0 || start + count > len(value) {return 0, false}
	for index in start..<start+count {
		if value[index] < '0' || value[index] > '9' {return 0, false}
	}
	parsed, ok := strconv.parse_int(value[start:start+count])
	return parsed, ok
}

ical_parse_date_time :: proc(value: string) -> (ICal_Date_Time, bool) {
	result: ICal_Date_Time
	if len(value) == 8 {
		result.year, _ = ical_parse_fixed_int(value, 0, 4)
		result.month, _ = ical_parse_fixed_int(value, 4, 2)
		result.day, _ = ical_parse_fixed_int(value, 6, 2)
		result.is_date = true
		return result, ical_date_time_valid(result)
	}
	expected := 15
	if len(value) == 16 && value[15] == 'Z' {
		result.utc = true
	} else if len(value) != expected {
		return {}, false
	}
	if value[8] != 'T' {return {}, false}
	result.year, _ = ical_parse_fixed_int(value, 0, 4)
	result.month, _ = ical_parse_fixed_int(value, 4, 2)
	result.day, _ = ical_parse_fixed_int(value, 6, 2)
	result.hour, _ = ical_parse_fixed_int(value, 9, 2)
	result.minute, _ = ical_parse_fixed_int(value, 11, 2)
	result.second, _ = ical_parse_fixed_int(value, 13, 2)
	return result, ical_date_time_valid(result)
}

ical_parse_duration_seconds :: proc(value: string) -> (i64, bool) {
	if len(value) < 2 {return 0, false}
	sign := i64(1)
	index := 0
	if value[index] == '-' {
		sign = -1
		index += 1
	} else if value[index] == '+' {
		index += 1
	}
	if index >= len(value) || value[index] != 'P' {return 0, false}
	index += 1

	in_time := false
	has_value := false
	has_time_value := false
	last_rank := 0
	total := i64(0)
	for index < len(value) {
		if value[index] == 'T' {
			if in_time {return 0, false}
			in_time = true
			index += 1
			continue
		}
		number_start := index
		for index < len(value) && value[index] >= '0' && value[index] <= '9' {
			index += 1
		}
		if number_start == index || index >= len(value) {return 0, false}
		number, ok := strconv.parse_int(value[number_start:index])
		if !ok {return 0, false}
		unit := value[index]
		index += 1
		switch unit {
		case 'W':
			if in_time || has_value || index != len(value) {return 0, false}
			total += i64(number)*7*86400
			last_rank = 1
		case 'D':
			if in_time || last_rank >= 1 {return 0, false}
			total += i64(number)*86400
			last_rank = 1
		case 'H':
			if !in_time || last_rank >= 2 {return 0, false}
			total += i64(number)*3600
			last_rank = 2
			has_time_value = true
		case 'M':
			if !in_time || last_rank >= 3 {return 0, false}
			total += i64(number)*60
			last_rank = 3
			has_time_value = true
		case 'S':
			if !in_time || last_rank >= 4 {return 0, false}
			total += i64(number)
			last_rank = 4
			has_time_value = true
		case:
			return 0, false
		}
		has_value = true
	}
	if !has_value || (in_time && !has_time_value) {return 0, false}
	return total*sign, true
}

ical_format_date_time :: proc(
	value: ICal_Date_Time,
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

// This transformation maps a civil date to a day index relative to 1970-01-01.
ical_days_from_civil :: proc(year, month, day: int) -> i64 {
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

ical_civil_from_days :: proc(days: i64) -> (year, month, day: int) {
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

ical_date_time_stamp :: proc(value: ICal_Date_Time) -> i64 {
	return ical_days_from_civil(value.year, value.month, value.day) * 86400 +
	       i64(value.hour * 3600 + value.minute * 60 + min(value.second, 59))
}

ical_date_time_from_stamp :: proc(stamp: i64, is_date := false) -> ICal_Date_Time {
	days := stamp / 86400
	seconds := stamp % 86400
	if seconds < 0 {
		seconds += 86400
		days -= 1
	}
	year, month, day := ical_civil_from_days(days)
	result := ICal_Date_Time{year=year, month=month, day=day, is_date=is_date}
	if !is_date {
		result.hour = int(seconds / 3600)
		result.minute = int(seconds % 3600 / 60)
		result.second = int(seconds % 60)
	}
	return result
}

ical_date_time_compare :: proc(a, b: ICal_Date_Time) -> int {
	a_stamp := ical_date_time_stamp(a)
	b_stamp := ical_date_time_stamp(b)
	if a_stamp < b_stamp {return -1}
	if a_stamp > b_stamp {return 1}
	return 0
}

ical_weekday :: proc(value: ICal_Date_Time) -> ICal_Weekday {
	days := ical_days_from_civil(value.year, value.month, value.day)
	index := int((days + 4) % 7)
	if index < 0 {index += 7}
	return ICal_Weekday(index)
}

ical_day_of_year :: proc(value: ICal_Date_Time) -> int {
	return int(
		ical_days_from_civil(value.year, value.month, value.day) -
		ical_days_from_civil(value.year, 1, 1) +
		1,
	)
}

ical_weekday_from_text :: proc(value: string) -> (ICal_Weekday, bool) {
	switch strings.to_upper(value, context.temp_allocator) {
	case "SU": return .Sunday, true
	case "MO": return .Monday, true
	case "TU": return .Tuesday, true
	case "WE": return .Wednesday, true
	case "TH": return .Thursday, true
	case "FR": return .Friday, true
	case "SA": return .Saturday, true
	}
	return {}, false
}

ical_frequency_from_text :: proc(value: string) -> (ICal_Frequency, bool) {
	switch strings.to_upper(value, context.temp_allocator) {
	case "SECONDLY": return .Secondly, true
	case "MINUTELY": return .Minutely, true
	case "HOURLY": return .Hourly, true
	case "DAILY": return .Daily, true
	case "WEEKLY": return .Weekly, true
	case "MONTHLY": return .Monthly, true
	case "YEARLY": return .Yearly, true
	}
	return {}, false
}

ical_parse_integer_list :: proc(
	value: string,
	minimum, maximum: int,
	disallow_zero := false,
	allocator := context.allocator,
) -> ([dynamic]int, bool) {
	result := make([dynamic]int, allocator)
	remaining := value
	for part in strings.split_iterator(&remaining, ",") {
		parsed, ok := strconv.parse_int(part)
		if !ok || parsed < minimum || parsed > maximum ||
		   (disallow_zero && parsed == 0) {
			delete(result)
			return nil, false
		}
		append(&result, parsed)
	}
	return result, len(result) > 0
}

ical_parse_by_day_list :: proc(
	value: string,
	allocator := context.allocator,
) -> ([dynamic]ICal_By_Day, bool) {
	result := make([dynamic]ICal_By_Day, allocator)
	remaining := value
	for part in strings.split_iterator(&remaining, ",") {
		if len(part) < 2 {
			delete(result)
			return nil, false
		}
		weekday, ok := ical_weekday_from_text(part[len(part)-2:])
		if !ok {
			delete(result)
			return nil, false
		}
		ordinal := 0
		if len(part) > 2 {
			ordinal, ok = strconv.parse_int(part[:len(part)-2])
			if !ok || ordinal == 0 || ordinal < -53 || ordinal > 53 {
				delete(result)
				return nil, false
			}
		}
		append(&result, ICal_By_Day{ordinal=ordinal, weekday=weekday})
	}
	return result, len(result) > 0
}

ical_recurrence_error :: proc(message: string) -> (ICal_Recurrence_Rule, string, bool) {
	return {}, ical_clone(message), false
}

ical_parse_recurrence :: proc(
	value: string,
	allocator := context.allocator,
) -> (ICal_Recurrence_Rule, string, bool) {
	rule := ICal_Recurrence_Rule{
		interval = 1,
		week_start = .Monday,
		by_seconds = make([dynamic]int, allocator),
		by_minutes = make([dynamic]int, allocator),
		by_hours = make([dynamic]int, allocator),
		by_days = make([dynamic]ICal_By_Day, allocator),
		by_month_days = make([dynamic]int, allocator),
		by_year_days = make([dynamic]int, allocator),
		by_week_numbers = make([dynamic]int, allocator),
		by_months = make([dynamic]int, allocator),
		by_set_positions = make([dynamic]int, allocator),
	}
	seen := make(map[string]bool, context.temp_allocator)
	remaining := value
	for part in strings.split_iterator(&remaining, ";") {
		equals := strings.index(part, "=")
		if equals <= 0 {
			ical_recurrence_destroy(&rule)
			return ical_recurrence_error("Each recurrence rule part requires a name and value.")
		}
		name := strings.to_upper(part[:equals], context.temp_allocator)
		part_value := part[equals+1:]
		if seen[name] {
			ical_recurrence_destroy(&rule)
			return ical_recurrence_error(fmt.tprintf("The %s rule part occurs more than once.", name))
		}
		seen[name] = true
		switch name {
		case "FREQ":
			frequency, ok := ical_frequency_from_text(part_value)
			if !ok {
				ical_recurrence_destroy(&rule)
				return ical_recurrence_error("FREQ has an invalid value.")
			}
			rule.frequency = frequency
		case "UNTIL":
			until, ok := ical_parse_date_time(part_value)
			if !ok {
				ical_recurrence_destroy(&rule)
				return ical_recurrence_error("UNTIL has an invalid date or date-time.")
			}
			rule.until = until
			rule.has_until = true
		case "COUNT":
			count, ok := strconv.parse_int(part_value)
			if !ok || count <= 0 {
				ical_recurrence_destroy(&rule)
				return ical_recurrence_error("COUNT must be a positive integer.")
			}
			rule.count = count
			rule.has_count = true
		case "INTERVAL":
			interval, ok := strconv.parse_int(part_value)
			if !ok || interval <= 0 {
				ical_recurrence_destroy(&rule)
				return ical_recurrence_error("INTERVAL must be a positive integer.")
			}
			rule.interval = interval
		case "BYSECOND":
			values, ok := ical_parse_integer_list(part_value, 0, 60, false, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYSECOND contains an invalid value.")}
			delete(rule.by_seconds)
			rule.by_seconds = values
		case "BYMINUTE":
			values, ok := ical_parse_integer_list(part_value, 0, 59, false, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYMINUTE contains an invalid value.")}
			delete(rule.by_minutes)
			rule.by_minutes = values
		case "BYHOUR":
			values, ok := ical_parse_integer_list(part_value, 0, 23, false, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYHOUR contains an invalid value.")}
			delete(rule.by_hours)
			rule.by_hours = values
		case "BYDAY":
			values, ok := ical_parse_by_day_list(part_value, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYDAY contains an invalid value.")}
			delete(rule.by_days)
			rule.by_days = values
		case "BYMONTHDAY":
			values, ok := ical_parse_integer_list(part_value, -31, 31, true, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYMONTHDAY contains an invalid value.")}
			delete(rule.by_month_days)
			rule.by_month_days = values
		case "BYYEARDAY":
			values, ok := ical_parse_integer_list(part_value, -366, 366, true, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYYEARDAY contains an invalid value.")}
			delete(rule.by_year_days)
			rule.by_year_days = values
		case "BYWEEKNO":
			values, ok := ical_parse_integer_list(part_value, -53, 53, true, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYWEEKNO contains an invalid value.")}
			delete(rule.by_week_numbers)
			rule.by_week_numbers = values
		case "BYMONTH":
			values, ok := ical_parse_integer_list(part_value, 1, 12, false, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYMONTH contains an invalid value.")}
			delete(rule.by_months)
			rule.by_months = values
		case "BYSETPOS":
			values, ok := ical_parse_integer_list(part_value, -366, 366, true, allocator)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("BYSETPOS contains an invalid value.")}
			delete(rule.by_set_positions)
			rule.by_set_positions = values
		case "WKST":
			weekday, ok := ical_weekday_from_text(part_value)
			if !ok {ical_recurrence_destroy(&rule); return ical_recurrence_error("WKST contains an invalid weekday.")}
			rule.week_start = weekday
		case:
			ical_recurrence_destroy(&rule)
			return ical_recurrence_error(fmt.tprintf("The %s rule part is not defined by RFC 5545.", name))
		}
	}
	if rule.frequency == .None {
		ical_recurrence_destroy(&rule)
		return ical_recurrence_error("FREQ is required.")
	}
	if rule.has_count && rule.has_until {
		ical_recurrence_destroy(&rule)
		return ical_recurrence_error("COUNT and UNTIL cannot occur together.")
	}
	if len(rule.by_set_positions) > 0 &&
	   len(rule.by_seconds) == 0 && len(rule.by_minutes) == 0 &&
	   len(rule.by_hours) == 0 && len(rule.by_days) == 0 &&
	   len(rule.by_month_days) == 0 && len(rule.by_year_days) == 0 &&
	   len(rule.by_week_numbers) == 0 && len(rule.by_months) == 0 {
		ical_recurrence_destroy(&rule)
		return ical_recurrence_error("BYSETPOS requires another BY rule part.")
	}
	if rule.frequency != .Yearly && len(rule.by_week_numbers) > 0 {
		ical_recurrence_destroy(&rule)
		return ical_recurrence_error("BYWEEKNO is valid only with YEARLY.")
	}
	if rule.frequency == .Weekly && len(rule.by_month_days) > 0 {
		ical_recurrence_destroy(&rule)
		return ical_recurrence_error("BYMONTHDAY is not valid with WEEKLY.")
	}
	if rule.frequency != .Yearly && len(rule.by_year_days) > 0 {
		ical_recurrence_destroy(&rule)
		return ical_recurrence_error("BYYEARDAY is valid only with YEARLY.")
	}
	for by_day in rule.by_days {
		if by_day.ordinal == 0 {continue}
		if rule.frequency != .Monthly && rule.frequency != .Yearly {
			ical_recurrence_destroy(&rule)
			return ical_recurrence_error(
				"A numeric BYDAY is valid only with MONTHLY or YEARLY.",
			)
		}
		if rule.frequency == .Yearly && len(rule.by_week_numbers) > 0 {
			ical_recurrence_destroy(&rule)
			return ical_recurrence_error(
				"A numeric BYDAY cannot occur with YEARLY and BYWEEKNO.",
			)
		}
	}
	return rule, "", true
}

ical_int_list_contains :: proc(values: []int, value: int) -> bool {
	for candidate in values {if candidate == value {return true}}
	return false
}

ical_week_start_day :: proc(value: ICal_Date_Time, week_start: ICal_Weekday) -> i64 {
	day := ical_days_from_civil(value.year, value.month, value.day)
	offset := (int(ical_weekday(value)) - int(week_start) + 7) % 7
	return day - i64(offset)
}

ical_week_number :: proc(
	value: ICal_Date_Time,
	week_start: ICal_Weekday,
) -> (number, count: int) {
	jan4 := ICal_Date_Time{year=value.year, month=1, day=4, is_date=true}
	next_jan4 := ICal_Date_Time{year=value.year+1, month=1, day=4, is_date=true}
	week1 := ical_week_start_day(jan4, week_start)
	next_week1 := ical_week_start_day(next_jan4, week_start)
	day := ical_days_from_civil(value.year, value.month, value.day)
	count = int((next_week1 - week1) / 7)
	if day < week1 {
		previous_jan4 := ICal_Date_Time{
			year = value.year-1,
			month = 1,
			day = 4,
			is_date = true,
		}
		previous_week1 := ical_week_start_day(previous_jan4, week_start)
		number = int((day-previous_week1)/7)+1
		count = int((week1-previous_week1)/7)
		return
	}
	if day >= next_week1 {
		following_jan4 := ICal_Date_Time{
			year = value.year+2,
			month = 1,
			day = 4,
			is_date = true,
		}
		following_week1 := ical_week_start_day(following_jan4, week_start)
		number = 1
		count = int((following_week1-next_week1)/7)
		return
	}
	number = int((day - week1) / 7) + 1
	return
}

ical_nth_weekday_in_month :: proc(value: ICal_Date_Time) -> (positive, negative: int) {
	positive = (value.day - 1) / 7 + 1
	negative = -((ical_days_in_month(value.year, value.month) - value.day) / 7 + 1)
	return
}

ical_nth_weekday_in_year :: proc(value: ICal_Date_Time) -> (positive, negative: int) {
	day_of_year := ical_day_of_year(value)
	total := 365 + (ical_is_leap_year(value.year) ? 1 : 0)
	positive = (day_of_year - 1) / 7 + 1
	negative = -((total - day_of_year) / 7 + 1)
	return
}

ical_matches_by_day :: proc(
	rule: ^ICal_Recurrence_Rule,
	value: ICal_Date_Time,
) -> bool {
	if len(rule.by_days) == 0 {return true}
	weekday := ical_weekday(value)
	for by_day in rule.by_days {
		if by_day.weekday != weekday {continue}
		if by_day.ordinal == 0 {return true}
		if rule.frequency == .Monthly || len(rule.by_months) > 0 {
			positive, negative := ical_nth_weekday_in_month(value)
			if by_day.ordinal == positive || by_day.ordinal == negative {return true}
		} else if rule.frequency == .Yearly {
			positive, negative := ical_nth_weekday_in_year(value)
			if by_day.ordinal == positive || by_day.ordinal == negative {return true}
		}
	}
	return false
}

ical_matches_date_filters :: proc(
	rule: ^ICal_Recurrence_Rule,
	value, dtstart: ICal_Date_Time,
) -> bool {
	if len(rule.by_months) > 0 && !ical_int_list_contains(rule.by_months[:], value.month) {
		return false
	}
	if len(rule.by_week_numbers) > 0 {
		number, count := ical_week_number(value, rule.week_start)
		matched := false
		for requested in rule.by_week_numbers {
			resolved := requested
			if requested < 0 {resolved = count + requested + 1}
			if number == resolved {matched = true; break}
		}
		if !matched {return false}
	}
	if len(rule.by_year_days) > 0 {
		year_day := ical_day_of_year(value)
		total := 365 + (ical_is_leap_year(value.year) ? 1 : 0)
		matched := false
		for requested in rule.by_year_days {
			resolved := requested
			if requested < 0 {resolved = total + requested + 1}
			if year_day == resolved {matched = true; break}
		}
		if !matched {return false}
	}
	if len(rule.by_month_days) > 0 {
		month_days := ical_days_in_month(value.year, value.month)
		matched := false
		for requested in rule.by_month_days {
			resolved := requested
			if requested < 0 {resolved = month_days + requested + 1}
			if value.day == resolved {matched = true; break}
		}
		if !matched {return false}
	}
	if !ical_matches_by_day(rule, value) {return false}

	has_day_selector := len(rule.by_days) > 0 || len(rule.by_month_days) > 0 ||
	                    len(rule.by_year_days) > 0 || len(rule.by_week_numbers) > 0
	if !has_day_selector {
		#partial switch rule.frequency {
		case .Yearly:
			if len(rule.by_months) == 0 && value.month != dtstart.month {return false}
			if value.day != dtstart.day {return false}
		case .Monthly:
			if value.day != dtstart.day {return false}
		case .Weekly:
			if ical_weekday(value) != ical_weekday(dtstart) {return false}
		}
	}
	return true
}

ical_frequency_rank :: proc(frequency: ICal_Frequency) -> int {
	#partial switch frequency {
	case .Secondly: return 0
	case .Minutely: return 1
	case .Hourly: return 2
	case .Daily: return 3
	case .Weekly: return 4
	case .Monthly: return 5
	case .Yearly: return 6
	}
	return -1
}

ical_period_bounds :: proc(
	rule: ^ICal_Recurrence_Rule,
	dtstart: ICal_Date_Time,
	period_index: int,
) -> (start, end: ICal_Date_Time) {
	step := period_index * rule.interval
	#partial switch rule.frequency {
	case .Yearly:
		year := dtstart.year+step
		if len(rule.by_week_numbers) > 0 {
			jan4 := ICal_Date_Time{
				year = year,
				month = 1,
				day = 4,
				is_date = true,
			}
			next_jan4 := ICal_Date_Time{
				year = year+1,
				month = 1,
				day = 4,
				is_date = true,
			}
			start = ical_date_time_from_stamp(
				ical_week_start_day(jan4, rule.week_start)*86400,
			)
			end = ical_date_time_from_stamp(
				ical_week_start_day(next_jan4, rule.week_start)*86400,
			)
		} else {
			start = ICal_Date_Time{year=year, month=1, day=1}
			end = ICal_Date_Time{year=year+1, month=1, day=1}
		}
	case .Monthly:
		total_month := dtstart.year * 12 + dtstart.month - 1 + step
		year := total_month / 12
		month := total_month % 12 + 1
		start = ICal_Date_Time{year=year, month=month, day=1}
		next := total_month + 1
		end = ICal_Date_Time{year=next/12, month=next%12+1, day=1}
	case .Weekly:
		day := ical_week_start_day(dtstart, rule.week_start) + i64(step * 7)
		start = ical_date_time_from_stamp(day * 86400)
		end = ical_date_time_from_stamp((day + 7) * 86400)
	case .Daily:
		stamp := ical_days_from_civil(dtstart.year, dtstart.month, dtstart.day) + i64(step)
		start = ical_date_time_from_stamp(stamp * 86400)
		end = ical_date_time_from_stamp((stamp + 1) * 86400)
	case .Hourly:
		stamp := ical_date_time_stamp(dtstart) - i64(dtstart.minute*60+dtstart.second) + i64(step*3600)
		start = ical_date_time_from_stamp(stamp)
		end = ical_date_time_from_stamp(stamp + 3600)
	case .Minutely:
		stamp := ical_date_time_stamp(dtstart) - i64(dtstart.second) + i64(step*60)
		start = ical_date_time_from_stamp(stamp)
		end = ical_date_time_from_stamp(stamp + 60)
	case .Secondly:
		stamp := ical_date_time_stamp(dtstart) + i64(step)
		start = ical_date_time_from_stamp(stamp)
		end = ical_date_time_from_stamp(stamp + 1)
	}
	return
}

ical_candidate_compare :: proc(a, b: ICal_Date_Time) -> int {
	return ical_date_time_compare(a, b)
}

ical_append_unique_sorted :: proc(
	values: ^[dynamic]ICal_Date_Time,
	value: ICal_Date_Time,
) {
	for current in values^ {
		if ical_date_time_compare(current, value) == 0 {return}
	}
	append(values, value)
}

ical_period_candidates :: proc(
	rule: ^ICal_Recurrence_Rule,
	dtstart: ICal_Date_Time,
	period_index: int,
	allocator := context.allocator,
) -> ([dynamic]ICal_Date_Time, bool) {
	period_start, period_end := ical_period_bounds(rule, dtstart, period_index)
	candidates := make([dynamic]ICal_Date_Time, allocator)
	first_day := ical_days_from_civil(period_start.year, period_start.month, period_start.day)
	last_day := ical_days_from_civil(period_end.year, period_end.month, period_end.day)
	if rule.frequency == .Hourly || rule.frequency == .Minutely || rule.frequency == .Secondly {
		first_day = ical_days_from_civil(period_start.year, period_start.month, period_start.day)
		last_day = first_day + 1
	}
	hours := rule.by_hours[:]
	default_hours := [1]int{dtstart.hour}
	if len(hours) == 0 {
		if ical_frequency_rank(rule.frequency) < ical_frequency_rank(.Daily) {
			default_hours[0] = period_start.hour
		}
		hours = default_hours[:]
	}
	minutes := rule.by_minutes[:]
	default_minutes := [1]int{dtstart.minute}
	if len(minutes) == 0 {
		if ical_frequency_rank(rule.frequency) < ical_frequency_rank(.Hourly) {
			default_minutes[0] = period_start.minute
		}
		minutes = default_minutes[:]
	}
	seconds := rule.by_seconds[:]
	default_seconds := [1]int{dtstart.second}
	if len(seconds) == 0 {
		if ical_frequency_rank(rule.frequency) < ical_frequency_rank(.Minutely) {
			default_seconds[0] = period_start.second
		}
		seconds = default_seconds[:]
	}
	for day_stamp in first_day..<last_day {
		date := ical_date_time_from_stamp(day_stamp * 86400)
		if !ical_matches_date_filters(rule, date, dtstart) {continue}
		for hour in hours {
			for minute in minutes {
				for second in seconds {
					candidate := date
					candidate.hour = hour
					candidate.minute = minute
					candidate.second = second
					candidate.utc = dtstart.utc
					candidate.is_date = dtstart.is_date
					if dtstart.is_date {
						candidate.hour, candidate.minute, candidate.second = 0, 0, 0
					}
					if ical_date_time_compare(candidate, period_start) < 0 ||
					   ical_date_time_compare(candidate, period_end) >= 0 {
						continue
					}
					append(&candidates, candidate)
					if len(candidates) > ICAL_MAX_PERIOD_CANDIDATES {
						return candidates, false
					}
				}
			}
		}
	}
	sort.merge_sort_proc(candidates[:], ical_candidate_compare)
	if len(rule.by_set_positions) == 0 {return candidates, true}
	selected := make([dynamic]ICal_Date_Time, allocator)
	for position in rule.by_set_positions {
		index := position - 1
		if position < 0 {index = len(candidates) + position}
		if index >= 0 && index < len(candidates) {
			ical_append_unique_sorted(&selected, candidates[index])
		}
	}
	delete(candidates)
	sort.merge_sort_proc(selected[:], ical_candidate_compare)
	return selected, true
}

ical_expand_recurrence :: proc(
	rule: ^ICal_Recurrence_Rule,
	dtstart, range_start, range_end: ICal_Date_Time,
	limit := 10_000,
	allocator := context.allocator,
) -> ICal_Expansion {
	result := ICal_Expansion{
		occurrences = make([dynamic]ICal_Date_Time, allocator),
	}
	if rule == nil || rule.frequency == .None || !ical_date_time_valid(dtstart) ||
	   ical_date_time_compare(range_start, range_end) >= 0 {
		result.error = ical_clone("The recurrence expansion input is invalid.", allocator)
		return result
	}
	result_limit := min(max(1, limit), ICAL_MAX_EXPANSION_RESULTS)
	emitted_total := 0
	for period_index in 0..<ICAL_MAX_PERIODS {
		period_start, _ := ical_period_bounds(rule, dtstart, period_index)
		if rule.has_until && ical_date_time_compare(period_start, rule.until) > 0 {break}
		if ical_date_time_compare(period_start, range_end) >= 0 &&
		   (!rule.has_count || emitted_total >= rule.count) {
			break
		}
		candidates, complete := ical_period_candidates(
			rule,
			dtstart,
			period_index,
			context.temp_allocator,
		)
		if !complete {
			result.error = ical_clone(
				"One recurrence period exceeds the candidate resource limit.",
				allocator,
			)
			return result
		}
		for candidate in candidates {
			if ical_date_time_compare(candidate, dtstart) < 0 {continue}
			if rule.has_until && ical_date_time_compare(candidate, rule.until) > 0 {continue}
			emitted_total += 1
			if rule.has_count && emitted_total > rule.count {break}
			if ical_date_time_compare(candidate, range_start) < 0 {continue}
			if ical_date_time_compare(candidate, range_end) >= 0 {continue}
			append(&result.occurrences, candidate)
			if len(result.occurrences) >= result_limit {
				result.truncated = true
				return result
			}
		}
		if rule.has_count && emitted_total >= rule.count {break}
		if ical_date_time_compare(period_start, range_end) >= 0 {break}
	}
	if !rule.has_count && !rule.has_until {
		period_start, _ := ical_period_bounds(rule, dtstart, ICAL_MAX_PERIODS-1)
		if ical_date_time_compare(period_start, range_end) < 0 {
			result.error = ical_clone(
				"The recurrence range exceeds the period resource limit.",
				allocator,
			)
		}
	}
	return result
}
