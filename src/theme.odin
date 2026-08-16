package main

import "core:fmt"

CALENDAR_BODY_SIZE :: 10.5
CALENDAR_LINE_HEIGHT :: 1.2
CALENDAR_TRACKING :: -0.45
CALENDAR_CELL_WIDTH :: 7.0
CALENDAR_CELL_HEIGHT :: CALENDAR_BODY_SIZE * CALENDAR_LINE_HEIGHT
CALENDAR_CHROME_HEIGHT :: CALENDAR_CELL_HEIGHT
CALENDAR_HAIRLINE_MIX :: 0.75
CALENDAR_TICK_WIDTH :: 2.0
CALENDAR_BANNER_ACCENT :: 3.0
CALENDAR_DIM_ALPHA :: 0.45
CALENDAR_CHROME_BUTTON_CHARS :: 3
CALENDAR_PAPER :: [4]f32{250.0 / 255.0, 250.0 / 255.0, 249.0 / 255.0, 1}
CALENDAR_INK :: [4]f32{16.0 / 255.0, 16.0 / 255.0, 16.0 / 255.0, 1}
CALENDAR_LIGHT_DESTRUCTIVE :: [4]f32{168.0 / 255.0, 32.0 / 255.0, 28.0 / 255.0, 1}
CALENDAR_DARK_DESTRUCTIVE :: [4]f32{208.0 / 255.0, 64.0 / 255.0, 56.0 / 255.0, 1}

Calendar_Theme_ID :: enum {
	HW_Light,
	HW_Dark,
}

Calendar_UI_Theme :: struct {
	id: Calendar_Theme_ID,
	name: string,
	storage_id: string,
	dark: bool,
	canvas: [4]f32,
	header: [4]f32,
	surface: [4]f32,
	raised: [4]f32,
	control: [4]f32,
	modal: [4]f32,
	overlay: [4]f32,
	text: [4]f32,
	text_soft: [4]f32,
	muted: [4]f32,
	inverse: [4]f32,
	hairline: [4]f32,
	warm: [4]f32,
	warm_strong: [4]f32,
	cool: [4]f32,
	cool_strong: [4]f32,
	focus: [4]f32,
	personal: [4]f32,
	work: [4]f32,
	important: [4]f32,
	holiday: [4]f32,
	memorial: [4]f32,
	positive: [4]f32,
	destructive: [4]f32,
}

calendar_color :: proc(r, g, b: u8) -> [4]f32 {
	return {f32(r) / 255, f32(g) / 255, f32(b) / 255, 1}
}

calendar_blend :: proc(base, accent: [4]f32, amount: f32) -> [4]f32 {
	t := clamp(amount, 0, 1)
	return {
		base[0] + (accent[0] - base[0]) * t,
		base[1] + (accent[1] - base[1]) * t,
		base[2] + (accent[2] - base[2]) * t,
		base[3] + (accent[3] - base[3]) * t,
	}
}

calendar_hairline :: proc(paper, ink: [4]f32) -> [4]f32 {
	return calendar_blend(paper, ink, CALENDAR_HAIRLINE_MIX)
}

calendar_bracket :: proc(label: string) -> string {
	return fmt.tprintf("[%s]", label)
}

calendar_field_label :: proc(sample: string, focused: bool) -> string {
	caret := "_"
	if focused {caret = "█"}
	return fmt.tprintf("> %s%s", sample, caret)
}

calendar_toggle_mark :: proc(checked: bool) -> string {
	return "[x]" if checked else "[ ]"
}

calendar_chrome_button_width :: proc() -> f64 {
	return CALENDAR_CELL_WIDTH * CALENDAR_CHROME_BUTTON_CHARS
}

calendar_color64 :: proc(color: [4]f32) -> [4]f64 {
	return {f64(color[0]), f64(color[1]), f64(color[2]), f64(color[3])}
}

calendar_theme :: proc(id: Calendar_Theme_ID) -> Calendar_UI_Theme {
	paper := CALENDAR_PAPER
	ink := CALENDAR_INK
	destructive := CALENDAR_LIGHT_DESTRUCTIVE
	if id == .HW_Dark {
		paper = CALENDAR_INK
		ink = CALENDAR_PAPER
		destructive = CALENDAR_DARK_DESTRUCTIVE
	}
	muted := calendar_blend(ink, paper, 0.50)
	return {
		id = id,
		name = id == .HW_Dark ? "Dark" : "Light",
		storage_id = id == .HW_Dark ? "hw-dark" : "hw-light",
		dark = id == .HW_Dark,
		canvas = paper,
		header = paper,
		surface = paper,
		raised = paper,
		control = paper,
		modal = paper,
		overlay = {0, 0, 0, CALENDAR_DIM_ALPHA},
		text = ink,
		text_soft = calendar_blend(ink, paper, 0.30),
		muted = muted,
		inverse = paper,
		hairline = calendar_hairline(paper, ink),
		warm = ink,
		warm_strong = destructive,
		cool = ink,
		cool_strong = ink,
		focus = ink,
		personal = ink,
		work = ink,
		important = ink,
		holiday = muted,
		memorial = muted,
		positive = ink,
		destructive = destructive,
	}
}

calendar_theme_ids :: proc() -> [2]Calendar_Theme_ID {
	return {
		.HW_Light,
		.HW_Dark,
	}
}

calendar_theme_from_storage :: proc(value: string) -> (Calendar_Theme_ID, bool) {
	switch value {
	case "light", "gruvbox-light", "catppuccin-latte":
		return .HW_Light, true
	case "dark", "gruvbox-dark", "catppuccin-frappe",
	     "catppuccin-macchiato", "catppuccin-mocha":
		return .HW_Dark, true
	}
	for id in calendar_theme_ids() {
		if calendar_theme(id).storage_id == value {return id, true}
	}
	return .HW_Light, false
}

calendar_theme_command_title :: proc(id: Calendar_Theme_ID) -> string {
	switch id {
	case .HW_Light: return "Switch theme to light mode"
	case .HW_Dark: return "Switch theme to dark mode"
	}
	return "Switch theme"
}
