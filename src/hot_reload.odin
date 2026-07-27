package main

import "base:runtime"
import "core:fmt"
import hot_reload "../dev/hot_reload_contract"

calendar_hot_previous_solid_pipeline: Id
calendar_hot_previous_texture_pipeline: Id

Calendar_Hot_Reload_Snapshot :: struct {
	ui:                            Calendar_UI_State,
	notification_authorization:    Calendar_Notification_Authorization,
	notification_center:           Id,
	database:                      ^SQLite_DB,
	database_owner:                Calendar_CLI_Database_Owner,
	ui_diagnostic_serial:          int,
}

calendar_hot_reload_initialize :: proc "c" (
	services: ^hot_reload.Host_Services,
) -> bool {
	context = runtime.default_context()
	if services == nil {return false}
	if !calendar_cli_database_try_acquire() || !calendar_database_open() {
		return false
	}
	if !calendar_gui_initialize(services) {
		calendar_database_close()
		calendar_cli_database_release()
		return false
	}
	return true
}

calendar_hot_reload_can_reload :: proc "c" () -> bool {
	return calendar_cli_ipc_work == nil &&
	       calendar_notification_callbacks_pending == 0
}

calendar_hot_reload_capture :: proc "c" (destination: rawptr) {
	if destination == nil {return}
	(^Calendar_Hot_Reload_Snapshot)(destination)^ = {
		ui = calendar_ui,
		notification_authorization = calendar_notification_authorization,
		notification_center = calendar_notification_center,
		database = calendar_database,
		database_owner = calendar_cli_database_owner,
		ui_diagnostic_serial = calendar_ui_diagnostic_serial,
	}
}

calendar_hot_reload_stage :: proc "c" (
	source: rawptr,
	services: ^hot_reload.Host_Services,
) -> bool {
	context = runtime.default_context()
	if source == nil || services == nil {return false}
	snapshot := (^Calendar_Hot_Reload_Snapshot)(source)
	calendar_ui = snapshot.ui
	calendar_ui.app = Id(services.app)
	calendar_ui.delegate = Id(services.delegate)
	calendar_notification_authorization = snapshot.notification_authorization
	calendar_notification_center = snapshot.notification_center
	calendar_database = snapshot.database
	calendar_cli_database_owner = snapshot.database_owner
	calendar_ui_diagnostic_serial = snapshot.ui_diagnostic_serial
	calendar_cli_ipc_state = {}
	calendar_cli_ipc_work = nil
	calendar_notification_callbacks_pending = 0
	calendar_auth_block = {}
	calendar_settings_block = {}
	if !objc_initialize() {return false}
	previous_solid := calendar_ui.solid_pipeline
	previous_texture := calendar_ui.texture_pipeline
	calendar_ui.solid_pipeline = nil
	calendar_ui.texture_pipeline = nil
	if !calendar_compile_pipelines() {
		if calendar_ui.solid_pipeline != nil {
			msg_void(calendar_ui.solid_pipeline, sel_registerName("release"))
		}
		if calendar_ui.texture_pipeline != nil {
			msg_void(calendar_ui.texture_pipeline, sel_registerName("release"))
		}
		calendar_ui.solid_pipeline = previous_solid
		calendar_ui.texture_pipeline = previous_texture
		return false
	}
	calendar_hot_previous_solid_pipeline = previous_solid
	calendar_hot_previous_texture_pipeline = previous_texture
	return true
}

calendar_hot_reload_before_swap :: proc "c" () {
	context = runtime.default_context()
	calendar_cli_ipc_server_stop()
}

calendar_hot_reload_commit :: proc "c" () {
	context = runtime.default_context()
	if calendar_hot_previous_solid_pipeline != nil {
		msg_void(
			calendar_hot_previous_solid_pipeline,
			sel_registerName("release"),
		)
		calendar_hot_previous_solid_pipeline = nil
	}
	if calendar_hot_previous_texture_pipeline != nil {
		msg_void(
			calendar_hot_previous_texture_pipeline,
			sel_registerName("release"),
		)
		calendar_hot_previous_texture_pipeline = nil
	}
	calendar_notification_prepare_blocks()
	if calendar_notification_center != nil && calendar_ui.delegate != nil {
		msg_void_id(
			calendar_notification_center,
			sel_registerName("setDelegate:"),
			calendar_ui.delegate,
		)
	}
	if !calendar_cli_ipc_server_start() {
		fmt.eprintln("HW Calendar could not restart its local control socket.")
	}
	calendar_ui.needs_redraw = true
}

calendar_hot_reload_shutdown :: proc "c" () {
	context = runtime.default_context()
	calendar_gui_shutdown()
	calendar_database_close()
	calendar_cli_database_release()
}

calendar_hot_reload_cli_main :: proc "c" (
	args: [^]cstring,
	count: int,
) -> i32 {
	context = runtime.default_context()
	values := make([]string, count, context.temp_allocator)
	for i in 0..<count {
		values[i] = string(args[i])
	}
	calendar_process_main(values)
	return 0
}

calendar_hot_reload_api := hot_reload.Module_API{
	api_version = hot_reload.API_VERSION,
	state_version = hot_reload.STATE_VERSION,
	snapshot_size = size_of(Calendar_Hot_Reload_Snapshot),
	snapshot_align = align_of(Calendar_Hot_Reload_Snapshot),
	initialize = rawptr(calendar_hot_reload_initialize),
	can_reload = rawptr(calendar_hot_reload_can_reload),
	capture = rawptr(calendar_hot_reload_capture),
	stage = rawptr(calendar_hot_reload_stage),
	before_swap = rawptr(calendar_hot_reload_before_swap),
	commit = rawptr(calendar_hot_reload_commit),
	shutdown = rawptr(calendar_hot_reload_shutdown),
	cli_main = rawptr(calendar_hot_reload_cli_main),
	callbacks = {
		hot_reload.Callback.Frame = rawptr(calendar_on_frame),
		hot_reload.Callback.CLI_Request = rawptr(calendar_on_cli_ipc_request),
		hot_reload.Callback.Should_Terminate = rawptr(calendar_should_terminate),
		hot_reload.Callback.Notification_Response = rawptr(calendar_notification_response),
		hot_reload.Callback.Notification_Foreground = rawptr(calendar_notification_foreground),
		hot_reload.Callback.AX_Press = rawptr(calendar_on_ax_press),
		hot_reload.Callback.AX_Value = rawptr(calendar_on_ax_value),
		hot_reload.Callback.AX_Set_Value = rawptr(calendar_on_ax_set_value),
		hot_reload.Callback.AX_Children = rawptr(calendar_on_ax_children),
		hot_reload.Callback.AX_Is_Element = rawptr(calendar_on_ax_is_element),
		hot_reload.Callback.Accepts_First = rawptr(calendar_on_accepts_first),
		hot_reload.Callback.Mouse_Down = rawptr(calendar_on_mouse_down),
		hot_reload.Callback.Mouse_Dragged = rawptr(calendar_on_mouse_dragged),
		hot_reload.Callback.Mouse_Up = rawptr(calendar_on_mouse_up),
		hot_reload.Callback.Scroll = rawptr(calendar_on_scroll),
		hot_reload.Callback.Key_Down = rawptr(calendar_on_key_down),
		hot_reload.Callback.Window_Can_Become_Key = rawptr(calendar_window_can_become_key),
	},
}

@(export)
calendar_hot_reload_get_api :: proc "c" () -> ^hot_reload.Module_API {
	return &calendar_hot_reload_api
}
