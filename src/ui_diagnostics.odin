package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sys/posix"
import "core:time"
import command_palette "command_palette:."

CALENDAR_UI_DIAGNOSTIC_SCHEMA_VERSION :: 2
CALENDAR_UI_DIAGNOSTIC_RETENTION :: 20

Calendar_UI_Diagnostic_Rect :: struct {
	x, y, w, h: f64,
}

Calendar_UI_Diagnostic_Control :: struct {
	id: u64,
	functional_name: string,
	flash_label: string,
	accessibility_label: string,
	accessibility_role: string,
	action: string,
	event_index: int,
	rect: Calendar_UI_Diagnostic_Rect,
}

Calendar_UI_Diagnostic_Snapshot :: struct {
	schema_version: int,
	process_id: int,
	frame: int,
	day_offset: int,
	command_palette_open: bool,
	editor_open: bool,
	archive_modal_open: bool,
	controls: []Calendar_UI_Diagnostic_Control,
}

Calendar_UI_Diagnostic_Change :: struct {
	functional_name: string,
	reason: string,
}

Calendar_UI_Diagnostic_Check_Artifact :: struct {
	schema_version: int,
	ok: bool,
	baseline: Calendar_UI_Diagnostic_Snapshot,
	current: Calendar_UI_Diagnostic_Snapshot,
	added: []string,
	removed: []string,
	changed: []Calendar_UI_Diagnostic_Change,
}

Calendar_CLI_UI_Snapshot_Data :: struct {
	path: string,
	control_count: int,
	frame: int,
}

Calendar_CLI_UI_Snapshot_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_UI_Snapshot_Data,
}

Calendar_CLI_UI_Check_Data :: struct {
	path: string,
	control_count: int,
	added_count: int,
	removed_count: int,
	changed_count: int,
}

Calendar_CLI_UI_Check_Response :: struct {
	ok: bool,
	command: string,
	data: Calendar_CLI_UI_Check_Data,
}

Calendar_UI_Diagnostic_Artifact_File :: struct {
	path: string,
	name: string,
	modified_nano: i64,
}

calendar_ui_diagnostic_serial: int

calendar_ui_diagnostic_action_name :: proc(action: Calendar_UI_Action) -> string {
	switch action {
	case .None: return "none"
	case .Window_Close: return "window-close"
	case .Window_Minimize: return "window-minimize"
	case .Window_Zoom: return "window-zoom"
	case .Theme_Toggle: return "theme-toggle"
	case .Today: return "today"
	case .Search: return "search"
	case .New_Event: return "new-event"
	case .Open_Event: return "open-event"
	case .Focus_Event: return "focus-event"
	case .Focus_Holiday: return "focus-holiday"
	case .Action_Edit: return "action-edit"
	case .Action_Open_URL: return "action-open-url"
	case .Action_Archive: return "action-archive"
	case .Archive_Cancel: return "archive-cancel"
	case .Archive_Occurrence: return "archive-occurrence"
	case .Archive_Series: return "archive-series"
	case .Editor_Field: return "editor-field"
	case .Editor_Important: return "editor-important"
	case .Editor_Save: return "editor-save"
	case .Editor_Delete: return "editor-delete"
	case .Editor_Cancel: return "editor-cancel"
	}
	return "unknown"
}

calendar_ui_diagnostic_snapshot :: proc(
	allocator := context.allocator,
) -> (Calendar_UI_Diagnostic_Snapshot, bool) {
	if len(calendar_ui.controls) == 0 {return {}, false}
	controls := make(
		[]Calendar_UI_Diagnostic_Control,
		len(calendar_ui.controls),
		allocator,
	)
	seen := make(map[u64]bool, context.temp_allocator)
	for &control, index in calendar_ui.controls {
		if seen[control.id] {return {}, false}
		seen[control.id] = true
		controls[index] = {
			id = control.id,
			functional_name = strings.clone(control.name, allocator),
			flash_label = strings.clone(control.label, allocator),
			accessibility_label = strings.clone(
				calendar_ui_ax_label(&control),
				allocator,
			),
			accessibility_role = strings.clone(
				control.action == .Editor_Field ? "AXTextField" : "AXButton",
				allocator,
			),
			action = strings.clone(
				calendar_ui_diagnostic_action_name(control.action),
				allocator,
			),
			event_index = control.event_index,
			rect = {
				x = control.rect.x,
				y = control.rect.y,
				w = control.rect.w,
				h = control.rect.h,
			},
		}
	}
	return {
		schema_version = CALENDAR_UI_DIAGNOSTIC_SCHEMA_VERSION,
		process_id = int(posix.getpid()),
		frame = calendar_ui.frame_index,
		day_offset = calendar_ui.day_offset,
		command_palette_open = command_palette.is_open(&calendar_ui.palette),
		editor_open = calendar_ui.editor_open,
		archive_modal_open = calendar_ui.archive_modal_open,
		controls = controls,
	}, true
}

calendar_ui_diagnostic_artifact_path :: proc(
	kind: string,
	allocator := context.allocator,
) -> string {
	calendar_ui_diagnostic_serial += 1
	directory := fmt.aprintf(
		"%s/ui-checks",
		calendar_support_dir(),
		allocator = context.temp_allocator,
	)
	_ = os.make_directory(calendar_support_dir())
	_ = os.make_directory(directory)
	return fmt.aprintf(
		"%s/%s-%d-%d-%d.json",
		directory,
		kind,
		int(posix.getpid()),
		calendar_ui.frame_index,
		calendar_ui_diagnostic_serial,
		allocator = allocator,
	)
}

calendar_ui_diagnostic_prune :: proc(directory: string) {
	handle, open_error := os.open(directory)
	if open_error != nil {return}
	entries, read_error := os.read_dir(handle, -1, context.temp_allocator)
	os.close(handle)
	if read_error != nil {return}
	files := make(
		[dynamic]Calendar_UI_Diagnostic_Artifact_File,
		context.temp_allocator,
	)
	for entry in entries {
		if entry.is_dir || !strings.has_suffix(entry.name, ".json") {continue}
		append(&files, Calendar_UI_Diagnostic_Artifact_File{
			path = entry.fullpath,
			name = entry.name,
			modified_nano = time.time_to_unix_nano(entry.modification_time),
		})
	}
	if len(files) <= CALENDAR_UI_DIAGNOSTIC_RETENTION {return}
	slice.sort_by(
		files[:],
		proc(a, b: Calendar_UI_Diagnostic_Artifact_File) -> bool {
			if a.modified_nano == b.modified_nano {return a.name < b.name}
			return a.modified_nano < b.modified_nano
		},
	)
	for index in 0..<len(files)-CALENDAR_UI_DIAGNOSTIC_RETENTION {
		_ = os.remove(files[index].path)
	}
}

calendar_ui_diagnostic_write :: proc(path: string, value: $T) -> bool {
	bytes, encode_error := json.marshal(
		value,
		{pretty=true, use_spaces=true, spaces=2},
		context.temp_allocator,
	)
	if encode_error != nil || !os.write_entire_file(path, bytes) {return false}
	calendar_ui_diagnostic_prune(filepath.dir(path, context.temp_allocator))
	return true
}

calendar_ui_diagnostic_find :: proc(
	controls: []Calendar_UI_Diagnostic_Control,
	name: string,
) -> ^Calendar_UI_Diagnostic_Control {
	for &control in controls {
		if control.functional_name == name {return &control}
	}
	return nil
}

calendar_ui_diagnostic_snapshot_command :: proc(
	request: Calendar_CLI_Request,
) -> Calendar_CLI_Result {
	snapshot, captured := calendar_ui_diagnostic_snapshot(
		context.temp_allocator,
	)
	if !captured {
		return calendar_cli_error(
			request.command,
			6,
			"snapshot_failed",
			"The live control registry is empty or invalid.",
		)
	}
	path := calendar_ui_diagnostic_artifact_path(
		"snapshot",
		context.temp_allocator,
	)
	if !calendar_ui_diagnostic_write(path, snapshot) {
		return calendar_cli_error(
			request.command,
			6,
			"snapshot_failed",
			"The UI snapshot artifact could not be written.",
		)
	}
	return {
		output = calendar_cli_encode(Calendar_CLI_UI_Snapshot_Response{
			ok = true,
			command = calendar_cli_command_name(request.command),
			data = {
				path = path,
				control_count = len(snapshot.controls),
				frame = snapshot.frame,
			},
		}),
	}
}

calendar_ui_diagnostic_check_command :: proc(
	request: Calendar_CLI_Request,
) -> Calendar_CLI_Result {
	if len(request.baseline) == 0 {
		return calendar_cli_error(
			request.command,
			2,
			"usage",
			"ui check requires --baseline.",
		)
	}
	bytes, read := os.read_entire_file(
		request.baseline,
		context.temp_allocator,
	)
	if !read {
		return calendar_cli_error(
			request.command,
			3,
			"baseline_failed",
			"The baseline snapshot could not be read.",
		)
	}
	baseline: Calendar_UI_Diagnostic_Snapshot
	if decode_error := json.unmarshal(
		bytes,
		&baseline,
		.JSON,
		context.temp_allocator,
	); decode_error != nil {
		return calendar_cli_error(
			request.command,
			3,
			"baseline_failed",
			"The baseline snapshot is invalid.",
		)
	}
	current, captured := calendar_ui_diagnostic_snapshot(
		context.temp_allocator,
	)
	if !captured {
		return calendar_cli_error(
			request.command,
			6,
			"snapshot_failed",
			"The live control registry is empty or invalid.",
		)
	}
	added := make([dynamic]string, context.temp_allocator)
	removed := make([dynamic]string, context.temp_allocator)
	changed := make(
		[dynamic]Calendar_UI_Diagnostic_Change,
		context.temp_allocator,
	)
	for control in baseline.controls {
		candidate := calendar_ui_diagnostic_find(
			current.controls,
			control.functional_name,
		)
		if candidate == nil {
			append(&removed, control.functional_name)
		} else if candidate.id != control.id ||
		          candidate.action != control.action ||
		          candidate.event_index != control.event_index ||
		          candidate.rect != control.rect {
			append(&changed, Calendar_UI_Diagnostic_Change{
				functional_name = control.functional_name,
				reason = "contract",
			})
		}
	}
	for control in current.controls {
		if calendar_ui_diagnostic_find(
			baseline.controls,
			control.functional_name,
		) == nil {
			append(&added, control.functional_name)
		}
	}
	ok := baseline.schema_version == CALENDAR_UI_DIAGNOSTIC_SCHEMA_VERSION &&
	      baseline.process_id == current.process_id &&
	      current.frame >= baseline.frame &&
	      len(removed) == 0 && len(changed) == 0
	artifact := Calendar_UI_Diagnostic_Check_Artifact{
		schema_version = CALENDAR_UI_DIAGNOSTIC_SCHEMA_VERSION,
		ok = ok,
		baseline = baseline,
		current = current,
		added = added[:],
		removed = removed[:],
		changed = changed[:],
	}
	path := calendar_ui_diagnostic_artifact_path(
		"check",
		context.temp_allocator,
	)
	if !calendar_ui_diagnostic_write(path, artifact) {
		return calendar_cli_error(
			request.command,
			6,
			"check_failed",
			"The UI check artifact could not be written.",
		)
	}
	response := Calendar_CLI_UI_Check_Response{
		ok = ok,
		command = calendar_cli_command_name(request.command),
		data = {
			path = path,
			control_count = len(current.controls),
			added_count = len(added),
			removed_count = len(removed),
			changed_count = len(changed),
		},
	}
	result := Calendar_CLI_Result{output=calendar_cli_encode(response)}
	if !ok {result.exit_code = 5}
	return result
}
