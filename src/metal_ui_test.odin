package main

import "core:testing"
import flash "flash:."

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
