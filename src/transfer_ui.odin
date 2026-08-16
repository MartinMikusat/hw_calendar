package main

import "core:fmt"
import "core:strings"
import flash "flash:."

calendar_ui_archive_import_rect :: proc() -> Calendar_UI_Rect {
	cell := calendar_cell_height()
	pad := calendar_half_cell()
	width := calendar_modal_width(560, calendar_ui.width)
	height := cell*8+pad*2
	return {(calendar_ui.width-width)/2, (calendar_ui.height-height)/2, width, height}
}

calendar_ui_archive_import_button_rect :: proc(index: int) -> Calendar_UI_Rect {
	modal := calendar_ui_archive_import_rect()
	gap := calendar_cell_width()
	pad := calendar_half_cell()
	width := (modal.w-pad*2-gap)/2
	return {modal.x+pad+f64(index)*(width+gap), modal.y+pad, width, calendar_cell_height()}
}

calendar_ui_set_settings_message :: proc(message: string, is_error := false) {
	delete(calendar_ui.settings_error)
	calendar_ui.settings_error = strings.clone(message)
	calendar_ui.settings_message_is_error = is_error
	calendar_ui.needs_redraw = true
}

calendar_ui_show_settings_message :: proc(
	category: Calendar_Settings_Category,
	message: string,
	is_error := false,
) {
	if !calendar_ui.settings_open {
		_ = calendar_settings_open()
	}
	calendar_ui.settings_category = category
	_ = calendar_settings_set_query("")
	calendar_ui.settings_query_focused = false
	calendar_ui_set_settings_message(message, is_error)
}

calendar_archive_panel_path :: proc(save: bool) -> (string, bool) {
	panel_class := save ? objc_getClass("NSSavePanel") : objc_getClass("NSOpenPanel")
	panel_selector := save ? sel_registerName("savePanel") : sel_registerName("openPanel")
	panel := msg_id(panel_class, panel_selector)
	if panel == nil {return "", false}
	extensions := msg_id_id(
		objc_getClass("NSArray"),
		sel_registerName("arrayWithObject:"),
		nsstring("json"),
	)
	msg_void_id(panel, sel_registerName("setAllowedFileTypes:"), extensions)
	msg_void_bool(panel, sel_registerName("setCanCreateDirectories:"), true)
	if save {
		now := agenda_local_today()
		name := fmt.tprintf(
			"hw_calendar-%04d-%02d-%02d.hwcalendar.json",
			now.year,
			now.month,
			now.day,
		)
		msg_void_id(
			panel,
			sel_registerName("setNameFieldStringValue:"),
			nsstring(name),
		)
	} else {
		msg_void_bool(panel, sel_registerName("setCanChooseFiles:"), true)
		msg_void_bool(panel, sel_registerName("setCanChooseDirectories:"), false)
		msg_void_bool(panel, sel_registerName("setAllowsMultipleSelection:"), false)
	}
	if calendar_msg_i64(panel, sel_registerName("runModal")) != 1 {
		return "", false
	}
	url := msg_id(panel, sel_registerName("URL"))
	path_value := msg_id(url, sel_registerName("path"))
	utf8 := calendar_msg_cstring(path_value, sel_registerName("UTF8String"))
	if utf8 == nil {return "", false}
	return strings.clone(string(utf8)), true
}

calendar_ui_export_agenda :: proc() -> bool {
	path, selected := calendar_archive_panel_path(true)
	if !selected {return false}
	defer delete(path)
	summary, archive_error := calendar_archive_export(path)
	if archive_error != .None {
		calendar_ui_show_settings_message(
			.Data,
			strings.to_upper(calendar_archive_error_text(archive_error), context.temp_allocator),
			true,
		)
		return false
	}
	calendar_ui_show_settings_message(
		.Data,
		fmt.tprintf(
			"EXPORTED %d ENTRIES AND %d COMPLETIONS",
			summary.entry_count,
			summary.completion_count,
		),
	)
	return true
}

calendar_ui_import_agenda_begin :: proc() -> bool {
	path, selected := calendar_archive_panel_path(false)
	if !selected {return false}
	archive, summary, archive_error := calendar_archive_read(path)
	if archive_error != .None {
		delete(path)
		calendar_ui_show_settings_message(
			.Data,
			strings.to_upper(calendar_archive_error_text(archive_error), context.temp_allocator),
			true,
		)
		return false
	}
	calendar_archive_destroy(&archive)
	if calendar_ui.settings_open {calendar_settings_close()}
	delete(calendar_ui.archive_import_path)
	calendar_ui.archive_import_path = path
	calendar_ui.archive_import_summary = summary
	delete(calendar_ui.archive_import_error)
	calendar_ui.archive_import_error = ""
	calendar_ui.archive_import_open = true
	calendar_ui.needs_redraw = true
	return true
}

calendar_ui_import_agenda_close :: proc(return_to_settings := true) {
	calendar_ui.archive_import_open = false
	delete(calendar_ui.archive_import_path)
	calendar_ui.archive_import_path = ""
	delete(calendar_ui.archive_import_error)
	calendar_ui.archive_import_error = ""
	calendar_ui.archive_import_summary = {}
	flash.cancel(&calendar_ui.flash)
	calendar_ui.needs_redraw = true
	if return_to_settings {
		_ = calendar_settings_open()
		calendar_ui.settings_category = .Data
		calendar_ui.settings_query_focused = false
	}
}

calendar_ui_import_agenda_replace :: proc() -> bool {
	archive, summary, archive_error := calendar_archive_read(
		calendar_ui.archive_import_path,
	)
	if archive_error != .None {
		delete(calendar_ui.archive_import_error)
		calendar_ui.archive_import_error = strings.to_upper(
			calendar_archive_error_text(archive_error),
		)
		calendar_ui.needs_redraw = true
		return false
	}
	defer calendar_archive_destroy(&archive)
	backup_path, install_error := calendar_archive_install(&archive)
	if install_error != .None {
		delete(calendar_ui.archive_import_error)
		calendar_ui.archive_import_error = strings.to_upper(
			calendar_archive_error_text(install_error),
		)
		calendar_ui.needs_redraw = true
		return false
	}
	delete(backup_path)
	calendar_ui_import_agenda_close()
	calendar_ui_reload_data()
	calendar_notification_reconcile()
	calendar_ui_set_settings_message(
		fmt.tprintf(
			"IMPORTED %d ENTRIES AND %d COMPLETIONS",
			summary.entry_count,
			summary.completion_count,
		),
	)
	return true
}

calendar_ui_check_for_updates :: proc(show_settings := true) -> bool {
	checked := updater_check_for_updates()
	if show_settings {
		message := "THE RELEASE UPDATER IS NOT AVAILABLE IN THIS BUILD"
		if checked {message = "CHECKING THE STABLE RELEASE FEED"}
		calendar_ui_show_settings_message(.Updates, message, !checked)
	}
	return checked
}
