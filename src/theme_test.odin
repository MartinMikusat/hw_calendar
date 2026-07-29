package main

import "core:testing"

@(test)
calendar_theme_registry_has_stable_unique_identifiers_test :: proc(t: ^testing.T) {
	seen := make(map[string]bool, context.temp_allocator)
	for id in calendar_theme_ids() {
		theme := calendar_theme(id)
		testing.expect(t, len(theme.name) > 0)
		testing.expect(t, len(theme.storage_id) > 0)
		testing.expect(t, !seen[theme.storage_id])
		seen[theme.storage_id] = true
		testing.expect_value(t, theme.id, id)
		testing.expect_value(t, theme.canvas[3], f32(1))
		testing.expect_value(t, theme.text[3], f32(1))
	}
	testing.expect_value(t, len(seen), 2)
}

@(test)
calendar_theme_storage_migrates_legacy_values_test :: proc(t: ^testing.T) {
	id, found := calendar_theme_from_storage("light")
	testing.expect(t, found)
	testing.expect_value(t, id, Calendar_Theme_ID.HW_Light)
	id, found = calendar_theme_from_storage("dark")
	testing.expect(t, found)
	testing.expect_value(t, id, Calendar_Theme_ID.HW_Dark)
	light_values := []string{"gruvbox-light", "catppuccin-latte"}
	for value in light_values {
		id, found = calendar_theme_from_storage(value)
		testing.expect(t, found)
		testing.expect_value(t, id, Calendar_Theme_ID.HW_Light)
	}
	dark_values := []string{
		"gruvbox-dark",
		"catppuccin-frappe",
		"catppuccin-macchiato",
		"catppuccin-mocha",
	}
	for value in dark_values {
		id, found = calendar_theme_from_storage(value)
		testing.expect(t, found)
		testing.expect_value(t, id, Calendar_Theme_ID.HW_Dark)
	}
	id, found = calendar_theme_from_storage("unknown")
	testing.expect(t, !found)
	testing.expect_value(t, id, Calendar_Theme_ID.HW_Light)
}

@(test)
calendar_theme_commands_use_direct_action_titles_test :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		calendar_theme_command_title(.HW_Dark),
		"Switch theme to dark mode",
	)
	testing.expect_value(
		t,
		calendar_theme_command_title(.HW_Light),
		"Switch theme to light mode",
	)
}
