package main

import "base:runtime"
import "core:strings"
import CF "core:sys/darwin/CoreFoundation"
import command_palette "command_palette:."
import text_input "components:text_input"

calendar_text_field_id :: proc(field: Calendar_Text_Field) -> text_input.Field_ID {
	return text_input.Field_ID(field)
}

calendar_text_field :: proc(id: text_input.Field_ID) -> Calendar_Text_Field {
	return Calendar_Text_Field(id)
}

calendar_text_editor_field :: proc(index: int) -> Calendar_Text_Field {
	if index < 0 || index >= 10 {return .None}
	return Calendar_Text_Field(int(Calendar_Text_Field.Editor_Summary)+index)
}

calendar_text_target :: proc(field: Calendar_Text_Field) -> ^string {
	switch field {
	case .Command_Palette: return &calendar_ui.palette_query
	case .Settings_Search: return &calendar_ui.settings_query
	case .Editor_Summary: return &calendar_ui.editor_summary
	case .Editor_Start: return &calendar_ui.editor_start
	case .Editor_End: return &calendar_ui.editor_end
	case .Editor_Location: return &calendar_ui.editor_location
	case .Editor_URL: return &calendar_ui.editor_url
	case .Editor_Categories: return &calendar_ui.editor_categories
	case .Editor_Description: return &calendar_ui.editor_description
	case .Editor_Time_Zone: return &calendar_ui.editor_time_zone
	case .Editor_Alarms: return &calendar_ui.editor_alarms
	case .Editor_RRule: return &calendar_ui.editor_rrule
	case .None:
	}
	return nil
}

calendar_text_active_field :: proc() -> Calendar_Text_Field {
	return calendar_text_field(calendar_ui.input_state.active_field)
}

calendar_text_active_target :: proc() -> ^string {
	return calendar_text_target(calendar_text_active_field())
}

calendar_text_field_rect :: proc(field: Calendar_Text_Field) -> Calendar_UI_Rect {
	switch field {
	case .Command_Palette:
		modal := calendar_ui_palette_rect()
		return {modal.x+16, modal.y+modal.h-48, modal.w-32, 34}
	case .Settings_Search:
		return calendar_settings_search_rect()
	case .Editor_Summary, .Editor_Start, .Editor_End, .Editor_Location,
	     .Editor_URL, .Editor_Categories, .Editor_Description,
	     .Editor_Time_Zone, .Editor_Alarms, .Editor_RRule:
		return calendar_ui_editor_field_rect(
			int(field)-int(Calendar_Text_Field.Editor_Summary),
		)
	case .None:
	}
	return {}
}

calendar_text_focus :: proc(field: Calendar_Text_Field) {
	target := calendar_text_target(field)
	if target == nil {return}
	_ = text_input.focus(
		&calendar_ui.input_state,
		calendar_text_field_id(field),
		target^,
	)
	if calendar_ui.window != nil && calendar_ui.view != nil {
		msg_void_id(
			calendar_ui.window,
			sel_registerName("makeFirstResponder:"),
			calendar_ui.view,
		)
	}
	calendar_ui.settings_query_focused = field == .Settings_Search
	if field >= .Editor_Summary && field <= .Editor_RRule {
		calendar_ui.editor_field =
			int(field)-int(Calendar_Text_Field.Editor_Summary)
	}
	calendar_ui.needs_redraw = true
}

calendar_text_blur :: proc() -> bool {
	target := calendar_text_active_target()
	blurred := text_input.blur(&calendar_ui.input_state, target)
	if blurred {
		calendar_ui.settings_query_focused = false
		calendar_ui.needs_redraw = true
	}
	return blurred
}

calendar_text_changed :: proc(field: Calendar_Text_Field) {
	switch field {
	case .Command_Palette:
		if error := command_palette.set_query(
			&calendar_ui.palette,
			calendar_ui.palette_query,
		); error != .None {
			replace := strings.clone(
				command_palette.query(&calendar_ui.palette),
			)
			delete(calendar_ui.palette_query)
			calendar_ui.palette_query = replace
		}
	case .Settings_Search:
		if error := command_palette.set_query(
			&calendar_ui.settings_search,
			calendar_ui.settings_query,
		); error != .None {
			replace := strings.clone(
				command_palette.query(&calendar_ui.settings_search),
			)
			delete(calendar_ui.settings_query)
			calendar_ui.settings_query = replace
		}
	case .None, .Editor_Summary, .Editor_Start, .Editor_End,
	     .Editor_Location, .Editor_URL, .Editor_Categories,
	     .Editor_Description, .Editor_Time_Zone, .Editor_Alarms,
	     .Editor_RRule:
	}
	calendar_ui.needs_redraw = true
}

calendar_text_input_string :: proc(value: Id) -> (string, bool) {
	if value == nil {return "", false}
	utf8_selector := sel_registerName("UTF8String")
	text_object := value
	if !calendar_msg_bool_sel(
		text_object,
		sel_registerName("respondsToSelector:"),
		utf8_selector,
	) {
		string_selector := sel_registerName("string")
		if !calendar_msg_bool_sel(
			text_object,
			sel_registerName("respondsToSelector:"),
			string_selector,
		) {
			return "", false
		}
		text_object = msg_id(text_object, string_selector)
		if text_object == nil {return "", false}
	}
	utf8 := calendar_msg_cstring(text_object, utf8_selector)
	if utf8 == nil {return "", false}
	return string(utf8), true
}

calendar_text_event_is_insertable :: proc(value: string) -> bool {
	if len(value) == 0 {return false}
	for rune in value {
		if rune < 32 || rune == 127 {return false}
		if rune >= 0xF700 && rune <= 0xF8FF {return false}
	}
	return true
}

calendar_text_insert :: proc(value: string) {
	target := calendar_text_active_target()
	if target == nil || !calendar_text_event_is_insertable(value) {return}
	_ = text_input.remove_marked_text(&calendar_ui.input_state, target)
	if text_input.insert_text(&calendar_ui.input_state, target, value) {
		calendar_text_changed(calendar_text_active_field())
	}
	text_input.unmark_text(&calendar_ui.input_state)
}

calendar_text_copy :: proc() -> bool {
	target := calendar_text_active_target()
	if target == nil {return false}
	selected := text_input.selected_text(&calendar_ui.input_state, target^)
	if len(selected) == 0 {return false}
	pasteboard := msg_id(
		objc_getClass("NSPasteboard"),
		sel_registerName("generalPasteboard"),
	)
	if pasteboard == nil {return false}
	_ = calendar_msg_i64(pasteboard, sel_registerName("clearContents"))
	return calendar_msg_bool_id_id(
		pasteboard,
		sel_registerName("setString:forType:"),
		nsstring(selected),
		nsstring("public.utf8-plain-text"),
	)
}

calendar_on_text_copy :: proc "c" (self: Id, command: Sel, sender: Id) {
	context = runtime.default_context()
	_ = calendar_text_copy()
}

calendar_on_text_cut :: proc "c" (self: Id, command: Sel, sender: Id) {
	context = runtime.default_context()
	target := calendar_text_active_target()
	if target == nil || !calendar_text_copy() {return}
	if text_input.remove_selection(&calendar_ui.input_state, target) {
		calendar_text_changed(calendar_text_active_field())
	}
}

calendar_on_text_select_all :: proc "c" (self: Id, command: Sel, sender: Id) {
	context = runtime.default_context()
	target := calendar_text_active_target()
	if target == nil {return}
	text_input.set_selection(
		&calendar_ui.input_state,
		target^,
		0,
		len(target^),
	)
	calendar_ui.needs_redraw = true
}

calendar_on_text_paste :: proc "c" (self: Id, command: Sel, sender: Id) {
	context = runtime.default_context()
	target := calendar_text_active_target()
	if target == nil {return}
	pasteboard := msg_id(
		objc_getClass("NSPasteboard"),
		sel_registerName("generalPasteboard"),
	)
	if pasteboard == nil {return}
	value := msg_id_id(
		pasteboard,
		sel_registerName("stringForType:"),
		nsstring("public.utf8-plain-text"),
	)
	text, ok := calendar_text_input_string(value)
	if !ok {return}
	_ = text_input.remove_marked_text(&calendar_ui.input_state, target)
	if text_input.insert_text(&calendar_ui.input_state, target, text) {
		calendar_text_changed(calendar_text_active_field())
	}
}

calendar_on_text_insert_simple :: proc "c" (
	self: Id,
	command: Sel,
	value: Id,
) {
	calendar_on_text_insert(self, command, value, {})
}

calendar_on_text_insert :: proc "c" (
	self: Id,
	command: Sel,
	value: Id,
	replacement: Calendar_NS_Range,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if text, ok := calendar_text_input_string(value); ok {
		calendar_text_insert(text)
	}
}

calendar_text_move_command :: proc(
	target: ^string,
	selector: Sel,
) -> bool {
	state := &calendar_ui.input_state
	if selector == sel_registerName("deleteBackward:") {
		return text_input.delete_backward(state, target)
	} else if selector == sel_registerName("deleteForward:") {
		return text_input.delete_forward(state, target)
	} else if selector == sel_registerName("deleteWordBackward:") {
		return text_input.delete_word_backward(state, target)
	} else if selector == sel_registerName("moveLeft:") {
		text_input.move_left(state, target^, false)
	} else if selector == sel_registerName("moveRight:") {
		text_input.move_right(state, target^, false)
	} else if selector == sel_registerName("moveLeftAndModifySelection:") {
		text_input.move_left(state, target^, true)
	} else if selector == sel_registerName("moveRightAndModifySelection:") {
		text_input.move_right(state, target^, true)
	} else if selector == sel_registerName("moveWordLeft:") ||
	          selector == sel_registerName("moveWordBackward:") {
		text_input.move_word_left(state, target^, false)
	} else if selector == sel_registerName("moveWordRight:") ||
	          selector == sel_registerName("moveWordForward:") {
		text_input.move_word_right(state, target^, false)
	} else if selector == sel_registerName("moveWordLeftAndModifySelection:") ||
	          selector == sel_registerName("moveWordBackwardAndModifySelection:") {
		text_input.move_word_left(state, target^, true)
	} else if selector == sel_registerName("moveWordRightAndModifySelection:") ||
	          selector == sel_registerName("moveWordForwardAndModifySelection:") {
		text_input.move_word_right(state, target^, true)
	} else if selector == sel_registerName("moveUp:") {
		text_input.move_vertical(state, target^, -1, false)
	} else if selector == sel_registerName("moveDown:") {
		text_input.move_vertical(state, target^, 1, false)
	} else if selector == sel_registerName("moveUpAndModifySelection:") {
		text_input.move_vertical(state, target^, -1, true)
	} else if selector == sel_registerName("moveDownAndModifySelection:") {
		text_input.move_vertical(state, target^, 1, true)
	} else if selector == sel_registerName("moveToBeginningOfLine:") ||
	          selector == sel_registerName("moveToLeftEndOfLine:") {
		text_input.move_line_start(state, target^, false)
	} else if selector == sel_registerName("moveToEndOfLine:") ||
	          selector == sel_registerName("moveToRightEndOfLine:") {
		text_input.move_line_end(state, target^, false)
	} else if selector == sel_registerName("moveToBeginningOfLineAndModifySelection:") ||
	          selector == sel_registerName("moveToLeftEndOfLineAndModifySelection:") {
		text_input.move_line_start(state, target^, true)
	} else if selector == sel_registerName("moveToEndOfLineAndModifySelection:") ||
	          selector == sel_registerName("moveToRightEndOfLineAndModifySelection:") {
		text_input.move_line_end(state, target^, true)
	} else {
		return false
	}
	return true
}

calendar_on_text_command :: proc "c" (
	self: Id,
	command: Sel,
	selector: Sel,
) {
	context = runtime.default_context()
	target := calendar_text_active_target()
	if target == nil {return}
	field := calendar_text_active_field()
	changed := false
	if selector == sel_registerName("selectAll:") {
		calendar_on_text_select_all(self, selector, nil)
		return
	} else if selector == sel_registerName("copy:") {
		calendar_on_text_copy(self, selector, nil)
		return
	} else if selector == sel_registerName("cut:") {
		calendar_on_text_cut(self, selector, nil)
		return
	} else if selector == sel_registerName("paste:") {
		calendar_on_text_paste(self, selector, nil)
		return
	} else if selector == sel_registerName("insertNewline:") {
		if field == .Command_Palette {
			calendar_ui_activate_palette()
		} else if field >= .Editor_Summary && field <= .Editor_RRule {
			calendar_ui_editor_commit()
		}
		return
	} else if selector == sel_registerName("insertTab:") {
		if field >= .Editor_Summary && field <= .Editor_RRule {
			next := (calendar_ui.editor_field+1)%7
			calendar_text_focus(calendar_text_editor_field(next))
		} else {
			_ = calendar_text_blur()
		}
		return
	}
	had_marked := text_input.remove_marked_text(
		&calendar_ui.input_state,
		target,
	)
	changed = calendar_text_move_command(target, selector)
	if changed || had_marked {calendar_text_changed(field)}
	calendar_ui.needs_redraw = true
}

calendar_on_text_set_marked :: proc "c" (
	self: Id,
	command: Sel,
	value: Id,
	selected, replacement: Calendar_NS_Range,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	target := calendar_text_active_target()
	if target == nil {return}
	text, ok := calendar_text_input_string(value)
	if !ok {return}
	_ = text_input.set_marked_text(
		&calendar_ui.input_state,
		target,
		text,
		int(selected.location),
		int(selected.length),
	)
	calendar_text_changed(calendar_text_active_field())
}

calendar_on_text_unmark :: proc "c" (self: Id, command: Sel) {
	context = runtime.default_context()
	text_input.unmark_text(&calendar_ui.input_state)
}

calendar_on_text_has_marked :: proc "c" (self: Id, command: Sel) -> bool {
	return calendar_ui.input_state.has_marked_text
}

calendar_text_ns_range :: proc(value: text_input.UTF16_Range) -> Calendar_NS_Range {
	if !value.valid {return {~uint(0), 0}}
	return {uint(value.location), uint(value.length)}
}

calendar_on_text_range :: proc "c" (
	self: Id,
	command: Sel,
) -> Calendar_NS_Range {
	context = runtime.default_context()
	target := calendar_text_active_target()
	if target == nil {return {~uint(0), 0}}
	if command == sel_registerName("markedRange") {
		return calendar_text_ns_range(text_input.marked_utf16_range(
			&calendar_ui.input_state,
			target^,
		))
	}
	return calendar_text_ns_range(text_input.selected_utf16_range(
		&calendar_ui.input_state,
		target^,
	))
}

calendar_on_text_valid_attributes :: proc "c" (
	self: Id,
	command: Sel,
) -> Id {
	context = runtime.default_context()
	return msg_id(objc_getClass("NSArray"), sel_registerName("array"))
}

calendar_on_text_attributed_substring :: proc "c" (
	self: Id,
	command: Sel,
	range: Calendar_NS_Range,
	actual: ^Calendar_NS_Range,
) -> Id {
	return nil
}

calendar_on_text_character_index :: proc "c" (
	self: Id,
	command: Sel,
	point: Point,
) -> uint {
	return 0
}

calendar_on_text_first_rect :: proc "c" (
	self: Id,
	command: Sel,
	range: Calendar_NS_Range,
	actual: ^Calendar_NS_Range,
) -> Rect {
	context = runtime.default_context()
	rect := calendar_text_field_rect(calendar_text_active_field())
	screen := calendar_ui_ax_screen_rect(rect)
	return {
		{screen.origin.x, screen.origin.y},
		{1, max(18, rect.h)},
	}
}

calendar_text_interpret_event :: proc(self, event: Id) {
	array := msg_id_id(
		objc_getClass("NSArray"),
		sel_registerName("arrayWithObject:"),
		event,
	)
	msg_void_id(self, sel_registerName("interpretKeyEvents:"), array)
}

calendar_text_handle_shortcut :: proc(
	self, event: Id,
	key_code, modifiers: uint,
) -> bool {
	target := calendar_text_active_target()
	if target == nil {return false}
	command := modifiers&CALENDAR_EVENT_MODIFIER_COMMAND != 0
	option := modifiers&CALENDAR_EVENT_MODIFIER_OPTION != 0
	control := modifiers&CALENDAR_SHORTCUT_MODIFIER_CONTROL != 0
	if command && key_code == 8 {
		calendar_on_text_copy(self, sel_registerName("copy:"), nil)
		return true
	}
	if command && key_code == 7 {
		calendar_on_text_cut(self, sel_registerName("cut:"), nil)
		return true
	}
	if command && key_code == 9 {
		calendar_on_text_paste(self, sel_registerName("paste:"), nil)
		return true
	}
	if command && key_code == 0 {
		calendar_on_text_select_all(self, sel_registerName("selectAll:"), nil)
		return true
	}
	if key_code == 51 && (option || control) {
		_ = text_input.remove_marked_text(&calendar_ui.input_state, target)
		if text_input.delete_word_backward(&calendar_ui.input_state, target) {
			calendar_text_changed(calendar_text_active_field())
		}
		return true
	}
	calendar_text_interpret_event(self, event)
	return true
}

calendar_text_offset_at_point :: proc(
	field: Calendar_Text_Field,
	point: Point,
) -> int {
	target := calendar_text_target(field)
	if target == nil || len(target^) == 0 {return 0}
	font := calendar_system_monospaced_font(11*calendar_ui.scale)
	if font == nil {return 0}
	defer CFRelease(font)
	run := calendar_text_run(font, target^)
	if run.line == nil {return 0}
	defer CFRelease(run.line)
	rect := calendar_text_field_rect(field)
	x := max(
		0,
		(point.x-rect.x-8+calendar_ui.input_state.scroll_x)*
		calendar_ui.scale,
	)
	utf16 := CTLineGetStringIndexForPosition(run.line, {x, 0})
	if utf16 < 0 {utf16 = 0}
	return text_input.byte_offset_for_utf16_index(target^, utf16)
}

calendar_text_begin_pointer :: proc(
	field: Calendar_Text_Field,
	point: Point,
	click_count: uint,
) {
	target := calendar_text_target(field)
	if target == nil {return}
	offset := calendar_text_offset_at_point(field, point)
	text_input.begin_pointer_selection(
		&calendar_ui.input_state,
		calendar_text_field_id(field),
		target^,
		offset,
		click_count,
	)
	calendar_ui.settings_query_focused = field == .Settings_Search
	if field >= .Editor_Summary && field <= .Editor_RRule {
		calendar_ui.editor_field =
			int(field)-int(Calendar_Text_Field.Editor_Summary)
	}
	if calendar_ui.window != nil && calendar_ui.view != nil {
		msg_void_id(
			calendar_ui.window,
			sel_registerName("makeFirstResponder:"),
			calendar_ui.view,
		)
	}
	calendar_ui.needs_redraw = true
}

calendar_text_update_pointer :: proc(point: Point) -> bool {
	field := calendar_text_active_field()
	target := calendar_text_target(field)
	if target == nil {return false}
	offset := calendar_text_offset_at_point(field, point)
	if !text_input.update_pointer_selection(
		&calendar_ui.input_state,
		calendar_text_field_id(field),
		target^,
		offset,
	) {
		return false
	}
	calendar_ui.needs_redraw = true
	return true
}

calendar_draw_editable_text :: proc(
	ctx, font: rawptr,
	field: Calendar_Text_Field,
	text, placeholder: string,
	rect: Calendar_UI_Rect,
	text_color, placeholder_color, caret_color: [4]f64,
	inset := 8.0,
) {
	if calendar_text_active_field() != field {
		value, color := text, text_color
		if len(value) == 0 {value, color = placeholder, placeholder_color}
		calendar_draw_text(ctx, font, value, rect, color, inset)
		return
	}
	run_text := text
	if len(run_text) == 0 {run_text = " "}
	run := calendar_text_run(font, run_text)
	if run.line == nil {return}
	defer CFRelease(run.line)
	caret_utf16 := text_input.utf16_index_for_byte_offset(
		text,
		calendar_ui.input_state.caret_byte_offset,
	)
	caret_advance := CTLineGetOffsetForStringIndex(
		run.line,
		caret_utf16,
		nil,
	)/calendar_ui.scale
	scroll := text_input.update_horizontal_scroll(
		&calendar_ui.input_state,
		caret_advance,
		max(0, rect.w-inset*2),
	)
	origin_x := rect.x+inset-scroll
	origin_y := rect.y+
	            (rect.h-(run.ascent+run.descent)/calendar_ui.scale)/2+
	            run.descent/calendar_ui.scale
	if calendar_ordered_active {
		calendar_ordered_push_clip(rect)
		defer calendar_ordered_pop_clip()
	} else {
		CGContextSaveGState(ctx)
		defer CGContextRestoreGState(ctx)
		CGContextClipToRect(
			ctx,
			{
				{rect.x*calendar_ui.scale, rect.y*calendar_ui.scale},
				{rect.w*calendar_ui.scale, rect.h*calendar_ui.scale},
			},
		)
	}
	start, end := text_input.selection_bounds(&calendar_ui.input_state, text)
	if start < end {
		start_x := CTLineGetOffsetForStringIndex(
			run.line,
			text_input.utf16_index_for_byte_offset(text, start),
			nil,
		)/calendar_ui.scale
		end_x := CTLineGetOffsetForStringIndex(
			run.line,
			text_input.utf16_index_for_byte_offset(text, end),
			nil,
		)/calendar_ui.scale
		selection := caret_color
		selection[3] = 0.32
		calendar_fill_overlay_rect(
			ctx,
			{
				origin_x+start_x,
				rect.y+4,
				max(1/calendar_ui.scale, end_x-start_x),
				max(1, rect.h-8),
			},
			selection,
		)
	}
	if len(text) > 0 {
		if calendar_ordered_active {
			calendar_ordered_emit_line(run.line, origin_x, origin_y, text_color)
		} else {
			CGContextSetRGBFillColor(
				ctx,
				text_color[0],
				text_color[1],
				text_color[2],
				text_color[3],
			)
			CGContextSetTextPosition(
				ctx,
				origin_x*calendar_ui.scale,
				origin_y*calendar_ui.scale,
			)
			CTLineDraw(run.line, ctx)
		}
	}
	if start == end {
		calendar_fill_overlay_rect(
			ctx,
			{
				origin_x+caret_advance,
				rect.y+5,
				max(1/calendar_ui.scale, 0.5),
				max(1, rect.h-10),
			},
			caret_color,
		)
	}
}
