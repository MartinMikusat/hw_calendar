package main

import "core:strings"
import "core:testing"

@(test)
ical_parse_preserves_complete_component_tree_test :: proc(t: ^testing.T) {
	input :=
		"BEGIN:VCALENDAR\r\n" +
		"PRODID:-//HW Calendar//EN\r\n" +
		"VERSION:2.0\r\n" +
		"BEGIN:VTIMEZONE\r\n" +
		"TZID:Europe/Bratislava\r\n" +
		"BEGIN:STANDARD\r\n" +
		"DTSTART:20261025T030000\r\n" +
		"TZOFFSETFROM:+0200\r\n" +
		"TZOFFSETTO:+0100\r\n" +
		"END:STANDARD\r\n" +
		"END:VTIMEZONE\r\n" +
		"BEGIN:VEVENT\r\n" +
		"UID:event-1\r\n" +
		"DTSTAMP:20260727T120000Z\r\n" +
		"DTSTART;TZID=Europe/Bratislava:20260728T090000\r\n" +
		"SUMMARY:Review\r\n" +
		"X-VENDOR-PROP;X-PARAM=\"a,b\":opaque\r\n" +
		"BEGIN:VALARM\r\n" +
		"ACTION:DISPLAY\r\n" +
		"TRIGGER:-PT15M\r\n" +
		"DESCRIPTION:Review\r\n" +
		"END:VALARM\r\n" +
		"END:VEVENT\r\n" +
		"END:VCALENDAR\r\n"
	document := ical_parse(input)
	defer ical_document_destroy(&document)
	testing.expect_value(t, len(document.components), 1)
	calendar := &document.components[0]
	testing.expect_value(t, calendar.name, "VCALENDAR")
	testing.expect_value(t, len(calendar.children), 2)
	event := &calendar.children[1]
	testing.expect_value(t, event.name, "VEVENT")
	testing.expect_value(t, len(event.children), 1)
	extension := ical_component_property(event, "X-VENDOR-PROP")
	testing.expect(t, extension != nil)
	testing.expect_value(t, extension.value, "opaque")
	testing.expect_value(t, extension.parameters[0].values[0], "a,b")
	testing.expect_value(t, len(document.diagnostics), 0)
	output := ical_serialize(&document)
	defer delete(output)
	testing.expect_value(t, output, input)
}

@(test)
ical_unfolds_input_and_folds_edited_output_by_octet_test :: proc(t: ^testing.T) {
	input :=
		"BEGIN:VCALENDAR\r\n" +
		"PRODID:-//HW Calendar//EN\r\n" +
		"VERSION:2.0\r\n" +
		"BEGIN:VEVENT\r\n" +
		"UID:event-1\r\n" +
		"DTSTAMP:20260727T120000Z\r\n" +
		"SUMMARY:This is a folded\r\n" +
		" value\r\n" +
		"END:VEVENT\r\n" +
		"END:VCALENDAR\r\n"
	document := ical_parse(input)
	defer ical_document_destroy(&document)
	event := &document.components[0].children[0]
	summary := ical_component_property(event, "SUMMARY")
	testing.expect_value(t, summary.value, "This is a foldedvalue")
	delete(summary.value)
	summary.value = ical_clone(
		"This summary is deliberately long enough to cross the seventy-five octet content line boundary without splitting a UTF-8 code unit.",
	)
	summary.dirty = true
	output := ical_serialize(&document)
	defer delete(output)
	lines := strings.split_lines(output)
	defer delete(lines)
	for line in lines {
		testing.expect(t, len(line) <= 75)
	}
	testing.expect(t, strings.contains(output, "\r\n "))
}

@(test)
ical_reports_invalid_alarm_pair_without_dropping_component_test :: proc(t: ^testing.T) {
	input :=
		"BEGIN:VCALENDAR\r\n" +
		"PRODID:-//HW Calendar//EN\r\n" +
		"VERSION:2.0\r\n" +
		"BEGIN:VEVENT\r\n" +
		"UID:event-1\r\n" +
		"DTSTAMP:20260727T120000Z\r\n" +
		"BEGIN:VALARM\r\n" +
		"ACTION:DISPLAY\r\n" +
		"TRIGGER:-PT15M\r\n" +
		"REPEAT:2\r\n" +
		"END:VALARM\r\n" +
		"END:VEVENT\r\n" +
		"END:VCALENDAR\r\n"
	document := ical_parse(input)
	defer ical_document_destroy(&document)
	found := false
	for diagnostic in document.diagnostics {
		if diagnostic.code == "alarm_repeat_pair" {found = true}
	}
	testing.expect(t, found)
	testing.expect_value(t, len(document.components[0].children[0].children), 1)
}

@(test)
ical_text_escape_round_trip_test :: proc(t: ^testing.T) {
	original := "one, two; three\\four\nfive"
	escaped := ical_escape_text(original)
	defer delete(escaped)
	decoded := ical_unescape_text(escaped)
	defer delete(decoded)
	testing.expect_value(t, decoded, original)
}

@(test)
ical_edit_preserves_unknown_properties_and_attachments_test :: proc(
	t: ^testing.T,
) {
	input :=
		"BEGIN:VCALENDAR\r\n" +
		"PRODID:-//HW Calendar//EN\r\n" +
		"VERSION:2.0\r\n" +
		"BEGIN:VEVENT\r\n" +
		"UID:event-1\r\n" +
		"DTSTAMP:20260727T120000Z\r\n" +
		"DTSTART:20260728T090000\r\n" +
		"SUMMARY:Before\r\n" +
		"ATTACH;FMTTYPE=application/pdf:https://example.test/a.pdf\r\n" +
		"X-HW-OPAQUE;X-KEY=\"a,b\":payload\r\n" +
		"END:VEVENT\r\n" +
		"END:VCALENDAR\r\n"
	document := ical_parse(input)
	defer ical_document_destroy(&document)
	event := &document.components[0].children[0]
	ical_component_set_property(event, "SUMMARY", "After")
	output := ical_serialize(&document)
	defer delete(output)
	testing.expect(t, strings.contains(output, "SUMMARY:After\r\n"))
	testing.expect(
		t,
		strings.contains(
			output,
			"ATTACH;FMTTYPE=application/pdf:https://example.test/a.pdf\r\n",
		),
	)
	testing.expect(
		t,
		strings.contains(output, "X-HW-OPAQUE;X-KEY=\"a,b\":payload\r\n"),
	)
}

recurrence_test_expand :: proc(
	t: ^testing.T,
	rule_text, start_text, range_start_text, range_end_text: string,
) -> ICal_Expansion {
	rule, error, parsed := ical_parse_recurrence(rule_text)
	testing.expect(t, parsed, error)
	if !parsed {return {}}
	defer ical_recurrence_destroy(&rule)
	start, start_ok := ical_parse_date_time(start_text)
	range_start, range_start_ok := ical_parse_date_time(range_start_text)
	range_end, range_end_ok := ical_parse_date_time(range_end_text)
	testing.expect(t, start_ok && range_start_ok && range_end_ok)
	return ical_expand_recurrence(&rule, start, range_start, range_end)
}

@(test)
recurrence_supports_every_frequency_test :: proc(t: ^testing.T) {
	cases := [7]struct {
		rule: string,
		end: string,
		expected: [3]string,
	}{
		{
			"FREQ=SECONDLY;INTERVAL=30;COUNT=3",
			"20260727T090200",
			{"20260727T090000", "20260727T090030", "20260727T090100"},
		},
		{
			"FREQ=MINUTELY;INTERVAL=15;COUNT=3",
			"20260727T100000",
			{"20260727T090000", "20260727T091500", "20260727T093000"},
		},
		{
			"FREQ=HOURLY;INTERVAL=2;COUNT=3",
			"20260728T000000",
			{"20260727T090000", "20260727T110000", "20260727T130000"},
		},
		{
			"FREQ=DAILY;INTERVAL=2;COUNT=3",
			"20260810T000000",
			{"20260727T090000", "20260729T090000", "20260731T090000"},
		},
		{
			"FREQ=WEEKLY;INTERVAL=2;COUNT=3",
			"20260901T000000",
			{"20260727T090000", "20260810T090000", "20260824T090000"},
		},
		{
			"FREQ=MONTHLY;COUNT=3",
			"20261101T000000",
			{"20260727T090000", "20260827T090000", "20260927T090000"},
		},
		{
			"FREQ=YEARLY;COUNT=3",
			"20290101T000000",
			{"20260727T090000", "20270727T090000", "20280727T090000"},
		},
	}
	for test_case in cases {
		expansion := recurrence_test_expand(
			t,
			test_case.rule,
			"20260727T090000",
			"20260701T000000",
			test_case.end,
		)
		testing.expect_value(t, len(expansion.occurrences), 3)
		for expected, index in test_case.expected {
			if index >= len(expansion.occurrences) {break}
			actual := ical_format_date_time(expansion.occurrences[index])
			testing.expect_value(t, actual, expected)
			delete(actual)
		}
		ical_expansion_destroy(&expansion)
	}
}

@(test)
recurrence_applies_complete_by_rule_surface_test :: proc(t: ^testing.T) {
	expansion := recurrence_test_expand(
		t,
		"FREQ=YEARLY;BYMONTH=1,2;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=30;BYSECOND=15;BYSETPOS=-1;COUNT=3",
		"20260130T093015",
		"20260101T000000",
		"20300101T000000",
	)
	defer ical_expansion_destroy(&expansion)
	testing.expect_value(t, len(expansion.occurrences), 3)
	expected := [3]string{
		"20260227T093015",
		"20270226T093015",
		"20280229T093015",
	}
	for value, index in expansion.occurrences {
		actual := ical_format_date_time(value)
		testing.expect_value(t, actual, expected[index])
		delete(actual)
	}
}

@(test)
recurrence_applies_negative_month_year_and_week_selectors_test :: proc(t: ^testing.T) {
	monthly := recurrence_test_expand(
		t,
		"FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3",
		"20260131T090000",
		"20260101T000000",
		"20260501T000000",
	)
	testing.expect_value(t, len(monthly.occurrences), 3)
	testing.expect_value(t, monthly.occurrences[1].day, 28)
	ical_expansion_destroy(&monthly)

	yearly := recurrence_test_expand(
		t,
		"FREQ=YEARLY;BYYEARDAY=-1;COUNT=3",
		"20261231T090000",
		"20260101T000000",
		"20300101T000000",
	)
	testing.expect_value(t, len(yearly.occurrences), 3)
	for value in yearly.occurrences {
		testing.expect_value(t, value.month, 12)
		testing.expect_value(t, value.day, 31)
	}
	ical_expansion_destroy(&yearly)

	week := recurrence_test_expand(
		t,
		"FREQ=YEARLY;BYWEEKNO=1;BYDAY=MO;COUNT=3;WKST=MO",
		"20270104T090000",
		"20270101T000000",
		"20310101T000000",
	)
	testing.expect_value(t, len(week.occurrences), 3)
	for value in week.occurrences {
		testing.expect_value(t, ical_weekday(value), ICal_Weekday.Monday)
	}
	ical_expansion_destroy(&week)
}

@(test)
recurrence_rejects_invalid_rfc_combinations_test :: proc(t: ^testing.T) {
	invalid := [6]string{
		"FREQ=DAILY;COUNT=2;UNTIL=20270101T000000Z",
		"FREQ=WEEKLY;BYMONTHDAY=1",
		"FREQ=MONTHLY;BYWEEKNO=1",
		"FREQ=DAILY;BYSETPOS=1",
		"FREQ=DAILY;BYDAY=1MO",
		"FREQ=YEARLY;BYWEEKNO=1;BYDAY=1MO",
	}
	for value in invalid {
		rule, error, ok := ical_parse_recurrence(value)
		testing.expect(t, !ok)
		testing.expect(t, len(error) > 0)
		delete(error)
		ical_recurrence_destroy(&rule)
	}
}

@(test)
recurrence_applies_this_and_future_override_test :: proc(t: ^testing.T) {
	events := []Calendar_Event{
		{
			uid = "series",
			summary = "Original",
			dtstart = "20260727T090000",
			dtend = "20260727T100000",
			rrule = "FREQ=DAILY;COUNT=3",
			raw_component =
				"BEGIN:VEVENT\r\n" +
				"UID:series\r\n" +
				"DTSTAMP:20260727T000000Z\r\n" +
				"DTSTART:20260727T090000\r\n" +
				"DTEND:20260727T100000\r\n" +
				"RRULE:FREQ=DAILY;COUNT=3\r\n" +
				"END:VEVENT\r\n",
		},
		{
			uid = "series",
			recurrence_id = "20260728T090000",
			summary = "Moved",
			dtstart = "20260728T110000",
			dtend = "20260728T123000",
			raw_component =
				"BEGIN:VEVENT\r\n" +
				"UID:series\r\n" +
				"DTSTAMP:20260727T000000Z\r\n" +
				"RECURRENCE-ID;RANGE=THISANDFUTURE:20260728T090000\r\n" +
				"DTSTART:20260728T110000\r\n" +
				"DTEND:20260728T123000\r\n" +
				"SUMMARY:Moved\r\n" +
				"END:VEVENT\r\n",
		},
	}
	range_start, _ := ical_parse_date_time("20260727T000000")
	range_end, _ := ical_parse_date_time("20260731T000000")
	occurrences, truncated := calendar_expand_events(
		events,
		range_start,
		range_end,
	)
	defer calendar_occurrences_destroy(&occurrences)
	testing.expect(t, !truncated)
	testing.expect_value(t, len(occurrences), 3)
	testing.expect_value(t, occurrences[0].start.hour, 9)
	testing.expect_value(t, occurrences[1].start.hour, 11)
	testing.expect_value(t, occurrences[2].start.hour, 11)
	testing.expect_value(t, occurrences[2].summary, "Moved")
	testing.expect_value(
		t,
		ical_date_time_stamp(occurrences[2].end) -
		ical_date_time_stamp(occurrences[2].start),
		i64(90*60),
	)
}

@(test)
rdate_period_preserves_occurrence_duration_test :: proc(t: ^testing.T) {
	events := []Calendar_Event{
		{
			uid = "period-series",
			summary = "Period",
			dtstart = "20260727T090000",
			dtend = "20260727T100000",
			raw_component =
				"BEGIN:VEVENT\r\n" +
				"UID:period-series\r\n" +
				"DTSTAMP:20260727T000000Z\r\n" +
				"DTSTART:20260727T090000\r\n" +
				"DTEND:20260727T100000\r\n" +
				"RDATE;VALUE=PERIOD:20260730T090000/20260730T113000," +
				"20260731T090000/PT45M\r\n" +
				"END:VEVENT\r\n",
		},
	}
	range_start, _ := ical_parse_date_time("20260727T000000")
	range_end, _ := ical_parse_date_time("20260801T000000")
	occurrences, truncated := calendar_expand_events(
		events,
		range_start,
		range_end,
	)
	defer calendar_occurrences_destroy(&occurrences)
	testing.expect(t, !truncated)
	testing.expect_value(t, len(occurrences), 3)
	testing.expect_value(
		t,
		ical_date_time_stamp(occurrences[0].end) -
		ical_date_time_stamp(occurrences[0].start),
		i64(60*60),
	)
	testing.expect_value(
		t,
		ical_date_time_stamp(occurrences[1].end) -
		ical_date_time_stamp(occurrences[1].start),
		i64(150*60),
	)
	testing.expect_value(
		t,
		ical_date_time_stamp(occurrences[2].end) -
		ical_date_time_stamp(occurrences[2].start),
		i64(45*60),
	)
}

@(test)
display_alarm_without_repeat_schedules_initial_delivery_test :: proc(t: ^testing.T) {
	event := Calendar_Event{
		uid = "event",
		summary = "Review",
		dtstart = "20260728T090000",
		raw_component =
			"BEGIN:VEVENT\r\n" +
			"UID:event\r\n" +
			"DTSTAMP:20260727T000000Z\r\n" +
			"DTSTART:20260728T090000\r\n" +
			"SUMMARY:Review\r\n" +
			"BEGIN:VALARM\r\n" +
			"ACTION:DISPLAY\r\n" +
			"TRIGGER:-PT15M\r\n" +
			"DESCRIPTION:Review\r\n" +
			"END:VALARM\r\n" +
			"END:VEVENT\r\n",
	}
	occurrence := Calendar_Occurrence{
		event_index = 0,
		uid = "event",
		recurrence_id = "20260728T090000",
		summary = "Review",
		start = ICal_Date_Time{
			year = 2026,
			month = 7,
			day = 28,
			hour = 9,
		},
		end = ICal_Date_Time{
			year = 2026,
			month = 7,
			day = 28,
			hour = 10,
		},
	}
	candidates := calendar_notification_collect(
		[]Calendar_Event{event},
		[]Calendar_Occurrence{occurrence},
		ical_date_time_stamp(occurrence.start)-3600,
	)
	defer calendar_notification_candidates_destroy(&candidates)
	testing.expect_value(t, len(candidates), 1)
	testing.expect_value(
		t,
		candidates[0].fire_stamp,
		ical_date_time_stamp(occurrence.start)-15*60,
	)
}
