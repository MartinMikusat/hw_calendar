package main

import "core:fmt"
import "core:strings"
import command_palette "command_palette:."
import flash "flash:."

Calendar_Settings_Category :: enum {
	Styling,
	Connected_Calendars,
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
CALENDAR_SETTING_EVENTKIT_ACCESS_ID :: command_palette.Entry_ID(200)
CALENDAR_SETTING_ARCHIVE_EXPORT_ID :: command_palette.Entry_ID(300)
CALENDAR_SETTING_ARCHIVE_IMPORT_ID :: command_palette.Entry_ID(301)
CALENDAR_SETTING_UPDATE_CHECK_ID :: command_palette.Entry_ID(400)
CALENDAR_SETTING_EVENTKIT_CALENDAR_BASE_ID :: command_palette.Entry_ID(1_000)
CALENDAR_SETTINGS_ROW_HEIGHT :: 36.0

calendar_settings_category_name :: proc(category: Calendar_Settings_Category) -> string {
	switch category {
	case .Styling: return "STYLING"
	case .Connected_Calendars: return "CALENDARS"
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
	for id in calendar_theme_ids() {
		theme := calendar_theme(id)
		keywords := make([]string, 5, allocator)
		keywords[0] = "theme"
		keywords[1] = "appearance"
		keywords[2] = "style"
		keywords[3] = theme.dark ? "dark" : "light"
		keywords[4] = theme.storage_id
		append(&result, Calendar_Setting_Descriptor{
			id = command_palette.Entry_ID(int(id)+1),
			category = .Styling,
			title = theme.name,
			subtitle = theme.dark ? "Dark interface theme" : "Light interface theme",
			keywords = keywords,
			action = {kind = .Set_Theme, theme_id = id},
		})
	}
	flash_keywords := make([]string, 5, allocator)
	copy(
		flash_keywords,
		[]string{"keyboard", "shortcut", "leader", "navigation", "jump"},
	)
	when false {
	access_keywords := make([]string, 5, allocator)
	copy(
		access_keywords,
		[]string{"calendar", "eventkit", "permission", "account", "access"},
	)
	append(&result, Calendar_Setting_Descriptor{
		id = CALENDAR_SETTING_EVENTKIT_ACCESS_ID,
		category = .Connected_Calendars,
		title = "Calendar access",
		subtitle = fmt.tprintf(
			"EventKit access: %s",
			calendar_eventkit_authorization_name(),
		),
		keywords = access_keywords,
		action = {kind = .Request_Calendar_Access},
	})
	for calendar, index in calendar_eventkit_calendars {
		source_type := calendar_eventkit_source_type_name(calendar.source_type)
		visibility_keywords := make([]string, 6, allocator)
		copy(
			visibility_keywords,
			[]string{
				"calendar",
				"visibility",
				"show",
				"hide",
				calendar.source_title,
				source_type,
			},
		)
		append(&result, Calendar_Setting_Descriptor{
			id = CALENDAR_SETTING_EVENTKIT_CALENDAR_BASE_ID+
			     command_palette.Entry_ID(index*2),
			category = .Connected_Calendars,
			title = calendar.title,
			subtitle = fmt.tprintf(
				"%s · %s · %s",
				calendar.source_title,
				calendar.writable ? "writable" : "read only",
				calendar.color,
			),
			keywords = visibility_keywords,
			action = {
				kind = .Toggle_Connected_Calendar,
				index = index,
			},
		})
		default_keywords := make([]string, 6, allocator)
		copy(
			default_keywords,
			[]string{
				"calendar",
				"default",
				"destination",
				"new event",
				calendar.source_title,
				source_type,
			},
		)
		append(&result, Calendar_Setting_Descriptor{
			id = CALENDAR_SETTING_EVENTKIT_CALENDAR_BASE_ID+
			     command_palette.Entry_ID(index*2+1),
			category = .Connected_Calendars,
			title = fmt.tprintf("Default: %s", calendar.title),
			subtitle = (
				calendar.writable ?
					"Use this calendar for new connected events" :
					"This calendar is read only"
			),
			keywords = default_keywords,
			action = {
				kind = .Set_Default_Connected_Calendar,
				index = index,
			},
		})
	}
	}
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
	modal_width := min(900.0, width-48)
	modal_height := min(600.0, height-72)
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
	return {modal.x+20, modal.y+modal.h-62, modal.w-76, 34}
}

calendar_settings_close_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_settings_rect()
	return {modal.x+modal.w-48, modal.y+modal.h-62, 28, 34}
}

calendar_settings_sidebar_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_settings_rect()
	return {modal.x+20, modal.y+20, 168, modal.h-94}
}

calendar_settings_content_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_settings_rect()
	return {modal.x+200, modal.y+20, modal.w-220, modal.h-94}
}

calendar_settings_category_rect :: proc(index: int) -> Calendar_UI_Rect {
	sidebar := calendar_settings_sidebar_rect()
	return {
		sidebar.x,
		sidebar.y+sidebar.h-CALENDAR_SETTINGS_ROW_HEIGHT-f64(index)*CALENDAR_SETTINGS_ROW_HEIGHT,
		sidebar.w,
		CALENDAR_SETTINGS_ROW_HEIGHT-2,
	}
}

calendar_settings_result_rect :: proc(index: int) -> Calendar_UI_Rect {
	content := calendar_settings_content_rect()
	return {
		content.x,
		content.y+content.h-CALENDAR_SETTINGS_ROW_HEIGHT-f64(index)*CALENDAR_SETTINGS_ROW_HEIGHT,
		content.w,
		CALENDAR_SETTINGS_ROW_HEIGHT-2,
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
	width := min(560.0, calendar_ui.width-48)
	height := 260.0
	return {
		(calendar_ui.width-width)/2,
		(calendar_ui.height-height)/2,
		width,
		height,
	}
}

calendar_shortcut_record_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_shortcut_modal_rect()
	return {modal.x+24, modal.y+86, modal.w-48, 54}
}

calendar_shortcut_action_rect :: proc(index: int) -> Calendar_UI_Rect {
	modal := calendar_shortcut_modal_rect()
	gap := 8.0
	width := (modal.w-48-gap*2)/3
	return {
		modal.x+24+f64(index)*(width+gap),
		modal.y+24,
		width,
		34,
	}
}
