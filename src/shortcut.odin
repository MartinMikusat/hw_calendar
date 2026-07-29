package main

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

Calendar_Shortcut_Modifier :: enum {
	Control,
	Option,
	Shift,
	Command,
}

Calendar_Shortcut_Modifiers :: bit_set[Calendar_Shortcut_Modifier]

Calendar_Shortcut_Key_Kind :: enum {
	Character,
	Named,
}

Calendar_Shortcut :: struct {
	kind: Calendar_Shortcut_Key_Kind,
	key: string,
	modifiers: Calendar_Shortcut_Modifiers,
}

Calendar_Shortcut_Wire :: struct {
	version: int,
	kind: string,
	key: string,
	modifiers: []string,
}

CALENDAR_SHORTCUT_MODIFIER_SHIFT :: uint(1 << 17)
CALENDAR_SHORTCUT_MODIFIER_CONTROL :: uint(1 << 18)
CALENDAR_SHORTCUT_MODIFIER_OPTION :: uint(1 << 19)
CALENDAR_SHORTCUT_MODIFIER_COMMAND :: uint(1 << 20)

calendar_shortcut_default :: proc() -> Calendar_Shortcut {
	return {kind = .Character, key = "/"}
}

calendar_shortcut_clone :: proc(
	value: Calendar_Shortcut,
	allocator := context.allocator,
) -> Calendar_Shortcut {
	return {
		kind = value.kind,
		key = strings.clone(value.key, allocator),
		modifiers = value.modifiers,
	}
}

calendar_shortcut_destroy :: proc(value: ^Calendar_Shortcut) {
	if value == nil {return}
	delete(value.key)
	value^ = {}
}

calendar_shortcut_equal :: proc(a, b: Calendar_Shortcut) -> bool {
	return a.kind == b.kind && a.key == b.key && a.modifiers == b.modifiers
}

calendar_shortcut_modifiers_from_event :: proc(
	flags: uint,
) -> Calendar_Shortcut_Modifiers {
	result: Calendar_Shortcut_Modifiers
	if flags & CALENDAR_SHORTCUT_MODIFIER_CONTROL != 0 {
		result += {.Control}
	}
	if flags & CALENDAR_SHORTCUT_MODIFIER_OPTION != 0 {
		result += {.Option}
	}
	if flags & CALENDAR_SHORTCUT_MODIFIER_SHIFT != 0 {
		result += {.Shift}
	}
	if flags & CALENDAR_SHORTCUT_MODIFIER_COMMAND != 0 {
		result += {.Command}
	}
	return result
}

calendar_shortcut_named_key :: proc(key_code: uint) -> (string, bool) {
	switch key_code {
	case 123: return "left", true
	case 124: return "right", true
	case 125: return "down", true
	case 126: return "up", true
	case 115: return "home", true
	case 119: return "end", true
	case 116: return "page-up", true
	case 121: return "page-down", true
	case 122: return "f1", true
	case 120: return "f2", true
	case 99: return "f3", true
	case 118: return "f4", true
	case 96: return "f5", true
	case 97: return "f6", true
	case 98: return "f7", true
	case 100: return "f8", true
	case 101: return "f9", true
	case 109: return "f10", true
	case 103: return "f11", true
	case 111: return "f12", true
	case 105: return "f13", true
	case 107: return "f14", true
	case 113: return "f15", true
	case 106: return "f16", true
	case 64: return "f17", true
	case 79: return "f18", true
	case 80: return "f19", true
	case 90: return "f20", true
	}
	return "", false
}

calendar_shortcut_control_key :: proc(key_code: uint) -> bool {
	return key_code == 53 || key_code == 36 || key_code == 76 ||
	       key_code == 48 || key_code == 51 || key_code == 117
}

calendar_shortcut_from_event :: proc(
	key_code: uint,
	text: string,
	flags: uint,
	allocator := context.allocator,
) -> (Calendar_Shortcut, bool) {
	if calendar_shortcut_control_key(key_code) {return {}, false}
	modifiers := calendar_shortcut_modifiers_from_event(flags)
	if named, found := calendar_shortcut_named_key(key_code); found {
		return {
			kind = .Named,
			key = strings.clone(named, allocator),
			modifiers = modifiers,
		}, true
	}
	if len(text) == 0 {return {}, false}
	key := text
	if len(key) == 1 && key[0] >= 'A' && key[0] <= 'Z' {
		lower := [1]u8{key[0]+'a'-'A'}
		return {
			kind = .Character,
			key = strings.clone(string(lower[:]), allocator),
			modifiers = modifiers,
		}, true
	}
	rune_value, _ := utf8.decode_rune(key)
	if utf8.rune_count(key) != 1 || rune_value < 0x20 {return {}, false}
	return {
		kind = .Character,
		key = strings.clone(key, allocator),
		modifiers = modifiers,
	}, true
}

calendar_shortcut_matches_event :: proc(
	shortcut: Calendar_Shortcut,
	key_code: uint,
	text: string,
	flags: uint,
) -> bool {
	candidate, valid := calendar_shortcut_from_event(
		key_code,
		text,
		flags,
		context.temp_allocator,
	)
	if !valid {return false}
	return calendar_shortcut_equal(shortcut, candidate)
}

calendar_shortcut_display_key :: proc(
	value: Calendar_Shortcut,
	allocator := context.temp_allocator,
) -> string {
	if value.kind == .Character {
		if value.key == " " {return "SPACE"}
		return strings.to_upper(value.key, allocator)
	}
	switch value.key {
	case "left": return "←"
	case "right": return "→"
	case "down": return "↓"
	case "up": return "↑"
	case "home": return "HOME"
	case "end": return "END"
	case "page-up": return "PAGE UP"
	case "page-down": return "PAGE DOWN"
	case:
		return strings.to_upper(value.key, allocator)
	}
}

calendar_shortcut_display :: proc(
	value: Calendar_Shortcut,
	allocator := context.temp_allocator,
) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	if .Control in value.modifiers {strings.write_string(&builder, "⌃")}
	if .Option in value.modifiers {strings.write_string(&builder, "⌥")}
	if .Shift in value.modifiers {strings.write_string(&builder, "⇧")}
	if .Command in value.modifiers {strings.write_string(&builder, "⌘")}
	strings.write_string(&builder, calendar_shortcut_display_key(value))
	return strings.to_string(builder)
}

calendar_shortcut_character :: proc(
	key: string,
	modifiers: Calendar_Shortcut_Modifiers = {},
) -> Calendar_Shortcut {
	return {kind = .Character, key = key, modifiers = modifiers}
}

calendar_shortcut_named :: proc(
	key: string,
	modifiers: Calendar_Shortcut_Modifiers = {},
) -> Calendar_Shortcut {
	return {kind = .Named, key = key, modifiers = modifiers}
}

calendar_shortcut_collision :: proc(
	value: Calendar_Shortcut,
) -> (string, bool) {
	collisions := []struct {
		shortcut: Calendar_Shortcut,
		owner: string,
	}{
		{calendar_shortcut_character("k", {.Control}), "Command palette"},
		{calendar_shortcut_named("up"), "Previous day"},
		{calendar_shortcut_named("down"), "Next day"},
		{calendar_shortcut_named("up", {.Command}), "Previous calendar item"},
		{calendar_shortcut_named("down", {.Command}), "Next calendar item"},
		{calendar_shortcut_character("q", {.Command}), "Quit application"},
		{calendar_shortcut_character("w", {.Command}), "Close window"},
		{calendar_shortcut_character("m", {.Command}), "Minimize window"},
		{calendar_shortcut_character("h", {.Command}), "Hide application"},
		{calendar_shortcut_character("h", {.Option, .Command}), "Hide other applications"},
		{calendar_shortcut_character(",", {.Command}), "Open Settings"},
		{calendar_shortcut_character(" ", {.Command}), "Spotlight"},
		{calendar_shortcut_character(" ", {.Option, .Command}), "Finder search"},
		{calendar_shortcut_character("3", {.Shift, .Command}), "Screenshot"},
		{calendar_shortcut_character("4", {.Shift, .Command}), "Screenshot selection"},
		{calendar_shortcut_character("5", {.Shift, .Command}), "Screenshot controls"},
		{calendar_shortcut_character("q", {.Shift, .Command}), "Log out"},
		{calendar_shortcut_character("q", {.Control, .Command}), "Lock screen"},
		{calendar_shortcut_character("d", {.Option, .Command}), "Show or hide the Dock"},
		{calendar_shortcut_named("up", {.Control}), "Mission Control"},
		{calendar_shortcut_named("down", {.Control}), "Application windows"},
		{calendar_shortcut_named("left", {.Control}), "Previous desktop"},
		{calendar_shortcut_named("right", {.Control}), "Next desktop"},
	}
	for index in 0..<3 {
		key := [1]u8{u8('1'+index)}
		candidate := calendar_shortcut_character(string(key[:]))
		if calendar_shortcut_equal(value, candidate) {
			return fmt.aprintf(
				"Numbered action %s",
				string(key[:]),
				allocator = context.temp_allocator,
			), true
		}
	}
	for collision in collisions {
		if calendar_shortcut_equal(value, collision.shortcut) {
			return collision.owner, true
		}
	}
	return "", false
}

calendar_shortcut_serialize :: proc(
	value: Calendar_Shortcut,
	allocator := context.allocator,
) -> (string, bool) {
	modifiers := make([dynamic]string, context.temp_allocator)
	if .Control in value.modifiers {append(&modifiers, "control")}
	if .Option in value.modifiers {append(&modifiers, "option")}
	if .Shift in value.modifiers {append(&modifiers, "shift")}
	if .Command in value.modifiers {append(&modifiers, "command")}
	kind := "character"
	if value.kind == .Named {kind = "named"}
	bytes, marshal_error := json.marshal(
		Calendar_Shortcut_Wire{
			version = 1,
			kind = kind,
			key = value.key,
			modifiers = modifiers[:],
		},
		allocator = allocator,
	)
	if marshal_error != nil {return "", false}
	return string(bytes), true
}

calendar_shortcut_deserialize :: proc(
	value: string,
	allocator := context.allocator,
) -> (Calendar_Shortcut, bool) {
	wire: Calendar_Shortcut_Wire
	if error := json.unmarshal(transmute([]u8)value, &wire); error != nil {
		return {}, false
	}
	defer delete(wire.kind)
	defer delete(wire.key)
	defer {
		for modifier in wire.modifiers {delete(modifier)}
		delete(wire.modifiers)
	}
	if wire.version != 1 || len(wire.key) == 0 {return {}, false}
	kind: Calendar_Shortcut_Key_Kind
	switch wire.kind {
	case "character": kind = .Character
	case "named":
		kind = .Named
		valid := false
		for code := uint(0); code <= 126; code += 1 {
			if named, found := calendar_shortcut_named_key(code);
			   found && named == wire.key {
				valid = true
				break
			}
		}
		if !valid {return {}, false}
	case:
		return {}, false
	}
	modifiers: Calendar_Shortcut_Modifiers
	for modifier in wire.modifiers {
		switch modifier {
		case "control": modifiers += {.Control}
		case "option": modifiers += {.Option}
		case "shift": modifiers += {.Shift}
		case "command": modifiers += {.Command}
		case: return {}, false
		}
	}
	return {
		kind = kind,
		key = strings.clone(wire.key, allocator),
		modifiers = modifiers,
	}, true
}
