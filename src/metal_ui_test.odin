package main

import "core:testing"
import flash "flash:."

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
	testing.expect_value(t, calendar.h, 674.0)
}

@(test)
calendar_action_bar_uses_five_fixed_slots_test :: proc(t: ^testing.T) {
	first := calendar_ui_action_rect_for_width(0, 1280)
	second := calendar_ui_action_rect_for_width(1, 1280)
	third := calendar_ui_action_rect_for_width(2, 1280)
	fourth := calendar_ui_action_rect_for_width(3, 1280)
	fifth := calendar_ui_action_rect_for_width(4, 1280)
	sixth := calendar_ui_action_rect_for_width(5, 1280)
	testing.expect_value(t, first.x, CALENDAR_LAYOUT_MARGIN)
	testing.expect_value(t, first.y, CALENDAR_ACTION_BAR_BOTTOM)
	testing.expect_value(t, first.h, CALENDAR_ACTION_BAR_HEIGHT)
	testing.expect_value(t, second.x-(first.x+first.w), CALENDAR_ACTION_BAR_GAP)
	testing.expect_value(t, third.x-(second.x+second.w), CALENDAR_ACTION_BAR_GAP)
	testing.expect_value(t, fourth.x-(third.x+third.w), CALENDAR_ACTION_BAR_GAP)
	testing.expect_value(t, fifth.x-(fourth.x+fourth.w), CALENDAR_ACTION_BAR_GAP)
	testing.expect_value(t, sixth.x-(fifth.x+fifth.w), CALENDAR_ACTION_BAR_GAP)
	testing.expect_value(t, sixth.x+sixth.w, 1274.0)
}

@(test)
calendar_action_bar_maps_complete_code_test :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		calendar_main_action_for_code(1, 4),
		Calendar_UI_Action.Action_Complete,
	)
}

@(test)
calendar_day_list_stops_above_action_bar_test :: proc(t: ^testing.T) {
	count := calendar_ui_visible_day_count_for_height(
		CALENDAR_DEFAULT_WINDOW_HEIGHT,
	)
	testing.expect_value(t, count, 22)
	last_y := CALENDAR_DEFAULT_WINDOW_HEIGHT-CALENDAR_HEADER_HEIGHT-
	          CALENDAR_DAY_TOP_GAP-
	          CALENDAR_DAY_ROW_PITCH*f64(count-1)-CALENDAR_DAY_ROW_HEIGHT
	testing.expect(t, last_y >= CALENDAR_CONTENT_BOTTOM)
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
calendar_main_action_codes_use_event_section_test :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		calendar_main_action_for_code(1, 1),
		Calendar_UI_Action.Action_Edit,
	)
	testing.expect_value(
		t,
		calendar_main_action_for_code(1, 2),
		Calendar_UI_Action.Action_Open_URL,
	)
	testing.expect_value(
		t,
		calendar_main_action_for_code(1, 3),
		Calendar_UI_Action.Action_Archive,
	)
	testing.expect_value(
		t,
		calendar_main_action_for_code(2, 1),
		Calendar_UI_Action.None,
	)
}

@(test)
calendar_main_action_prefix_waits_expires_and_clears_test :: proc(
	t: ^testing.T,
) {
	old_prefix := calendar_ui.number_prefix
	old_deadline := calendar_ui.number_prefix_deadline_ms
	old_redraw := calendar_ui.needs_redraw
	defer {
		calendar_ui.number_prefix = old_prefix
		calendar_ui.number_prefix_deadline_ms = old_deadline
		calendar_ui.needs_redraw = old_redraw
	}
	calendar_clear_number_prefix()
	action, handled := calendar_consume_main_action_digit_at(1, 10_000)
	testing.expect(t, handled)
	testing.expect_value(t, action, Calendar_UI_Action.None)
	testing.expect_value(t, calendar_ui.number_prefix, 1)

	action, handled = calendar_consume_main_action_digit_at(2, 10_500)
	testing.expect(t, handled)
	testing.expect_value(t, action, Calendar_UI_Action.Action_Open_URL)
	testing.expect_value(t, calendar_ui.number_prefix, 0)

	action, handled = calendar_consume_main_action_digit_at(1, 20_000)
	testing.expect(t, handled)
	action, handled = calendar_consume_main_action_digit_at(3, 21_000)
	testing.expect(t, !handled)
	testing.expect_value(t, action, Calendar_UI_Action.None)
	testing.expect_value(t, calendar_ui.number_prefix, 0)

	action, handled = calendar_consume_main_action_digit_at(1, 30_000)
	testing.expect(t, handled)
	action, handled = calendar_consume_main_action_digit_at(9, 30_100)
	testing.expect(t, handled)
	testing.expect_value(t, action, Calendar_UI_Action.None)
	testing.expect_value(t, calendar_ui.number_prefix, 0)
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
