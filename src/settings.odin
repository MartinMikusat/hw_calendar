package main

import "core:fmt"
import "core:strings"
import command_palette "command_palette:."
import flash "flash:."

Calendar_Settings_Category :: enum {
	Styling,
	Data,
	Shortcuts,
	Updates,
}

Calendar_Setting_Descriptor :: struct {
	id: command_palette.Entry_ID,
	category: Calendar_Settings_Category,
	title: string,
	subtitle: string,
	keywords: []string,
	action: Calendar_App_Action,
}

CALENDAR_SETTING_FLASH_ID :: command_palette.Entry_ID(100)
CALENDAR_SETTING_ARCHIVE_EXPORT_ID :: command_palette.Entry_ID(300)
CALENDAR_SETTING_ARCHIVE_IMPORT_ID :: command_palette.Entry_ID(301)
CALENDAR_SETTING_BIRTHDAY_DEFAULT_ID :: command_palette.Entry_ID(302)
CALENDAR_SETTING_UPDATE_CHECK_ID :: command_palette.Entry_ID(400)
CALENDAR_SETTINGS_ROW_HEIGHT :: 25.2

calendar_settings_category_name :: proc(category: Calendar_Settings_Category) -> string {
	switch category {
	case .Styling: return "STYLING"
	case .Data: return "DATA"
	case .Shortcuts: return "SHORTCUTS"
	case .Updates: return "UPDATES"
	}
	return "SETTINGS"
}

calendar_settings_descriptors :: proc(
	allocator := context.temp_allocator,
) -> [dynamic]Calendar_Setting_Descriptor {
	result := make([dynamic]Calendar_Setting_Descriptor, allocator)
	dark_keywords := make([]string, 5, allocator)
	copy(dark_keywords, []string{"theme", "appearance", "style", "dark", "light"})
	append(&result, Calendar_Setting_Descriptor{
		id = command_palette.Entry_ID(2),
		category = .Styling,
		title = "Dark",
		subtitle = "Invert paper and ink",
		keywords = dark_keywords,
		action = {kind = .Set_Theme, theme_id = .HW_Dark},
	})
	flash_keywords := make([]string, 5, allocator)
	copy(
		flash_keywords,
		[]string{"keyboard", "shortcut", "leader", "navigation", "jump"},
	)
	append(&result, Calendar_Setting_Descriptor{
		id = CALENDAR_SETTING_FLASH_ID,
		category = .Shortcuts,
		title = "Flash leader",
		subtitle = "Configure the key chord that opens Flash targets",
		keywords = flash_keywords,
		action = {kind = .Configure_Flash},
	})
	export_keywords := make([]string, 4, allocator)
	copy(export_keywords, []string{"archive", "backup", "portable", "json"})
	append(&result, Calendar_Setting_Descriptor{
		id = CALENDAR_SETTING_ARCHIVE_EXPORT_ID,
		category = .Data,
		title = "Export agenda",
		subtitle = "Save entries, proposals, and completion history",
		keywords = export_keywords,
		action = {kind = .Export_Agenda},
	})
	import_keywords := make([]string, 4, allocator)
	copy(import_keywords, []string{"archive", "restore", "portable", "json"})
	append(&result, Calendar_Setting_Descriptor{
		id = CALENDAR_SETTING_ARCHIVE_IMPORT_ID,
		category = .Data,
		title = "Import agenda",
		subtitle = "Replace agenda data after creating a backup",
		keywords = import_keywords,
		action = {kind = .Import_Agenda},
	})
	update_keywords := make([]string, 4, allocator)
	copy(update_keywords, []string{"release", "version", "sparkle", "download"})
	append(&result, Calendar_Setting_Descriptor{
		id = CALENDAR_SETTING_UPDATE_CHECK_ID,
		category = .Updates,
		title = "Check for updates",
		subtitle = "Check the stable release feed",
		keywords = update_keywords,
		action = {kind = .Check_For_Updates},
	})
	birthday_keywords := make([]string, 4, allocator)
	copy(birthday_keywords, []string{"birthday", "advance", "days", "default"})
	append(&result, Calendar_Setting_Descriptor{
		id = CALENDAR_SETTING_BIRTHDAY_DEFAULT_ID,
		category = .Data,
		title = "Birthday advance",
		subtitle = fmt.tprintf(
			"Default advance notice: %d days (use birthday default --days N)",
			birthday_default_advance_days(),
		),
		keywords = birthday_keywords,
		action = {},
	})
	return result
}

calendar_setting_descriptor_for_id :: proc(
	id: command_palette.Entry_ID,
) -> (Calendar_Setting_Descriptor, bool) {
	for descriptor in calendar_settings_descriptors() {
		if descriptor.id == id {return descriptor, true}
	}
	return {}, false
}

calendar_settings_entries :: proc(
	allocator := context.temp_allocator,
) -> [dynamic]command_palette.Entry {
	descriptors := calendar_settings_descriptors(allocator)
	entries := make([dynamic]command_palette.Entry, allocator)
	for descriptor in descriptors {
		append(&entries, command_palette.Entry{
			id = descriptor.id,
			title = descriptor.title,
			subtitle = descriptor.subtitle,
			category = calendar_settings_category_name(descriptor.category),
			keywords = descriptor.keywords,
		})
	}
	return entries
}

calendar_settings_rect_for_size :: proc(
	width, height: f64,
) -> Calendar_UI_Rect {
	inset := CALENDAR_DIALOG_VIEWPORT_INSET*2
	modal_width := min(900.0, max(CALENDAR_DIALOG_MIN_WIDTH, width-inset))
	modal_height := min(calendar_cell_height()*24, height-inset)
	return {
		(width-modal_width)/2,
		(height-modal_height)/2,
		modal_width,
		modal_height,
	}
}

calendar_settings_rect :: proc() -> Calendar_UI_Rect {
	return calendar_settings_rect_for_size(calendar_ui.width, calendar_ui.height)
}

calendar_settings_search_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_settings_rect()
	cell := calendar_cell_height()
	gap := calendar_cell_width()
	close_w := calendar_label_width(calendar_bracket("x"))
	return {
		modal.x+gap,
		modal.y+modal.h-cell-gap,
		modal.w-close_w-gap*3,
		cell,
	}
}

calendar_settings_close_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_settings_rect()
	cell := calendar_cell_height()
	gap := calendar_cell_width()
	close_w := calendar_label_width(calendar_bracket("x"))
	return {
		modal.x+modal.w-close_w-gap,
		modal.y+modal.h-cell-gap,
		close_w,
		cell,
	}
}

calendar_settings_sidebar_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_settings_rect()
	pad := calendar_half_cell()
	search := calendar_settings_search_rect()
	return {
		modal.x+pad,
		modal.y+pad,
		calendar_label_width("SHORTCUTS  00")+calendar_cell_width()*2,
		search.y-modal.y-pad*2,
	}
}

calendar_settings_content_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_settings_rect()
	sidebar := calendar_settings_sidebar_rect()
	pad := calendar_half_cell()
	search := calendar_settings_search_rect()
	x := sidebar.x+sidebar.w+calendar_cell_width()
	return {
		x,
		modal.y+pad,
		modal.x+modal.w-pad-x,
		search.y-modal.y-pad*2,
	}
}

calendar_settings_category_rect :: proc(index: int) -> Calendar_UI_Rect {
	sidebar := calendar_settings_sidebar_rect()
	return {
		sidebar.x,
		sidebar.y+sidebar.h-CALENDAR_SETTINGS_ROW_HEIGHT-
			f64(index)*CALENDAR_SETTINGS_ROW_HEIGHT,
		sidebar.w,
		CALENDAR_SETTINGS_ROW_HEIGHT,
	}
}

calendar_settings_result_rect :: proc(index: int) -> Calendar_UI_Rect {
	content := calendar_settings_content_rect()
	return {
		content.x,
		content.y+content.h-CALENDAR_SETTINGS_ROW_HEIGHT-
			f64(index)*CALENDAR_SETTINGS_ROW_HEIGHT,
		content.w,
		CALENDAR_SETTINGS_ROW_HEIGHT,
	}
}

calendar_settings_search_active :: proc() -> bool {
	return len(calendar_ui.settings_query) > 0
}

calendar_settings_result_descriptors :: proc(
	allocator := context.temp_allocator,
) -> [dynamic]Calendar_Setting_Descriptor {
	result := make([dynamic]Calendar_Setting_Descriptor, allocator)
	if calendar_settings_search_active() {
		for ranked in command_palette.visible_results(&calendar_ui.settings_search) {
			if descriptor, found := calendar_setting_descriptor_for_id(ranked.entry.id); found {
				append(&result, descriptor)
			}
		}
		return result
	}
	for descriptor in calendar_settings_descriptors() {
		if descriptor.category == calendar_ui.settings_category {
			append(&result, descriptor)
		}
	}
	return result
}

calendar_settings_category_match_count :: proc(
	category: Calendar_Settings_Category,
) -> int {
	if !calendar_settings_search_active() {
		count := 0
		for descriptor in calendar_settings_descriptors() {
			if descriptor.category == category {count += 1}
		}
		return count
	}
	count := 0
	for ranked in command_palette.visible_results(&calendar_ui.settings_search) {
		if descriptor, found := calendar_setting_descriptor_for_id(ranked.entry.id);
		   found && descriptor.category == category {
			count += 1
		}
	}
	return count
}

calendar_settings_set_query :: proc(value: string) -> bool {
	if error := command_palette.set_query(&calendar_ui.settings_search, value);
	   error != .None {
		return false
	}
	copy := strings.clone(value)
	delete(calendar_ui.settings_query)
	calendar_ui.settings_query = copy
	calendar_ui.needs_redraw = true
	return true
}

calendar_settings_open :: proc() -> bool {
	if calendar_ui.settings_open {
		calendar_text_focus(.Settings_Search)
		calendar_ui.needs_redraw = true
		return true
	}
	if calendar_active_modal().kind != .None {return false}
	entries := calendar_settings_entries()
	if error := command_palette.open(&calendar_ui.settings_search, entries[:], 0);
	   error != .None {
		return false
	}
	calendar_ui.settings_open = true
	calendar_ui.settings_category = .Styling
	calendar_ui.settings_query_focused = true
	delete(calendar_ui.settings_query)
	calendar_ui.settings_query = ""
	delete(calendar_ui.settings_error)
	calendar_ui.settings_error = ""
	calendar_ui.settings_message_is_error = false
	flash.cancel(&calendar_ui.flash)
	calendar_text_focus(.Settings_Search)
	calendar_ui.needs_redraw = true
	return true
}

calendar_settings_close :: proc() {
	if !calendar_ui.settings_open {return}
	if calendar_ui.shortcut_open {
		calendar_shortcut_recorder_close()
	}
	command_palette.close(&calendar_ui.settings_search)
	calendar_ui.settings_open = false
	if calendar_text_active_field() == .Settings_Search {
		_ = calendar_text_blur()
	}
	calendar_ui.settings_query_focused = false
	delete(calendar_ui.settings_query)
	calendar_ui.settings_query = ""
	delete(calendar_ui.settings_error)
	calendar_ui.settings_error = ""
	calendar_ui.settings_message_is_error = false
	flash.cancel(&calendar_ui.flash)
	calendar_ui.needs_redraw = true
}

calendar_ui_apply_theme :: proc(id: Calendar_Theme_ID) -> bool {
	if id == calendar_ui.theme_id {return true}
	theme := calendar_theme(id)
	if !calendar_meta_set("interface_theme", theme.storage_id) {
		delete(calendar_ui.settings_error)
		calendar_ui.settings_error = strings.clone("THE THEME COULD NOT BE SAVED")
		calendar_ui.needs_redraw = true
		return false
	}
	calendar_ui.theme_id = id
	delete(calendar_ui.settings_error)
	calendar_ui.settings_error = ""
	calendar_ui.needs_redraw = true
	return true
}

calendar_shortcut_recorder_open :: proc() {
	calendar_shortcut_destroy(&calendar_ui.shortcut_candidate)
	calendar_ui.shortcut_candidate_valid = false
	delete(calendar_ui.shortcut_collision)
	calendar_ui.shortcut_collision = ""
	delete(calendar_ui.shortcut_error)
	calendar_ui.shortcut_error = ""
	calendar_ui.shortcut_live_modifiers = {}
	calendar_ui.shortcut_open = true
	calendar_ui.shortcut_listening = true
	calendar_ui.settings_query_focused = false
	flash.cancel(&calendar_ui.flash)
	calendar_ui.needs_redraw = true
}

calendar_shortcut_recorder_close :: proc() {
	calendar_shortcut_destroy(&calendar_ui.shortcut_candidate)
	calendar_ui.shortcut_candidate_valid = false
	delete(calendar_ui.shortcut_collision)
	calendar_ui.shortcut_collision = ""
	delete(calendar_ui.shortcut_error)
	calendar_ui.shortcut_error = ""
	calendar_ui.shortcut_live_modifiers = {}
	calendar_ui.shortcut_open = false
	calendar_ui.shortcut_listening = false
	calendar_ui.needs_redraw = true
}

calendar_shortcut_recorder_capture :: proc(
	key_code: uint,
	text: string,
	flags: uint,
) -> bool {
	candidate, valid := calendar_shortcut_from_event(
		key_code,
		text,
		flags,
	)
	if !valid {return false}
	calendar_shortcut_destroy(&calendar_ui.shortcut_candidate)
	calendar_ui.shortcut_candidate = candidate
	calendar_ui.shortcut_candidate_valid = true
	delete(calendar_ui.shortcut_collision)
	calendar_ui.shortcut_collision = ""
	if owner, collides := calendar_shortcut_collision(candidate); collides {
		calendar_ui.shortcut_collision = strings.clone(
			fmt.tprintf("CONFLICTS WITH %s", owner),
		)
	}
	calendar_ui.shortcut_listening = false
	calendar_ui.shortcut_live_modifiers = candidate.modifiers
	delete(calendar_ui.shortcut_error)
	calendar_ui.shortcut_error = ""
	calendar_ui.needs_redraw = true
	return true
}

calendar_shortcut_recorder_save :: proc() -> bool {
	if !calendar_ui.shortcut_candidate_valid ||
	   len(calendar_ui.shortcut_collision) > 0 {
		return false
	}
	encoded, valid := calendar_shortcut_serialize(
		calendar_ui.shortcut_candidate,
		context.temp_allocator,
	)
	if !valid || !calendar_meta_set("flash_leader", encoded) {
		delete(calendar_ui.shortcut_error)
		calendar_ui.shortcut_error = strings.clone(
			"THE SHORTCUT COULD NOT BE SAVED",
		)
		calendar_ui.needs_redraw = true
		return false
	}
	calendar_shortcut_destroy(&calendar_ui.flash_leader)
	calendar_ui.flash_leader = calendar_shortcut_clone(
		calendar_ui.shortcut_candidate,
	)
	calendar_shortcut_recorder_close()
	return true
}

calendar_shortcut_recorder_reset :: proc() -> bool {
	default_value := calendar_shortcut_default()
	encoded, valid := calendar_shortcut_serialize(
		default_value,
		context.temp_allocator,
	)
	if !valid || !calendar_meta_set("flash_leader", encoded) {
		delete(calendar_ui.shortcut_error)
		calendar_ui.shortcut_error = strings.clone(
			"THE DEFAULT SHORTCUT COULD NOT BE SAVED",
		)
		calendar_ui.needs_redraw = true
		return false
	}
	calendar_shortcut_destroy(&calendar_ui.flash_leader)
	calendar_ui.flash_leader = calendar_shortcut_clone(default_value)
	calendar_shortcut_recorder_close()
	return true
}

calendar_shortcut_modal_rect :: proc() -> Calendar_UI_Rect {
	cell := calendar_cell_height()
	pad := calendar_half_cell()
	width := calendar_modal_width(560, calendar_ui.width)
	height := cell*10+pad*2
	return {
		(calendar_ui.width-width)/2,
		(calendar_ui.height-height)/2,
		width,
		height,
	}
}

calendar_shortcut_record_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_shortcut_modal_rect()
	pad := calendar_half_cell()
	return {
		modal.x+pad,
		modal.y+pad+calendar_cell_height()*3,
		modal.w-pad*2,
		calendar_cell_height()*2,
	}
}

calendar_shortcut_action_rect :: proc(index: int) -> Calendar_UI_Rect {
	modal := calendar_shortcut_modal_rect()
	gap := calendar_cell_width()
	pad := calendar_half_cell()
	width := (modal.w-pad*2-gap*2)/3
	return {
		modal.x+pad+f64(index)*(width+gap),
		modal.y+pad,
		width,
		calendar_cell_height(),
	}
}
