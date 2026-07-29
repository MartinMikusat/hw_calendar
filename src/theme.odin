package main

Calendar_Theme_ID :: enum {
	HW_Light,
	HW_Dark,
	Gruvbox_Light,
	Gruvbox_Dark,
	Catppuccin_Latte,
	Catppuccin_Frappe,
	Catppuccin_Macchiato,
	Catppuccin_Mocha,
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
	case .Gruvbox_Light:
		return {
			id = id,
			name = "Gruvbox Light",
			storage_id = "gruvbox-light",
			canvas = calendar_color(251, 241, 199),
			header = calendar_color(242, 229, 188),
			surface = calendar_color(235, 219, 178),
			raised = calendar_color(213, 196, 161),
			control = calendar_color(213, 196, 161),
			overlay = calendar_color(189, 174, 147),
			text = calendar_color(60, 56, 54),
			text_soft = calendar_color(80, 73, 69),
			muted = calendar_color(124, 111, 100),
			inverse = calendar_color(251, 241, 199),
			warm = calendar_color(175, 58, 3),
			warm_strong = calendar_color(157, 0, 6),
			cool = calendar_color(121, 116, 14),
			cool_strong = calendar_color(66, 123, 88),
			focus = calendar_color(7, 102, 120),
			personal = calendar_color(175, 58, 3),
			work = calendar_color(121, 116, 14),
			important = calendar_color(214, 93, 14),
			holiday = calendar_color(181, 118, 20),
			memorial = calendar_color(66, 123, 88),
			positive = calendar_color(121, 116, 14),
			destructive = calendar_color(157, 0, 6),
		}
	case .Gruvbox_Dark:
		return {
			id = id,
			name = "Gruvbox Dark",
			storage_id = "gruvbox-dark",
			dark = true,
			canvas = calendar_color(40, 40, 40),
			header = calendar_color(29, 32, 33),
			surface = calendar_color(60, 56, 54),
			raised = calendar_color(80, 73, 69),
			control = calendar_color(80, 73, 69),
			overlay = calendar_color(29, 32, 33),
			text = calendar_color(235, 219, 178),
			text_soft = calendar_color(213, 196, 161),
			muted = calendar_color(146, 131, 116),
			inverse = calendar_color(40, 40, 40),
			warm = calendar_color(214, 93, 14),
			warm_strong = calendar_color(204, 36, 29),
			cool = calendar_color(152, 151, 26),
			cool_strong = calendar_color(104, 157, 106),
			focus = calendar_color(69, 133, 136),
			personal = calendar_color(214, 93, 14),
			work = calendar_color(104, 157, 106),
			important = calendar_color(175, 58, 3),
			holiday = calendar_color(215, 153, 33),
			memorial = calendar_color(104, 157, 106),
			positive = calendar_color(152, 151, 26),
			destructive = calendar_color(204, 36, 29),
		}
	case .Catppuccin_Latte:
		return calendar_catppuccin_theme(
			id,
			"Catppuccin Latte",
			"catppuccin-latte",
			false,
			calendar_color(239, 241, 245),
			calendar_color(230, 233, 239),
			calendar_color(220, 224, 232),
			calendar_color(204, 208, 218),
			calendar_color(188, 192, 204),
			calendar_color(76, 79, 105),
			calendar_color(92, 95, 119),
			calendar_color(108, 111, 133),
			calendar_color(210, 15, 57),
			calendar_color(254, 100, 11),
			calendar_color(64, 160, 43),
			calendar_color(23, 146, 153),
			calendar_color(30, 102, 245),
			calendar_color(136, 57, 239),
			calendar_color(223, 142, 29),
		)
	case .Catppuccin_Frappe:
		return calendar_catppuccin_theme(
			id,
			"Catppuccin Frappé",
			"catppuccin-frappe",
			true,
			calendar_color(48, 52, 70),
			calendar_color(41, 44, 60),
			calendar_color(35, 38, 52),
			calendar_color(65, 69, 89),
			calendar_color(81, 87, 109),
			calendar_color(198, 208, 245),
			calendar_color(181, 191, 226),
			calendar_color(165, 173, 206),
			calendar_color(231, 130, 132),
			calendar_color(239, 159, 118),
			calendar_color(166, 209, 137),
			calendar_color(129, 200, 190),
			calendar_color(140, 170, 238),
			calendar_color(202, 158, 230),
			calendar_color(229, 200, 144),
		)
	case .Catppuccin_Macchiato:
		return calendar_catppuccin_theme(
			id,
			"Catppuccin Macchiato",
			"catppuccin-macchiato",
			true,
			calendar_color(36, 39, 58),
			calendar_color(30, 32, 48),
			calendar_color(24, 25, 38),
			calendar_color(54, 58, 79),
			calendar_color(73, 77, 100),
			calendar_color(202, 211, 245),
			calendar_color(184, 192, 224),
			calendar_color(165, 173, 203),
			calendar_color(237, 135, 150),
			calendar_color(245, 169, 127),
			calendar_color(166, 218, 149),
			calendar_color(139, 213, 202),
			calendar_color(138, 173, 244),
			calendar_color(198, 160, 246),
			calendar_color(238, 212, 159),
		)
	case .Catppuccin_Mocha:
		return calendar_catppuccin_theme(
			id,
			"Catppuccin Mocha",
			"catppuccin-mocha",
			true,
			calendar_color(30, 30, 46),
			calendar_color(24, 24, 37),
			calendar_color(17, 17, 27),
			calendar_color(49, 50, 68),
			calendar_color(69, 71, 90),
			calendar_color(205, 214, 244),
			calendar_color(186, 194, 222),
			calendar_color(166, 173, 200),
			calendar_color(243, 139, 168),
			calendar_color(250, 179, 135),
			calendar_color(166, 227, 161),
			calendar_color(148, 226, 213),
			calendar_color(137, 180, 250),
			calendar_color(203, 166, 247),
			calendar_color(249, 226, 175),
		)
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

calendar_catppuccin_theme :: proc(
	id: Calendar_Theme_ID,
	name, storage_id: string,
	dark: bool,
	base, mantle, crust, surface0, surface1, text, subtext1, overlay1,
	red, peach, green, teal, blue, mauve, yellow: [4]f32,
) -> Calendar_UI_Theme {
	return {
		id = id,
		name = name,
		storage_id = storage_id,
		dark = dark,
		canvas = base,
		header = mantle,
		surface = crust,
		raised = surface0,
		control = surface1,
		overlay = mantle,
		text = text,
		text_soft = subtext1,
		muted = overlay1,
		inverse = crust,
		warm = peach,
		warm_strong = red,
		cool = teal,
		cool_strong = green,
		focus = blue,
		personal = peach,
		work = green,
		important = mauve,
		holiday = yellow,
		memorial = teal,
		positive = green,
		destructive = red,
	}
}

calendar_theme_ids :: proc() -> [8]Calendar_Theme_ID {
	return {
		.HW_Light,
		.HW_Dark,
		.Gruvbox_Light,
		.Gruvbox_Dark,
		.Catppuccin_Latte,
		.Catppuccin_Frappe,
		.Catppuccin_Macchiato,
		.Catppuccin_Mocha,
	}
}

calendar_theme_from_storage :: proc(value: string) -> (Calendar_Theme_ID, bool) {
	if value == "light" {return .HW_Light, true}
	if value == "dark" {return .HW_Dark, true}
	for id in calendar_theme_ids() {
		if calendar_theme(id).storage_id == value {return id, true}
	}
	return .HW_Light, false
}

calendar_theme_command_title :: proc(id: Calendar_Theme_ID) -> string {
	switch id {
	case .HW_Light: return "Switch theme to light mode"
	case .HW_Dark: return "Switch theme to dark mode"
	case .Gruvbox_Light: return "Switch theme to Gruvbox Light"
	case .Gruvbox_Dark: return "Switch theme to Gruvbox Dark"
	case .Catppuccin_Latte: return "Switch theme to Catppuccin Latte"
	case .Catppuccin_Frappe: return "Switch theme to Catppuccin Frappé"
	case .Catppuccin_Macchiato: return "Switch theme to Catppuccin Macchiato"
	case .Catppuccin_Mocha: return "Switch theme to Catppuccin Mocha"
	}
	return "Switch theme"
}
