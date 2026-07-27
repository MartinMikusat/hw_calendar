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
