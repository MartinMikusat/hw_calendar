package main

import "base:runtime"
import "core:hash"
import "core:strings"
import command_palette "command_palette:."
import framework_ui "ui_framework:core"
import framework_macos "ui_framework:macos"

calendar_shared_registry: framework_ui.Registry_Builder
calendar_shared_view: framework_ui.Registry_View

@(init)
calendar_shared_registry_initialize :: proc "contextless" () {
	context = runtime.default_context()
	calendar_shared_registry = framework_ui.registry_begin(0)
}

@(fini)
calendar_shared_registry_finalize :: proc "contextless" () {
	context = runtime.default_context()
	framework_ui.registry_destroy(&calendar_shared_registry)
}

calendar_control_id :: proc(name: string) -> u64 {
	return hash.fnv64a(transmute([]u8)name)
}

calendar_ui_clear_controls :: proc() {
	for &control in calendar_ui.controls {
		delete(control.name)
		delete(control.label)
	}
	clear(&calendar_ui.controls)
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
	append(&calendar_ui.controls, Calendar_UI_Control{
		id = calendar_control_id(name),
		name = strings.clone(name),
		label = strings.clone(label),
		rect = rect,
		action = {
			kind = action,
			index = event_index,
			definition_index = holiday_definition_index,
			occurrence_stamp = occurrence_stamp,
			occurrence_is_date = occurrence_is_date,
		},
	})
	if holiday_country_index >= 0 {
		calendar_ui.controls[len(calendar_ui.controls)-1].action.index =
			holiday_country_index
	}
}

calendar_ui_add_action_control :: proc(
	name, label: string,
	rect: Calendar_UI_Rect,
	action: Calendar_App_Action,
) {
	append(&calendar_ui.controls, Calendar_UI_Control{
		id = calendar_control_id(name),
		name = strings.clone(name),
		label = strings.clone(label),
		rect = rect,
		action = action,
	})
}

calendar_ui_find_control :: proc(id: u64) -> ^Calendar_UI_Control {
	for &control in calendar_ui.controls {
		if control.id == id {return &control}
	}
	return nil
}

calendar_framework_role :: proc(action: Calendar_App_Action) -> framework_ui.Accessibility_Role {
	#partial switch action.kind {
	case .Settings_Search, .Command_Palette_Search, .Editor_Field, .Chore_Name:
		return .Text_Field
	case .Set_Theme, .Settings_Category, .Set_Default_Connected_Calendar, .Chore_Interval:
		return .Radio_Button
	case .Toggle_Connected_Calendar, .Editor_Important, .Editor_All_Day:
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
	case .Archive_Occurrence: return {1, 0, 1}
	case .Archive_Series: return {2, 0, 1}
	case .Archive_Cancel: return {3, 0, 1}
	}
	return {}
}

calendar_framework_capabilities :: proc(
	control: ^Calendar_UI_Control,
) -> framework_ui.Control_Capabilities {
	result := framework_ui.Control_Capabilities{
		.Hover,
		.Primary_Press,
		.Accessibility,
		.Flash,
		.CLI,
	}
	#partial switch control.action.kind {
	case .Settings_Search, .Command_Palette_Search, .Editor_Field, .Chore_Name:
		result += {.Editable, .Drag, .Direct_Keyboard}
	}
	code := calendar_framework_number_code(control.action)
	if code.digits > 0 {result += {.Numbered, .Direct_Keyboard}}
	if !calendar_ui_is_window_action(control.action.kind) &&
	   .Editable not_in result {
		result += {.Command_Menu}
	}
	return result
}

calendar_control_in_active_scope :: proc(control: ^Calendar_UI_Control) -> bool {
	if calendar_ui_is_window_action(control.action.kind) {return true}
	if calendar_ui.discard_changes_open {
		return control.action.kind == .Discard_Keep_Editing ||
		       control.action.kind == .Discard_Changes
	}
	if calendar_ui.shortcut_open {
		return control.action.kind == .Shortcut_Record ||
		       control.action.kind == .Shortcut_Save ||
		       control.action.kind == .Shortcut_Reset ||
		       control.action.kind == .Shortcut_Cancel
	}
	if calendar_ui.settings_open {
		return control.action.kind == .Settings_Close ||
		       control.action.kind == .Settings_Category ||
		       control.action.kind == .Settings_Search ||
		       control.action.kind == .Set_Theme ||
		       control.action.kind == .Request_Calendar_Access ||
		       control.action.kind == .Toggle_Connected_Calendar ||
		       control.action.kind == .Set_Default_Connected_Calendar ||
		       control.action.kind == .Configure_Flash
	}
	if calendar_ui.archive_modal_open {
		return control.action.kind == .Archive_Cancel ||
		       control.action.kind == .Archive_Occurrence ||
		       control.action.kind == .Archive_Series
	}
	if calendar_ui.editor_open {
		return control.action.kind == .Editor_Field ||
		       control.action.kind == .Editor_Important ||
		       control.action.kind == .Editor_All_Day ||
		       control.action.kind == .Editor_Calendar ||
		       control.action.kind == .Editor_Save ||
		       control.action.kind == .Editor_Delete ||
		       control.action.kind == .Editor_Cancel
	}
	if calendar_ui.chore_open && command_palette.is_open(&calendar_ui.palette) {
		return control.action.kind == .Command_Palette_Search
	}
	if calendar_ui.chore_open {
		return control.action.kind == .Chore_Name ||
		       control.action.kind == .Chore_Interval ||
		       control.action.kind == .Chore_Save ||
		       control.action.kind == .Chore_Cancel
	}
	if command_palette.is_open(&calendar_ui.palette) {
		return control.action.kind == .Command_Palette_Search
	}
	return true
}

calendar_publish_shared_registry :: proc() {
	framework_ui.registry_reset(
		&calendar_shared_registry,
		u64(calendar_ui.frame_index),
	)
	modal_active := calendar_active_modal().kind != .None
	for &control in calendar_ui.controls {
		if !calendar_control_in_active_scope(&control) {continue}
		action_id := framework_ui.Action_ID(control.id)
		framework_ui.registry_add_action(&calendar_shared_registry, {
			id = action_id,
			functional_name = control.name,
			label = calendar_ui_ax_label(&control),
			enabled = true,
			number_code = calendar_framework_number_code(control.action),
		})
		layer := framework_ui.Layer.Base
		if modal_active && !calendar_ui_is_window_action(control.action.kind) {
			layer = .Modal
		}
		capabilities := calendar_framework_capabilities(&control)
		framework_ui.registry_add_control(&calendar_shared_registry, {
			id = framework_ui.Key(control.id),
			functional_name = control.name,
			accessibility_label = calendar_ui_ax_label(&control),
			accessibility_role = calendar_framework_role(control.action),
			flash_label = control.label,
			flash_anchor = .Top_Left,
			capabilities = capabilities,
			action = action_id,
			rect = {
				f32(control.rect.x),
				f32(control.rect.y),
				f32(control.rect.w),
				f32(control.rect.h),
			},
			layer = layer,
			focusable = .Editable in capabilities || .Numbered in capabilities,
			enabled = true,
		})
	}
	calendar_shared_view = framework_ui.registry_view(&calendar_shared_registry)
	framework_ui.registry_assert_valid(calendar_shared_view)
}

calendar_shared_control_at_point :: proc(point: Point) -> ^Calendar_UI_Control {
	activation, activated := framework_macos.pointer_activation_view(
		calendar_shared_view,
		.Primary_Press,
		{f32(point.x), f32(point.y)},
	)
	if !activated {return nil}
	return calendar_ui_find_control(u64(activation.control))
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
