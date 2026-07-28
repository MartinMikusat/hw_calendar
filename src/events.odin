package main

import "core:sort"
import "core:strings"

Calendar_Occurrence :: struct {
	event_index: int,
	uid: string,
	recurrence_id: string,
	summary: string,
	location: string,
	categories: string,
	important: bool,
	start: ICal_Date_Time,
	end: ICal_Date_Time,
}

Calendar_RDate :: struct {
	start: ICal_Date_Time,
	duration_seconds: i64,
	has_duration: bool,
}

calendar_occurrences_destroy :: proc(values: ^[dynamic]Calendar_Occurrence) {
	for &value in values^ {
		delete(value.uid)
		delete(value.recurrence_id)
		delete(value.summary)
		delete(value.location)
		delete(value.categories)
	}
	delete(values^)
	values^ = nil
}

calendar_event_component :: proc(
	event: ^Calendar_Event,
	allocator := context.allocator,
) -> (ICal_Document, ^ICal_Component, bool) {
	document := ical_parse(event.raw_component, allocator)
	if len(document.components) == 0 {return document, nil, false}
	component := &document.components[0]
	if component.name != "VEVENT" {return document, nil, false}
	return document, component, true
}

calendar_property_date_values :: proc(
	component: ^ICal_Component,
	name: string,
	allocator := context.allocator,
) -> [dynamic]ICal_Date_Time {
	result := make([dynamic]ICal_Date_Time, allocator)
	properties := ical_component_properties(component, name, context.temp_allocator)
	for property in properties {
		remaining := property.value
		for raw in strings.split_iterator(&remaining, ",") {
			value := raw
			if slash := strings.index(value, "/"); slash >= 0 {value = value[:slash]}
			parsed, ok := ical_parse_date_time(value)
			if ok {ical_append_unique_sorted(&result, parsed)}
		}
	}
	sort.merge_sort_proc(result[:], ical_candidate_compare)
	return result
}

calendar_rdate_compare :: proc(a, b: Calendar_RDate) -> int {
	return ical_date_time_compare(a.start, b.start)
}

calendar_property_rdates :: proc(
	component: ^ICal_Component,
	allocator := context.allocator,
) -> [dynamic]Calendar_RDate {
	result := make([dynamic]Calendar_RDate, allocator)
	properties := ical_component_properties(component, "RDATE", context.temp_allocator)
	for property in properties {
		remaining := property.value
		for raw in strings.split_iterator(&remaining, ",") {
			value := strings.trim_space(raw)
			start_value := value
			period_value := ""
			if slash := strings.index(value, "/"); slash >= 0 {
				start_value = value[:slash]
				period_value = value[slash+1:]
			}
			start, start_ok := ical_parse_date_time(start_value)
			if !start_ok {continue}
			rdate := Calendar_RDate{start = start}
			if len(period_value) > 0 {
				if period_end, end_ok := ical_parse_date_time(period_value); end_ok {
					rdate.duration_seconds =
						ical_date_time_stamp(period_end) -
						ical_date_time_stamp(start)
					rdate.has_duration = rdate.duration_seconds > 0
				} else if period_duration, duration_ok :=
					ical_parse_duration_seconds(period_value);
					duration_ok && period_duration > 0 {
					rdate.duration_seconds = period_duration
					rdate.has_duration = true
				}
				if !rdate.has_duration {continue}
			}
			duplicate := false
			for existing in result {
				if ical_date_time_compare(existing.start, start) == 0 {
					duplicate = true
					break
				}
			}
			if !duplicate {append(&result, rdate)}
		}
	}
	sort.merge_sort_proc(result[:], calendar_rdate_compare)
	return result
}

calendar_rdate_duration :: proc(
	values: []Calendar_RDate,
	start: ICal_Date_Time,
	default_duration: i64,
) -> i64 {
	for value in values {
		if ical_date_time_compare(value.start, start) == 0 {
			return value.duration_seconds if value.has_duration else default_duration
		}
	}
	return default_duration
}

calendar_date_list_contains :: proc(
	values: []ICal_Date_Time,
	target: ICal_Date_Time,
) -> bool {
	for value in values {
		if ical_date_time_compare(value, target) == 0 {return true}
	}
	return false
}

calendar_event_range_this_and_future :: proc(event: ^Calendar_Event) -> bool {
	if event == nil || len(event.recurrence_id) == 0 {return false}
	document, component, parsed := calendar_event_component(
		event,
		context.temp_allocator,
	)
	if !parsed {
		ical_document_destroy(&document, context.temp_allocator)
		return false
	}
	defer ical_document_destroy(&document, context.temp_allocator)
	property := ical_component_property(component, "RECURRENCE-ID")
	parameter := ical_property_parameter(property, "RANGE")
	return parameter != nil && len(parameter.values) > 0 &&
	       strings.equal_fold(parameter.values[0], "THISANDFUTURE")
}

calendar_future_override :: proc(
	events: []Calendar_Event,
	uid: string,
	recurrence: ICal_Date_Time,
) -> (^Calendar_Event, int, ICal_Date_Time, bool) {
	best: ^Calendar_Event
	best_index := -1
	best_recurrence: ICal_Date_Time
	for &candidate, candidate_index in events {
		if candidate.uid != uid || len(candidate.recurrence_id) == 0 ||
		   !calendar_event_range_this_and_future(&candidate) {
			continue
		}
		candidate_recurrence, parsed := ical_parse_date_time(candidate.recurrence_id)
		if !parsed || ical_date_time_compare(candidate_recurrence, recurrence) > 0 {
			continue
		}
		if best == nil ||
		   ical_date_time_compare(candidate_recurrence, best_recurrence) > 0 {
			best = &candidate
			best_index = candidate_index
			best_recurrence = candidate_recurrence
		}
	}
	return best, best_index, best_recurrence, best != nil
}

calendar_append_occurrence :: proc(
	result: ^[dynamic]Calendar_Occurrence,
	event: ^Calendar_Event,
	event_index: int,
	start, end: ICal_Date_Time,
	recurrence_id: string,
	allocator := context.allocator,
) {
	append(result, Calendar_Occurrence{
		event_index = event_index,
		uid = ical_clone(event.uid, allocator),
		recurrence_id = ical_clone(recurrence_id, allocator),
		summary = ical_clone(event.summary, allocator),
		location = ical_clone(event.location, allocator),
		categories = ical_clone(event.categories, allocator),
		important = event.important,
		start = start,
		end = end,
	})
}

calendar_occurrence_compare :: proc(a, b: Calendar_Occurrence) -> int {
	compared := ical_date_time_compare(a.start, b.start)
	if compared != 0 {return compared}
	if a.uid < b.uid {return -1}
	if a.uid > b.uid {return 1}
	return 0
}

calendar_expand_events :: proc(
	events: []Calendar_Event,
	range_start, range_end: ICal_Date_Time,
	limit := 10_000,
	allocator := context.allocator,
) -> ([dynamic]Calendar_Occurrence, bool) {
	result := make([dynamic]Calendar_Occurrence, allocator)
	for &event, event_index in events {
		if len(event.recurrence_id) > 0 ||
		   event.archived ||
		   strings.equal_fold(event.status, "CANCELLED") {
			continue
		}
		dtstart, start_ok := ical_parse_date_time(event.dtstart)
		if !start_ok {continue}
		dtend := dtstart
		if parsed_end, end_ok := ical_parse_date_time(event.dtend); end_ok {
			dtend = parsed_end
		}
		duration := ical_date_time_stamp(dtend) - ical_date_time_stamp(dtstart)
		document, component, parsed := calendar_event_component(&event, context.temp_allocator)
		if !parsed {
			ical_document_destroy(&document, context.temp_allocator)
			continue
		}
		rdates := calendar_property_rdates(component, context.temp_allocator)
		exdates := calendar_property_date_values(component, "EXDATE", context.temp_allocator)
		starts := make([dynamic]ICal_Date_Time, context.temp_allocator)
		if len(event.rrule) > 0 {
			rule, parse_error, rule_ok := ical_parse_recurrence(
				event.rrule,
				context.temp_allocator,
			)
			if rule_ok {
				expansion := ical_expand_recurrence(
					&rule,
					dtstart,
					range_start,
					range_end,
					limit,
					context.temp_allocator,
				)
				for value in expansion.occurrences {
					ical_append_unique_sorted(&starts, value)
				}
				ical_expansion_destroy(&expansion)
				ical_recurrence_destroy(&rule)
			} else {
				delete(parse_error)
			}
		} else if ical_date_time_compare(dtstart, range_start) >= 0 &&
		          ical_date_time_compare(dtstart, range_end) < 0 {
			append(&starts, dtstart)
		}
		for value in rdates {
			if ical_date_time_compare(value.start, range_start) >= 0 &&
			   ical_date_time_compare(value.start, range_end) < 0 {
				ical_append_unique_sorted(&starts, value.start)
			}
		}
		sort.merge_sort_proc(starts[:], ical_candidate_compare)
		for start in starts {
			if calendar_date_list_contains(exdates[:], start) {continue}
			occurrence_duration := calendar_rdate_duration(
				rdates[:],
				start,
				duration,
			)
			recurrence_id := ical_format_date_time(start, context.temp_allocator)
			override: ^Calendar_Event
			override_index := -1
			for &candidate, candidate_index in events {
				if candidate.uid == event.uid &&
				   candidate.recurrence_id == recurrence_id {
					override = &candidate
					override_index = candidate_index
					break
				}
			}
			if override != nil {
				if override.archived ||
				   strings.equal_fold(override.status, "CANCELLED") {
					delete(recurrence_id, context.temp_allocator)
					continue
				}
				override_start, override_ok := ical_parse_date_time(override.dtstart)
					if override_ok {
						override_end := ical_date_time_from_stamp(
							ical_date_time_stamp(override_start) +
							occurrence_duration,
						override_start.is_date,
					)
					if parsed_end, end_ok := ical_parse_date_time(override.dtend); end_ok {
						override_end = parsed_end
					}
					calendar_append_occurrence(
						&result,
						override,
						override_index,
						override_start,
						override_end,
						recurrence_id,
						allocator,
					)
				}
			} else {
				future, future_index, future_recurrence, has_future :=
					calendar_future_override(events, event.uid, start)
				if has_future {
					if future.archived ||
					   strings.equal_fold(future.status, "CANCELLED") {
						delete(recurrence_id, context.temp_allocator)
						continue
					}
					future_start, future_start_ok :=
						ical_parse_date_time(future.dtstart)
					if future_start_ok {
						adjusted_start := ical_date_time_from_stamp(
							ical_date_time_stamp(start) +
							ical_date_time_stamp(future_start) -
							ical_date_time_stamp(future_recurrence),
							start.is_date,
						)
						future_duration := occurrence_duration
						if future_end, future_end_ok :=
						   ical_parse_date_time(future.dtend);
						   future_end_ok {
							future_duration =
								ical_date_time_stamp(future_end) -
								ical_date_time_stamp(future_start)
						}
						end := ical_date_time_from_stamp(
							ical_date_time_stamp(adjusted_start) + future_duration,
							adjusted_start.is_date,
						)
						calendar_append_occurrence(
							&result,
							future,
							future_index,
							adjusted_start,
							end,
							recurrence_id,
							allocator,
						)
						delete(recurrence_id, context.temp_allocator)
						continue
					}
				}
				end := ical_date_time_from_stamp(
					ical_date_time_stamp(start) + occurrence_duration,
					start.is_date,
				)
				calendar_append_occurrence(
					&result,
					&event,
					event_index,
					start,
					end,
					recurrence_id,
					allocator,
				)
			}
			delete(recurrence_id, context.temp_allocator)
			if len(result) >= limit {
				sort.merge_sort_proc(result[:], calendar_occurrence_compare)
				delete(rdates)
				delete(exdates)
				delete(starts)
				ical_document_destroy(&document, context.temp_allocator)
				return result, true
			}
		}
		delete(rdates)
		delete(exdates)
		delete(starts)
		ical_document_destroy(&document, context.temp_allocator)
	}
	sort.merge_sort_proc(result[:], calendar_occurrence_compare)
	return result, false
}
