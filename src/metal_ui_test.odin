package main

import "core:testing"
import flash "flash:."

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
calendar_theme_switch_uses_opposite_theme_label_test :: proc(t: ^testing.T) {
	testing.expect_value(t, calendar_theme_toggle_label(false), "DARK")
	testing.expect_value(t, calendar_theme_toggle_label(true), "LIGHT")
	testing.expect(t, calendar_theme_is_dark("dark"))
	testing.expect(t, !calendar_theme_is_dark("light"))
}

@(test)
calendar_theme_switch_precedes_header_actions_test :: proc(t: ^testing.T) {
	theme := calendar_ui_theme_rect_for_size(896, 760)
	today := Calendar_UI_Rect{626, 729, 76, 30}
	testing.expect_value(t, theme, Calendar_UI_Rect{554, 729, 64, 30})
	testing.expect_value(t, today, Calendar_UI_Rect{626, 729, 76, 30})
	testing.expect_value(t, today.x-(theme.x+theme.w), 8.0)
}

@(test)
calendar_navigation_selects_adjacent_event_and_holiday_test :: proc(
	t: ^testing.T,
) {
	day := ical_days_from_civil(2026, 7, 28)*86400
	items := []Calendar_Navigation_Item{
		{
			kind = .Event,
			event = {event_index = 4, start = ical_date_time_from_stamp(day)},
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

	next, found = calendar_navigation_find(items, .Next, day, &items[0])
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
