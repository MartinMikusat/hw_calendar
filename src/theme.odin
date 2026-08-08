package main

import hal_ui "ui_framework:hal_wayland"

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
	return {f32(r)/255, f32(g)/255, f32(b)/255, 1}
}

calendar_color64 :: proc(color: [4]f32) -> [4]f64 {
	return {f64(color[0]), f64(color[1]), f64(color[2]), f64(color[3])}
}

calendar_theme :: proc(id: Calendar_Theme_ID) -> Calendar_UI_Theme {
	shared_id := id == .HW_Dark ? hal_ui.Theme_ID.HW_Dark : hal_ui.Theme_ID.HW_Light
	shared := hal_ui.palette(shared_id)
	return {
		id = id,
		name = id == .HW_Dark ? "HW Dark" : "HW Light",
		storage_id = id == .HW_Dark ? "hw-dark" : "hw-light",
		dark = id == .HW_Dark,
		canvas = shared.canvas,
		header = shared.header,
		surface = shared.surface,
		raised = shared.raised,
		control = shared.field,
		modal = shared.modal,
		overlay = shared.backdrop,
		text = shared.text,
		text_soft = shared.text_soft,
		muted = shared.muted,
		inverse = calendar_color(247, 242, 224),
		warm = shared.primary,
		warm_strong = shared.destructive,
		cool = shared.alternate,
		cool_strong = shared.focus,
		focus = shared.focus,
		personal = calendar_color(127, 75, 48),
		work = calendar_color(23, 49, 37),
		important = calendar_color(178, 125, 87),
		holiday = calendar_color(178, 125, 87),
		memorial = calendar_color(125, 135, 105),
		positive = shared.positive,
		destructive = shared.destructive,
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
