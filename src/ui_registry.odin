package main

import "core:fmt"
import framework_ui "ui_framework:core"
import framework_draw "ui_framework:draw"
import framework_macos "ui_framework:macos"

calendar_shared_view: framework_ui.Registry_View
calendar_control_frame: ^framework_ui.Frame

calendar_control_id :: proc(name: string) -> u64 {
	return u64(framework_ui.key_from_string(name))
}

calendar_control_binding :: proc(
	id: framework_ui.Action_ID,
) -> ^Calendar_Action_Binding {
	for &binding in calendar_ui.control_bindings {
		if binding.id == id {return &binding}
	}
	return nil
}

calendar_control_binding_for_control :: proc(
	control: ^framework_ui.Control_Record,
) -> ^Calendar_Action_Binding {
	if control == nil {return nil}
	return calendar_control_binding(control.action)
}

calendar_shared_control :: proc(id: framework_ui.Key) -> ^framework_ui.Control_Record {
	for &control in calendar_shared_view.controls {
		if control.id == id {return &control}
	}
	return nil
}

calendar_control_rect :: proc(rect: Calendar_UI_Rect) -> framework_draw.Rect {
	return {f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
}

calendar_ui_rect_from_framework :: proc(rect: framework_draw.Rect) -> Calendar_UI_Rect {
	return {f64(rect.x), f64(rect.y), f64(rect.w), f64(rect.h)}
}

calendar_framework_role :: proc(action: Calendar_App_Action) -> framework_ui.Accessibility_Role {
	#partial switch action.kind {
	case .Settings_Search, .Command_Palette_Search, .Editor_Field, .Chore_Name,
	     .Chore_Days:
		return .Text_Field
	case .Set_Theme, .Settings_Category, .Chore_Interval:
		return .Radio_Button
	case .Editor_All_Day:
		return .Check_Box
	}
	return .Button
}

calendar_framework_number_code :: proc(action: Calendar_App_Action) -> framework_ui.Number_Code {
	#partial switch action.kind {
	case .Action_Edit: return {1, 1, 2}
	case .Action_Open_URL: return {1, 2, 2}
	case .Action_Archive: return {1, 3, 2}
	case .Action_Complete: return {1, 4, 2}
	case .Action_Confirm_Proposal: return {1, 5, 2}
	case .Action_Reject_Proposal: return {1, 6, 2}
	case .New_Chore: return {2, 1, 2}
	case .Chore_Interval:
		if action.index >= 0 && action.index < len(CALENDAR_CHORE_PRESETS) {
			return {i8(action.index+1), 0, 1}
		}
	case .Chore_Save: return {6, 0, 1}
	case .Chore_Cancel: return {7, 0, 1}
	case .Archive_Confirm: return {1, 0, 1}
	case .Archive_Cancel: return {2, 0, 1}
	case .Import_Agenda_Cancel: return {1, 0, 1}
	case .Import_Agenda_Replace: return {2, 0, 1}
	}
	return {}
}

calendar_framework_capabilities :: proc(
	action: Calendar_App_Action,
) -> framework_ui.Control_Capabilities {
	result := framework_ui.Control_Capabilities{
		.Hover,
		.Primary_Press,
		.Accessibility,
		.Flash,
		.CLI,
	}
	#partial switch action.kind {
	case .Settings_Search, .Command_Palette_Search, .Editor_Field, .Chore_Name,
	     .Chore_Days:
		result += {.Editable, .Drag, .Direct_Keyboard}
	}
	code := calendar_framework_number_code(action)
	if code.digits > 0 {result += {.Numbered, .Direct_Keyboard}}
	if !calendar_ui_is_window_action(action.kind) &&
	   .Editable not_in result {
		result += {.Command_Menu}
	}
	return result
}

calendar_ui_add_action_control :: proc(
	name, label: string,
	rect: Calendar_UI_Rect,
	action: Calendar_App_Action,
) {
	assert(calendar_control_frame != nil)
	id := framework_ui.action_id_from_string(name)
	capabilities := calendar_framework_capabilities(action)
	accessibility_label := calendar_ui_ax_label(action, name)
	framework_ui.register_action(calendar_control_frame, {
		id = id,
		functional_name = name,
		label = accessibility_label,
		enabled = true,
		number_code = calendar_framework_number_code(action),
	})
	append(&calendar_ui.control_bindings, Calendar_Action_Binding{
		id = id,
		action = action,
	})
	flags := framework_ui.Box_Flags{.Interactive}
	if calendar_ui_is_window_action(action.kind) {flags += {.Input_Passthrough}}
	if .Editable in capabilities || .Numbered in capabilities {
		flags += {.Click_To_Focus}
	}
	_ = framework_ui.box_add(calendar_control_frame, framework_ui.Box{
		key = framework_ui.Key(id),
		layout = {position = .Absolute, absolute = calendar_control_rect(rect)},
		flags = flags,
		control = {
			functional_name = name,
			accessibility_label = accessibility_label,
			accessibility_role = calendar_framework_role(action),
			flash_label = label,
			flash_anchor = .Top_Left,
			capabilities = capabilities,
			action = id,
		},
	})
}

calendar_control_scope_begin :: proc(kind: Calendar_Modal_Kind) {
	assert(calendar_control_frame != nil)
	flags: framework_ui.Box_Flags
	if calendar_active_modal().kind == kind {
		flags += {.Modal_Root, .Input_Root}
	}
	_ = framework_ui.box_begin(calendar_control_frame, framework_ui.Box{
		key = framework_ui.key_from_string(
			fmt.tprintf("%s control root", calendar_modal_kind_name(kind)),
		),
		layout = {
			position = .Absolute,
			absolute = {0, 0, f32(calendar_ui.width), f32(calendar_ui.height)},
			flow = .Overlay,
		},
		flags = flags,
		layer = .Modal,
	})
}

calendar_control_scope_end :: proc() {
	framework_ui.box_end(calendar_control_frame)
}

calendar_ui_add_control :: proc(
	name, label: string,
	rect: Calendar_UI_Rect,
	action := Calendar_UI_Action.None,
	event_index := -1,
	occurrence_stamp := i64(0),
	occurrence_is_date := false,
	holiday_country_index := -1,
	holiday_definition_index := -1,
) {
	index := event_index
	if holiday_country_index >= 0 {index = holiday_country_index}
	calendar_ui_add_action_control(name, label, rect, {
		kind = action,
		index = index,
		definition_index = holiday_definition_index,
		occurrence_stamp = occurrence_stamp,
		occurrence_is_date = occurrence_is_date,
	})
}

calendar_control_frame_finish :: proc(frame: ^framework_ui.Frame) {
	output := framework_ui.end_frame(frame)
	framework_ui.publish(&calendar_ui.control_context, output)
	calendar_shared_view = framework_ui.registry_view_from_records(
		calendar_ui.control_context.published.actions[:],
		calendar_ui.control_context.published.controls[:],
		calendar_ui.control_context.published.frame,
	)
	framework_ui.registry_assert_valid(calendar_shared_view)
}

calendar_shared_control_at_point :: proc(point: Point) -> ^framework_ui.Control_Record {
	activation, activated := framework_macos.pointer_activation_view(
		calendar_shared_view,
		.Primary_Press,
		{f32(point.x), f32(point.y)},
	)
	if !activated {return nil}
	return calendar_shared_control(activation.control)
}

calendar_consume_shared_numbered_digit :: proc(
	digit: int,
	now_ms: i64,
) -> (u64, bool, bool) {
	state := framework_macos.Numbered_State{
		first = i8(calendar_ui.number_prefix),
		deadline_ms = calendar_ui.number_prefix_deadline_ms,
	}
	activation, activated, handled := framework_macos.consume_numbered_digit_view(
		&state,
		calendar_shared_view,
		i8(digit),
		now_ms,
	)
	changed := calendar_ui.number_prefix != int(state.first) ||
	           calendar_ui.number_prefix_deadline_ms != state.deadline_ms
	calendar_ui.number_prefix = int(state.first)
	calendar_ui.number_prefix_deadline_ms = state.deadline_ms
	if changed || handled {calendar_ui.needs_redraw = true}
	if !activated {return 0, false, handled}
	return u64(activation.action), true, handled
}
