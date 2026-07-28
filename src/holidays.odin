package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"

CALENDAR_HOLIDAY_SCHEMA_VERSION :: 1

Calendar_Holiday_Kind :: enum {
	Invalid,
	State_Holiday,
	Public_Holiday,
	Memorial_Day,
}

Calendar_Holiday_Rule :: enum {
	Invalid,
	Fixed,
	Easter_Offset,
}

Calendar_Holiday_Definition :: struct {
	id: string,
	name: string,
	kind: string,
	rule: string,
	month: int,
	day: int,
	easter_offset_days: int,
}

Calendar_Holiday_Country :: struct {
	schema_version: int,
	country_code: string,
	country_name: string,
	effective_from_year: int,
	source_title: string,
	source_url: string,
	source_effective_date: string,
	source_retrieved_date: string,
	entries: []Calendar_Holiday_Definition,
	enabled: bool,
}

Calendar_Holiday_Occurrence :: struct {
	country_index: int,
	definition_index: int,
	date: ICal_Date_Time,
}

calendar_holiday_country_destroy :: proc(country: ^Calendar_Holiday_Country) {
	if country == nil {return}
	delete(country.country_code)
	delete(country.country_name)
	delete(country.source_title)
	delete(country.source_url)
	delete(country.source_effective_date)
	delete(country.source_retrieved_date)
	for &entry in country.entries {
		delete(entry.id)
		delete(entry.name)
		delete(entry.kind)
		delete(entry.rule)
	}
	delete(country.entries)
	country^ = {}
}

calendar_holiday_countries_destroy :: proc(
	countries: ^[dynamic]Calendar_Holiday_Country,
) {
	for &country in countries^ {calendar_holiday_country_destroy(&country)}
	delete(countries^)
	countries^ = nil
}

calendar_holiday_kind :: proc(value: string) -> Calendar_Holiday_Kind {
	switch value {
	case "state_holiday": return .State_Holiday
	case "public_holiday": return .Public_Holiday
	case "memorial_day": return .Memorial_Day
	}
	return .Invalid
}

calendar_holiday_rule :: proc(value: string) -> Calendar_Holiday_Rule {
	switch value {
	case "fixed": return .Fixed
	case "easter_offset": return .Easter_Offset
	}
	return .Invalid
}

calendar_holiday_country_valid :: proc(
	country: ^Calendar_Holiday_Country,
) -> bool {
	if country == nil ||
	   country.schema_version != CALENDAR_HOLIDAY_SCHEMA_VERSION ||
	   len(country.country_code) != 2 ||
	   len(country.country_name) == 0 ||
	   country.effective_from_year < 1 ||
	   len(country.source_title) == 0 ||
	   len(country.source_url) == 0 ||
	   len(country.source_effective_date) == 0 ||
	   len(country.source_retrieved_date) == 0 ||
	   len(country.entries) == 0 {
		return false
	}
	for character in country.country_code {
		if character < 'A' || character > 'Z' {return false}
	}
	ids := make(map[string]bool, context.temp_allocator)
	for &entry in country.entries {
		if len(entry.id) == 0 || ids[entry.id] || len(entry.name) == 0 ||
		   calendar_holiday_kind(entry.kind) == .Invalid {
			return false
		}
		ids[entry.id] = true
		switch calendar_holiday_rule(entry.rule) {
		case .Fixed:
			if entry.month < 1 || entry.month > 12 ||
			   entry.day < 1 || entry.day > 31 {
				return false
			}
			date := ICal_Date_Time{
				year = 2024,
				month = entry.month,
				day = entry.day,
				is_date = true,
			}
			stamp := ical_days_from_civil(date.year, date.month, date.day)
			round_trip := ical_date_time_from_stamp(stamp*86400, true)
			if round_trip.year != date.year ||
			   round_trip.month != date.month ||
			   round_trip.day != date.day {
				return false
			}
		case .Easter_Offset:
			if entry.easter_offset_days < -14 ||
			   entry.easter_offset_days > 14 {
				return false
			}
		case .Invalid:
			return false
		}
	}
	return true
}

calendar_holiday_decode :: proc(
	bytes: []u8,
) -> (Calendar_Holiday_Country, bool) {
	country: Calendar_Holiday_Country
	if error := json.unmarshal(bytes, &country); error != nil {
		calendar_holiday_country_destroy(&country)
		return {}, false
	}
	if !calendar_holiday_country_valid(&country) {
		calendar_holiday_country_destroy(&country)
		return {}, false
	}
	return country, true
}

calendar_holiday_preference_key :: proc(code: string) -> string {
	return fmt.tprintf(
		"holidays.country.%s.enabled",
		strings.to_lower(code, context.temp_allocator),
	)
}

calendar_holiday_country_enabled :: proc(code: string) -> bool {
	key := calendar_holiday_preference_key(code)
	value, found := calendar_meta_get(key, context.temp_allocator)
	if !found {return true}
	return value == "enabled"
}

calendar_holiday_country_set_enabled :: proc(
	country: ^Calendar_Holiday_Country,
	enabled: bool,
) -> bool {
	if country == nil {return false}
	key := calendar_holiday_preference_key(country.country_code)
	if !calendar_meta_set(key, enabled ? "enabled" : "disabled") {
		return false
	}
	country.enabled = enabled
	return true
}

calendar_holiday_bundle_resource_path :: proc(filename: string) -> string {
	bundle := msg_id(objc_getClass("NSBundle"), sel_registerName("mainBundle"))
	if bundle == nil {return ""}
	resource_path := msg_id(bundle, sel_registerName("resourcePath"))
	if resource_path == nil {return ""}
	utf8 := calendar_msg_cstring(resource_path, sel_registerName("UTF8String"))
	if utf8 == nil {return ""}
	return fmt.tprintf("%s/Holidays/%s", string(utf8), filename)
}

calendar_holiday_countries_load :: proc(
	allocator := context.allocator,
) -> [dynamic]Calendar_Holiday_Country {
	countries := make([dynamic]Calendar_Holiday_Country, allocator)
	resources := []string{"sk.json"}
	for filename in resources {
		path := calendar_holiday_bundle_resource_path(filename)
		if len(path) == 0 {
			fmt.eprintf("[hw_calendar] could not resolve holiday resource %s\n", filename)
			continue
		}
		bytes, read := os.read_entire_file(path, allocator)
		if !read {
			fmt.eprintf("[hw_calendar] could not read holiday resource %s\n", filename)
			continue
		}
		country, decoded := calendar_holiday_decode(bytes)
		delete(bytes)
		if !decoded {
			fmt.eprintf("[hw_calendar] invalid holiday resource %s\n", filename)
			continue
		}
		country.enabled = calendar_holiday_country_enabled(country.country_code)
		append(&countries, country)
	}
	return countries
}

calendar_gregorian_easter :: proc(year: int) -> ICal_Date_Time {
	a := year%19
	b := year/100
	c := year%100
	d := b/4
	e := b%4
	f := (b+8)/25
	g := (b-f+1)/3
	h := (19*a+b-d-g+15)%30
	i := c/4
	k := c%4
	l := (32+2*e+2*i-h-k)%7
	m := (a+11*h+22*l)/451
	month := (h+l-7*m+114)/31
	day := (h+l-7*m+114)%31+1
	return {year = year, month = month, day = day, is_date = true}
}

calendar_holiday_definition_date :: proc(
	definition: ^Calendar_Holiday_Definition,
	year: int,
) -> (ICal_Date_Time, bool) {
	if definition == nil {return {}, false}
	switch calendar_holiday_rule(definition.rule) {
	case .Fixed:
		return {
			year = year,
			month = definition.month,
			day = definition.day,
			is_date = true,
		}, true
	case .Easter_Offset:
		easter := calendar_gregorian_easter(year)
		days := ical_days_from_civil(easter.year, easter.month, easter.day) +
		        i64(definition.easter_offset_days)
		return ical_date_time_from_stamp(days*86400, true), true
	case .Invalid:
	}
	return {}, false
}

calendar_holiday_occurrence_compare :: proc(
	a, b: Calendar_Holiday_Occurrence,
) -> int {
	a_days := ical_days_from_civil(a.date.year, a.date.month, a.date.day)
	b_days := ical_days_from_civil(b.date.year, b.date.month, b.date.day)
	if a_days < b_days {return -1}
	if a_days > b_days {return 1}
	if a.country_index < b.country_index {return -1}
	if a.country_index > b.country_index {return 1}
	if a.definition_index < b.definition_index {return -1}
	if a.definition_index > b.definition_index {return 1}
	return 0
}

calendar_holiday_occurrences_expand :: proc(
	countries: []Calendar_Holiday_Country,
	range_start, range_end: ICal_Date_Time,
	allocator := context.allocator,
) -> [dynamic]Calendar_Holiday_Occurrence {
	result := make([dynamic]Calendar_Holiday_Occurrence, allocator)
	start_days := ical_days_from_civil(
		range_start.year,
		range_start.month,
		range_start.day,
	)
	end_days := ical_days_from_civil(range_end.year, range_end.month, range_end.day)
	for &country, country_index in countries {
		if !country.enabled {continue}
		first_year := max(range_start.year, country.effective_from_year)
		for year in first_year..=range_end.year {
			for &definition, definition_index in country.entries {
				date, valid := calendar_holiday_definition_date(&definition, year)
				if !valid {continue}
				days := ical_days_from_civil(date.year, date.month, date.day)
				if days < start_days || days >= end_days {continue}
				append(&result, Calendar_Holiday_Occurrence{
					country_index = country_index,
					definition_index = definition_index,
					date = date,
				})
			}
		}
	}
	sort.merge_sort_proc(result[:], calendar_holiday_occurrence_compare)
	return result
}

calendar_holiday_next_date :: proc(
	country: ^Calendar_Holiday_Country,
	definition: ^Calendar_Holiday_Definition,
	from: ICal_Date_Time,
) -> (ICal_Date_Time, bool) {
	if country == nil || definition == nil {return {}, false}
	from_days := ical_days_from_civil(from.year, from.month, from.day)
	first_year := max(from.year, country.effective_from_year)
	for year in first_year..=first_year+1 {
		date, valid := calendar_holiday_definition_date(definition, year)
		if !valid {continue}
		days := ical_days_from_civil(date.year, date.month, date.day)
		if days >= from_days {return date, true}
	}
	return {}, false
}
