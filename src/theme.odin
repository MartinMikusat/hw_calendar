package main

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
	switch id {
	case .HW_Dark:
		return {
			id = id,
			name = "HW Dark",
			storage_id = "hw-dark",
			dark = true,
			canvas = calendar_color(10, 11, 10),
			header = calendar_color(8, 9, 8),
			surface = calendar_color(14, 15, 14),
			raised = calendar_color(17, 18, 17),
			control = calendar_color(17, 18, 17),
			overlay = calendar_color(5, 6, 5),
			text = calendar_color(247, 242, 224),
			text_soft = calendar_color(173, 171, 158),
			muted = calendar_color(120, 125, 117),
			inverse = calendar_color(247, 242, 224),
			warm = calendar_color(178, 125, 87),
			warm_strong = calendar_color(127, 75, 48),
			cool = calendar_color(125, 135, 105),
			cool_strong = calendar_color(23, 49, 37),
			focus = calendar_color(125, 135, 105),
			personal = calendar_color(127, 75, 48),
			work = calendar_color(23, 49, 37),
			important = calendar_color(127, 75, 48),
			holiday = calendar_color(178, 125, 87),
			memorial = calendar_color(125, 135, 105),
			positive = calendar_color(66, 76, 33),
			destructive = calendar_color(127, 75, 48),
		}
	case .HW_Light:
	}
	return {
		id = .HW_Light,
		name = "HW Light",
		storage_id = "hw-light",
		canvas = calendar_color(204, 199, 184),
		header = calendar_color(232, 227, 209),
		surface = calendar_color(224, 219, 201),
		raised = calendar_color(217, 212, 194),
		control = calendar_color(212, 207, 189),
		overlay = calendar_color(174, 169, 155),
		text = calendar_color(38, 37, 40),
		text_soft = calendar_color(69, 66, 71),
		muted = calendar_color(122, 117, 107),
		inverse = calendar_color(247, 242, 224),
		warm = calendar_color(178, 125, 87),
		warm_strong = calendar_color(127, 75, 48),
		cool = calendar_color(125, 135, 105),
		cool_strong = calendar_color(23, 49, 37),
		focus = calendar_color(23, 49, 37),
		personal = calendar_color(127, 75, 48),
		work = calendar_color(23, 49, 37),
		important = calendar_color(178, 125, 87),
		holiday = calendar_color(178, 125, 87),
		memorial = calendar_color(125, 135, 105),
		positive = calendar_color(66, 76, 33),
		destructive = calendar_color(127, 75, 48),
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
