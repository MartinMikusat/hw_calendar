package main

import "core:math"
import "core:testing"
import "core:sync"
import flash "flash:."
import "core:strings"
import framework_ui "ui_framework:core"

calendar_ui_test_mutex: sync.Mutex

calendar_test_expect_approx :: proc(t: ^testing.T, actual, expected: f64) {
	testing.expect(t, math.abs(actual-expected) < 0.001)
}

@(test)
calendar_text_styles_bind_size_and_tracking_test :: proc(t: ^testing.T) {
	label := calendar_text_style_spec(.Label)
	body := calendar_text_style_spec(.Body)
	heading := calendar_text_style_spec(.Heading)
	testing.expect_value(t, label.size_scale, 0.7)
	testing.expect_value(t, label.tracking, 0.0)
	testing.expect_value(t, body.size_scale, 1.0)
	testing.expect_value(t, body.tracking, -0.45)
	testing.expect_value(t, heading.size_scale, 2.0)
	testing.expect(t, heading.tracking < body.tracking)
}

@(test)
calendar_event_rect_uses_available_day_width_test :: proc(t: ^testing.T) {
	day := Calendar_UI_Rect{0, 0, 900, CALENDAR_DAY_ROW_HEIGHT}
	single := calendar_ui_event_rect(day, 0, 1)
	first_of_two := calendar_ui_event_rect(day, 0, 2)
	second_of_two := calendar_ui_event_rect(day, 1, 2)
	first_of_three := calendar_ui_event_rect(day, 0, 3)
	testing.expect_value(t, single.x, 178.0)
	testing.expect_value(t, single.x+single.w, 888.0)
	testing.expect(t, single.w > first_of_two.w)
	testing.expect(t, first_of_two.w > first_of_three.w)
	testing.expect_value(
		t,
		second_of_two.x-(first_of_two.x+first_of_two.w),
		6.0,
	)
}

@(test)
calendar_editor_all_day_conversion_uses_exclusive_end_date_test :: proc(
	t: ^testing.T,
) {
	start, _ := ical_parse_date_time("20260730T090000")
	end, _ := ical_parse_date_time("20260730T100000")
	all_day_start, all_day_end := calendar_editor_toggle_all_day_dates(
		start,
		end,
		true,
	)
	testing.expect(t, all_day_start.is_date)
	testing.expect(t, all_day_end.is_date)
	testing.expect_value(t, all_day_start.day, 30)
	testing.expect_value(t, all_day_end.day, 31)

	timed_start, timed_end := calendar_editor_toggle_all_day_dates(
		all_day_start,
		all_day_end,
		false,
	)
	testing.expect(t, !timed_start.is_date)
	testing.expect(t, !timed_end.is_date)
	testing.expect_value(t, timed_start.day, 30)
	testing.expect_value(t, timed_start.hour, 9)
	testing.expect_value(t, timed_end.day, 30)
	testing.expect_value(t, timed_end.hour, 10)
}

CALENDAR_SLOVAK_HOLIDAY_TEST_DATA :: #load("../resources/holidays/sk.json")

@(test)
calendar_launch_activation_respects_background_policy_test :: proc(
	t: ^testing.T,
) {
	testing.expect(t, calendar_launch_should_activate(""))
	testing.expect(t, !calendar_launch_should_activate("", true))
	testing.expect(t, calendar_launch_should_activate("1", true))
	testing.expect(t, !calendar_launch_should_activate("0"))
	testing.expect(t, !calendar_launch_should_activate("0", true))
}

@(test)
calendar_launch_visibility_respects_explicit_policy_test :: proc(t: ^testing.T) {
	testing.expect(t, calendar_launch_should_show(""))
	testing.expect(t, calendar_launch_should_show("1"))
	testing.expect(t, !calendar_launch_should_show("0"))
}

@(test)
calendar_automation_uses_accessory_activation_policy_test :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		calendar_application_activation_policy(false),
		CALENDAR_APPLICATION_ACTIVATION_POLICY_REGULAR,
	)
	testing.expect_value(
		t,
		calendar_application_activation_policy(true),
		CALENDAR_APPLICATION_ACTIVATION_POLICY_ACCESSORY,
	)
}

@(test)
calendar_modal_backdrop_uses_eighty_percent_opacity_test :: proc(t: ^testing.T) {
	testing.expect_value(t, calendar_theme(.HW_Light).overlay[3], f32(0.80))
	testing.expect_value(t, calendar_theme(.HW_Dark).overlay[3], f32(0.80))
	testing.expect_value(t, calendar_theme(.HW_Light).modal[3], f32(1.0))
	testing.expect_value(t, calendar_theme(.HW_Dark).modal[3], f32(1.0))
}

@(test)
calendar_discard_confirmation_owns_modal_input_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous := calendar_ui
	defer {calendar_ui = previous}
	calendar_ui = Calendar_UI_State{
		width = 900,
		height = 700,
		settings_open = true,
		discard_changes_open = true,
	}
	modal := calendar_active_modal()
	testing.expect_value(t, modal.kind, Calendar_Modal_Kind.Discard_Changes)
	testing.expect_value(t, modal.dismissal, Calendar_Modal_Dismissal.Blocking)
}

@(test)
calendar_agenda_import_confirmation_owns_modal_input_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous := calendar_ui
	defer {calendar_ui = previous}
	calendar_ui = Calendar_UI_State{
		width = 900,
		height = 700,
		settings_open = true,
		archive_import_open = true,
	}
	modal := calendar_active_modal()
	testing.expect_value(t, modal.kind, Calendar_Modal_Kind.Agenda_Import)
	testing.expect_value(t, modal.dismissal, Calendar_Modal_Dismissal.Dismissible)
}

@(test)
calendar_chore_cancel_requests_dirty_confirmation_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous := calendar_ui
	defer {calendar_ui = previous}
	calendar_ui = {
		width = 900,
		height = 700,
		chore_open = true,
		chore_days = strings.clone("7"),
		chore_interval = CALENDAR_CHORE_DEFAULT_INTERVAL,
		chore_focus_slot = CALENDAR_CHORE_FOCUS_NAME,
	}
	defer delete(calendar_ui.chore_days)
	calendar_ui.chore_initial_hash = calendar_chore_fingerprint()
	delete(calendar_ui.chore_days)
	calendar_ui.chore_days = strings.clone("1")
	calendar_ui.chore_interval = CALENDAR_CHORE_PRESETS[0]
	calendar_ui_execute_action(Calendar_App_Action{kind = .Chore_Cancel})
	testing.expect(t, calendar_ui.chore_open)
	testing.expect(t, calendar_ui.discard_changes_open)
	testing.expect_value(t, calendar_ui.discard_target, Calendar_Modal_Kind.Chore)
}

@(test)
calendar_chore_geometry_stays_inside_modal_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous := calendar_ui
	defer {calendar_ui = previous}
	widths := [3]f64{640, 900, 1440}
	for width in widths {
		calendar_ui = {width = width, height = 760}
		modal := calendar_ui_chore_rect()
		name := calendar_chore_name_rect()
		days := calendar_chore_days_rect()
		first_interval := calendar_chore_interval_rect(0)
		last_interval := calendar_chore_interval_rect(
			len(CALENDAR_CHORE_PRESETS)-1,
		)
		error_rect := calendar_chore_error_rect()
		save := calendar_chore_button_rect(0)
		testing.expect(t, name.x >= modal.x+24)
		testing.expect(t, name.x+name.w <= modal.x+modal.w-24)
		testing.expect(t, days.x >= modal.x+24)
		testing.expect(t, days.x+days.w <= modal.x+modal.w-24)
		testing.expect(t, days.y+days.h < name.y)
		testing.expect(t, first_interval.y+first_interval.h < days.y)
		testing.expect(t, first_interval.x >= modal.x+24)
		testing.expect(t, last_interval.x+last_interval.w <= modal.x+modal.w-24)
		testing.expect(t, save.y+save.h < error_rect.y)
		testing.expect(t, error_rect.y+error_rect.h < first_interval.y)
	}
}

@(test)
calendar_chore_modal_blocks_sibling_modals_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous := calendar_ui
	defer {calendar_ui = previous}
	calendar_ui = {width = 900, height = 700, settings_open = true}
	calendar_ui_chore_open()
	testing.expect(t, !calendar_ui.chore_open)
	calendar_ui.settings_open = false
	calendar_ui.chore_open = true
	calendar_ui_editor_open()
	testing.expect(t, !calendar_ui.editor_open)
	testing.expect(t, !calendar_settings_open())
}

@(test)
calendar_chore_palette_contains_only_chore_actions_test :: proc(t: ^testing.T) {
	testing.expect(t, calendar_palette_action_allowed_over_chore(.Chore_Interval))
	testing.expect(t, calendar_palette_action_allowed_over_chore(.Chore_Days))
	testing.expect(t, calendar_palette_action_allowed_over_chore(.Chore_Save))
	testing.expect(t, calendar_palette_action_allowed_over_chore(.Chore_Cancel))
	testing.expect(t, !calendar_palette_action_allowed_over_chore(.New_Event))
	testing.expect(t, !calendar_palette_action_allowed_over_chore(.Open_Settings))
	testing.expect(t, !calendar_palette_action_allowed_over_chore(.Configure_Flash))
}

@(test)
calendar_next_chore_deadline_uses_earliest_future_due_test :: proc(t: ^testing.T) {
	entries := [4]Agenda_Entry{
		{state = "active", recurrence_seconds = 60, due_at = "90"},
		{state = "active", recurrence_seconds = 60, due_at = "140"},
		{state = "active", recurrence_seconds = 60, due_at = "120"},
		{state = "active", due_at = "110"},
	}
	testing.expect_value(t, calendar_next_chore_due_stamp(entries[:], 100), i64(120))
	testing.expect_value(t, calendar_next_chore_due_stamp(entries[:], 140), i64(0))
}

@(test)
calendar_due_section_is_top_pinned_and_bounded_test :: proc(t: ^testing.T) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous := calendar_ui
	defer {calendar_ui = previous}
	calendar_ui = {width = 640, height = 480}
	calendar_ui.due_entries = make([dynamic]Agenda_Entry, 30)
	defer delete(calendar_ui.due_entries)
	panel := calendar_ui_details_rect()
	section := calendar_ui_due_section_rect()
	testing.expect_value(t, section.y+section.h, panel.y+panel.h)
	testing.expect(t, section.h <= panel.h*2/3)
	start, end := calendar_ui_due_visible_range()
	testing.expect_value(t, start, 0)
	testing.expect(t, end < len(calendar_ui.due_entries))
	first := calendar_ui_due_row_rect(start)
	last := calendar_ui_due_row_rect(end-1)
	testing.expect(t, first.y+first.h <= section.y+section.h-CALENDAR_DUE_HEADER_HEIGHT)
	testing.expect(t, last.y >= section.y+CALENDAR_DUE_FOOTER_HEIGHT)
	done := calendar_ui_due_done_rect(start)
	focus := calendar_ui_due_focus_rect(start)
	testing.expect(t, done.x >= focus.x+focus.w)
	testing.expect(t, done.y >= first.y && done.y+done.h <= first.y+first.h)
	calendar_ui_scroll_due_rows(-24)
	start, _ = calendar_ui_due_visible_range()
	testing.expect(t, start > 0)
	for index in 0..<len(calendar_ui.due_entries) {
		calendar_ui.due_entries[index].id = i64(index+1)
	}
	calendar_ui.events = make([dynamic]Calendar_Event, 1)
	defer delete(calendar_ui.events)
	calendar_ui.events[0].row_id = calendar_ui.due_entries[20].id
	calendar_ui.due_first_row = 0
	calendar_ui_reveal_due_event(0)
	start, end = calendar_ui_due_visible_range()
	testing.expect(t, start > 0)
	testing.expect(t, 20 >= start && 20 < end)
}

@(test)
calendar_detail_dates_use_readable_display_format_test :: proc(t: ^testing.T) {
	date, date_ok := ical_parse_date_time("20260808")
	testing.expect(t, date_ok)
	if date_ok {
		formatted := calendar_format_display_date_time(date, context.temp_allocator)
		testing.expect_value(t, formatted, "Sat, 8 Aug 2026")
	}
	timed, timed_ok := ical_parse_date_time("20260808T094546")
	testing.expect(t, timed_ok)
	if timed_ok {
		formatted := calendar_format_display_date_time(timed, context.temp_allocator)
		testing.expect_value(t, formatted, "Sat, 8 Aug 2026 · 09:45")
	}
	utc, utc_ok := ical_parse_date_time("20260808T094546Z")
	testing.expect(t, utc_ok)
	if utc_ok {
		formatted := calendar_format_display_date_time(utc, context.temp_allocator)
		testing.expect_value(t, formatted, "Sat, 8 Aug 2026 · 09:45 UTC")
	}
	testing.expect_value(
		t,
		calendar_format_detail_date_time("invalid date"),
		"invalid date",
	)
}

@(test)
calendar_chore_interval_label_supports_custom_day_counts_test :: proc(t: ^testing.T) {
	testing.expect_value(t, calendar_chore_interval_label(259200), "3 days")
	testing.expect_value(t, calendar_chore_interval_label(345600), "4 days")
}

@(test)
calendar_chore_interval_parses_positive_whole_days_test :: proc(t: ^testing.T) {
	interval, valid := calendar_chore_interval_from_days(" 4 ")
	testing.expect(t, valid)
	testing.expect_value(t, interval, i64(345600))
	invalid_values := [6]string{"", "0", "-1", "1.5", "days", "106751991167301"}
	for invalid in invalid_values {
		_, item_valid := calendar_chore_interval_from_days(invalid)
		testing.expect(t, !item_valid)
	}
}

@(test)
calendar_day_items_group_chores_and_preserve_selected_chore_test :: proc(
	t: ^testing.T,
) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous := calendar_ui
	defer {calendar_ui = previous}
	calendar_ui = {
		events = make([dynamic]Calendar_Event),
		navigation_active = true,
		navigation_kind = .Event,
		navigation_event_index = 1,
		navigation_start_stamp = 172800,
	}
	defer calendar_events_destroy(&calendar_ui.events)
	append(&calendar_ui.events, Calendar_Event{recurrence_seconds = 86400})
	append(&calendar_ui.events, Calendar_Event{recurrence_seconds = 172800})
	append(&calendar_ui.events, Calendar_Event{})
	items := [3]Calendar_Day_Item{
		{kind = .Event, event = {event_index = 0, start = ical_date_time_from_stamp(86400, true)}},
		{kind = .Event, event = {event_index = 1, start = ical_date_time_from_stamp(172800, true)}},
		{kind = .Event, event = {event_index = 2, start = ical_date_time_from_stamp(259200, true)}},
	}
	grouped := calendar_group_day_chore_items(items[:])
	testing.expect_value(t, len(grouped), 2)
	if len(grouped) == 2 {
		testing.expect_value(t, grouped[0].kind, Calendar_Day_Item_Kind.Chores)
		testing.expect_value(t, grouped[0].chore_count, 2)
		testing.expect_value(t, grouped[0].event.event_index, 1)
		testing.expect(t, calendar_day_item_is_navigation_selected(grouped[0]))
		testing.expect_value(t, grouped[1].kind, Calendar_Day_Item_Kind.Event)
	}
}

calendar_icon_points_use_iconoir_viewbox_test :: proc(
	t: ^testing.T,
	points: []Calendar_Icon_Point,
	path_length: int,
) {
	for point, index in points {
		testing.expect(t, point.point.x >= 0 && point.point.x <= 24)
		testing.expect(t, point.point.y >= 0 && point.point.y <= 24)
		testing.expect_value(t, point.move, index%path_length == 0)
	}
}

@(test)
calendar_window_icons_match_iconoir_paths_test :: proc(t: ^testing.T) {
	xmark := calendar_icon_xmark_points()
	testing.expect_value(t, len(xmark), 8)
	calendar_icon_points_use_iconoir_viewbox_test(t, xmark[:], 2)

	minus := calendar_icon_minus_points()
	testing.expect_value(t, len(minus), 2)
	calendar_icon_points_use_iconoir_viewbox_test(t, minus[:], 2)

	maximize := calendar_icon_maximize_points()
	testing.expect_value(t, len(maximize), 12)
	calendar_icon_points_use_iconoir_viewbox_test(t, maximize[:], 3)
}

@(test)
calendar_window_controls_reach_top_edge_test :: proc(t: ^testing.T) {
	height := 720.0
	close := calendar_ui_window_control_rect_for_height(0, height)
	minimize := calendar_ui_window_control_rect_for_height(1, height)
	zoom := calendar_ui_window_control_rect_for_height(2, height)
	testing.expect_value(t, close, Calendar_UI_Rect{0, 690, 30, 30})
	testing.expect_value(t, minimize, Calendar_UI_Rect{38, 690, 30, 30})
	testing.expect_value(t, zoom, Calendar_UI_Rect{76, 690, 30, 30})
	testing.expect_value(t, close.y+close.h, height)
}

@(test)
calendar_settings_control_precedes_title_without_overlap_test :: proc(t: ^testing.T) {
	settings := calendar_ui_window_control_rect_for_height(3, 760)
	title := Calendar_UI_Rect{160, 729, 360, 30}
	testing.expect_value(t, settings, Calendar_UI_Rect{114, 730, 30, 30})
	testing.expect_value(t, title.x-(settings.x+settings.w), 16.0)
}

@(test)
calendar_details_layout_splits_default_content_width_test :: proc(t: ^testing.T) {
	calendar, details := calendar_ui_content_rects_for_size(
		CALENDAR_DEFAULT_WINDOW_WIDTH,
		CALENDAR_DEFAULT_WINDOW_HEIGHT,
	)
	testing.expect_value(t, calendar.x, CALENDAR_LAYOUT_MARGIN)
	testing.expect_value(t, calendar.w, 632.0)
	testing.expect_value(t, details.w, 632.0)
	testing.expect_value(
		t,
		details.x-(calendar.x+calendar.w),
		CALENDAR_PANEL_GAP,
	)
	testing.expect_value(t, details.x+details.w, 1274.0)
	testing.expect_value(
		t,
		calendar.h,
		CALENDAR_DEFAULT_WINDOW_HEIGHT-CALENDAR_HEADER_HEIGHT-
			calendar_ui_content_bottom_for_width(CALENDAR_DEFAULT_WINDOW_WIDTH)-
			CALENDAR_DAY_TOP_GAP,
	)
}

@(test)
calendar_action_bar_uses_one_row_with_section_gap_when_wide_test :: proc(t: ^testing.T) {
	_, layout := calendar_ui_action_bar_layout_for_width(1280)
	testing.expect(t, layout.fits)
	testing.expect_value(t, layout.row_count, 1)
	first := calendar_ui_action_rect_for_width(0, 1280)
	second := calendar_ui_action_rect_for_width(1, 1280)
	third := calendar_ui_action_rect_for_width(2, 1280)
	fourth := calendar_ui_action_rect_for_width(3, 1280)
	fifth := calendar_ui_action_rect_for_width(4, 1280)
	sixth := calendar_ui_action_rect_for_width(5, 1280)
	seventh := calendar_ui_action_rect_for_width(6, 1280)
	testing.expect_value(t, first.x, CALENDAR_LAYOUT_MARGIN)
	testing.expect_value(t, first.y, CALENDAR_ACTION_BAR_BOTTOM)
	testing.expect_value(t, first.h, CALENDAR_ACTION_BAR_HEIGHT)
	calendar_test_expect_approx(t, second.x-(first.x+first.w), CALENDAR_ACTION_BAR_GAP)
	calendar_test_expect_approx(t, third.x-(second.x+second.w), CALENDAR_ACTION_BAR_GAP)
	calendar_test_expect_approx(t, fourth.x-(third.x+third.w), CALENDAR_ACTION_BAR_GAP)
	calendar_test_expect_approx(t, fifth.x-(fourth.x+fourth.w), CALENDAR_ACTION_BAR_GAP)
	calendar_test_expect_approx(t, sixth.x-(fifth.x+fifth.w), CALENDAR_ACTION_BAR_GAP)
	calendar_test_expect_approx(
		t,
		seventh.x-(sixth.x+sixth.w),
		CALENDAR_ACTION_BAR_GAP*2,
	)
	testing.expect_value(t, seventh.x+seventh.w, 1274.0)
}

@(test)
calendar_action_bar_wraps_four_plus_three_when_narrow_test :: proc(t: ^testing.T) {
	rects, layout := calendar_ui_action_bar_layout_for_width(CALENDAR_WINDOW_MIN_WIDTH)
	testing.expect(t, layout.fits)
	testing.expect_value(t, layout.row_count, 2)
	testing.expect_value(t, layout.first_row_count, 4)
	for index in 0..<3 {
		testing.expect(t, rects[index].x+rects[index].w < rects[index+1].x)
	}
	testing.expect(t, rects[0].y > rects[4].y)
	testing.expect_value(
		t,
		calendar_ui_content_bottom_for_width(CALENDAR_WINDOW_MIN_WIDTH),
		CALENDAR_ACTION_BAR_BOTTOM+CALENDAR_ACTION_BAR_HEIGHT*2+
			CALENDAR_ACTION_BAR_ROW_GAP+CALENDAR_LAYOUT_MARGIN,
	)
}

@(test)
calendar_day_list_stops_above_action_bar_test :: proc(t: ^testing.T) {
	count := calendar_ui_visible_day_count_for_size(
		CALENDAR_DEFAULT_WINDOW_WIDTH,
		CALENDAR_DEFAULT_WINDOW_HEIGHT,
	)
	testing.expect_value(t, count, 22)
	last_y := CALENDAR_DEFAULT_WINDOW_HEIGHT-CALENDAR_HEADER_HEIGHT-
	          CALENDAR_DAY_TOP_GAP-
	          CALENDAR_DAY_ROW_PITCH*f64(count-1)-CALENDAR_DAY_ROW_HEIGHT
	testing.expect(t, last_y >= calendar_ui_content_bottom_for_width(CALENDAR_DEFAULT_WINDOW_WIDTH))
}

@(test)
calendar_day_list_centers_its_anchor_test :: proc(t: ^testing.T) {
	testing.expect_value(t, calendar_ui_first_visible_day(100, 1), i64(100))
	testing.expect_value(t, calendar_ui_first_visible_day(100, 5), i64(98))
	testing.expect_value(t, calendar_ui_first_visible_day(100, 22), i64(90))
	now := ical_days_from_civil(2026, 8, 8)*86400+12*3600
	target := ical_days_from_civil(2026, 8, 12)*86400
	testing.expect_value(t, calendar_ui_day_offset_for_stamp(target, now), 4)
}

@(test)
calendar_action_bar_enables_actions_for_focused_item_test :: proc(t: ^testing.T) {
	testing.expect(t, calendar_action_available(
		.Action_Edit, true, .Event, true, false,
	))
	testing.expect(t, calendar_action_available(
		.Action_Archive, true, .Event, true, false,
	))
	testing.expect(t, !calendar_action_available(
		.Action_Open_URL, true, .Event, true, false,
	))
	testing.expect(t, !calendar_action_available(
		.Action_Edit, true, .Holiday, false, true,
	))
	testing.expect(t, calendar_action_available(
		.Action_Open_URL, true, .Holiday, false, true,
	))
	testing.expect(t, !calendar_action_available(
		.Action_Archive, true, .Holiday, false, true,
	))
	testing.expect(t, !calendar_action_available(
		.Action_Edit, false, .Event, true, true,
	))
}

@(test)
calendar_number_keys_map_to_action_slots_test :: proc(t: ^testing.T) {
	expected_codes := [8]uint{18, 19, 20, 21, 23, 22, 26, 28}
	for key_code, expected_slot in expected_codes {
		slot, found := calendar_number_slot_for_key_code(key_code)
		testing.expect(t, found)
		testing.expect_value(t, slot, expected_slot)
		digit, digit_found := calendar_number_digit_for_key_code(key_code)
		testing.expect(t, digit_found)
		testing.expect_value(t, digit, expected_slot+1)
	}
	_, found := calendar_number_slot_for_key_code(29)
	testing.expect(t, !found)
}

@(test)
calendar_number_prefix_highlights_only_its_section_test :: proc(t: ^testing.T) {
	testing.expect(t, calendar_action_number_section_active(
		.Action_Edit, 1, 11_000, 10_000,
	))
	testing.expect(t, !calendar_action_number_section_active(
		.New_Chore, 1, 11_000, 10_000,
	))
	testing.expect(t, calendar_action_number_section_active(
		.New_Chore, 2, 11_000, 10_000,
	))
	testing.expect(t, !calendar_action_number_section_active(
		.New_Chore, 2, 10_000, 10_000,
	))
}

@(test)
calendar_chore_modal_actions_use_single_digit_codes_test :: proc(t: ^testing.T) {
	for index in 0..<len(CALENDAR_CHORE_PRESETS) {
		code := calendar_framework_number_code(Calendar_App_Action{
			kind = .Chore_Interval,
			index = index,
		})
		testing.expect_value(t, code.first, i8(index+1))
		testing.expect_value(t, code.digits, i8(1))
	}
	testing.expect_value(
		t,
		calendar_framework_number_code(
			Calendar_App_Action{kind = .Chore_Save},
		).first,
		i8(6),
	)
	testing.expect_value(
		t,
		calendar_framework_number_code(
			Calendar_App_Action{kind = .Chore_Cancel},
		).first,
		i8(7),
	)
}

@(test)
calendar_agenda_import_modal_numbers_actions_from_left_to_right_test :: proc(
	t: ^testing.T,
) {
	cancel := calendar_framework_number_code(
		Calendar_App_Action{kind = .Import_Agenda_Cancel},
	)
	replace := calendar_framework_number_code(
		Calendar_App_Action{kind = .Import_Agenda_Replace},
	)
	testing.expect_value(t, cancel.first, i8(1))
	testing.expect_value(t, cancel.digits, i8(1))
	testing.expect_value(t, replace.first, i8(2))
	testing.expect_value(t, replace.digits, i8(1))
}

@(test)
calendar_archive_modal_numbers_actions_from_left_to_right_test :: proc(
	t: ^testing.T,
) {
	testing.expect_value(
		t,
		calendar_archive_action_for_slot(false, 0),
		Calendar_UI_Action.Archive_Occurrence,
	)
	testing.expect_value(
		t,
		calendar_archive_action_for_slot(false, 1),
		Calendar_UI_Action.Archive_Cancel,
	)
	testing.expect_value(
		t,
		calendar_archive_action_for_slot(true, 0),
		Calendar_UI_Action.Archive_Occurrence,
	)
	testing.expect_value(
		t,
		calendar_archive_action_for_slot(true, 1),
		Calendar_UI_Action.Archive_Series,
	)
	testing.expect_value(
		t,
		calendar_archive_action_for_slot(true, 2),
		Calendar_UI_Action.Archive_Cancel,
	)
	testing.expect_value(
		t,
		calendar_archive_action_for_slot(true, 3),
		Calendar_UI_Action.None,
	)
}

@(test)
calendar_navigation_selects_adjacent_event_and_holiday_test :: proc(
	t: ^testing.T,
) {
	day := ical_days_from_civil(2026, 7, 28)*86400
	items := []Calendar_Navigation_Item{
		{
			kind = .Event,
			event = {
				event_index = 4,
				uid = "imported-event",
				start = ical_date_time_from_stamp(day, true),
			},
		},
		{
			kind = .Holiday,
			holiday = {
				country_index = 0,
				definition_index = 1,
				date = ical_date_time_from_stamp(day, true),
			},
		},
		{
			kind = .Event,
			event = {
				event_index = 5,
				start = ical_date_time_from_stamp(day+9*3600),
			},
		},
	}
	next, found := calendar_navigation_find(items, .Next, day)
	testing.expect(t, found)
	testing.expect_value(t, next.kind, Calendar_Navigation_Item_Kind.Event)
	testing.expect_value(t, next.event.event_index, 4)

	reconstructed_selection := Calendar_Navigation_Item{
		kind = .Event,
		event = {
			event_index = 4,
			start = ical_date_time_from_stamp(day, true),
		},
	}
	next, found = calendar_navigation_find(
		items,
		.Next,
		day,
		&reconstructed_selection,
	)
	testing.expect(t, found)
	testing.expect_value(t, next.kind, Calendar_Navigation_Item_Kind.Holiday)

	previous, previous_found := calendar_navigation_find(
		items,
		.Previous,
		day,
		&items[2],
	)
	testing.expect(t, previous_found)
	testing.expect_value(
		t,
		previous.kind,
		Calendar_Navigation_Item_Kind.Holiday,
	)

	_, found = calendar_navigation_find(items, .Previous, day)
	testing.expect(t, !found)
}

@(test)
calendar_navigation_includes_dated_agenda_entries_test :: proc(t: ^testing.T) {
	day := ical_days_from_civil(2026, 8, 8)*86400
	events := []Calendar_Event{{
		row_id = 1,
		uid = "agenda-1",
		dtstart = "20260808",
		dtend = "20260808",
	}}
	items := calendar_navigation_items(
		events,
		nil,
		ical_date_time_from_stamp(day-86400, true),
		ical_date_time_from_stamp(day+86400, true),
		context.temp_allocator,
	)
	testing.expect_value(t, len(items), 1)
	if len(items) == 1 {
		testing.expect_value(t, items[0].kind, Calendar_Navigation_Item_Kind.Event)
		testing.expect_value(t, items[0].event.event_index, 0)
	}
}

@(test)
calendar_navigation_jumps_once_per_occupied_day_test :: proc(t: ^testing.T) {
	day_1 := i64(ical_days_from_civil(2026, 8, 8))*86400
	day_2 := day_1+86400
	day_3 := day_2+86400
	items := [4]Calendar_Navigation_Item{
		{kind = .Event, event = {start = ical_date_time_from_stamp(day_1+3600, true)}},
		{kind = .Event, event = {start = ical_date_time_from_stamp(day_1+7200, true)}},
		{kind = .Holiday, holiday = {date = ical_date_time_from_stamp(day_2, true)}},
		{kind = .Event, event = {start = ical_date_time_from_stamp(day_3+3600, true)}},
	}
	next_day, next_found := calendar_navigation_find_day(items[:], .Next, day_1)
	testing.expect(t, next_found)
	testing.expect_value(t, next_day, day_2)
	previous_day, previous_found := calendar_navigation_find_day(
		items[:],
		.Previous,
		day_3,
	)
	testing.expect(t, previous_found)
	testing.expect_value(t, previous_day, day_2)
}

@(test)
calendar_slovak_holiday_data_matches_current_legal_categories_test :: proc(
	t: ^testing.T,
) {
	country, decoded := calendar_holiday_decode(
		transmute([]u8)CALENDAR_SLOVAK_HOLIDAY_TEST_DATA,
	)
	testing.expect(t, decoded)
	if !decoded {return}
	defer calendar_holiday_country_destroy(&country)
	testing.expect_value(t, country.country_code, "SK")
	testing.expect_value(t, country.country_name, "Slovensko")
	testing.expect_value(t, country.effective_from_year, 2026)
	testing.expect_value(t, len(country.entries), 39)
	counts: [Calendar_Holiday_Kind]int
	for entry in country.entries {counts[calendar_holiday_kind(entry.kind)] += 1}
	testing.expect_value(t, counts[.State_Holiday], 6)
	testing.expect_value(t, counts[.Public_Holiday], 10)
	testing.expect_value(t, counts[.Memorial_Day], 23)
}

@(test)
calendar_slovak_movable_holidays_follow_gregorian_easter_test :: proc(
	t: ^testing.T,
) {
	easter := calendar_gregorian_easter(2026)
	testing.expect_value(t, easter, ICal_Date_Time{
		year = 2026,
		month = 4,
		day = 5,
		is_date = true,
	})
	good_friday := Calendar_Holiday_Definition{
		rule = "easter_offset",
		easter_offset_days = -2,
	}
	date, valid := calendar_holiday_definition_date(&good_friday, 2026)
	testing.expect(t, valid)
	testing.expect_value(t, date, ICal_Date_Time{
		year = 2026,
		month = 4,
		day = 3,
		is_date = true,
	})
	easter_monday := good_friday
	easter_monday.easter_offset_days = 1
	date, valid = calendar_holiday_definition_date(&easter_monday, 2026)
	testing.expect(t, valid)
	testing.expect_value(t, date, ICal_Date_Time{
		year = 2026,
		month = 4,
		day = 6,
		is_date = true,
	})
}

@(test)
calendar_slovak_holidays_start_in_2026_test :: proc(t: ^testing.T) {
	country, decoded := calendar_holiday_decode(
		transmute([]u8)CALENDAR_SLOVAK_HOLIDAY_TEST_DATA,
	)
	testing.expect(t, decoded)
	if !decoded {return}
	defer calendar_holiday_country_destroy(&country)
	country.enabled = true
	before := calendar_holiday_occurrences_expand(
		[]Calendar_Holiday_Country{country},
		{year = 2025, month = 1, day = 1, is_date = true},
		{year = 2026, month = 1, day = 1, is_date = true},
	)
	defer delete(before)
	testing.expect_value(t, len(before), 0)
	first_week := calendar_holiday_occurrences_expand(
		[]Calendar_Holiday_Country{country},
		{year = 2026, month = 1, day = 1, is_date = true},
		{year = 2026, month = 1, day = 7, is_date = true},
	)
	defer delete(first_week)
	testing.expect_value(t, len(first_week), 2)
}

@(test)
calendar_header_double_click_toggles_window_zoom_test :: proc(t: ^testing.T) {
	testing.expect(t, !calendar_header_click_should_zoom(1))
	testing.expect(t, calendar_header_click_should_zoom(2))
	testing.expect(t, calendar_header_click_should_zoom(3))
}

@(test)
calendar_window_zoom_geometry_fills_and_restores_test :: proc(t: ^testing.T) {
	current := Rect{Point{200, 140}, Size{1200, 800}}
	visible := Rect{Point{0, 31}, Size{1920, 1049}}
	next, restore, has_restore := calendar_window_zoom_next_frame(
		current,
		visible,
		{},
		false,
	)
	testing.expect_value(t, next, visible)
	testing.expect_value(t, restore, current)
	testing.expect(t, has_restore)

	next, restore, has_restore = calendar_window_zoom_next_frame(
		next,
		visible,
		restore,
		has_restore,
	)
	testing.expect_value(t, next, current)
	testing.expect_value(t, restore, Rect{})
	testing.expect(t, !has_restore)
}

@(test)
calendar_flash_badges_use_vocal_training_geometry_test :: proc(t: ^testing.T) {
	target_rect := flash.Rect{10, 20, 100, 30}
	left := calendar_flash_badge_rect(
		flash.Target{label = "play", rect = target_rect, anchor = .Top_Left},
		2,
		200,
		100,
	)
	right := calendar_flash_badge_rect(
		flash.Target{label = "play", rect = target_rect, anchor = .Top_Right},
		2,
		200,
		100,
	)
	testing.expect(t, left.x < right.x)
	testing.expect_value(t, left.y, right.y)
	testing.expect_value(t, left.w, 24.0)
	testing.expect_value(t, left.h, 18.0)
}

@(test)
calendar_flash_badges_clamp_to_view_test :: proc(t: ^testing.T) {
	badge := calendar_flash_badge_rect(
		flash.Target{
			label = "play",
			rect = {-20, -10, 8, 8},
			anchor = .Bottom_Left,
		},
		1,
		100,
		100,
	)
	testing.expect_value(t, badge.x, 0.0)
	testing.expect_value(t, badge.y, 0.0)
	testing.expect_value(t, badge.w, 16.0)
}

@(test)
calendar_shared_registry_preserves_control_identity_and_capabilities_test :: proc(
	t: ^testing.T,
) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous_ui := calendar_ui
	calendar_ui = {width = 800, height = 600}
	framework_ui.context_init(&calendar_ui.control_context)
	calendar_ui.control_bindings = make([dynamic]Calendar_Action_Binding)
	frame := framework_ui.begin_frame(
		&calendar_ui.control_context,
		{viewport = {0, 0, 800, 600}},
	)
	calendar_control_frame = &frame
	defer {
		calendar_control_frame = nil
		framework_ui.frame_destroy(&frame)
		framework_ui.context_destroy(&calendar_ui.control_context)
		delete(calendar_ui.control_bindings)
		calendar_shared_view = {}
		calendar_ui = previous_ui
	}
	calendar_ui_add_control(
		"today",
		"today",
		{10, 10, 80, 30},
		.Today,
	)
	calendar_control_frame_finish(&frame)
	testing.expect_value(t, len(calendar_shared_view.actions), 1)
	testing.expect_value(t, len(calendar_shared_view.controls), 1)
	control := calendar_shared_view.controls[0]
	testing.expect_value(t, control.id, framework_ui.Key(calendar_control_id("today")))
	testing.expect(t, .Primary_Press in control.capabilities)
	testing.expect(t, .Accessibility in control.capabilities)
	testing.expect(t, .Flash in control.capabilities)
	testing.expect(t, .CLI in control.capabilities)
}

@(test)
calendar_shared_numbered_dispatch_activates_new_chore_test :: proc(
	t: ^testing.T,
) {
	sync.mutex_lock(&calendar_ui_test_mutex)
	defer sync.mutex_unlock(&calendar_ui_test_mutex)
	previous_ui := calendar_ui
	calendar_ui = {width = 800, height = 600}
	framework_ui.context_init(&calendar_ui.control_context)
	calendar_ui.control_bindings = make([dynamic]Calendar_Action_Binding)
	frame := framework_ui.begin_frame(
		&calendar_ui.control_context,
		{viewport = {0, 0, 800, 600}},
	)
	calendar_control_frame = &frame
	defer {
		calendar_control_frame = nil
		framework_ui.frame_destroy(&frame)
		framework_ui.context_destroy(&calendar_ui.control_context)
		delete(calendar_ui.control_bindings)
		calendar_shared_view = {}
		calendar_ui = previous_ui
	}
	calendar_ui_add_control(
		"new chore",
		"new chore",
		{10, 10, 80, 30},
		.New_Chore,
	)
	calendar_control_frame_finish(&frame)
	control_id, activated, handled := calendar_consume_shared_numbered_digit(
		2,
		10_000,
	)
	testing.expect(t, handled)
	testing.expect(t, !activated)
	testing.expect_value(t, calendar_ui.number_prefix, 2)
	control_id, activated, handled = calendar_consume_shared_numbered_digit(
		1,
		10_500,
	)
	testing.expect(t, handled)
	testing.expect(t, activated)
	testing.expect_value(t, control_id, calendar_control_id("new chore"))
	testing.expect_value(t, calendar_ui.number_prefix, 0)
}
