package main

import "core:testing"
import command_palette "command_palette:."
import match_sorter "match_sorter:."

@(test)
calendar_settings_layout_contains_two_columns_at_minimum_size_test :: proc(
	t: ^testing.T,
) {
	modal := calendar_settings_rect_for_size(640, 480)
	testing.expect_value(t, modal, Calendar_UI_Rect{24, 36, 592, 408})
	testing.expect(t, modal.w > 168+32+240)
	testing.expect(t, modal.h > 300)
}

@(test)
calendar_settings_catalog_contains_every_theme_and_flash_test :: proc(t: ^testing.T) {
	descriptors := calendar_settings_descriptors()
	testing.expect_value(t, len(descriptors), 9)
	theme_count := 0
	flash_count := 0
	for descriptor in descriptors {
		if descriptor.action.kind == .Set_Theme {theme_count += 1}
		if descriptor.action.kind == .Configure_Flash {flash_count += 1}
	}
	testing.expect_value(t, theme_count, 8)
	testing.expect_value(t, flash_count, 1)
}

@(test)
calendar_settings_search_ranks_gruvbox_and_flash_test :: proc(t: ^testing.T) {
	state: command_palette.State
	testing.expect(t, command_palette.state_init(
		&state,
		search_reserve_size = 4*1024*1024,
		search_commit_size = 64*1024,
	) == nil)
	defer command_palette.state_destroy(&state)
	entries := calendar_settings_entries()
	testing.expect_value(
		t,
		command_palette.open(&state, entries[:], 0),
		match_sorter.Search_Error.None,
	)
	testing.expect_value(
		t,
		command_palette.set_query(&state, "Gruvbox"),
		match_sorter.Search_Error.None,
	)
	testing.expect_value(t, len(command_palette.visible_results(&state)), 2)
	testing.expect_value(
		t,
		command_palette.set_query(&state, "leader"),
		match_sorter.Search_Error.None,
	)
	results := command_palette.visible_results(&state)
	testing.expect_value(t, len(results), 1)
	testing.expect_value(t, results[0].entry.id, CALENDAR_SETTING_FLASH_ID)
}
