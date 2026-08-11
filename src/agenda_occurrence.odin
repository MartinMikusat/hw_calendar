package main

import "core:strconv"

Agenda_Occurrence :: struct {
	entry_index: int,
	start_stamp: i64,
	end_stamp: i64,
	all_day: bool,
}

agenda_occurrence_from_entry :: proc(
	entry: ^Agenda_Entry,
	entry_index: int,
) -> (Agenda_Occurrence, bool) {
	if entry == nil || entry.state != "active" {return {}, false}
	stamp_text := entry.start_at
	from_due := entry.recurrence_seconds > 0 || len(stamp_text) == 0
	if from_due {stamp_text = entry.due_at}
	start_stamp, valid := strconv.parse_i64(stamp_text)
	if !valid {return {}, false}
	if from_due {
		start_stamp = agenda_date_time_stamp(
			agenda_date_time_from_stamp(start_stamp, true),
		)
		return {
			entry_index = entry_index,
			start_stamp = start_stamp,
			end_stamp = start_stamp+86_400,
			all_day = true,
		}, true
	}
	end_stamp := start_stamp
	has_end := false
	if len(entry.end_at) > 0 {
		if parsed, ok := strconv.parse_i64(entry.end_at); ok {
			end_stamp = parsed
			has_end = true
		}
	}
	all_day := start_stamp % 86_400 == 0 &&
	           (!has_end || end_stamp > start_stamp && end_stamp % 86_400 == 0)
	if all_day && !has_end {end_stamp = start_stamp+86_400}
	return {
		entry_index = entry_index,
		start_stamp = start_stamp,
		end_stamp = end_stamp,
		all_day = all_day,
	}, true
}

agenda_occurrence_compare :: proc(a, b: Agenda_Occurrence) -> int {
	if a.start_stamp < b.start_stamp {return -1}
	if a.start_stamp > b.start_stamp {return 1}
	if a.entry_index < b.entry_index {return -1}
	if a.entry_index > b.entry_index {return 1}
	return 0
}
