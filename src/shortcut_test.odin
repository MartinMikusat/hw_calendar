package main

import "core:testing"

@(test)
calendar_shortcut_normalizes_logical_characters_and_named_keys_test :: proc(
	t: ^testing.T,
) {
	value, valid := calendar_shortcut_from_event(
		5,
		"G",
		CALENDAR_SHORTCUT_MODIFIER_COMMAND |
		CALENDAR_SHORTCUT_MODIFIER_SHIFT,
	)
	defer calendar_shortcut_destroy(&value)
	testing.expect(t, valid)
	testing.expect_value(t, value.key, "g")
	testing.expect_value(
		t,
		value.modifiers,
		Calendar_Shortcut_Modifiers{.Command, .Shift},
	)
	testing.expect_value(t, calendar_shortcut_display(value), "⇧⌘G")

	named, named_valid := calendar_shortcut_from_event(97, "", 0)
	defer calendar_shortcut_destroy(&named)
	testing.expect(t, named_valid)
	testing.expect_value(t, named.kind, Calendar_Shortcut_Key_Kind.Named)
	testing.expect_value(t, named.key, "f6")
	testing.expect_value(t, calendar_shortcut_display(named), "F6")
}

@(test)
calendar_shortcut_rejects_modal_control_keys_test :: proc(t: ^testing.T) {
	codes := [6]uint{53, 36, 76, 48, 51, 117}
	for code in codes {
		value, valid := calendar_shortcut_from_event(code, "", 0)
		calendar_shortcut_destroy(&value)
		testing.expect(t, !valid)
	}
}

@(test)
calendar_shortcut_collision_reports_owning_action_test :: proc(t: ^testing.T) {
	owner, found := calendar_shortcut_collision(
		calendar_shortcut_character("k", {.Control}),
	)
	testing.expect(t, found)
	testing.expect_value(t, owner, "Command palette")
	owner, found = calendar_shortcut_collision(calendar_shortcut_character("1"))
	testing.expect(t, found)
	testing.expect_value(t, owner, "Numbered action 1")
	owner, found = calendar_shortcut_collision(
		calendar_shortcut_character(" ", {.Command}),
	)
	testing.expect(t, found)
	testing.expect_value(t, owner, "Spotlight")
	owner, found = calendar_shortcut_collision(
		calendar_shortcut_character("4", {.Shift, .Command}),
	)
	testing.expect(t, found)
	testing.expect_value(t, owner, "Screenshot selection")
	_, found = calendar_shortcut_collision(calendar_shortcut_character("4"))
	testing.expect(t, !found)
	_, found = calendar_shortcut_collision(
		calendar_shortcut_character("g", {.Command, .Shift}),
	)
	testing.expect(t, !found)
}

@(test)
calendar_shortcut_json_round_trip_and_version_validation_test :: proc(t: ^testing.T) {
	original := calendar_shortcut_character("g", {.Command, .Shift})
	encoded, encoded_ok := calendar_shortcut_serialize(original)
	defer delete(encoded)
	testing.expect(t, encoded_ok)
	decoded, decoded_ok := calendar_shortcut_deserialize(encoded)
	defer calendar_shortcut_destroy(&decoded)
	testing.expect(t, decoded_ok)
	testing.expect(t, calendar_shortcut_equal(original, decoded))

	invalid, invalid_ok := calendar_shortcut_deserialize(
		`{"version":2,"kind":"character","key":"/","modifiers":[]}`,
	)
	calendar_shortcut_destroy(&invalid)
	testing.expect(t, !invalid_ok)
}
