package main

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:time"
import CF "core:sys/darwin/CoreFoundation"
import command_palette "command_palette:."
import flash "flash:."
import text_input "components:text_input"

foreign import metal "system:Metal.framework"
foreign metal {
	MTLCreateSystemDefaultDevice :: proc "c" () -> Id ---
}

foreign import core_graphics "system:CoreGraphics.framework"
foreign core_graphics {
	CGColorSpaceCreateDeviceRGB :: proc "c" () -> rawptr ---
	CGColorSpaceRelease :: proc "c" (space: rawptr) ---
	CGBitmapContextCreate :: proc "c" (
		data: rawptr,
		width, height, bits_per_component, bytes_per_row: uint,
		space: rawptr,
		bitmap_info: u32,
	) -> rawptr ---
	CGContextRelease :: proc "c" (ctx: rawptr) ---
	CGContextClearRect :: proc "c" (ctx: rawptr, rect: Rect) ---
	CGContextFillRect :: proc "c" (ctx: rawptr, rect: Rect) ---
	CGContextSetRGBFillColor :: proc "c" (
		ctx: rawptr,
		red, green, blue, alpha: f64,
	) ---
	CGContextSetRGBStrokeColor :: proc "c" (
		ctx: rawptr,
		red, green, blue, alpha: f64,
	) ---
	CGContextSetLineWidth :: proc "c" (ctx: rawptr, width: f64) ---
	CGContextSetLineCap :: proc "c" (ctx: rawptr, cap: i32) ---
	CGContextSetLineJoin :: proc "c" (ctx: rawptr, join: i32) ---
	CGContextBeginPath :: proc "c" (ctx: rawptr) ---
	CGContextMoveToPoint :: proc "c" (ctx: rawptr, x, y: f64) ---
	CGContextAddLineToPoint :: proc "c" (ctx: rawptr, x, y: f64) ---
	CGContextAddCurveToPoint :: proc "c" (
		ctx: rawptr,
		cp1x, cp1y, cp2x, cp2y, x, y: f64,
	) ---
	CGContextClosePath :: proc "c" (ctx: rawptr) ---
	CGContextStrokePath :: proc "c" (ctx: rawptr) ---
	CGContextSetTextPosition :: proc "c" (ctx: rawptr, x, y: f64) ---
	CGContextSaveGState :: proc "c" (ctx: rawptr) ---
	CGContextRestoreGState :: proc "c" (ctx: rawptr) ---
	CGContextClipToRect :: proc "c" (ctx: rawptr, rect: Rect) ---
}

foreign import core_text "system:CoreText.framework"
foreign core_text {
	CTLineCreateWithAttributedString :: proc "c" (string: rawptr) -> rawptr ---
	CTLineGetTypographicBounds :: proc "c" (
		line: rawptr,
		ascent, descent, leading: ^f64,
	) -> f64 ---
	CTLineGetOffsetForStringIndex :: proc "c" (
		line: rawptr,
		index: int,
		secondary_offset: ^f64,
	) -> f64 ---
	CTLineGetStringIndexForPosition :: proc "c" (
		line: rawptr,
		position: Point,
	) -> int ---
	CTLineDraw :: proc "c" (line, ctx: rawptr) ---
	kCTFontAttributeName: rawptr
	kCTKernAttributeName: rawptr
	kCTForegroundColorFromContextAttributeName: rawptr
}

foreign import calendar_core_foundation "system:CoreFoundation.framework"
foreign calendar_core_foundation {
	CFRetain :: proc "c" (value: rawptr) -> rawptr ---
	CFStringCreateWithBytes :: proc "c" (
		allocator: CF.TypeRef,
		bytes: [^]u8,
		count: CF.Index,
		encoding: CF.StringEncoding,
		external: b8,
	) -> CF.String ---
	CFStringGetLength :: proc "c" (string: rawptr) -> int ---
	CFNumberCreate :: proc "c" (
		allocator: rawptr,
		number_type: int,
		value: rawptr,
	) -> rawptr ---
	CFAttributedStringCreateMutable :: proc "c" (
		allocator: rawptr,
		max_length: int,
	) -> rawptr ---
	CFAttributedStringReplaceString :: proc "c" (
		string: rawptr,
		range: CF.Range,
		replacement: rawptr,
	) ---
	CFAttributedStringSetAttribute :: proc "c" (
		string: rawptr,
		range: CF.Range,
		name, value: rawptr,
	) ---
	CFRelease :: proc "c" (value: rawptr) ---
	kCFBooleanTrue: rawptr
}

Calendar_UI_Rect :: struct {x, y, w, h: f64}
Calendar_Text_Style :: enum {Label, Body, Heading}
Calendar_Text_Style_Spec :: struct {
	size_scale: f64,
	weight: f64,
	tracking: f64,
}
Calendar_NS_Range :: struct {location, length: uint}
Calendar_Solid_Vertex :: struct {x, y, r, g, b, a: f32}
Calendar_Texture_Vertex :: struct {x, y, u, v, r, g, b, a: f32}
Calendar_MTL_Clear_Color :: struct {red, green, blue, alpha: f64}
Calendar_MTL_Origin :: struct {x, y, z: uint}
Calendar_MTL_Size :: struct {width, height, depth: uint}
Calendar_MTL_Region :: struct {origin: Calendar_MTL_Origin, size: Calendar_MTL_Size}

Calendar_UI_Action :: enum {
	None,
	Window_Close,
	Window_Minimize,
	Window_Zoom,
	Open_Settings,
	Settings_Close,
	Settings_Category,
	Settings_Search,
	Command_Palette_Search,
	Set_Theme,
	Request_Calendar_Access,
	Toggle_Connected_Calendar,
	Set_Default_Connected_Calendar,
	Configure_Flash,
	Shortcut_Record,
	Shortcut_Save,
	Shortcut_Reset,
	Shortcut_Cancel,
	Today,
	Search,
	New_Event,
	Open_Event,
	Jump_Event,
	Toggle_Holiday_Country,
	Jump_Holiday,
	Focus_Event,
	Focus_Holiday,
	Action_Edit,
	Action_Open_URL,
	Action_Archive,
	Action_Complete,
	Action_Confirm_Proposal,
	Action_Reject_Proposal,
	Action_Copy_To_Connected,
	Action_Open_In_Apple_Calendar,
	Archive_Cancel,
	Archive_Occurrence,
	Archive_Series,
	Editor_Field,
	Editor_Important,
	Editor_All_Day,
	Editor_Calendar,
	Editor_Save,
	Editor_Delete,
	Editor_Cancel,
}

Calendar_App_Action :: struct {
	kind: Calendar_UI_Action,
	index: int,
	definition_index: int,
	occurrence_stamp: i64,
	occurrence_is_date: bool,
	theme_id: Calendar_Theme_ID,
}

Calendar_UI_Control :: struct {
	id: u64,
	name: string,
	label: string,
	rect: Calendar_UI_Rect,
	action: Calendar_App_Action,
}

Calendar_UI_AX_Binding :: struct {
	element: Id,
	control_id: u64,
}

Calendar_Navigation_Item_Kind :: enum {
	Event,
	Holiday,
}

Calendar_Navigation_Item :: struct {
	kind: Calendar_Navigation_Item_Kind,
	event: Calendar_Occurrence,
	holiday: Calendar_Holiday_Occurrence,
}

Calendar_Navigation_Direction :: enum {
	Previous,
	Next,
}

Calendar_Text_Field :: enum u64 {
	None,
	Command_Palette,
	Settings_Search,
	Editor_Summary,
	Editor_Start,
	Editor_End,
	Editor_Location,
	Editor_URL,
	Editor_Categories,
	Editor_Description,
	Editor_Time_Zone,
	Editor_Alarms,
	Editor_RRule,
}

Calendar_UI_State :: struct {
	app: Id,
	window: Id,
	delegate: Id,
	view: Id,
	layer: Id,
	device: Id,
	queue: Id,
	solid_pipeline: Id,
	texture_pipeline: Id,
	text_texture: Id,
	text_width: uint,
	text_height: uint,
	width: f64,
	height: f64,
	scale: f64,
	needs_redraw: bool,
	resize_edges: u8,
	resize_start_mouse: Point,
	resize_start_frame: Rect,
	window_zoom_restore_frame: Rect,
	window_has_zoom_restore: bool,
	frame_index: int,
	notification_reconcile_stamp: i64,
	day_offset: int,
	number_prefix: int,
	number_prefix_deadline_ms: i64,
	theme_id: Calendar_Theme_ID,
	flash_leader: Calendar_Shortcut,
	events: [dynamic]Calendar_Event,
	occurrences: [dynamic]Calendar_Occurrence,
	holiday_countries: [dynamic]Calendar_Holiday_Country,
	holiday_occurrences: [dynamic]Calendar_Holiday_Occurrence,
	controls: [dynamic]Calendar_UI_Control,
	flash: flash.State,
	palette: command_palette.State,
	palette_query: string,
	palette_actions: [dynamic]Calendar_App_Action,
	input_state: text_input.State,
	text_previous_focus: text_input.Focus_Snapshot,
	text_previous_focus_valid: bool,
	settings_search: command_palette.State,
	settings_open: bool,
	settings_category: Calendar_Settings_Category,
	settings_query: string,
	settings_query_focused: bool,
	settings_error: string,
	shortcut_open: bool,
	shortcut_listening: bool,
	shortcut_candidate: Calendar_Shortcut,
	shortcut_candidate_valid: bool,
	shortcut_collision: string,
	shortcut_error: string,
	shortcut_live_modifiers: Calendar_Shortcut_Modifiers,
	promoted_holiday_active: bool,
	promoted_holiday_country_index: int,
	promoted_holiday_definition_index: int,
	promoted_holiday_days: i64,
	navigation_active: bool,
	navigation_kind: Calendar_Navigation_Item_Kind,
	navigation_event_index: int,
	navigation_start_stamp: i64,
	navigation_start_is_date: bool,
	navigation_holiday_country_index: int,
	navigation_holiday_definition_index: int,
	details_scroll: f64,
	archive_modal_open: bool,
	archive_error: string,
	editor_open: bool,
	editor_event_index: int,
	editor_field: int,
	editor_calendar_identifier: string,
	editor_summary: string,
	editor_start: string,
	editor_end: string,
	editor_location: string,
	editor_url: string,
	editor_categories: string,
	editor_description: string,
	editor_time_zone: string,
	editor_alarms: string,
	editor_rrule: string,
	editor_error: string,
	editor_important: bool,
	editor_all_day: bool,
	ax_children: Id,
	ax_bindings: [dynamic]Calendar_UI_AX_Binding,
}

calendar_ui: Calendar_UI_State

CALENDAR_HEADER_HEIGHT :: 40.0
CALENDAR_HEADER_CONTROL_HEIGHT :: 30.0
CALENDAR_EVENT_MODIFIER_SHIFT :: uint(1 << 17)
CALENDAR_EVENT_MODIFIER_OPTION :: uint(1 << 19)
CALENDAR_EVENT_MODIFIER_COMMAND :: uint(1 << 20)
CALENDAR_DEFAULT_WINDOW_WIDTH :: 1280.0
CALENDAR_DEFAULT_WINDOW_HEIGHT :: 760.0
CALENDAR_DAY_ROW_HEIGHT :: 28.0
CALENDAR_DAY_ROW_PITCH :: 30.0
CALENDAR_LAYOUT_MARGIN :: 6.0
CALENDAR_PANEL_GAP :: 4.0
CALENDAR_DAY_TOP_GAP :: CALENDAR_LAYOUT_MARGIN
CALENDAR_ACTION_BAR_HEIGHT :: 28.0
CALENDAR_ACTION_BAR_GAP :: 6.0
CALENDAR_ACTION_BAR_BOTTOM :: CALENDAR_LAYOUT_MARGIN
CALENDAR_CONTENT_BOTTOM :: CALENDAR_ACTION_BAR_BOTTOM+
                           CALENDAR_ACTION_BAR_HEIGHT+
                           CALENDAR_LAYOUT_MARGIN
CALENDAR_WINDOW_STYLE :: uint(14)
CALENDAR_WINDOW_MINIMIZE_STYLE :: uint(15)
CALENDAR_WINDOW_RESIZE_INSET :: 6.0
CALENDAR_TEXT_BASE_SIZE :: 11.0

calendar_text_style_spec :: proc(style: Calendar_Text_Style) -> Calendar_Text_Style_Spec {
	switch style {
	case .Label: return {size_scale=0.7, weight=0, tracking=0}
	case .Body: return {size_scale=1, weight=0, tracking=-0.45}
	case .Heading: return {size_scale=2, weight=0.35, tracking=-0.7}
	}
	return {size_scale=1}
}
CALENDAR_WINDOW_MIN_WIDTH :: 640.0
CALENDAR_WINDOW_MIN_HEIGHT :: 480.0

calendar_system_monospaced_font_weight :: proc(size, weight: f64) -> rawptr {
	font := msg_id_f64_f64(
		objc_getClass("NSFont"),
		sel_registerName("monospacedSystemFontOfSize:weight:"),
		size,
		weight,
	)
	if font == nil {return nil}
	return CFRetain(font)
}

calendar_system_monospaced_font :: proc(size: f64) -> rawptr {
	return calendar_system_monospaced_font_weight(size, 0)
}

calendar_system_monospaced_font_for_style :: proc(style: Calendar_Text_Style) -> rawptr {
	spec := calendar_text_style_spec(style)
	return calendar_system_monospaced_font_weight(
		CALENDAR_TEXT_BASE_SIZE*spec.size_scale*calendar_ui.scale,
		spec.weight,
	)
}

calendar_msg_void_size :: proc(receiver: Id, selector: Sel, size: Size) {
	p := transmute(proc "c" (Id, Sel, Size))objc_send_address
	p(receiver, selector, size)
}

calendar_msg_void_clear_color :: proc(
	receiver: Id,
	selector: Sel,
	color: Calendar_MTL_Clear_Color,
) {
	p := transmute(proc "c" (Id, Sel, Calendar_MTL_Clear_Color))objc_send_address
	p(receiver, selector, color)
}

calendar_msg_void_region :: proc(
	receiver: Id,
	selector: Sel,
	region: Calendar_MTL_Region,
	level: uint,
	bytes: rawptr,
	bytes_per_row: uint,
) {
	p := transmute(proc "c" (
		Id, Sel, Calendar_MTL_Region, uint, rawptr, uint,
	))objc_send_address
	p(receiver, selector, region, level, bytes, bytes_per_row)
}

calendar_msg_id_id_error :: proc(
	receiver: Id,
	selector: Sel,
	a, b: Id,
	error: ^Id,
) -> Id {
	p := transmute(proc "c" (Id, Sel, Id, Id, ^Id) -> Id)objc_send_address
	return p(receiver, selector, a, b, error)
}

calendar_msg_id_id_error_2 :: proc(
	receiver: Id,
	selector: Sel,
	a: Id,
	error: ^Id,
) -> Id {
	p := transmute(proc "c" (Id, Sel, Id, ^Id) -> Id)objc_send_address
	return p(receiver, selector, a, error)
}

calendar_msg_uint :: proc(receiver: Id, selector: Sel) -> uint {
	p := transmute(proc "c" (Id, Sel) -> uint)objc_send_address
	return p(receiver, selector)
}

calendar_msg_i64 :: proc(receiver: Id, selector: Sel) -> i64 {
	p := transmute(proc "c" (Id, Sel) -> i64)objc_send_address
	return p(receiver, selector)
}

calendar_msg_bool_sel :: proc(receiver: Id, selector, value: Sel) -> bool {
	p := transmute(proc "c" (Id, Sel, Sel) -> bool)objc_send_address
	return p(receiver, selector, value)
}

calendar_msg_bool_id_id :: proc(
	receiver: Id,
	selector: Sel,
	a, b: Id,
) -> bool {
	p := transmute(proc "c" (Id, Sel, Id, Id) -> bool)objc_send_address
	return p(receiver, selector, a, b)
}

calendar_msg_id_bool :: proc(receiver: Id, selector: Sel, value: bool) -> Id {
	p := transmute(proc "c" (Id, Sel, bool) -> Id)objc_send_address
	return p(receiver, selector, value)
}

calendar_msg_cstring :: proc(receiver: Id, selector: Sel) -> cstring {
	p := transmute(proc "c" (Id, Sel) -> cstring)objc_send_address
	return p(receiver, selector)
}

calendar_msg_point_point_id :: proc(
	receiver: Id,
	selector: Sel,
	point: Point,
	view: Id,
) -> Point {
	p := transmute(proc "c" (Id, Sel, Point, Id) -> Point)objc_send_address
	return p(receiver, selector, point, view)
}

calendar_msg_void_rect :: proc(receiver: Id, selector: Sel, rect: Rect) {
	p := transmute(proc "c" (Id, Sel, Rect))objc_send_address
	p(receiver, selector, rect)
}

calendar_msg_rect_rect_id :: proc(
	receiver: Id,
	selector: Sel,
	rect: Rect,
	view: Id,
) -> Rect {
	p := transmute(proc "c" (Id, Sel, Rect, Id) -> Rect)objc_send_address
	return p(receiver, selector, rect, view)
}

calendar_msg_rect_rect :: proc(
	receiver: Id,
	selector: Sel,
	rect: Rect,
) -> Rect {
	p := transmute(proc "c" (Id, Sel, Rect) -> Rect)objc_send_address
	return p(receiver, selector, rect)
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

calendar_ui_ax_control :: proc(element: Id) -> ^Calendar_UI_Control {
	for binding in calendar_ui.ax_bindings {
		if binding.element == element {
			return calendar_ui_find_control(binding.control_id)
		}
	}
	return nil
}

calendar_ui_ax_screen_rect :: proc(rect: Calendar_UI_Rect) -> Rect {
	view_rect := Rect{{rect.x, rect.y}, {rect.w, rect.h}}
	window_rect := calendar_msg_rect_rect_id(
		calendar_ui.view,
		sel_registerName("convertRect:toView:"),
		view_rect,
		nil,
	)
	return calendar_msg_rect_rect(
		calendar_ui.window,
		sel_registerName("convertRectToScreen:"),
		window_rect,
	)
}

calendar_ui_ax_label :: proc(control: ^Calendar_UI_Control) -> string {
	if control == nil {return ""}
	switch control.action.kind {
	case .Window_Close: return "Close window"
	case .Window_Minimize: return "Minimize window"
	case .Window_Zoom: return "Zoom window"
	case .Open_Settings: return "Open Settings"
	case .Settings_Close: return "Close Settings"
	case .Settings_Category:
		return fmt.tprintf(
			"Show %s settings",
			calendar_settings_category_name(
				Calendar_Settings_Category(control.action.index),
			),
		)
	case .Settings_Search: return "Search Settings"
	case .Command_Palette_Search: return "Search commands"
	case .Set_Theme:
		return calendar_theme_command_title(control.action.theme_id)
	case .Request_Calendar_Access: return "Request calendar access"
	case .Toggle_Connected_Calendar:
		if control.action.index >= 0 &&
		   control.action.index < len(calendar_eventkit_calendars) {
			return fmt.tprintf(
				"Show calendar %s",
				calendar_eventkit_calendars[control.action.index].title,
			)
		}
		return "Show connected calendar"
	case .Set_Default_Connected_Calendar:
		if control.action.index >= 0 &&
		   control.action.index < len(calendar_eventkit_calendars) {
			return fmt.tprintf(
				"Use %s as the default calendar",
				calendar_eventkit_calendars[control.action.index].title,
			)
		}
		return "Set the default connected calendar"
	case .Configure_Flash: return "Configure leader key for Flash"
	case .Shortcut_Record: return "Record another Flash leader"
	case .Shortcut_Save: return "Save Flash leader"
	case .Shortcut_Reset: return "Reset Flash leader to slash"
	case .Shortcut_Cancel: return "Cancel Flash leader configuration"
	case .Today: return "Jump to today"
	case .Search: return "Search calendar"
	case .New_Event: return "New agenda entry"
	case .Open_Event:
		if control.action.index >= 0 &&
		   control.action.index < len(calendar_ui.events) {
			return fmt.tprintf(
				"Open event %s",
				calendar_ui.events[control.action.index].summary,
			)
		}
		return "Open event"
	case .Focus_Event: return "Show event details"
	case .Focus_Holiday: return "Show holiday details"
	case .Jump_Event: return "Jump to event"
	case .Toggle_Holiday_Country: return "Toggle holiday calendar"
	case .Jump_Holiday: return "Jump to holiday"
	case .Action_Edit: return "Edit focused event"
	case .Action_Open_URL: return "Open focused details URL"
	case .Action_Archive:
		if calendar_ui.navigation_event_index >= 0 &&
		   calendar_ui.navigation_event_index < len(calendar_ui.events) &&
		   calendar_ui.events[calendar_ui.navigation_event_index].source ==
				.EventKit {
			return "Delete focused connected event"
		}
		return "Archive focused event"
	case .Action_Complete: return "Complete focused entry"
	case .Action_Confirm_Proposal: return "Confirm proposed entry fields"
	case .Action_Reject_Proposal: return "Reject proposed entry fields"
	case .Action_Copy_To_Connected:
		return "Copy focused event to the default connected calendar"
	case .Action_Open_In_Apple_Calendar:
		return "Open Apple Calendar for the focused invitation"
	case .Archive_Cancel:
		if calendar_ui.navigation_event_index >= 0 &&
		   calendar_ui.navigation_event_index < len(calendar_ui.events) &&
		   calendar_ui.events[calendar_ui.navigation_event_index].source ==
				.EventKit {
			return "Cancel connected event delete"
		}
		return "Cancel event archive"
	case .Archive_Occurrence:
		if calendar_ui.navigation_event_index >= 0 &&
		   calendar_ui.navigation_event_index < len(calendar_ui.events) &&
		   calendar_ui.events[calendar_ui.navigation_event_index].source ==
				.EventKit {
			return "Delete this connected event occurrence"
		}
		if calendar_ui.navigation_active &&
		   calendar_ui.navigation_kind == .Event &&
		   calendar_ui.navigation_event_index >= 0 &&
		   calendar_ui.navigation_event_index < len(calendar_ui.events) &&
		   calendar_event_is_recurring(
				&calendar_ui.events[calendar_ui.navigation_event_index],
		   ) {
			return "Archive this occurrence"
		}
		return "Archive event"
	case .Archive_Series:
		if calendar_ui.navigation_event_index >= 0 &&
		   calendar_ui.navigation_event_index < len(calendar_ui.events) &&
		   calendar_ui.events[calendar_ui.navigation_event_index].source ==
				.EventKit {
			return "Delete this and future connected event occurrences"
		}
		return "Archive the complete series"
	case .Editor_Field:
		labels := [10]string{
			"Event summary",
			"Event start",
			"Event end",
			"Event location",
			"Event URL",
			"Event categories",
			"Event description",
			"Event time zone",
			"Event alarms",
			"Event recurrence rule",
		}
		if control.action.index >= 0 && control.action.index < len(labels) {
			return labels[control.action.index]
		}
	case .Editor_Important: return "Important event"
	case .Editor_All_Day: return "All-day event"
	case .Editor_Calendar: return "Select the next event calendar"
	case .Editor_Save: return "Save agenda entry"
	case .Editor_Delete: return "Delete event"
	case .Editor_Cancel: return "Cancel event editor"
	case .None:
	}
	return control.name
}

calendar_on_ax_press :: proc "c" (self: Id, command: Sel) -> bool {
	context = runtime.default_context()
	control := calendar_ui_ax_control(self)
	if control == nil {return false}
	calendar_ui_activate_control(control.id)
	return true
}

calendar_on_ax_value :: proc "c" (self: Id, command: Sel) -> Id {
	context = runtime.default_context()
	control := calendar_ui_ax_control(self)
	if control == nil {return nil}
	if control.action.kind == .Editor_Field {
		value := calendar_ui_editor_field_text(control.action.index)
		if value != nil {return nsstring(value^)}
	}
	if control.action.kind == .Editor_Important {
		return calendar_msg_id_bool(
			objc_getClass("NSNumber"),
			sel_registerName("numberWithBool:"),
			calendar_ui.editor_important,
		)
	}
	if control.action.kind == .Editor_All_Day {
		return calendar_msg_id_bool(
			objc_getClass("NSNumber"),
			sel_registerName("numberWithBool:"),
			calendar_ui.editor_all_day,
		)
	}
	if control.action.kind == .Settings_Search {
		return nsstring(calendar_ui.settings_query)
	}
	if control.action.kind == .Command_Palette_Search {
		return nsstring(calendar_ui.palette_query)
	}
	if control.action.kind == .Set_Theme {
		return calendar_msg_id_bool(
			objc_getClass("NSNumber"),
			sel_registerName("numberWithBool:"),
			control.action.theme_id == calendar_ui.theme_id,
		)
	}
	if control.action.kind == .Toggle_Connected_Calendar &&
	   control.action.index >= 0 &&
	   control.action.index < len(calendar_eventkit_calendars) {
		return calendar_msg_id_bool(
			objc_getClass("NSNumber"),
			sel_registerName("numberWithBool:"),
			calendar_connected_calendar_visible(
				calendar_eventkit_calendars[control.action.index].identifier,
			),
		)
	}
	if control.action.kind == .Set_Default_Connected_Calendar &&
	   control.action.index >= 0 &&
	   control.action.index < len(calendar_eventkit_calendars) {
		default_identifier, _ := calendar_connected_default_calendar(
			context.temp_allocator,
		)
		return calendar_msg_id_bool(
			objc_getClass("NSNumber"),
			sel_registerName("numberWithBool:"),
			default_identifier ==
				calendar_eventkit_calendars[control.action.index].identifier,
		)
	}
	if control.action.kind == .Settings_Category {
		return calendar_msg_id_bool(
			objc_getClass("NSNumber"),
			sel_registerName("numberWithBool:"),
			control.action.index == int(calendar_ui.settings_category),
		)
	}
	if control.action.kind == .Configure_Flash {
		return nsstring(calendar_shortcut_display(calendar_ui.flash_leader))
	}
	return nil
}

calendar_on_ax_set_value :: proc "c" (
	self: Id,
	command: Sel,
	value: Id,
) {
	context = runtime.default_context()
	control := calendar_ui_ax_control(self)
	if control == nil {return}
	if control.action.kind == .Settings_Search {
		utf8 := calendar_msg_cstring(value, sel_registerName("UTF8String"))
		if utf8 == nil {return}
		replace := strings.clone(string(utf8))
		delete(calendar_ui.settings_query)
		calendar_ui.settings_query = replace
		calendar_text_focus(.Settings_Search)
		calendar_text_changed(.Settings_Search)
		return
	}
	if control.action.kind == .Command_Palette_Search {
		utf8 := calendar_msg_cstring(value, sel_registerName("UTF8String"))
		if utf8 == nil {return}
		replace := strings.clone(string(utf8))
		delete(calendar_ui.palette_query)
		calendar_ui.palette_query = replace
		calendar_text_focus(.Command_Palette)
		calendar_text_changed(.Command_Palette)
		return
	}
	if control.action.kind != .Editor_Field {return}
	text_value := calendar_ui_editor_field_text(control.action.index)
	if text_value == nil {return}
	utf8 := calendar_msg_cstring(value, sel_registerName("UTF8String"))
	if utf8 == nil {return}
	delete(text_value^)
	text_value^ = strings.clone(string(utf8))
	calendar_text_focus(calendar_text_editor_field(control.action.index))
	calendar_ui.needs_redraw = true
}

calendar_on_ax_children :: proc "c" (self: Id, command: Sel) -> Id {
	return calendar_ui.ax_children
}

calendar_on_ax_is_element :: proc "c" (self: Id, command: Sel) -> bool {
	return false
}

calendar_ui_rebuild_accessibility :: proc() {
	clear(&calendar_ui.ax_bindings)
	if calendar_ui.ax_children != nil {
		msg_void(calendar_ui.ax_children, sel_registerName("release"))
	}
	array := msg_id(objc_getClass("NSMutableArray"), sel_registerName("array"))
	calendar_ui.ax_children = msg_id(array, sel_registerName("retain"))
	element_class := objc_getClass("hw_calendar_AccessibilityElement")
	for &control in calendar_ui.controls {
		if calendar_ui.shortcut_open &&
		   !calendar_ui_is_window_action(control.action.kind) &&
		   control.action.kind != .Shortcut_Record &&
		   control.action.kind != .Shortcut_Save &&
		   control.action.kind != .Shortcut_Reset &&
		   control.action.kind != .Shortcut_Cancel {
			continue
		} else if !calendar_ui.shortcut_open && calendar_ui.settings_open &&
		          !calendar_ui_is_window_action(control.action.kind) &&
		          control.action.kind != .Open_Settings &&
		          control.action.kind != .Settings_Close &&
		          control.action.kind != .Settings_Category &&
		          control.action.kind != .Settings_Search &&
		          control.action.kind != .Set_Theme &&
		          control.action.kind != .Request_Calendar_Access &&
		          control.action.kind != .Toggle_Connected_Calendar &&
		          control.action.kind != .Set_Default_Connected_Calendar &&
		          control.action.kind != .Configure_Flash {
			continue
		} else if !calendar_ui.shortcut_open && !calendar_ui.settings_open &&
		          calendar_ui.archive_modal_open &&
		          !calendar_ui_is_window_action(control.action.kind) &&
		          control.action.kind != .Archive_Cancel &&
		          control.action.kind != .Archive_Occurrence &&
		          control.action.kind != .Archive_Series {
			continue
		} else if !calendar_ui.shortcut_open && !calendar_ui.settings_open &&
		          !calendar_ui.archive_modal_open && calendar_ui.editor_open &&
		   !calendar_ui_is_window_action(control.action.kind) &&
		   control.action.kind != .Editor_Field &&
		   control.action.kind != .Editor_Important &&
		   control.action.kind != .Editor_All_Day &&
		   control.action.kind != .Editor_Calendar &&
		   control.action.kind != .Editor_Save &&
		   control.action.kind != .Editor_Delete &&
		   control.action.kind != .Editor_Cancel {
			continue
		}
		element := msg_id(element_class, sel_registerName("new"))
		role := "AXButton"
	if control.action.kind == .Editor_Field ||
	   control.action.kind == .Settings_Search ||
	   control.action.kind == .Command_Palette_Search {
			role = "AXTextField"
		} else if control.action.kind == .Set_Theme ||
		          control.action.kind == .Settings_Category {
			role = "AXRadioButton"
		}
		msg_void_id(
			element,
			sel_registerName("setAccessibilityParent:"),
			calendar_ui.view,
		)
		msg_void_id(
			element,
			sel_registerName("setAccessibilityRole:"),
			nsstring(role),
		)
		msg_void_id(
			element,
			sel_registerName("setAccessibilityLabel:"),
			nsstring(calendar_ui_ax_label(&control)),
		)
		msg_void_bool(
			element,
			sel_registerName("setAccessibilityEnabled:"),
			true,
		)
		calendar_msg_void_rect(
			element,
			sel_registerName("setAccessibilityFrame:"),
			calendar_ui_ax_screen_rect(control.rect),
		)
		if control.action.kind == .Editor_Field {
			if value := calendar_ui_editor_field_text(control.action.index);
			   value != nil {
				msg_void_id(
					element,
					sel_registerName("setAccessibilityValue:"),
					nsstring(value^),
				)
			}
		} else if control.action.kind == .Settings_Search {
			msg_void_id(
				element,
				sel_registerName("setAccessibilityValue:"),
				nsstring(calendar_ui.settings_query),
			)
		} else if control.action.kind == .Command_Palette_Search {
			msg_void_id(
				element,
				sel_registerName("setAccessibilityValue:"),
				nsstring(calendar_ui.palette_query),
			)
		} else if control.action.kind == .Set_Theme {
			msg_void_id(
				element,
				sel_registerName("setAccessibilityValue:"),
				calendar_msg_id_bool(
					objc_getClass("NSNumber"),
					sel_registerName("numberWithBool:"),
					control.action.theme_id == calendar_ui.theme_id,
				),
			)
		} else if control.action.kind == .Settings_Category {
			msg_void_id(
				element,
				sel_registerName("setAccessibilityValue:"),
				calendar_msg_id_bool(
					objc_getClass("NSNumber"),
					sel_registerName("numberWithBool:"),
					control.action.index == int(calendar_ui.settings_category),
				),
			)
		}
		msg_void_id(array, sel_registerName("addObject:"), element)
		append(&calendar_ui.ax_bindings, Calendar_UI_AX_Binding{
			element = element,
			control_id = control.id,
		})
		msg_void(element, sel_registerName("release"))
	}
}

calendar_ui_header_rect :: proc() -> Calendar_UI_Rect {
	return {
		0,
		calendar_ui.height-CALENDAR_HEADER_HEIGHT,
		calendar_ui.width,
		CALENDAR_HEADER_HEIGHT,
	}
}

calendar_ui_title_rect :: proc() -> Calendar_UI_Rect {
	return {
		160,
		calendar_ui.height-CALENDAR_HEADER_CONTROL_HEIGHT-1,
		360,
		CALENDAR_HEADER_CONTROL_HEIGHT,
	}
}

calendar_ui_window_control_rect_for_height :: proc(
	index: int,
	height: f64,
) -> Calendar_UI_Rect {
	return {
		38*f64(index),
		height-CALENDAR_HEADER_CONTROL_HEIGHT,
		30,
		CALENDAR_HEADER_CONTROL_HEIGHT,
	}
}

calendar_ui_window_control_rect :: proc(index: int) -> Calendar_UI_Rect {
	return calendar_ui_window_control_rect_for_height(index, calendar_ui.height)
}

calendar_ui_window_icon_rect :: proc(index: int) -> Calendar_UI_Rect {
	control := calendar_ui_window_control_rect(index)
	return {
		control.x+5,
		control.y+5,
		20,
		20,
	}
}

calendar_ui_settings_rect :: proc() -> Calendar_UI_Rect {
	return calendar_ui_window_control_rect(3)
}

calendar_ui_settings_icon_rect :: proc() -> Calendar_UI_Rect {
	control := calendar_ui_settings_rect()
	return {control.x+6, control.y+6, 18, 18}
}

calendar_ui_is_window_action :: proc(action: Calendar_UI_Action) -> bool {
	return action == .Window_Close ||
	       action == .Window_Minimize ||
	       action == .Window_Zoom
}

calendar_ui_today_rect :: proc() -> Calendar_UI_Rect {
	return {
		calendar_ui.width-270,
		calendar_ui.height-CALENDAR_HEADER_CONTROL_HEIGHT-1,
		76,
		CALENDAR_HEADER_CONTROL_HEIGHT,
	}
}

calendar_ui_search_rect :: proc() -> Calendar_UI_Rect {
	return {
		calendar_ui.width-186,
		calendar_ui.height-CALENDAR_HEADER_CONTROL_HEIGHT-1,
		88,
		CALENDAR_HEADER_CONTROL_HEIGHT,
	}
}

calendar_ui_new_rect :: proc() -> Calendar_UI_Rect {
	return {
		calendar_ui.width-90,
		calendar_ui.height-CALENDAR_HEADER_CONTROL_HEIGHT-1,
		90,
		CALENDAR_HEADER_CONTROL_HEIGHT,
	}
}

calendar_ui_visible_day_count_for_height :: proc(height: f64) -> int {
	available := height-CALENDAR_HEADER_HEIGHT-CALENDAR_DAY_TOP_GAP-
	             CALENDAR_CONTENT_BOTTOM
	return max(1, int(available/CALENDAR_DAY_ROW_PITCH))
}

calendar_ui_visible_day_count :: proc() -> int {
	return calendar_ui_visible_day_count_for_height(calendar_ui.height)
}

calendar_ui_content_rects_for_size :: proc(
	width, height: f64,
) -> (calendar, details: Calendar_UI_Rect) {
	calendar_width := (
		width-CALENDAR_LAYOUT_MARGIN*2-CALENDAR_PANEL_GAP
	)/2
	calendar = {
		CALENDAR_LAYOUT_MARGIN,
		CALENDAR_CONTENT_BOTTOM,
		calendar_width,
		height-CALENDAR_HEADER_HEIGHT-CALENDAR_CONTENT_BOTTOM-
		CALENDAR_LAYOUT_MARGIN,
	}
	details = {
		calendar.x+calendar.w+CALENDAR_PANEL_GAP,
		CALENDAR_CONTENT_BOTTOM,
		width-calendar.x-calendar.w-CALENDAR_PANEL_GAP-
		CALENDAR_LAYOUT_MARGIN,
		calendar.h,
	}
	return
}

calendar_ui_calendar_content_rect :: proc() -> Calendar_UI_Rect {
	calendar, _ := calendar_ui_content_rects_for_size(
		calendar_ui.width,
		calendar_ui.height,
	)
	return calendar
}

calendar_ui_details_rect :: proc() -> Calendar_UI_Rect {
	_, details := calendar_ui_content_rects_for_size(calendar_ui.width, calendar_ui.height)
	return details
}

calendar_ui_action_rect_for_width :: proc(index: int, view_width: f64) -> Calendar_UI_Rect {
	width := (
		view_width-CALENDAR_LAYOUT_MARGIN*2-CALENDAR_ACTION_BAR_GAP*5
	)/6
	return {
		CALENDAR_LAYOUT_MARGIN+f64(index)*(width+CALENDAR_ACTION_BAR_GAP),
		CALENDAR_ACTION_BAR_BOTTOM,
		width,
		CALENDAR_ACTION_BAR_HEIGHT,
	}
}

calendar_ui_action_rect :: proc(index: int) -> Calendar_UI_Rect {
	return calendar_ui_action_rect_for_width(index, calendar_ui.width)
}

calendar_ui_archive_modal_rect :: proc() -> Calendar_UI_Rect {
	width := min(560.0, calendar_ui.width-48)
	height := 210.0
	return {
		(calendar_ui.width-width)/2,
		(calendar_ui.height-height)/2,
		width,
		height,
	}
}

calendar_ui_archive_button_rect :: proc(index, count: int) -> Calendar_UI_Rect {
	modal := calendar_ui_archive_modal_rect()
	gap := 8.0
	width := (modal.w-48-gap*f64(count-1))/f64(count)
	return {
		modal.x+24+f64(index)*(width+gap),
		modal.y+24,
		width,
		34,
	}
}

calendar_number_slot_for_key_code :: proc(key_code: uint) -> (int, bool) {
	key_codes := [8]uint{18, 19, 20, 21, 23, 22, 26, 28}
	for candidate, index in key_codes {
		if candidate == key_code {return index, true}
	}
	return -1, false
}

calendar_number_digit_for_key_code :: proc(key_code: uint) -> (int, bool) {
	slot, found := calendar_number_slot_for_key_code(key_code)
	if !found {return 0, false}
	return slot+1, true
}

calendar_main_action_for_code :: proc(
	section, action_digit: int,
) -> Calendar_UI_Action {
	if section != 1 {return .None}
	switch action_digit {
	case 1: return .Action_Edit
	case 2: return .Action_Open_URL
	case 3: return .Action_Archive
	case 4: return .Action_Complete
	case 5: return .Action_Confirm_Proposal
	case 6: return .Action_Reject_Proposal
	}
	return .None
}

calendar_number_time_ms :: proc() -> i64 {
	return time.to_unix_nanoseconds(time.now()) / 1_000_000
}

calendar_clear_number_prefix :: proc() {
	calendar_ui.number_prefix = 0
	calendar_ui.number_prefix_deadline_ms = 0
}

calendar_expire_number_prefix_at :: proc(now_ms: i64) -> bool {
	if calendar_ui.number_prefix == 0 ||
	   now_ms < calendar_ui.number_prefix_deadline_ms {
		return false
	}
	calendar_clear_number_prefix()
	calendar_ui.needs_redraw = true
	return true
}

calendar_consume_main_action_digit_at :: proc(
	digit: int,
	now_ms: i64,
) -> (Calendar_UI_Action, bool) {
	_ = calendar_expire_number_prefix_at(now_ms)
	if calendar_ui.number_prefix == 0 {
		if digit != 1 {return .None, false}
		calendar_ui.number_prefix = digit
		calendar_ui.number_prefix_deadline_ms = now_ms+1_000
		calendar_ui.needs_redraw = true
		return .None, true
	}
	section := calendar_ui.number_prefix
	calendar_clear_number_prefix()
	calendar_ui.needs_redraw = true
	return calendar_main_action_for_code(section, digit), true
}

calendar_archive_action_for_slot :: proc(
	recurring: bool,
	slot: int,
) -> Calendar_UI_Action {
	if recurring {
		switch slot {
		case 0: return .Archive_Occurrence
		case 1: return .Archive_Series
		case 2: return .Archive_Cancel
		}
		return .None
	}
	switch slot {
	case 0: return .Archive_Occurrence
	case 1: return .Archive_Cancel
	}
	return .None
}

calendar_ui_day_rect :: proc(index: int) -> Calendar_UI_Rect {
	content := calendar_ui_calendar_content_rect()
	return {
		content.x,
		calendar_ui.height-CALENDAR_HEADER_HEIGHT-CALENDAR_DAY_TOP_GAP -
		CALENDAR_DAY_ROW_PITCH*f64(index)-CALENDAR_DAY_ROW_HEIGHT,
		content.w,
		CALENDAR_DAY_ROW_HEIGHT,
	}
}

calendar_ui_event_rect :: proc(
	day_rect: Calendar_UI_Rect,
	index: int,
	visible_count: int,
) -> Calendar_UI_Rect {
	count := max(1, min(3, visible_count))
	left := day_rect.x+178
	right := day_rect.x+day_rect.w-12
	gap := 6.0
	width := (right-left-gap*f64(count-1))/f64(count)
	return {
		left+f64(index)*(width+gap),
		day_rect.y+3,
		width,
		day_rect.h-6,
	}
}

calendar_ui_reload_data :: proc(request_connected := true) {
	calendar_events_destroy(&calendar_ui.events)
	calendar_occurrences_destroy(&calendar_ui.occurrences)
	clear(&calendar_ui.holiday_occurrences)
	calendar_ui.events = make([dynamic]Calendar_Event)
	calendar_ui.occurrences = make([dynamic]Calendar_Occurrence)
	entries := agenda_entries_list("", "", "")
	defer agenda_entries_destroy(&entries)
	now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
	anchor_days := ical_days_from_civil(now.year, now.month, now.day) +
	               i64(calendar_ui.day_offset)
	range_start := ical_date_time_from_stamp((anchor_days-7)*86400, true)
	range_end := ical_date_time_from_stamp((anchor_days+60)*86400, true)
	for &entry in entries {
		if entry.state != "active" {continue}
		stamp_text := entry.start_at
		if len(stamp_text) == 0 {stamp_text = entry.due_at}
		has_confirmed_time := len(stamp_text) > 0
		stamp, parsed_stamp := strconv.parse_i64(stamp_text)
		start := now
		if parsed_stamp {start = ical_date_time_from_stamp(stamp, true)} else if parsed, ok := ical_parse_date_time(stamp_text); ok {start = parsed}
		end := start
		if end_stamp, ok := strconv.parse_i64(entry.end_at); ok {end = ical_date_time_from_stamp(end_stamp, true)} else if parsed, ok := ical_parse_date_time(entry.end_at); ok {end = parsed}
		event := Calendar_Event{
			row_id = entry.id,
			uid = fmt.tprintf("agenda-%d", entry.id),
			summary = strings.clone(entry.original_text),
			location = strings.clone(entry.location),
			url = strings.clone(entry.source_url),
			dtstart = ical_format_date_time(start),
			dtend = ical_format_date_time(end),
			sequence = entry.revision,
		}
		append(&calendar_ui.events, event)
		if has_confirmed_time {
			calendar_append_occurrence(&calendar_ui.occurrences, &calendar_ui.events[len(calendar_ui.events)-1], len(calendar_ui.events)-1, start, end, "")
		}
	}
	calendar_ui.holiday_occurrences = calendar_holiday_occurrences_expand(
		calendar_ui.holiday_countries[:],
		range_start,
		range_end,
	)
}

calendar_ui_begin_flash :: proc() {
	if calendar_ui.shortcut_open {return}
	targets := make(
		[dynamic]flash.Target,
		0,
		len(calendar_ui.controls),
		context.temp_allocator,
	)
	for control in calendar_ui.controls {
		if calendar_ui.settings_open &&
		   !calendar_ui_is_window_action(control.action.kind) &&
		   control.action.kind != .Open_Settings &&
		   control.action.kind != .Settings_Close &&
		   control.action.kind != .Settings_Category &&
		   control.action.kind != .Settings_Search &&
		   control.action.kind != .Set_Theme &&
		   control.action.kind != .Request_Calendar_Access &&
		   control.action.kind != .Toggle_Connected_Calendar &&
		   control.action.kind != .Set_Default_Connected_Calendar &&
		   control.action.kind != .Configure_Flash {
			continue
		} else if !calendar_ui.settings_open &&
		          calendar_ui.archive_modal_open &&
		   !calendar_ui_is_window_action(control.action.kind) &&
		   control.action.kind != .Archive_Cancel &&
		   control.action.kind != .Archive_Occurrence &&
		   control.action.kind != .Archive_Series {
			continue
		}
		if !calendar_ui.settings_open && calendar_ui.editor_open &&
		   !calendar_ui_is_window_action(control.action.kind) &&
		   control.action.kind != .Editor_Field &&
		   control.action.kind != .Editor_Important &&
		   control.action.kind != .Editor_All_Day &&
		   control.action.kind != .Editor_Calendar &&
		   control.action.kind != .Editor_Save &&
		   control.action.kind != .Editor_Delete &&
		   control.action.kind != .Editor_Cancel {
			continue
		}
		append(&targets, flash.Target{
			id = flash.Target_ID(control.id),
			label = control.label,
			rect = {
				control.rect.x,
				control.rect.y,
				control.rect.w,
				control.rect.h,
			},
			anchor = .Top_Left,
		})
	}
	_ = flash.begin(&calendar_ui.flash, targets[:])
	calendar_ui.needs_redraw = true
}

calendar_event_palette_title :: proc(event: ^Calendar_Event) -> string {
	return event.summary
}

calendar_holiday_kind_label :: proc(kind: Calendar_Holiday_Kind) -> string {
	switch kind {
	case .State_Holiday: return "ŠTÁTNY SVIATOK"
	case .Public_Holiday: return "SVIATOK"
	case .Memorial_Day: return "PAMÄTNÝ DEŇ"
	case .Invalid:
	}
	return "SVIATOK"
}

calendar_ui_clear_holiday_promotion :: proc() {
	calendar_ui.promoted_holiday_active = false
	calendar_ui.promoted_holiday_country_index = -1
	calendar_ui.promoted_holiday_definition_index = -1
	calendar_ui.promoted_holiday_days = 0
}

calendar_ui_clear_navigation_selection :: proc() {
	calendar_ui.navigation_active = false
	calendar_ui.navigation_event_index = -1
	calendar_ui.navigation_start_stamp = 0
	calendar_ui.navigation_start_is_date = false
	calendar_ui.navigation_holiday_country_index = -1
	calendar_ui.navigation_holiday_definition_index = -1
	calendar_ui.details_scroll = 0
}

calendar_navigation_item_stamp :: proc(item: Calendar_Navigation_Item) -> i64 {
	if item.kind == .Event {return ical_date_time_stamp(item.event.start)}
	return ical_date_time_stamp(item.holiday.date)
}

calendar_navigation_item_compare :: proc(
	a, b: Calendar_Navigation_Item,
) -> int {
	a_stamp := calendar_navigation_item_stamp(a)
	b_stamp := calendar_navigation_item_stamp(b)
	if a_stamp < b_stamp {return -1}
	if a_stamp > b_stamp {return 1}
	if a.kind < b.kind {return -1}
	if a.kind > b.kind {return 1}
	if a.kind == .Event {
		if a.event.event_index < b.event.event_index {return -1}
		if a.event.event_index > b.event.event_index {return 1}
		return 0
	}
	return calendar_holiday_occurrence_compare(a.holiday, b.holiday)
}

calendar_navigation_item_matches_selection :: proc(
	item: Calendar_Navigation_Item,
) -> bool {
	if !calendar_ui.navigation_active || item.kind != calendar_ui.navigation_kind {
		return false
	}
	if calendar_navigation_item_stamp(item) != calendar_ui.navigation_start_stamp {
		return false
	}
	if item.kind == .Event {
		return item.event.event_index == calendar_ui.navigation_event_index
	}
	return item.holiday.country_index == calendar_ui.navigation_holiday_country_index &&
	       item.holiday.definition_index ==
			calendar_ui.navigation_holiday_definition_index
}

calendar_ui_set_navigation_selection :: proc(item: Calendar_Navigation_Item) {
	calendar_ui.navigation_active = true
	calendar_ui.details_scroll = 0
	calendar_ui.navigation_kind = item.kind
	calendar_ui.navigation_start_stamp = calendar_navigation_item_stamp(item)
	calendar_ui.navigation_start_is_date =
		item.kind == .Holiday || item.event.start.is_date
	if item.kind == .Event {
		calendar_ui.navigation_event_index = item.event.event_index
		calendar_ui.navigation_holiday_country_index = -1
		calendar_ui.navigation_holiday_definition_index = -1
		return
	}
	calendar_ui.navigation_event_index = -1
	calendar_ui.navigation_holiday_country_index = item.holiday.country_index
	calendar_ui.navigation_holiday_definition_index = item.holiday.definition_index
}

calendar_ui_focus_event :: proc(
	event_index: int,
	start_stamp: i64,
	start_is_date: bool,
) {
	if event_index < 0 || event_index >= len(calendar_ui.events) {return}
	calendar_ui_clear_holiday_promotion()
	calendar_ui.navigation_active = true
	calendar_ui.navigation_kind = .Event
	calendar_ui.navigation_event_index = event_index
	calendar_ui.navigation_start_stamp = start_stamp
	calendar_ui.navigation_start_is_date = start_is_date
	calendar_ui.navigation_holiday_country_index = -1
	calendar_ui.navigation_holiday_definition_index = -1
	calendar_ui.details_scroll = 0
}

calendar_ui_focus_holiday :: proc(
	country_index, definition_index: int,
	date_stamp: i64,
) {
	if country_index < 0 || country_index >= len(calendar_ui.holiday_countries) {
		return
	}
	calendar_ui_clear_holiday_promotion()
	calendar_ui.navigation_active = true
	calendar_ui.navigation_kind = .Holiday
	calendar_ui.navigation_event_index = -1
	calendar_ui.navigation_start_stamp = date_stamp
	calendar_ui.navigation_start_is_date = true
	calendar_ui.navigation_holiday_country_index = country_index
	calendar_ui.navigation_holiday_definition_index = definition_index
	calendar_ui.details_scroll = 0
}

calendar_ui_details_url :: proc() -> string {
	if !calendar_ui.navigation_active {return ""}
	if calendar_ui.navigation_kind == .Event {
		index := calendar_ui.navigation_event_index
		if index >= 0 && index < len(calendar_ui.events) {
			return calendar_ui.events[index].url
		}
		return ""
	}
	occurrence := Calendar_Holiday_Occurrence{
		country_index = calendar_ui.navigation_holiday_country_index,
		definition_index = calendar_ui.navigation_holiday_definition_index,
	}
	country, _, found := calendar_holiday_definition_for_occurrence(occurrence)
	return country.source_url if found else ""
}

calendar_ui_open_url :: proc(value: string) {
	if len(value) == 0 {return}
	url := msg_id_id(
		objc_getClass("NSURL"),
		sel_registerName("URLWithString:"),
		nsstring(value),
	)
	if url == nil {return}
	workspace := msg_id(
		objc_getClass("NSWorkspace"),
		sel_registerName("sharedWorkspace"),
	)
	if workspace != nil {msg_void_id(workspace, sel_registerName("openURL:"), url)}
}

calendar_ui_open_apple_calendar :: proc() {
	workspace := msg_id(
		objc_getClass("NSWorkspace"),
		sel_registerName("sharedWorkspace"),
	)
	if workspace == nil {return}
	launch := transmute(proc "c" (Id, Sel, Id) -> bool)objc_send_address
	_ = launch(
		workspace,
		sel_registerName("launchApplication:"),
		nsstring("Calendar"),
	)
}

calendar_action_available :: proc(
	action: Calendar_UI_Action,
	navigation_active: bool,
	kind: Calendar_Navigation_Item_Kind,
	event_available, has_url: bool,
) -> bool {
	if !navigation_active {return false}
	#partial switch action {
	case .Action_Edit, .Action_Archive, .Action_Complete:
		return kind == .Event && event_available
	case .Action_Open_URL:
		return has_url
	case:
	}
	return false
}

calendar_ui_action_available :: proc(action: Calendar_UI_Action) -> bool {
	available := calendar_action_available(
		action,
		calendar_ui.navigation_active,
		calendar_ui.navigation_kind,
		calendar_ui.navigation_event_index >= 0 &&
		calendar_ui.navigation_event_index < len(calendar_ui.events),
		len(calendar_ui_details_url()) > 0,
	)
	if action == .Action_Copy_To_Connected {
		return false
	}
	if action == .Action_Open_In_Apple_Calendar {
		return false
	}
	if action == .Action_Confirm_Proposal || action == .Action_Reject_Proposal {
		if !calendar_ui.navigation_active || calendar_ui.navigation_kind != .Event ||
		   calendar_ui.navigation_event_index < 0 || calendar_ui.navigation_event_index >= len(calendar_ui.events) {return false}
		event := &calendar_ui.events[calendar_ui.navigation_event_index]
		proposal, found := agenda_proposal_pending_for_entry(event.row_id, context.temp_allocator)
		if found {agenda_proposal_destroy(&proposal, context.temp_allocator)}
		return found
	}
	if available && (action == .Action_Edit || action == .Action_Archive) &&
	   calendar_ui.navigation_kind == .Event &&
	   calendar_ui.navigation_event_index >= 0 &&
	   calendar_ui.navigation_event_index < len(calendar_ui.events) {
		event := &calendar_ui.events[calendar_ui.navigation_event_index]
		if event.source == .EventKit {return event.writable}
	}
	return available
}

calendar_ui_selected_occurrence :: proc() -> (^Calendar_Occurrence, bool) {
	if !calendar_ui.navigation_active ||
	   calendar_ui.navigation_kind != .Event {
		return nil, false
	}
	for &occurrence in calendar_ui.occurrences {
		if occurrence.event_index == calendar_ui.navigation_event_index &&
		   ical_date_time_stamp(occurrence.start) ==
				calendar_ui.navigation_start_stamp {
			return &occurrence, true
		}
	}
	return nil, false
}

calendar_event_is_recurring :: proc(event: ^Calendar_Event) -> bool {
	if event == nil {return false}
	if event.source == .EventKit {return event.connected_recurring}
	for &candidate in calendar_ui.events {
		if candidate.uid != event.uid || len(candidate.recurrence_id) > 0 {
			continue
		}
		if len(candidate.rrule) > 0 {return true}
		document, component, parsed := calendar_event_component(
			&candidate,
			context.temp_allocator,
		)
		if !parsed {
			ical_document_destroy(&document, context.temp_allocator)
			return false
		}
		has_rdates := len(calendar_property_value(component, "RDATE")) > 0
		ical_document_destroy(&document, context.temp_allocator)
		return has_rdates
	}
	return false
}

calendar_ui_archive_modal_close :: proc() {
	calendar_ui.archive_modal_open = false
	flash.cancel(&calendar_ui.flash)
	delete(calendar_ui.archive_error)
	calendar_ui.archive_error = ""
	calendar_ui.needs_redraw = true
}

calendar_ui_archive_modal_open :: proc() {
	if !calendar_ui_action_available(.Action_Archive) {return}
	delete(calendar_ui.archive_error)
	calendar_ui.archive_error = ""
	calendar_ui.archive_modal_open = true
	flash.cancel(&calendar_ui.flash)
	command_palette.close(&calendar_ui.palette)
	calendar_ui.needs_redraw = true
}

calendar_ui_archive_occurrence :: proc() -> bool {
	occurrence, found := calendar_ui_selected_occurrence()
	if !found {return false}
	event := &calendar_ui.events[occurrence.event_index]
	if len(event.recurrence_id) > 0 &&
	   event.recurrence_id == occurrence.recurrence_id {
		return calendar_event_set_archived(event.row_id, true)
	}
	categories := []string{event.categories}
	input := Calendar_Event_Input{
		schema_version = 1,
		uid = event.uid,
		recurrence_id = occurrence.recurrence_id,
		summary = event.summary,
		description = event.description,
		location = event.location,
		url = event.url,
		categories = categories,
		important = event.important,
		dtstart = ical_format_date_time(
			occurrence.start,
			context.temp_allocator,
		),
		dtend = ical_format_date_time(
			occurrence.end,
			context.temp_allocator,
		),
		sequence = event.sequence+1,
	}
	contents, valid := calendar_cli_event_document(&input)
	if !valid {return false}
	defer delete(contents)
	document := ical_parse(contents)
	defer ical_document_destroy(&document)
	for &component in document.components {
		if !calendar_project_components(event.document_id, &component) {
			return false
		}
	}
	return calendar_event_identity_set_archived(
		event.uid,
		occurrence.recurrence_id,
		true,
	)
}

calendar_ui_archive_confirm :: proc(series: bool) {
	if !calendar_ui_action_available(.Action_Archive) {return}
	event := &calendar_ui.events[calendar_ui.navigation_event_index]
	updated, code := agenda_entry_set_state(event.row_id, event.sequence, "dismissed")
	if len(code) > 0 {
		delete(calendar_ui.archive_error)
		calendar_ui.archive_error = strings.clone("THE ENTRY COULD NOT BE DISMISSED")
		calendar_ui.needs_redraw = true
		return
	}
	agenda_entry_destroy(&updated)
	calendar_ui_archive_modal_close()
	calendar_ui_clear_navigation_selection()
	calendar_ui_reload_data()
	calendar_notification_reconcile()
}

calendar_ui_navigation_selection_item :: proc() -> (
	Calendar_Navigation_Item,
	bool,
) {
	if !calendar_ui.navigation_active {return {}, false}
	item := Calendar_Navigation_Item{kind = calendar_ui.navigation_kind}
	if item.kind == .Event {
		item.event.event_index = calendar_ui.navigation_event_index
		item.event.start = ical_date_time_from_stamp(
			calendar_ui.navigation_start_stamp,
			calendar_ui.navigation_start_is_date,
		)
	} else {
		item.holiday.country_index = calendar_ui.navigation_holiday_country_index
		item.holiday.definition_index =
			calendar_ui.navigation_holiday_definition_index
		item.holiday.date = ical_date_time_from_stamp(
			calendar_ui.navigation_start_stamp,
			true,
		)
	}
	return item, true
}

calendar_navigation_items :: proc(
	events: []Calendar_Event,
	countries: []Calendar_Holiday_Country,
	range_start, range_end: ICal_Date_Time,
	allocator := context.allocator,
) -> [dynamic]Calendar_Navigation_Item {
	items := make([dynamic]Calendar_Navigation_Item, allocator)
	occurrences, _ := calendar_expand_events(
		events,
		range_start,
		range_end,
		1_000,
		allocator,
	)
	for occurrence in occurrences {
		append(&items, Calendar_Navigation_Item{kind = .Event, event = occurrence})
	}
	for holiday in calendar_holiday_occurrences_expand(
		countries,
		range_start,
		range_end,
		allocator,
	) {
		append(&items, Calendar_Navigation_Item{kind = .Holiday, holiday = holiday})
	}
	sort.merge_sort_proc(items[:], calendar_navigation_item_compare)
	return items
}

calendar_navigation_find :: proc(
	items: []Calendar_Navigation_Item,
	direction: Calendar_Navigation_Direction,
	initial_day_stamp: i64,
	selection: ^Calendar_Navigation_Item = nil,
) -> (Calendar_Navigation_Item, bool) {
	if direction == .Next {
		for item in items {
			if selection != nil {
				if calendar_navigation_item_compare(item, selection^) <= 0 {continue}
			} else if calendar_navigation_item_stamp(item) < initial_day_stamp {
				continue
			}
			return item, true
		}
		return {}, false
	}
	for index := len(items)-1; index >= 0; index -= 1 {
		item := items[index]
		if selection != nil {
			if calendar_navigation_item_compare(item, selection^) >= 0 {continue}
		} else if calendar_navigation_item_stamp(item) >= initial_day_stamp {
			continue
		}
		return item, true
	}
	return {}, false
}

calendar_ui_navigate :: proc(direction: Calendar_Navigation_Direction) {
	now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
	anchor_days := ical_days_from_civil(now.year, now.month, now.day) +
	               i64(calendar_ui.day_offset)
	initial_day_stamp := anchor_days*86400
	reference_stamp := initial_day_stamp
	selection, has_selection := calendar_ui_navigation_selection_item()
	if calendar_ui.navigation_active {
		reference_stamp = calendar_ui.navigation_start_stamp
	}
	for span_days := i64(366); span_days <= 366*128; span_days *= 2 {
		range_start := reference_stamp
		range_end := reference_stamp+span_days*86400
		if direction == .Previous {
			range_start = reference_stamp-span_days*86400
			range_end = reference_stamp
			if calendar_ui.navigation_active {range_end += 86400}
		}
		items := calendar_navigation_items(
			calendar_ui.events[:],
			calendar_ui.holiday_countries[:],
			ical_date_time_from_stamp(range_start, true),
			ical_date_time_from_stamp(range_end, true),
			context.temp_allocator,
		)
		item, found := calendar_navigation_find(
			items[:],
			direction,
			initial_day_stamp,
			&selection if has_selection else nil,
		)
		if !found {continue}
		calendar_ui_clear_holiday_promotion()
		calendar_ui_set_navigation_selection(item)
		target_days := calendar_navigation_item_stamp(item)/86400
		calendar_ui.day_offset = int(target_days-anchor_days) +
		                         calendar_ui.day_offset
		calendar_ui_reload_data()
		calendar_ui.needs_redraw = true
		return
	}
}

calendar_ui_set_palette_query :: proc(value: string) -> bool {
	search_error := command_palette.set_query(&calendar_ui.palette, value)
	if search_error != .None {
		fmt.eprintln("[hw_calendar] command palette rejected invalid UTF-8")
		return false
	}
	copy := strings.clone(value)
	delete(calendar_ui.palette_query)
	calendar_ui.palette_query = copy
	return true
}

CALENDAR_PALETTE_FOCUSED_EVENT :: command_palette.Context_Mask(1 << 0)
CALENDAR_PALETTE_FOCUSED_URL :: command_palette.Context_Mask(1 << 1)
CALENDAR_PALETTE_EDITOR :: command_palette.Context_Mask(1 << 2)
CALENDAR_PALETTE_EDITOR_EXISTING :: command_palette.Context_Mask(1 << 3)
CALENDAR_PALETTE_ARCHIVE :: command_palette.Context_Mask(1 << 4)
CALENDAR_PALETTE_ARCHIVE_RECURRING :: command_palette.Context_Mask(1 << 5)
CALENDAR_PALETTE_SETTINGS :: command_palette.Context_Mask(1 << 6)
CALENDAR_PALETTE_THEME_BASE :: 8

calendar_palette_active_context :: proc() -> command_palette.Context_Mask {
	bits := u64(0)
	if calendar_ui.navigation_active &&
	   calendar_ui.navigation_kind == .Event {
		bits |= u64(CALENDAR_PALETTE_FOCUSED_EVENT)
	}
	if len(calendar_ui_details_url()) > 0 {
		bits |= u64(CALENDAR_PALETTE_FOCUSED_URL)
	}
	if calendar_ui.editor_open {
		bits |= u64(CALENDAR_PALETTE_EDITOR)
		if calendar_ui.editor_event_index >= 0 {
			bits |= u64(CALENDAR_PALETTE_EDITOR_EXISTING)
		}
	}
	if calendar_ui.archive_modal_open {
		bits |= u64(CALENDAR_PALETTE_ARCHIVE)
		if calendar_ui.navigation_event_index >= 0 &&
		   calendar_ui.navigation_event_index < len(calendar_ui.events) &&
		   calendar_event_is_recurring(
				&calendar_ui.events[calendar_ui.navigation_event_index],
		   ) {
			bits |= u64(CALENDAR_PALETTE_ARCHIVE_RECURRING)
		}
	}
	if calendar_ui.settings_open {
		bits |= u64(CALENDAR_PALETTE_SETTINGS)
	}
	bits |= u64(1) << uint(CALENDAR_PALETTE_THEME_BASE+int(calendar_ui.theme_id))
	return command_palette.Context_Mask(bits)
}

calendar_palette_append :: proc(
	entries: ^[dynamic]command_palette.Entry,
	action: Calendar_App_Action,
	title, subtitle, category: string,
	keywords: []string = nil,
	contexts := command_palette.Context_Condition{},
	unavailable_reason := "",
) {
	append(&calendar_ui.palette_actions, action)
	append(entries, command_palette.Entry{
		id = command_palette.Entry_ID(len(calendar_ui.palette_actions)),
		title = title,
		subtitle = subtitle,
		category = category,
		keywords = keywords,
		contexts = contexts,
		unavailable_reason = unavailable_reason,
	})
}

calendar_ui_open_palette :: proc() {
	if command_palette.is_open(&calendar_ui.palette) {
		command_palette.close(&calendar_ui.palette)
		calendar_ui.palette_query = ""
		clear(&calendar_ui.palette_actions)
		if calendar_ui.text_previous_focus_valid {
			target := calendar_text_target(
				calendar_text_field(calendar_ui.text_previous_focus.field),
			)
			if target != nil {
				text_input.restore_focus(
					&calendar_ui.input_state,
					calendar_ui.text_previous_focus,
					target^,
				)
			}
		} else if calendar_text_active_field() == .Command_Palette {
			_ = calendar_text_blur()
		}
		calendar_ui.text_previous_focus_valid = false
		calendar_ui.needs_redraw = true
		return
	}
	entries := make(
		[dynamic]command_palette.Entry,
		context.temp_allocator,
	)
	clear(&calendar_ui.palette_actions)
	calendar_palette_append(
		&entries,
		{kind = .Today},
		"Today",
		"Jump to the current date",
		"Command",
		[]string{"jump", "current", "date"},
	)
	calendar_palette_append(
		&entries,
		{kind = .New_Event},
		"New agenda entry",
		"Open the agenda entry editor",
		"Command",
		[]string{"create", "calendar"},
		{none = CALENDAR_PALETTE_EDITOR | CALENDAR_PALETTE_ARCHIVE},
		"Close the active event dialog first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Open_Settings},
		"Open Settings",
		"Search and configure application settings",
		"Command",
		[]string{"preferences", "configuration", "gear"},
		{none = CALENDAR_PALETTE_SETTINGS},
		"Settings is already open",
	)
	calendar_palette_append(
		&entries,
		{kind = .Configure_Flash},
		"Configure leader key for Flash",
		fmt.tprintf(
			"Current shortcut: %s",
			calendar_shortcut_display(calendar_ui.flash_leader),
		),
		"Shortcut",
		[]string{"keyboard", "shortcut", "leader", "jump", "navigation"},
	)
	for id in calendar_theme_ids() {
		theme := calendar_theme(id)
		theme_bit := command_palette.Context_Mask(
			u64(1) << uint(CALENDAR_PALETTE_THEME_BASE+int(id)),
		)
		calendar_palette_append(
			&entries,
			{kind = .Set_Theme, theme_id = id},
			calendar_theme_command_title(id),
			theme.dark ? "Dark interface theme" : "Light interface theme",
			"Theme",
			[]string{
				"appearance",
				"style",
				theme.name,
				theme.storage_id,
				theme.dark ? "dark" : "light",
			},
			{none = theme_bit},
			"Current theme",
		)
	}
	calendar_palette_append(
		&entries,
		{kind = .Action_Edit},
		"Edit focused entry",
		"Open the focused agenda entry in the editor",
		"Agenda action",
		[]string{"change", "update"},
		{all = CALENDAR_PALETTE_FOCUSED_EVENT},
		"Focus an event first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Action_Open_URL},
		"Open focused URL",
		"Open the URL from the focused event or holiday",
		"Event action",
		[]string{"link", "browser"},
		{all = CALENDAR_PALETTE_FOCUSED_URL},
		"The focused item has no URL",
	)
	calendar_palette_append(
		&entries,
		{kind = .Action_Archive},
		"Dismiss focused entry",
		"Hide the focused entry from the active agenda",
		"Agenda action",
		[]string{"remove", "hide"},
		{all = CALENDAR_PALETTE_FOCUSED_EVENT},
		"Focus an event first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Action_Complete},
		"Complete focused entry",
		"Complete the focused entry or advance its recurrence",
		"Agenda action",
		[]string{"done", "finish", "advance"},
		{all = CALENDAR_PALETTE_FOCUSED_EVENT},
		"Focus an entry first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Action_Confirm_Proposal},
		"Confirm focused proposal",
		"Apply the pending structured interpretation",
		"Agenda action",
		[]string{"proposal", "interpretation", "approve"},
		{all = CALENDAR_PALETTE_FOCUSED_EVENT},
		"Focus an entry with a pending proposal first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Action_Reject_Proposal},
		"Reject focused proposal",
		"Discard the pending structured interpretation",
		"Agenda action",
		[]string{"proposal", "interpretation", "discard"},
		{all = CALENDAR_PALETTE_FOCUSED_EVENT},
		"Focus an entry with a pending proposal first",
	)
	when false {calendar_palette_append(
		&entries,
		{kind = .Action_Copy_To_Connected},
		"Copy focused event to connected calendar",
		"Create an EventKit event in the default writable calendar",
		"Event action",
		[]string{"copy", "connected", "eventkit", "calendar"},
		{all = CALENDAR_PALETTE_FOCUSED_EVENT},
		"Focus a local event and configure a default calendar first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Action_Open_In_Apple_Calendar},
		"Open invitation in Apple Calendar",
		"Delegate invitation actions that EventKit cannot perform reliably",
		"Event action",
		[]string{"invitation", "attendee", "response", "apple calendar"},
		{all = CALENDAR_PALETTE_FOCUSED_EVENT},
		"Focus a connected invitation first",
	)}
	calendar_palette_append(
		&entries,
		{kind = .Editor_Save},
		"Save entry",
		"Commit the active agenda entry editor",
		"Dialog action",
		nil,
		{all = CALENDAR_PALETTE_EDITOR},
		"Open the event editor first",
	)
	when false {calendar_palette_append(
		&entries,
		{kind = .Editor_Calendar},
		"Select next event calendar",
		"Select local storage or a writable connected calendar",
		"Dialog action",
		[]string{"calendar", "move", "destination", "account"},
		{all = CALENDAR_PALETTE_EDITOR},
		"Open the event editor first",
	)}
	calendar_palette_append(
		&entries,
		{kind = .Editor_All_Day},
		"Toggle all-day entry",
		"Convert the active editor dates between all-day and timed values",
		"Dialog action",
		[]string{"date", "time", "all day"},
		{all = CALENDAR_PALETTE_EDITOR},
		"Open the event editor first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Editor_Delete},
		"Delete event",
		"Delete the event in the active editor",
		"Dialog action",
		nil,
		{all = CALENDAR_PALETTE_EDITOR_EXISTING},
		"Open an existing event in the editor first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Editor_Cancel},
		"Cancel event editor",
		"Close the editor without saving",
		"Dialog action",
		nil,
		{all = CALENDAR_PALETTE_EDITOR},
		"Open the event editor first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Archive_Occurrence},
		"Archive event occurrence",
		"Archive the selected occurrence",
		"Dialog action",
		nil,
		{all = CALENDAR_PALETTE_ARCHIVE},
		"Open the archive dialog first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Archive_Series},
		"Archive complete event series",
		"Archive every occurrence in the recurring series",
		"Dialog action",
		nil,
		{all = CALENDAR_PALETTE_ARCHIVE_RECURRING},
		"Open the archive dialog for a recurring event first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Archive_Cancel},
		"Cancel event archive",
		"Close the archive dialog",
		"Dialog action",
		nil,
		{all = CALENDAR_PALETTE_ARCHIVE},
		"Open the archive dialog first",
	)
	calendar_palette_append(
		&entries,
		{kind = .Settings_Close},
		"Close Settings",
		"Return to the calendar",
		"Dialog action",
		nil,
		{all = CALENDAR_PALETTE_SETTINGS},
		"Open Settings first",
	)
	for &country, country_index in calendar_ui.holiday_countries {
		action := country.enabled ? "Disable" : "Enable"
		calendar_palette_append(
			&entries,
			{kind = .Toggle_Holiday_Country, index = country_index},
			fmt.tprintf("%s holidays: %s", action, country.country_name),
			fmt.tprintf(
				"%s / %d bundled dates",
				country.country_code,
				len(country.entries),
			),
			"Command",
			[]string{
				"holidays",
				"memorial days",
				country.country_code,
				country.country_name,
			},
		)
		if !country.enabled {continue}
		for &definition, definition_index in country.entries {
			kind_label := calendar_holiday_kind_label(
				calendar_holiday_kind(definition.kind),
			)
			calendar_palette_append(
				&entries,
				{
					kind = .Jump_Holiday,
					index = country_index,
					definition_index = definition_index,
				},
				definition.name,
				fmt.tprintf(
					"%s / %s",
					country.country_code,
					kind_label,
				),
				"Holiday",
				[]string{
					country.country_code,
					country.country_name,
					kind_label,
					definition.id,
				},
			)
		}
	}
	for &event, event_index in calendar_ui.events {
		if event.archived ||
		   len(event.recurrence_id) > 0 ||
		   strings.equal_fold(event.status, "CANCELLED") {
			continue
		}
		calendar_palette_append(
			&entries,
			{kind = len(event.dtstart) > 0 ? .Jump_Event : .Open_Event, index = event_index},
			event.summary,
			event.location,
			"Entry",
			[]string{event.description, event.categories, event.uid, event.url},
		)
	}
	search_error := command_palette.open(
		&calendar_ui.palette,
		entries[:],
		calendar_palette_active_context(),
	)
	if search_error != .None {
		clear(&calendar_ui.palette_actions)
		fmt.eprintln("[hw_calendar] command palette rejected invalid UTF-8")
		calendar_ui.needs_redraw = true
		return
	}
	calendar_ui.palette_query = ""
	calendar_ui.text_previous_focus = text_input.snapshot_focus(
		&calendar_ui.input_state,
	)
	calendar_ui.text_previous_focus_valid =
		calendar_ui.text_previous_focus.field != text_input.NO_FIELD
	calendar_text_focus(.Command_Palette)
	calendar_ui.needs_redraw = true
}

calendar_ui_activate_palette :: proc() {
	id, activated := command_palette.activate_selected(&calendar_ui.palette)
	if !activated {return}
	index := int(id)-1
	if index < 0 || index >= len(calendar_ui.palette_actions) {return}
	action := calendar_ui.palette_actions[index]
	command_palette.close(&calendar_ui.palette)
	calendar_ui.palette_query = ""
	clear(&calendar_ui.palette_actions)
	if calendar_ui.text_previous_focus_valid {
		target := calendar_text_target(
			calendar_text_field(calendar_ui.text_previous_focus.field),
		)
		if target != nil {
			text_input.restore_focus(
				&calendar_ui.input_state,
				calendar_ui.text_previous_focus,
				target^,
			)
		}
	} else {
		_ = calendar_text_blur()
	}
	calendar_ui.text_previous_focus_valid = false
	calendar_ui_execute_action(action)
	calendar_ui.needs_redraw = true
}

calendar_ui_contains :: proc(rect: Calendar_UI_Rect, point: Point) -> bool {
	return point.x >= rect.x && point.x <= rect.x+rect.w &&
	       point.y >= rect.y && point.y <= rect.y+rect.h
}

calendar_utf8_previous_boundary :: proc(value: string) -> int {
	if len(value) == 0 {return 0}
	index := len(value)-1
	for index > 0 && value[index]&0xc0 == 0x80 {index -= 1}
	return index
}

calendar_ui_palette_rect :: proc() -> Calendar_UI_Rect {
	return {
		calendar_ui.width*0.15,
		calendar_ui.height*0.2,
		calendar_ui.width*0.7,
		calendar_ui.height*0.65,
	}
}

calendar_ui_editor_rect :: proc() -> Calendar_UI_Rect {
	width := min(680.0, calendar_ui.width-48)
	height := min(520.0, calendar_ui.height-72)
	return {
		(calendar_ui.width-width)/2,
		(calendar_ui.height-height)/2,
		width,
		height,
	}
}

calendar_ui_editor_field_rect :: proc(index: int) -> Calendar_UI_Rect {
	modal := calendar_ui_editor_rect()
	column := index / 5
	row := index % 5
	column_width := modal.w/2
	return {
		modal.x+90+f64(column)*column_width,
		modal.y+modal.h-86-f64(row)*48,
		column_width-106,
		34,
	}
}

calendar_ui_editor_button_rect :: proc(index: int) -> Calendar_UI_Rect {
	modal := calendar_ui_editor_rect()
	return {modal.x+150+f64(index)*112, modal.y+20, 100, 34}
}

calendar_ui_editor_calendar_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_ui_editor_rect()
	return {modal.x+486, modal.y+20, modal.w-504, 34}
}

calendar_ui_editor_all_day_rect :: proc() -> Calendar_UI_Rect {
	modal := calendar_ui_editor_rect()
	return {modal.x+modal.w-154, modal.y+modal.h-48, 136, 34}
}

calendar_ui_editor_calendar_title :: proc() -> string {
	if len(calendar_ui.editor_calendar_identifier) == 0 {return "LOCAL"}
	for calendar in calendar_eventkit_calendars {
		if calendar.identifier == calendar_ui.editor_calendar_identifier {
			return calendar.title
		}
	}
	return "UNAVAILABLE"
}

calendar_ui_editor_can_select_calendar :: proc() -> bool {
	if !calendar_ui.editor_open {return false}
	if calendar_ui.editor_event_index >= 0 {
		if calendar_ui.editor_event_index >= len(calendar_ui.events) ||
		   calendar_ui.events[calendar_ui.editor_event_index].source !=
				.EventKit {
			return false
		}
	}
	for calendar in calendar_eventkit_calendars {
		if calendar.writable {return true}
	}
	return false
}

calendar_editor_toggle_all_day_dates :: proc(
	start, end: ICal_Date_Time,
	all_day: bool,
) -> (ICal_Date_Time, ICal_Date_Time) {
	start_day := ical_days_from_civil(start.year, start.month, start.day)
	end_day := ical_days_from_civil(end.year, end.month, end.day)
	if all_day {
		if end_day <= start_day {end_day = start_day+1}
		return ical_date_time_from_stamp(
			start_day*86_400,
			true,
		), ical_date_time_from_stamp(
			end_day*86_400,
			true,
		)
	}
	day_span := max(i64(1), end_day-start_day)
	return ical_date_time_from_stamp(
		start_day*86_400+9*3_600,
	), ical_date_time_from_stamp(
		(start_day+day_span-1)*86_400+10*3_600,
	)
}

calendar_ui_editor_toggle_all_day :: proc() {
	start, start_valid := ical_parse_date_time(calendar_ui.editor_start)
	end, end_valid := ical_parse_date_time(calendar_ui.editor_end)
	if !start_valid || !end_valid {
		calendar_ui_editor_set_error("CHECK THE START AND END VALUES")
		return
	}
	calendar_ui.editor_all_day = !calendar_ui.editor_all_day
	start, end = calendar_editor_toggle_all_day_dates(
		start,
		end,
		calendar_ui.editor_all_day,
	)
	delete(calendar_ui.editor_start)
	delete(calendar_ui.editor_end)
	calendar_ui.editor_start = ical_format_date_time(start)
	calendar_ui.editor_end = ical_format_date_time(end)
	calendar_ui.needs_redraw = true
}

calendar_ui_editor_clear :: proc() {
	delete(calendar_ui.editor_summary)
	delete(calendar_ui.editor_calendar_identifier)
	delete(calendar_ui.editor_start)
	delete(calendar_ui.editor_end)
	delete(calendar_ui.editor_location)
	delete(calendar_ui.editor_url)
	delete(calendar_ui.editor_categories)
	delete(calendar_ui.editor_description)
	delete(calendar_ui.editor_time_zone)
	delete(calendar_ui.editor_alarms)
	delete(calendar_ui.editor_rrule)
	delete(calendar_ui.editor_error)
	calendar_ui.editor_summary = ""
	calendar_ui.editor_calendar_identifier = ""
	calendar_ui.editor_start = ""
	calendar_ui.editor_end = ""
	calendar_ui.editor_location = ""
	calendar_ui.editor_url = ""
	calendar_ui.editor_categories = ""
	calendar_ui.editor_description = ""
	calendar_ui.editor_time_zone = ""
	calendar_ui.editor_alarms = ""
	calendar_ui.editor_rrule = ""
	calendar_ui.editor_error = ""
}

calendar_ui_editor_open :: proc(event_index := -1) {
	calendar_ui_editor_clear()
	calendar_ui.editor_open = true
	calendar_ui.editor_event_index = event_index
	calendar_ui.editor_field = 0
	if event_index >= 0 && event_index < len(calendar_ui.events) {
		event := &calendar_ui.events[event_index]
		calendar_ui.editor_calendar_identifier = strings.clone(
			event.calendar_identifier,
		)
		calendar_ui.editor_summary = strings.clone(event.summary)
		calendar_ui.editor_start = strings.clone(event.dtstart)
		calendar_ui.editor_end = strings.clone(event.dtend)
		calendar_ui.editor_location = strings.clone(event.location)
		calendar_ui.editor_url = strings.clone(event.url)
		calendar_ui.editor_categories = strings.clone(event.categories)
		calendar_ui.editor_description = strings.clone(event.description)
		calendar_ui.editor_time_zone = strings.clone(event.time_zone)
		if event.source == .EventKit {
			calendar_ui.editor_alarms = strings.clone(event.alarm_offsets)
		} else {
			calendar_ui.editor_alarms =
				calendar_eventkit_local_alarm_offsets(event)
		}
		calendar_ui.editor_rrule = strings.clone(event.rrule)
		calendar_ui.editor_important = event.important
		start_value, start_valid := ical_parse_date_time(event.dtstart)
		calendar_ui.editor_all_day =
			event.all_day || (start_valid && start_value.is_date)
	} else {
		now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
		day := ical_days_from_civil(now.year, now.month, now.day) +
		       i64(calendar_ui.day_offset)
		start := ical_date_time_from_stamp(day*86400+9*3600)
		end := ical_date_time_from_stamp(day*86400+10*3600)
		calendar_ui.editor_start = ical_format_date_time(start)
		calendar_ui.editor_end = ical_format_date_time(end)
		calendar_ui.editor_important = false
		calendar_ui.editor_all_day = false
		if default_identifier, found := calendar_connected_default_calendar(
			context.temp_allocator,
		); found {
			for calendar in calendar_eventkit_calendars {
				if calendar.identifier == default_identifier &&
				   calendar.writable {
					calendar_ui.editor_calendar_identifier = strings.clone(
						default_identifier,
					)
					break
				}
			}
		}
	}
	calendar_text_focus(.Editor_Summary)
	flash.cancel(&calendar_ui.flash)
	command_palette.close(&calendar_ui.palette)
	calendar_ui.needs_redraw = true
}

calendar_ui_editor_close :: proc() {
	if field := calendar_text_active_field();
	   field >= .Editor_Summary && field <= .Editor_RRule {
		_ = calendar_text_blur()
	}
	calendar_ui_editor_clear()
	calendar_ui.editor_open = false
	calendar_ui.editor_event_index = -1
	calendar_ui.needs_redraw = true
}

calendar_ui_editor_field_text :: proc(index: int) -> ^string {
	switch index {
	case 0: return &calendar_ui.editor_summary
	case 1: return &calendar_ui.editor_start
	case 2: return &calendar_ui.editor_end
	case 3: return &calendar_ui.editor_location
	case 4: return &calendar_ui.editor_url
	case 5: return &calendar_ui.editor_categories
	case 6: return &calendar_ui.editor_description
	case 7: return &calendar_ui.editor_time_zone
	case 8: return &calendar_ui.editor_alarms
	case 9: return &calendar_ui.editor_rrule
	}
	return nil
}

calendar_ui_editor_set_error :: proc(message: string) {
	delete(calendar_ui.editor_error)
	calendar_ui.editor_error = strings.clone(message)
}

calendar_ui_editor_commit :: proc(cancelled := false) {
	if cancelled && (calendar_ui.editor_event_index < 0 ||
	   calendar_ui.editor_event_index >= len(calendar_ui.events)) {
		return
	}
	if len(strings.trim_space(calendar_ui.editor_summary)) == 0 {
		calendar_ui_editor_set_error("ENTRY TEXT IS REQUIRED")
		return
	}
	entry_id: i64
	expected_revision := 0
	if calendar_ui.editor_event_index >= 0 && calendar_ui.editor_event_index < len(calendar_ui.events) {
		entry_id = calendar_ui.events[calendar_ui.editor_event_index].row_id
		expected_revision = calendar_ui.events[calendar_ui.editor_event_index].sequence
	}
	if cancelled {
		_, code := agenda_entry_set_state(entry_id, expected_revision, "dismissed")
		if len(code) > 0 {calendar_ui_editor_set_error("THE ENTRY COULD NOT BE DISMISSED"); return}
		calendar_ui_editor_close()
		calendar_ui_reload_data()
		return
	}
	start_text := ""
	end_text := ""
	if start, ok := ical_parse_date_time(calendar_ui.editor_start); ok {start_text = fmt.tprintf("%d", ical_date_time_stamp(start))}
	if end, ok := ical_parse_date_time(calendar_ui.editor_end); ok {end_text = fmt.tprintf("%d", ical_date_time_stamp(end))}
	input := Agenda_Entry_Input{
		schema_version = 1,
		original_text = calendar_ui.editor_summary,
		start_at = start_text,
		end_at = end_text,
		location = calendar_ui.editor_location,
		source_url = calendar_ui.editor_url,
	}
	if entry_id > 0 {
		current, found := agenda_entry_get(entry_id, context.temp_allocator)
		if found {
			input.due_at = current.due_at
			input.reminder_at = current.reminder_at
			input.recurrence_seconds = current.recurrence_seconds
		}
		updated, code := agenda_entry_update(entry_id, expected_revision, &input)
		if found {agenda_entry_destroy(&current, context.temp_allocator)}
		if len(code) > 0 {calendar_ui_editor_set_error("THE ENTRY CHANGED OR COULD NOT BE STORED"); return}
		agenda_entry_destroy(&updated)
	} else {
		created, ok := agenda_entry_create(&input)
		if !ok {calendar_ui_editor_set_error("THE ENTRY COULD NOT BE STORED"); return}
		agenda_entry_destroy(&created)
	}
	calendar_ui_editor_close()
	calendar_ui_reload_data()
	when false {
	if calendar_ui.editor_event_index < 0 &&
	   len(calendar_ui.editor_calendar_identifier) > 0 {
		calendar_eventkit_clear_error()
		if !calendar_eventkit_queue_create(
			calendar_ui.editor_calendar_identifier,
			calendar_ui.editor_summary,
			calendar_ui.editor_description,
			calendar_ui.editor_location,
			calendar_ui.editor_url,
			calendar_ui.editor_categories,
			calendar_ui.editor_start,
			calendar_ui.editor_end,
			calendar_ui.editor_time_zone,
			calendar_ui.editor_alarms,
			calendar_ui.editor_rrule,
			calendar_ui.editor_important,
		) {
			calendar_ui_editor_set_error(
				"THE CONNECTED EVENT WRITE COULD NOT START",
			)
			return
		}
		calendar_ui_editor_close()
		return
	}
	if calendar_ui.editor_event_index >= 0 &&
	   calendar_ui.editor_event_index < len(calendar_ui.events) {
		event := &calendar_ui.events[calendar_ui.editor_event_index]
		if event.source == .EventKit {
			calendar_eventkit_clear_error()
			queued := false
			if cancelled {
				queued = calendar_eventkit_queue_delete(event)
			} else {
				queued = calendar_eventkit_queue_update(
					event,
					calendar_ui.editor_calendar_identifier,
					calendar_ui.editor_summary,
					calendar_ui.editor_description,
					calendar_ui.editor_location,
					calendar_ui.editor_url,
					calendar_ui.editor_categories,
					calendar_ui.editor_start,
					calendar_ui.editor_end,
					calendar_ui.editor_time_zone,
					calendar_ui.editor_alarms,
					calendar_ui.editor_rrule,
					calendar_ui.editor_important,
				)
			}
			if !queued {
				calendar_ui_editor_set_error(
					"THE CONNECTED EVENT WRITE COULD NOT START",
				)
				return
			}
			calendar_ui_editor_close()
			return
		}
	}
	input := Calendar_Event_Input{
		schema_version = 1,
		summary = calendar_ui.editor_summary,
		description = calendar_ui.editor_description,
		location = calendar_ui.editor_location,
		url = calendar_ui.editor_url,
		important = calendar_ui.editor_important,
		dtstart = calendar_ui.editor_start,
		dtend = calendar_ui.editor_end,
		rrule = calendar_ui.editor_rrule,
	}
	if len(calendar_ui.editor_categories) > 0 {
		input.categories = []string{calendar_ui.editor_categories}
	}
	alarm_offsets, alarms_valid := calendar_eventkit_parse_alarm_offsets(
		calendar_ui.editor_alarms,
	)
	if !alarms_valid {
		calendar_ui_editor_set_error(
			"ALARMS MUST BE COMMA-SEPARATED LEAD TIMES IN SECONDS",
		)
		return
	}
	defer delete(alarm_offsets)
	input.reminder_offsets_seconds = make([]int, len(alarm_offsets))
	defer delete(input.reminder_offsets_seconds)
	for offset, index in alarm_offsets {
		input.reminder_offsets_seconds[index] = int(offset)
	}
	if calendar_ui.editor_event_index >= 0 &&
	   calendar_ui.editor_event_index < len(calendar_ui.events) {
		event := &calendar_ui.events[calendar_ui.editor_event_index]
		input.uid = event.uid
		input.recurrence_id = event.recurrence_id
		input.sequence = event.sequence+1
	}
	contents, valid := calendar_cli_event_document(
		&input,
		cancelled,
		false,
		calendar_ui.editor_event_index >= 0,
	)
	if !valid {
		calendar_ui_editor_set_error("CHECK THE DATE, TIME, AND RECURRENCE VALUES")
		return
	}
	defer delete(contents)
	document := ical_parse(contents)
	defer ical_document_destroy(&document)
	if _, imported := calendar_import_document(&document); !imported {
		calendar_ui_editor_set_error("THE EVENT COULD NOT BE STORED")
		return
	}
	calendar_ui_editor_close()
	calendar_ui_reload_data()
	calendar_notification_reconcile()
	}
}

calendar_window_zoom_next_frame :: proc(
	current, visible, restore: Rect,
	has_restore: bool,
) -> (next, next_restore: Rect, next_has_restore: bool) {
	if has_restore && current == visible {
		return restore, {}, false
	}
	return visible, current, true
}

calendar_toggle_window_zoom :: proc() {
	screen := msg_id(calendar_ui.window, sel_registerName("screen"))
	if screen == nil {
		screen = msg_id(objc_getClass("NSScreen"), sel_registerName("mainScreen"))
	}
	if screen == nil {return}
	current := msg_rect(calendar_ui.window, sel_registerName("frame"))
	visible := msg_rect(screen, sel_registerName("visibleFrame"))
	next, restore, has_restore := calendar_window_zoom_next_frame(
		current,
		visible,
		calendar_ui.window_zoom_restore_frame,
		calendar_ui.window_has_zoom_restore,
	)
	calendar_ui.window_zoom_restore_frame = restore
	calendar_ui.window_has_zoom_restore = has_restore
	msg_void_rect_bool(
		calendar_ui.window,
		sel_registerName("setFrame:display:"),
		next,
		true,
	)
	calendar_ui.needs_redraw = true
}

calendar_ui_execute_action :: proc(action: Calendar_App_Action) {
	calendar_clear_number_prefix()
	switch action.kind {
	case .Window_Close:
		msg_void(calendar_ui.window, sel_registerName("close"))
	case .Window_Minimize:
		msg_void_u(
			calendar_ui.window,
			sel_registerName("setStyleMask:"),
			CALENDAR_WINDOW_MINIMIZE_STYLE,
		)
		msg_void_id(
			calendar_ui.window,
			sel_registerName("miniaturize:"),
			nil,
		)
		msg_void_u(
			calendar_ui.window,
			sel_registerName("setStyleMask:"),
			CALENDAR_WINDOW_STYLE,
		)
	case .Window_Zoom:
		calendar_toggle_window_zoom()
	case .Open_Settings:
		if calendar_ui.settings_open {
			calendar_settings_close()
		} else {
			_ = calendar_settings_open()
		}
	case .Settings_Close:
		calendar_settings_close()
	case .Settings_Category:
		if action.index >= 0 &&
		   action.index <= int(Calendar_Settings_Category.Shortcuts) {
			calendar_ui.settings_category =
				Calendar_Settings_Category(action.index)
			_ = calendar_settings_set_query("")
			calendar_ui.settings_query_focused = false
		}
	case .Settings_Search:
		calendar_text_focus(.Settings_Search)
	case .Command_Palette_Search:
		calendar_text_focus(.Command_Palette)
	case .Set_Theme:
		_ = calendar_ui_apply_theme(action.theme_id)
	case .Request_Calendar_Access:
		delete(calendar_ui.settings_error)
		calendar_ui.settings_error = ""
		switch calendar_eventkit_authorization {
		case .Not_Determined:
			if !calendar_eventkit_request_access() {
				calendar_ui.settings_error = strings.clone(
					"THE ACCESS REQUEST COULD NOT START",
				)
			}
		case .Full_Access:
			calendar_ui_reload_data()
		case .Denied, .Restricted:
			calendar_ui.settings_error = strings.clone(
				"ENABLE CALENDAR ACCESS IN SYSTEM SETTINGS",
			)
		case .Write_Only:
			calendar_ui.settings_error = strings.clone(
				"FULL CALENDAR ACCESS IS REQUIRED",
			)
		}
	case .Toggle_Connected_Calendar:
		if action.index >= 0 &&
		   action.index < len(calendar_eventkit_calendars) {
			calendar := &calendar_eventkit_calendars[action.index]
			visible := calendar_connected_calendar_visible(calendar.identifier)
			if calendar_connected_calendar_set_visible(
				calendar.identifier,
				!visible,
			) {
				calendar_ui_reload_data(false)
			} else {
				delete(calendar_ui.settings_error)
				calendar_ui.settings_error = strings.clone(
					"THE CALENDAR VISIBILITY COULD NOT BE SAVED",
				)
			}
		}
	case .Set_Default_Connected_Calendar:
		if action.index >= 0 &&
		   action.index < len(calendar_eventkit_calendars) {
			calendar := &calendar_eventkit_calendars[action.index]
			delete(calendar_ui.settings_error)
			calendar_ui.settings_error = ""
			if !calendar.writable {
				calendar_ui.settings_error = strings.clone(
					"THE SELECTED CALENDAR IS READ ONLY",
				)
			} else if !calendar_connected_set_default_calendar(
				calendar.identifier,
			) {
				calendar_ui.settings_error = strings.clone(
					"THE DEFAULT CALENDAR COULD NOT BE SAVED",
				)
			}
		}
	case .Configure_Flash:
		calendar_shortcut_recorder_open()
	case .Shortcut_Record:
		calendar_shortcut_destroy(&calendar_ui.shortcut_candidate)
		calendar_ui.shortcut_candidate_valid = false
		delete(calendar_ui.shortcut_collision)
		calendar_ui.shortcut_collision = ""
		delete(calendar_ui.shortcut_error)
		calendar_ui.shortcut_error = ""
		calendar_ui.shortcut_listening = true
		calendar_ui.shortcut_live_modifiers = {}
	case .Shortcut_Save:
		_ = calendar_shortcut_recorder_save()
	case .Shortcut_Reset:
		_ = calendar_shortcut_recorder_reset()
	case .Shortcut_Cancel:
		calendar_shortcut_recorder_close()
	case .Today:
		calendar_ui_clear_holiday_promotion()
		calendar_ui_clear_navigation_selection()
		calendar_ui.day_offset = 0
		calendar_ui_reload_data()
	case .Search:
		calendar_ui_open_palette()
	case .New_Event:
		if !calendar_ui.editor_open && !calendar_ui.archive_modal_open {
			calendar_ui_editor_open()
		}
	case .Open_Event:
		if action.index >= 0 && action.index < len(calendar_ui.events) {
			calendar_ui_editor_open(action.index)
		}
	case .Jump_Event:
		if action.index >= 0 && action.index < len(calendar_ui.events) {
			now := ical_date_time_from_stamp(
				time.to_unix_seconds(time.now()),
				true,
			)
			start, ok := ical_parse_date_time(
				calendar_ui.events[action.index].dtstart,
			)
			if ok {
				calendar_ui_clear_holiday_promotion()
				calendar_ui_clear_navigation_selection()
				calendar_ui.day_offset = int(
					ical_days_from_civil(start.year, start.month, start.day) -
					ical_days_from_civil(now.year, now.month, now.day),
				)
				calendar_ui_reload_data()
			}
		}
	case .Toggle_Holiday_Country:
		if action.index >= 0 &&
		   action.index < len(calendar_ui.holiday_countries) {
			country := &calendar_ui.holiday_countries[action.index]
			if calendar_holiday_country_set_enabled(country, !country.enabled) {
				calendar_ui_clear_holiday_promotion()
				calendar_ui_clear_navigation_selection()
				calendar_ui_reload_data()
			} else {
				fmt.eprintln("[hw_calendar] could not persist the holiday setting")
			}
		}
	case .Jump_Holiday:
		if action.index >= 0 &&
		   action.index < len(calendar_ui.holiday_countries) {
			country := &calendar_ui.holiday_countries[action.index]
			if action.definition_index >= 0 &&
			   action.definition_index < len(country.entries) {
				now := ical_date_time_from_stamp(
					time.to_unix_seconds(time.now()),
					true,
				)
				if date, found := calendar_holiday_next_date(
					country,
					&country.entries[action.definition_index],
					now,
				); found {
					target_days := ical_days_from_civil(
						date.year,
						date.month,
						date.day,
					)
					now_days := ical_days_from_civil(
						now.year,
						now.month,
						now.day,
					)
					calendar_ui_clear_navigation_selection()
					calendar_ui.day_offset = int(target_days-now_days)
					calendar_ui.promoted_holiday_active = true
					calendar_ui.promoted_holiday_country_index = action.index
					calendar_ui.promoted_holiday_definition_index =
						action.definition_index
					calendar_ui.promoted_holiday_days = target_days
					calendar_ui_reload_data()
				}
			}
		}
	case .Focus_Event:
		calendar_ui_focus_event(
			action.index,
			action.occurrence_stamp,
			action.occurrence_is_date,
		)
	case .Focus_Holiday:
		calendar_ui_focus_holiday(
			action.index,
			action.definition_index,
			action.occurrence_stamp,
		)
	case .Action_Edit:
		if calendar_ui_action_available(.Action_Edit) {
			calendar_ui_editor_open(calendar_ui.navigation_event_index)
		}
	case .Action_Open_URL:
		calendar_ui_open_url(calendar_ui_details_url())
	case .Action_Archive:
		if calendar_ui_action_available(.Action_Archive) {
			calendar_ui_archive_modal_open()
		}
	case .Action_Complete:
		if calendar_ui_action_available(.Action_Complete) {
			event := &calendar_ui.events[calendar_ui.navigation_event_index]
			updated, code := agenda_entry_set_state(event.row_id, event.sequence, "completed")
			if len(code) == 0 {
				agenda_entry_destroy(&updated)
				calendar_ui_clear_navigation_selection()
				calendar_ui_reload_data()
				calendar_notification_reconcile()
			}
		}
	case .Action_Confirm_Proposal, .Action_Reject_Proposal:
		if calendar_ui_action_available(action.kind) {
			event := &calendar_ui.events[calendar_ui.navigation_event_index]
			proposal, found := agenda_proposal_pending_for_entry(event.row_id, context.temp_allocator)
			if found {
				updated, code := agenda_proposal_resolve(proposal.id, action.kind == .Action_Confirm_Proposal)
				agenda_proposal_destroy(&proposal, context.temp_allocator)
				if len(code) == 0 {
					agenda_entry_destroy(&updated)
					calendar_ui_clear_navigation_selection()
					calendar_ui_reload_data()
					calendar_notification_reconcile()
				}
			}
		}
	case .Action_Copy_To_Connected:
		if calendar_ui_action_available(.Action_Copy_To_Connected) {
			event := &calendar_ui.events[calendar_ui.navigation_event_index]
			default_identifier, found := calendar_connected_default_calendar(
				context.temp_allocator,
			)
			calendar_eventkit_clear_error()
			if !found || !calendar_eventkit_queue_copy(
				event,
				default_identifier,
			) {
				calendar_eventkit_last_error = strings.clone(
					"THE CONNECTED EVENT COPY COULD NOT START",
				)
			}
		}
	case .Action_Open_In_Apple_Calendar:
		if calendar_ui_action_available(.Action_Open_In_Apple_Calendar) {
			calendar_ui_open_apple_calendar()
		}
	case .Archive_Cancel:
		calendar_ui_archive_modal_close()
	case .Archive_Occurrence:
		if calendar_ui.archive_modal_open {
			calendar_ui_archive_confirm(false)
		}
	case .Archive_Series:
		if calendar_ui.archive_modal_open {
			calendar_ui_archive_confirm(true)
		}
	case .Editor_Field:
		calendar_text_focus(calendar_text_editor_field(action.index))
	case .Editor_Important:
		calendar_ui.editor_important = !calendar_ui.editor_important
	case .Editor_All_Day:
		calendar_ui_editor_toggle_all_day()
	case .Editor_Calendar:
		if calendar_ui_editor_can_select_calendar() {
			if calendar_ui.editor_event_index < 0 {
				current_slot := 0
				for calendar, index in calendar_eventkit_calendars {
					if calendar.identifier ==
					   calendar_ui.editor_calendar_identifier {
						current_slot = index+1
						break
					}
				}
				for offset in 1..=len(calendar_eventkit_calendars)+1 {
					slot := (
						current_slot+offset
					)%(len(calendar_eventkit_calendars)+1)
					if slot == 0 {
						delete(calendar_ui.editor_calendar_identifier)
						calendar_ui.editor_calendar_identifier = ""
						break
					}
					calendar := &calendar_eventkit_calendars[slot-1]
					if !calendar.writable {continue}
					delete(calendar_ui.editor_calendar_identifier)
					calendar_ui.editor_calendar_identifier =
						strings.clone(calendar.identifier)
					break
				}
			} else {
				start := -1
				for calendar, index in calendar_eventkit_calendars {
					if calendar.identifier ==
					   calendar_ui.editor_calendar_identifier {
						start = index
						break
					}
				}
				for offset in 1..=len(calendar_eventkit_calendars) {
					index := (start+offset)%len(calendar_eventkit_calendars)
					calendar := &calendar_eventkit_calendars[index]
					if !calendar.writable {continue}
					delete(calendar_ui.editor_calendar_identifier)
					calendar_ui.editor_calendar_identifier =
						strings.clone(calendar.identifier)
					break
				}
			}
		}
	case .Editor_Save:
		if calendar_ui.editor_open {calendar_ui_editor_commit()}
	case .Editor_Delete:
		if calendar_ui.editor_open && calendar_ui.editor_event_index >= 0 {
			calendar_ui_editor_commit(true)
		}
	case .Editor_Cancel:
		if calendar_ui.editor_open {calendar_ui_editor_close()}
	case .None:
	}
	calendar_ui.needs_redraw = true
}

calendar_ui_activate_control :: proc(id: u64) {
	for control in calendar_ui.controls {
		if control.id != id {continue}
		calendar_ui_execute_action(control.action)
		break
	}
	calendar_ui.needs_redraw = true
}

calendar_ui_click :: proc(point: Point, click_count: uint = 1) -> bool {
	flash.cancel(&calendar_ui.flash)
	for index := len(calendar_ui.controls)-1; index >= 0; index -= 1 {
		control := calendar_ui.controls[index]
		if calendar_ui_contains(control.rect, point) {
			#partial switch control.action.kind {
			case .Settings_Search:
				calendar_text_begin_pointer(
					.Settings_Search,
					point,
					click_count,
				)
				return true
			case .Command_Palette_Search:
				calendar_text_begin_pointer(
					.Command_Palette,
					point,
					click_count,
				)
				return true
			case .Editor_Field:
				calendar_text_begin_pointer(
					calendar_text_editor_field(control.action.index),
					point,
					click_count,
				)
				return true
			case:
			}
			calendar_ui_activate_control(control.id)
			return true
		}
	}
	calendar_ui.needs_redraw = true
	return false
}

calendar_ui_resize_edges :: proc(point: Point) -> u8 {
	edges := u8(0)
	if point.x <= CALENDAR_WINDOW_RESIZE_INSET {edges |= 1}
	if point.x >= calendar_ui.width-CALENDAR_WINDOW_RESIZE_INSET {edges |= 2}
	if point.y <= CALENDAR_WINDOW_RESIZE_INSET {edges |= 4}
	if point.y >= calendar_ui.height-CALENDAR_WINDOW_RESIZE_INSET {edges |= 8}
	return edges
}

calendar_ui_begin_resize :: proc(point: Point) -> bool {
	edges := calendar_ui_resize_edges(point)
	if edges == 0 {return false}
	calendar_ui.resize_edges = edges
	calendar_ui.resize_start_mouse = msg_point(
		objc_getClass("NSEvent"),
		sel_registerName("mouseLocation"),
	)
	calendar_ui.resize_start_frame = msg_rect(
		calendar_ui.window,
		sel_registerName("frame"),
	)
	return true
}

calendar_on_mouse_dragged :: proc "c" (self: Id, command: Sel, event: Id) {
	context = runtime.default_context()
	if calendar_ui.resize_edges == 0 {
		window_point := msg_point(event, sel_registerName("locationInWindow"))
		point := calendar_msg_point_point_id(
			self,
			sel_registerName("convertPoint:fromView:"),
			window_point,
			nil,
		)
		_ = calendar_text_update_pointer(point)
		return
	}
	mouse := msg_point(
		objc_getClass("NSEvent"),
		sel_registerName("mouseLocation"),
	)
	delta := Point{
		mouse.x-calendar_ui.resize_start_mouse.x,
		mouse.y-calendar_ui.resize_start_mouse.y,
	}
	start := calendar_ui.resize_start_frame
	frame := start
	if calendar_ui.resize_edges&1 != 0 {
		frame.size.width = max(
			CALENDAR_WINDOW_MIN_WIDTH,
			start.size.width-delta.x,
		)
		frame.origin.x = start.origin.x+start.size.width-frame.size.width
	} else if calendar_ui.resize_edges&2 != 0 {
		frame.size.width = max(
			CALENDAR_WINDOW_MIN_WIDTH,
			start.size.width+delta.x,
		)
	}
	if calendar_ui.resize_edges&4 != 0 {
		frame.size.height = max(
			CALENDAR_WINDOW_MIN_HEIGHT,
			start.size.height-delta.y,
		)
		frame.origin.y = start.origin.y+start.size.height-frame.size.height
	} else if calendar_ui.resize_edges&8 != 0 {
		frame.size.height = max(
			CALENDAR_WINDOW_MIN_HEIGHT,
			start.size.height+delta.y,
		)
	}
	msg_void_rect_bool(
		calendar_ui.window,
		sel_registerName("setFrame:display:"),
		frame,
		true,
	)
	calendar_ui.needs_redraw = true
}

calendar_on_mouse_up :: proc "c" (self: Id, command: Sel, event: Id) {
	context = runtime.default_context()
	calendar_ui.resize_edges = 0
	text_input.end_pointer_selection(&calendar_ui.input_state)
}

calendar_header_click_should_zoom :: proc(click_count: uint) -> bool {
	return click_count >= 2
}

calendar_on_mouse_down :: proc "c" (self: Id, command: Sel, event: Id) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	window_point := msg_point(event, sel_registerName("locationInWindow"))
	point := calendar_msg_point_point_id(
		self,
		sel_registerName("convertPoint:fromView:"),
		window_point,
		nil,
	)
	if calendar_ui_begin_resize(point) {return}
	click_count := calendar_msg_uint(event, sel_registerName("clickCount"))
	if calendar_ui_click(point, click_count) {return}
	if calendar_ui_contains(calendar_ui_header_rect(), point) {
		if calendar_header_click_should_zoom(click_count) {
			calendar_toggle_window_zoom()
		} else {
			msg_void_id(
				calendar_ui.window,
				sel_registerName("performWindowDragWithEvent:"),
				event,
			)
		}
	}
}

calendar_on_scroll :: proc "c" (self: Id, command: Sel, event: Id) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	flash.cancel(&calendar_ui.flash)
	if calendar_ui.editor_open || calendar_ui.settings_open ||
	   calendar_ui.shortcut_open ||
	   command_palette.is_open(&calendar_ui.palette) {
		return
	}
	delta := msg_f64(event, sel_registerName("scrollingDeltaY"))
	if delta == 0 {delta = msg_f64(event, sel_registerName("deltaY"))}
	window_point := msg_point(event, sel_registerName("locationInWindow"))
	point := calendar_msg_point_point_id(
		self,
		sel_registerName("convertPoint:fromView:"),
		window_point,
		nil,
	)
	if calendar_ui.navigation_active &&
	   calendar_ui_contains(calendar_ui_details_rect(), point) {
		calendar_ui.details_scroll = max(0, min(4096, calendar_ui.details_scroll-delta*2))
		calendar_ui.needs_redraw = true
		return
	}
	if delta > 0 {
		calendar_ui.day_offset -= max(1, int(delta/12))
	} else if delta < 0 {
		calendar_ui.day_offset += max(1, int(-delta/12))
	}
	calendar_ui_clear_holiday_promotion()
	calendar_ui_clear_navigation_selection()
	calendar_ui_reload_data()
	calendar_ui.needs_redraw = true
}

calendar_on_key_down :: proc "c" (self: Id, command: Sel, event: Id) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	characters := msg_id(event, sel_registerName("charactersIgnoringModifiers"))
	utf8 := calendar_msg_cstring(characters, sel_registerName("UTF8String"))
	text := ""
	if utf8 != nil {text = string(utf8)}
	modifiers := calendar_msg_uint(event, sel_registerName("modifierFlags"))
	key_code := calendar_msg_uint(event, sel_registerName("keyCode"))
	control_down := modifiers & (1 << 18) != 0
	shift_down := modifiers & CALENDAR_EVENT_MODIFIER_SHIFT != 0
	option_down := modifiers & CALENDAR_EVENT_MODIFIER_OPTION != 0
	command_down := modifiers & CALENDAR_EVENT_MODIFIER_COMMAND != 0
	if calendar_ui.shortcut_open {
		if key_code == 53 {
			calendar_shortcut_recorder_close()
			return
		}
		if calendar_ui.shortcut_listening {
			_ = calendar_shortcut_recorder_capture(
				key_code,
				text,
				modifiers,
			)
			return
		}
		if !command_down && !control_down && !shift_down && !option_down {
			if slot, found := calendar_number_slot_for_key_code(key_code);
			   found && slot < 3 {
				actions := [3]Calendar_UI_Action{
					.Shortcut_Save,
					.Shortcut_Reset,
					.Shortcut_Cancel,
				}
				calendar_ui_execute_action({kind = actions[slot]})
			}
		}
		return
	}
	exact_settings_shortcut := command_down && !shift_down && !option_down &&
	                           !control_down && text == ","
	if exact_settings_shortcut {
		if command_palette.is_open(&calendar_ui.palette) {
			calendar_ui_open_palette()
		}
		_ = calendar_settings_open()
		return
	}
	exact_palette_shortcut := control_down && !shift_down && !option_down &&
	                          !command_down &&
	                          (text == "k" || text == "K")
	if exact_palette_shortcut {
		calendar_ui_open_palette()
		return
	}
	if command_palette.is_open(&calendar_ui.palette) {
		switch key_code {
		case 53:
			calendar_ui_open_palette()
			return
		case 36:
			calendar_ui_activate_palette()
			return
		case 125: command_palette.move_selection(&calendar_ui.palette, 1)
		case 126: command_palette.move_selection(&calendar_ui.palette, -1)
		case 48:
			command_palette.move_selection(
				&calendar_ui.palette,
				shift_down ? -1 : 1,
			)
		case:
			_ = calendar_text_handle_shortcut(
				self,
				event,
				key_code,
				modifiers,
			)
		}
		calendar_ui.needs_redraw = true
		return
	}
	if flash.is_active(&calendar_ui.flash) {
		if key_code == 53 {
			flash.cancel(&calendar_ui.flash)
		} else if key_code == 48 {
			flash.cycle_selection(
				&calendar_ui.flash,
				shift_down ? .Previous : .Next,
			)
		} else if key_code == 36 {
			result := flash.activate_selection(&calendar_ui.flash)
			if result.kind == .Activated {
				calendar_ui_activate_control(u64(result.target_id))
			}
		} else if len(text) == 1 {
			result := flash.consume(&calendar_ui.flash, text[0])
			if result.kind == .Activated {
				calendar_ui_activate_control(u64(result.target_id))
			}
		}
		calendar_ui.needs_redraw = true
		return
	}
	if calendar_ui.settings_open {
		settings_focused :=
			calendar_text_active_field() == .Settings_Search
		if !settings_focused &&
		   calendar_shortcut_matches_event(
				calendar_ui.flash_leader,
				key_code,
				text,
				modifiers,
		   ) {
			calendar_ui_begin_flash()
			return
		}
		if settings_focused {
			if key_code == 53 {
				_ = calendar_text_blur()
				return
			}
			_ = calendar_text_handle_shortcut(
				self,
				event,
				key_code,
				modifiers,
			)
			return
		}
		if key_code == 53 {
			calendar_settings_close()
		} else if key_code == 48 {
			calendar_text_focus(.Settings_Search)
		} else if key_code == 125 || key_code == 126 {
			if key_code == 125 {
				calendar_ui.settings_category = .Shortcuts
			} else {
				calendar_ui.settings_category = .Styling
			}
			calendar_ui.needs_redraw = true
		}
		return
	}
	if calendar_ui.archive_modal_open && !flash.is_active(&calendar_ui.flash) {
		if key_code == 53 {
			calendar_ui_archive_modal_close()
		} else if calendar_shortcut_matches_event(
			calendar_ui.flash_leader,
			key_code,
			text,
			modifiers,
		) {
			calendar_ui_begin_flash()
		} else if !command_down && !control_down &&
		          !shift_down && !option_down {
			if slot, found := calendar_number_slot_for_key_code(key_code);
			   found {
				event := &calendar_ui.events[
					calendar_ui.navigation_event_index
				]
				action := calendar_archive_action_for_slot(
					calendar_event_is_recurring(event),
					slot,
				)
				#partial switch action {
				case .Archive_Occurrence:
					calendar_ui_archive_confirm(false)
				case .Archive_Series:
					calendar_ui_archive_confirm(true)
				case .Archive_Cancel:
					calendar_ui_archive_modal_close()
				case:
				}
			}
		}
		return
	}
	if calendar_ui.editor_open {
		if key_code == 53 {
			calendar_ui_editor_close()
			return
		}
		if calendar_text_active_field() < .Editor_Summary ||
		   calendar_text_active_field() > .Editor_RRule {
			calendar_text_focus(
				calendar_text_editor_field(calendar_ui.editor_field),
			)
		}
		_ = calendar_text_handle_shortcut(
			self,
			event,
			key_code,
			modifiers,
		)
		return
	}
	if command_down && key_code == 125 {
		calendar_ui_navigate(.Next)
		return
	}
	if command_down && key_code == 126 {
		calendar_ui_navigate(.Previous)
		return
	}
	if key_code == 53 && calendar_ui.number_prefix != 0 {
		calendar_clear_number_prefix()
		calendar_ui.needs_redraw = true
		return
	}
	if !command_down && !control_down && !shift_down && !option_down {
		if digit, found := calendar_number_digit_for_key_code(key_code); found {
			action, handled := calendar_consume_main_action_digit_at(
				digit,
				calendar_number_time_ms(),
			)
			if action != .None && calendar_ui_action_available(action) {
				calendar_ui_execute_action({kind = action})
			}
			if handled {return}
		}
	}
	if calendar_shortcut_matches_event(
		calendar_ui.flash_leader,
		key_code,
		text,
		modifiers,
	) {
		calendar_ui_begin_flash()
	} else if key_code == 53 {
		calendar_ui_clear_holiday_promotion()
		calendar_ui_clear_navigation_selection()
		calendar_ui.day_offset = 0
		calendar_ui_reload_data()
		calendar_ui.needs_redraw = true
	} else if key_code == 125 {
		calendar_ui_clear_holiday_promotion()
		calendar_ui_clear_navigation_selection()
		calendar_ui.day_offset += 1
		calendar_ui_reload_data()
		calendar_ui.needs_redraw = true
	} else if key_code == 126 {
		calendar_ui_clear_holiday_promotion()
		calendar_ui_clear_navigation_selection()
		calendar_ui.day_offset -= 1
		calendar_ui_reload_data()
		calendar_ui.needs_redraw = true
	}
}

calendar_on_flags_changed :: proc "c" (self: Id, command: Sel, event: Id) {
	context = runtime.default_context()
	if !calendar_ui.shortcut_open || !calendar_ui.shortcut_listening {return}
	modifiers := calendar_msg_uint(event, sel_registerName("modifierFlags"))
	calendar_ui.shortcut_live_modifiers =
		calendar_shortcut_modifiers_from_event(modifiers)
	calendar_ui.needs_redraw = true
}

calendar_on_accepts_first :: proc "c" (self: Id, command: Sel) -> bool {
	return true
}

calendar_window_can_become_key :: proc "c" (self: Id, command: Sel) -> bool {
	return true
}

calendar_should_terminate :: proc "c" (self: Id, command: Sel, app: Id) -> bool {
	return true
}

calendar_push_rect :: proc(
	vertices: ^[dynamic]Calendar_Solid_Vertex,
	rect: Calendar_UI_Rect,
	color: [4]f32,
) {
	if rect.w <= 0 || rect.h <= 0 || calendar_ui.width <= 0 ||
	   calendar_ui.height <= 0 {
		return
	}
	x0 := f32(rect.x/calendar_ui.width*2-1)
	x1 := f32((rect.x+rect.w)/calendar_ui.width*2-1)
	y0 := f32(rect.y/calendar_ui.height*2-1)
	y1 := f32((rect.y+rect.h)/calendar_ui.height*2-1)
	v0 := Calendar_Solid_Vertex{x0, y0, color[0], color[1], color[2], color[3]}
	v1 := Calendar_Solid_Vertex{x1, y0, color[0], color[1], color[2], color[3]}
	v2 := Calendar_Solid_Vertex{x1, y1, color[0], color[1], color[2], color[3]}
	v3 := Calendar_Solid_Vertex{x0, y1, color[0], color[1], color[2], color[3]}
	append(vertices, v0, v1, v2, v0, v2, v3)
}

calendar_push_border :: proc(
	vertices: ^[dynamic]Calendar_Solid_Vertex,
	rect: Calendar_UI_Rect,
	color: [4]f32,
) {
	calendar_push_rect(vertices, {rect.x, rect.y, rect.w, 1}, color)
	calendar_push_rect(vertices, {rect.x, rect.y+rect.h-1, rect.w, 1}, color)
	calendar_push_rect(vertices, {rect.x, rect.y, 1, rect.h}, color)
	calendar_push_rect(vertices, {rect.x+rect.w-1, rect.y, 1, rect.h}, color)
}

calendar_occurrences_for_day :: proc(day: ICal_Date_Time) -> []Calendar_Occurrence {
	result := make([dynamic]Calendar_Occurrence, context.temp_allocator)
	day_start := ical_days_from_civil(day.year, day.month, day.day)*86400
	day_end := day_start+86400
	for occurrence in calendar_ui.occurrences {
		start := ical_date_time_stamp(occurrence.start)
		end := ical_date_time_stamp(occurrence.end)
		if end <= start {end = start+1}
		if start < day_end && end > day_start {append(&result, occurrence)}
	}
	return result[:]
}

Calendar_Day_Item_Kind :: enum {
	Event,
	Holiday,
}

Calendar_Day_Item :: struct {
	kind: Calendar_Day_Item_Kind,
	event: Calendar_Occurrence,
	holiday: Calendar_Holiday_Occurrence,
}

calendar_holiday_occurrence_is_promoted :: proc(
	occurrence: Calendar_Holiday_Occurrence,
) -> bool {
	return calendar_ui.promoted_holiday_active &&
	       occurrence.country_index ==
				calendar_ui.promoted_holiday_country_index &&
	       occurrence.definition_index ==
				calendar_ui.promoted_holiday_definition_index &&
	       ical_days_from_civil(
				occurrence.date.year,
				occurrence.date.month,
				occurrence.date.day,
		   ) == calendar_ui.promoted_holiday_days
}

calendar_event_occurrence_is_navigation_selected :: proc(
	occurrence: Calendar_Occurrence,
) -> bool {
	return calendar_ui.navigation_active &&
	       calendar_ui.navigation_kind == .Event &&
	       occurrence.event_index == calendar_ui.navigation_event_index &&
	       ical_date_time_stamp(occurrence.start) ==
			calendar_ui.navigation_start_stamp
}

calendar_holiday_occurrence_is_navigation_selected :: proc(
	occurrence: Calendar_Holiday_Occurrence,
) -> bool {
	return calendar_ui.navigation_active &&
	       calendar_ui.navigation_kind == .Holiday &&
	       occurrence.country_index == calendar_ui.navigation_holiday_country_index &&
	       occurrence.definition_index ==
			calendar_ui.navigation_holiday_definition_index &&
	       ical_date_time_stamp(occurrence.date) ==
			calendar_ui.navigation_start_stamp
}

calendar_day_item_is_navigation_selected :: proc(item: Calendar_Day_Item) -> bool {
	if item.kind == .Event {
		return calendar_event_occurrence_is_navigation_selected(item.event)
	}
	return calendar_holiday_occurrence_is_navigation_selected(item.holiday)
}

calendar_day_items :: proc(day: ICal_Date_Time) -> []Calendar_Day_Item {
	result := make([dynamic]Calendar_Day_Item, context.temp_allocator)
	day_days := ical_days_from_civil(day.year, day.month, day.day)
	if calendar_ui.navigation_active {
		for occurrence in calendar_occurrences_for_day(day) {
			if !calendar_event_occurrence_is_navigation_selected(occurrence) {continue}
			append(&result, Calendar_Day_Item{kind = .Event, event = occurrence})
			break
		}
		if len(result) == 0 {
			for occurrence in calendar_ui.holiday_occurrences {
				if ical_days_from_civil(
					occurrence.date.year,
					occurrence.date.month,
					occurrence.date.day,
				) != day_days ||
				   !calendar_holiday_occurrence_is_navigation_selected(occurrence) {
					continue
				}
				append(&result, Calendar_Day_Item{kind = .Holiday, holiday = occurrence})
				break
			}
		}
	} else {
		for occurrence in calendar_ui.holiday_occurrences {
			if ical_days_from_civil(
				occurrence.date.year,
				occurrence.date.month,
				occurrence.date.day,
			) == day_days && calendar_holiday_occurrence_is_promoted(occurrence) {
				append(&result, Calendar_Day_Item{
					kind = .Holiday,
					holiday = occurrence,
				})
				break
			}
		}
	}
	for occurrence in calendar_occurrences_for_day(day) {
		if calendar_event_occurrence_is_navigation_selected(occurrence) {continue}
		append(&result, Calendar_Day_Item{
			kind = .Event,
			event = occurrence,
		})
	}
	for occurrence in calendar_ui.holiday_occurrences {
		if ical_days_from_civil(
			occurrence.date.year,
			occurrence.date.month,
			occurrence.date.day,
		) != day_days || calendar_holiday_occurrence_is_promoted(occurrence) ||
		   calendar_holiday_occurrence_is_navigation_selected(occurrence) {
			continue
		}
		append(&result, Calendar_Day_Item{
			kind = .Holiday,
			holiday = occurrence,
		})
	}
	return result[:]
}

calendar_holiday_definition_for_occurrence :: proc(
	occurrence: Calendar_Holiday_Occurrence,
) -> (
	^Calendar_Holiday_Country,
	^Calendar_Holiday_Definition,
	bool,
) {
	if occurrence.country_index < 0 ||
	   occurrence.country_index >= len(calendar_ui.holiday_countries) {
		return nil, nil, false
	}
	country := &calendar_ui.holiday_countries[occurrence.country_index]
	if occurrence.definition_index < 0 ||
	   occurrence.definition_index >= len(country.entries) {
		return nil, nil, false
	}
	return country, &country.entries[occurrence.definition_index], true
}

calendar_detail_draw_field :: proc(
	ctx, font: rawptr,
	label, value: string,
	panel: Calendar_UI_Rect,
	cursor: ^f64,
	label_color, value_color: [4]f64,
	label_font: rawptr = nil,
) {
	if len(value) == 0 {return}
	effective_label_font := label_font
	if effective_label_font == nil {effective_label_font = font}
	calendar_draw_text(
		ctx,
		effective_label_font,
		label,
		{panel.x+20, cursor^-16, panel.w-40, 16},
		label_color,
		0,
		style = .Label,
	)
	cursor^ -= 10
	maximum := max(18, int((panel.w-40)/7))
	line := ""
	remaining := value
	for word in strings.split_iterator(&remaining, " ") {
		candidate := word if len(line) == 0 else fmt.tprintf("%s %s", line, word)
		if len(candidate) > maximum && len(line) > 0 {
			calendar_draw_text(
				ctx,
				font,
				line,
				{panel.x+20, cursor^-16, panel.w-40, 16},
				value_color,
				0,
			)
			cursor^ -= 16
			line = word
		} else {
			line = candidate
		}
	}
	if len(line) > 0 {
		calendar_draw_text(
			ctx,
			font,
			line,
			{panel.x+20, cursor^-16, panel.w-40, 16},
			value_color,
			0,
		)
		cursor^ -= 16
	}
	cursor^ -= 6
}

calendar_draw_details :: proc(
	ctx, font: rawptr,
	ink, muted: [4]f64,
) {
	panel := calendar_ui_details_rect()
	if !calendar_ui.navigation_active {
		calendar_draw_text(
			ctx,
			font,
			"FOCUSED DETAILS",
			{panel.x+16, panel.y+panel.h-42, panel.w-32, 24},
			ink,
			0,
		)
		calendar_draw_text(
			ctx,
			font,
			"SELECT AN EVENT OR HOLIDAY TO SHOW ITS DETAILS",
			{panel.x+16, panel.y+panel.h-72, panel.w-32, 20},
			muted,
			0,
		)
		return
	}
	CGContextSaveGState(ctx)
	CGContextClipToRect(
		ctx,
		{{panel.x*calendar_ui.scale, panel.y*calendar_ui.scale},
		 {panel.w*calendar_ui.scale, panel.h*calendar_ui.scale}},
	)
	cursor := panel.y+panel.h-16+calendar_ui.details_scroll
	if calendar_ui.navigation_kind == .Event &&
	   calendar_ui.navigation_event_index >= 0 &&
	   calendar_ui.navigation_event_index < len(calendar_ui.events) {
		event := &calendar_ui.events[calendar_ui.navigation_event_index]
		end := event.dtend
		for occurrence in calendar_ui.occurrences {
			if calendar_event_occurrence_is_navigation_selected(occurrence) {
				end = ical_format_date_time(occurrence.end)
				break
			}
		}
		calendar_detail_draw_field(ctx, font, "EVENT", event.summary, panel, &cursor, muted, ink)
		calendar_detail_draw_field(
			ctx, font, "START", ical_format_date_time(
				ical_date_time_from_stamp(calendar_ui.navigation_start_stamp),
			), panel, &cursor, muted, ink,
		)
		calendar_detail_draw_field(ctx, font, "END", end, panel, &cursor, muted, ink)
		calendar_detail_draw_field(ctx, font, "LOCATION", event.location, panel, &cursor, muted, ink)
		calendar_detail_draw_field(ctx, font, "CATEGORIES", event.categories, panel, &cursor, muted, ink)
		calendar_detail_draw_field(ctx, font, "IMPORTANCE", event.important ? "IMPORTANT" : "STANDARD", panel, &cursor, muted, ink)
		calendar_detail_draw_field(ctx, font, "DESCRIPTION", event.description, panel, &cursor, muted, ink)
		calendar_detail_draw_field(ctx, font, "RECURRENCE", event.rrule, panel, &cursor, muted, ink)
		calendar_detail_draw_field(ctx, font, "URL", event.url, panel, &cursor, muted, ink)
		calendar_detail_draw_field(ctx, font, "STATUS", event.status, panel, &cursor, muted, ink)
		if event.source == .EventKit {
			calendar_detail_draw_field(
				ctx,
				font,
				"CALENDAR",
				event.calendar_title,
				panel,
				&cursor,
				muted,
				ink,
			)
			calendar_detail_draw_field(
				ctx,
				font,
				"ACCOUNT",
				event.source_title,
				panel,
				&cursor,
				muted,
				ink,
			)
			calendar_detail_draw_field(
				ctx,
				font,
				"ACCESS",
				event.writable ? "WRITABLE" : "READ ONLY",
				panel,
				&cursor,
				muted,
				ink,
			)
			calendar_detail_draw_field(
				ctx,
				font,
				"TIME ZONE",
				event.time_zone,
				panel,
				&cursor,
				muted,
				ink,
			)
			calendar_detail_draw_field(
				ctx,
				font,
				"ALARMS",
				event.alarms,
				panel,
				&cursor,
				muted,
				ink,
			)
			calendar_detail_draw_field(
				ctx,
				font,
				"ORGANIZER",
				event.organizer,
				panel,
				&cursor,
				muted,
				ink,
			)
			calendar_detail_draw_field(
				ctx,
				font,
				"ATTENDEES",
				event.attendees,
				panel,
				&cursor,
				muted,
				ink,
			)
			calendar_detail_draw_field(
				ctx,
				font,
				"MY RESPONSE",
				event.participation_status,
				panel,
				&cursor,
				muted,
				ink,
			)
		}
		if len(calendar_eventkit_last_error) > 0 {
			calendar_detail_draw_field(
				ctx,
				font,
				"CONNECTED ERROR",
				calendar_eventkit_last_error,
				panel,
				&cursor,
				muted,
				calendar_color64(
					calendar_theme(calendar_ui.theme_id).destructive,
				),
			)
		}
	} else {
		occurrence := Calendar_Holiday_Occurrence{
			country_index = calendar_ui.navigation_holiday_country_index,
			definition_index = calendar_ui.navigation_holiday_definition_index,
			date = ical_date_time_from_stamp(calendar_ui.navigation_start_stamp, true),
		}
		country, definition, found := calendar_holiday_definition_for_occurrence(occurrence)
		if found {
			label_font := calendar_system_monospaced_font_for_style(.Label)
			heading_font := calendar_system_monospaced_font_for_style(.Heading)
			section_font := calendar_system_monospaced_font_weight(
				11*calendar_ui.scale,
				0.25,
			)
			if heading_font != nil {defer CFRelease(heading_font)}
			if section_font != nil {defer CFRelease(section_font)}
			if label_font != nil {defer CFRelease(label_font)}
			calendar_draw_text(
				ctx, label_font if label_font != nil else font,
				"HOLIDAY",
				{panel.x+20, cursor-16, panel.w-40, 16},
				muted,
				0,
				style = .Label,
			)
			cursor -= 44
			calendar_draw_text(
				ctx, heading_font if heading_font != nil else font,
				definition.name,
				{panel.x+20, cursor-28, panel.w-40, 32},
				ink,
				0,
				style = .Heading,
			)
			cursor -= 58
			column_gap := 20.0
			column_width := (panel.w-40-column_gap)/2
			calendar_draw_text(ctx, label_font if label_font != nil else font, "COUNTRY", {panel.x+20, cursor-16, column_width, 16}, muted, 0, style=.Label)
			calendar_draw_text(ctx, label_font if label_font != nil else font, "CATEGORY", {panel.x+20+column_width+column_gap, cursor-16, column_width, 16}, muted, 0, style=.Label)
			cursor -= 10
			calendar_draw_text(ctx, section_font if section_font != nil else font, country.country_name, {panel.x+20, cursor-20, column_width, 20}, ink, 0)
			calendar_draw_text(ctx, section_font if section_font != nil else font, calendar_holiday_kind_label(calendar_holiday_kind(definition.kind)), {panel.x+20+column_width+column_gap, cursor-20, column_width, 20}, ink, 0)
			cursor -= 22
			calendar_draw_text(ctx, label_font if label_font != nil else font, "DATE", {panel.x+20, cursor-16, panel.w-40, 16}, muted, 0, style=.Label)
			cursor -= 10
			calendar_draw_text(
				ctx, section_font if section_font != nil else font,
				fmt.tprintf("%04d-%02d-%02d", occurrence.date.year, occurrence.date.month, occurrence.date.day),
				{panel.x+20, cursor-20, panel.w-40, 20},
				ink,
				0,
			)
			cursor -= 36
			calendar_draw_text(ctx, section_font if section_font != nil else font, "SOURCE", {panel.x+20, cursor-18, panel.w-40, 18}, ink, 0)
			cursor -= 28
			calendar_detail_draw_field(ctx, font, "REFERENCE", country.source_title, panel, &cursor, muted, ink, label_font)
			calendar_detail_draw_field(ctx, font, "URL", country.source_url, panel, &cursor, muted, ink, label_font)
		}
	}
	CGContextRestoreGState(ctx)
}

calendar_build_geometry :: proc(vertices: ^[dynamic]Calendar_Solid_Vertex) {
	theme := calendar_theme(calendar_ui.theme_id)
	chassis := theme.canvas
	header := theme.header
	row := theme.surface
	row_alt := theme.raised
	important := theme.important
	button := theme.control
	ink := theme.overlay
	field := theme.control
	focus := theme.focus
	calendar_push_rect(vertices, {0, 0, calendar_ui.width, calendar_ui.height}, chassis)
	calendar_push_rect(vertices, calendar_ui_header_rect(), header)
	calendar_push_rect(vertices, calendar_ui_details_rect(), row_alt)
	buttons := [3]Calendar_UI_Rect{
		calendar_ui_today_rect(),
		calendar_ui_search_rect(),
		calendar_ui_new_rect(),
	}
	for rect in buttons {
		calendar_push_rect(vertices, rect, button)
	}
	now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
	anchor := ical_days_from_civil(now.year, now.month, now.day) +
	          i64(calendar_ui.day_offset)
	visible := calendar_ui_visible_day_count()
	for index in 0..<visible {
		day := ical_date_time_from_stamp((anchor+i64(index))*86400, true)
		rect := calendar_ui_day_rect(index)
		day_items := calendar_day_items(day)
		is_important := false
		for item in day_items {
			if item.kind == .Event && item.event.important {
				is_important = true
			}
		}
		color := row
		if index%2 == 1 {color = row_alt}
		if is_important {color = important}
		calendar_push_rect(vertices, rect, color)
		if ical_days_from_civil(day.year, day.month, day.day) ==
		   ical_days_from_civil(now.year, now.month, now.day) {
			calendar_push_border(vertices, rect, focus)
		}
		for item, item_index in day_items {
			if item_index >= 3 {break}
			event_rect := calendar_ui_event_rect(rect, item_index, min(3, len(day_items)))
			event_color := button
			if item.kind == .Holiday {
				calendar_push_rect(vertices, event_rect, event_color)
				_, definition, found :=
					calendar_holiday_definition_for_occurrence(item.holiday)
				if found {
					accent := theme.holiday
					if calendar_holiday_kind(definition.kind) == .Memorial_Day {
						accent = theme.memorial
					}
					calendar_push_rect(
						vertices,
						{event_rect.x, event_rect.y, 4, event_rect.h},
						accent,
					)
				}
				if calendar_day_item_is_navigation_selected(item) {
					calendar_push_border(vertices, event_rect, focus)
				}
				if !calendar_ui.editor_open && !calendar_ui.archive_modal_open &&
				   !calendar_ui.settings_open && !calendar_ui.shortcut_open {
					calendar_ui_add_control(
						fmt.tprintf(
							"holiday:%d:%d:%d",
							item.holiday.country_index,
							item.holiday.definition_index,
							ical_date_time_stamp(item.holiday.date),
						),
						"holiday",
						event_rect,
						.Focus_Holiday,
						occurrence_stamp = ical_date_time_stamp(item.holiday.date),
						holiday_country_index = item.holiday.country_index,
						holiday_definition_index = item.holiday.definition_index,
					)
				}
				continue
			}
			upper_categories := strings.to_upper(
				item.event.categories,
				context.temp_allocator,
			)
			personal := strings.contains(upper_categories, "PERSONAL")
			work := strings.contains(upper_categories, "WORK")
			if personal {event_color = theme.personal}
			if work {event_color = theme.work}
			calendar_push_rect(vertices, event_rect, event_color)
			if personal && work {
				calendar_push_rect(
					vertices,
					{event_rect.x, event_rect.y, 4, event_rect.h},
					theme.warm,
				)
				calendar_push_rect(
					vertices,
					{event_rect.x+4, event_rect.y, 4, event_rect.h},
					theme.cool,
				)
			}
			if calendar_day_item_is_navigation_selected(item) {
				calendar_push_border(vertices, event_rect, focus)
			}
			if !calendar_ui.editor_open && !calendar_ui.archive_modal_open &&
			   !calendar_ui.settings_open && !calendar_ui.shortcut_open {
				calendar_ui_add_control(
					fmt.tprintf(
						"event:%s:%s:%d:%d",
						item.event.uid,
						item.event.recurrence_id,
						ical_date_time_stamp(item.event.start),
						ical_date_time_stamp(day),
					),
					"event",
					event_rect,
					.Focus_Event,
					item.event.event_index,
					ical_date_time_stamp(item.event.start),
					item.event.start.is_date,
				)
			}
		}
	}
	action_kinds := [6]Calendar_UI_Action{
		.Action_Edit,
		.Action_Open_URL,
		.Action_Archive,
		.Action_Complete,
		.Action_Confirm_Proposal,
		.Action_Reject_Proposal,
	}
	action_names := [5]string{
		"action edit",
		"action open url",
		"action archive",
		"action copy connected",
		"action apple calendar",
	}
	action_labels := [5]string{
		"edit",
		"open url",
		"archive",
		"copy connected",
		"apple calendar",
	}
	number_prefix_active :=
		calendar_ui.number_prefix == 1 &&
		calendar_number_time_ms() < calendar_ui.number_prefix_deadline_ms
	for action, action_index in action_kinds {
		action_rect := calendar_ui_action_rect(action_index)
		available := calendar_ui_action_available(action)
		calendar_push_rect(vertices, action_rect, available ? button : field)
		if number_prefix_active {
			calendar_push_border(vertices, action_rect, focus)
		}
		if available && !calendar_ui.editor_open &&
		   !calendar_ui.archive_modal_open && !calendar_ui.settings_open &&
		   !calendar_ui.shortcut_open {
			calendar_ui_add_control(
				action_names[action_index],
				action_labels[action_index],
				action_rect,
				action,
			)
		}
	}
	if calendar_ui.editor_open && !calendar_ui.settings_open &&
	   !calendar_ui.shortcut_open {
		calendar_push_rect(
			vertices,
			{0, 0, calendar_ui.width, calendar_ui.height},
			ink,
		)
		modal := calendar_ui_editor_rect()
		calendar_push_rect(vertices, modal, header)
		for field_index in 0..<10 {
			field_rect := calendar_ui_editor_field_rect(field_index)
			calendar_push_rect(
				vertices,
				field_rect,
				field,
			)
			if field_index == calendar_ui.editor_field {
				calendar_push_border(vertices, field_rect, focus)
			}
			calendar_ui_add_control(
				fmt.tprintf("editor field %d", field_index),
				"field",
				field_rect,
				.Editor_Field,
				field_index,
			)
		}
		important_rect := Calendar_UI_Rect{
			modal.x+18,
			modal.y+20,
			112,
			34,
		}
		important_color := row_alt
		if calendar_ui.editor_important {
			important_color = theme.important
		}
		calendar_push_rect(
			vertices,
			important_rect,
			important_color,
		)
		calendar_ui_add_control(
			"editor important",
			"important",
			important_rect,
			.Editor_Important,
		)
		all_day_rect := calendar_ui_editor_all_day_rect()
		calendar_push_rect(
			vertices,
			all_day_rect,
			calendar_ui.editor_all_day ? theme.important : row_alt,
		)
		calendar_ui_add_control(
			"editor all day",
			"all day",
			all_day_rect,
			.Editor_All_Day,
		)
		if calendar_ui_editor_can_select_calendar() {
			calendar_rect := calendar_ui_editor_calendar_rect()
			calendar_push_rect(vertices, calendar_rect, button)
			calendar_ui_add_control(
				"editor event calendar",
				"select event calendar",
				calendar_rect,
				.Editor_Calendar,
			)
		}
		save_rect := calendar_ui_editor_button_rect(0)
		cancel_rect := calendar_ui_editor_button_rect(1)
		calendar_push_rect(vertices, save_rect, theme.positive)
		calendar_push_rect(vertices, cancel_rect, button)
		calendar_ui_add_control(
			"editor save",
			"save",
			save_rect,
			.Editor_Save,
		)
		calendar_ui_add_control(
			"editor cancel",
			"cancel",
			cancel_rect,
			.Editor_Cancel,
		)
		if calendar_ui.editor_event_index >= 0 {
			delete_rect := calendar_ui_editor_button_rect(2)
			calendar_push_rect(
				vertices,
				delete_rect,
				theme.destructive,
			)
			calendar_ui_add_control(
				"editor delete",
				"delete",
				delete_rect,
				.Editor_Delete,
			)
		}
	}
	if calendar_ui.archive_modal_open && !calendar_ui.settings_open &&
	   !calendar_ui.shortcut_open {
		modal := calendar_ui_archive_modal_rect()
		calendar_push_rect(vertices, modal, row_alt)
		event := &calendar_ui.events[calendar_ui.navigation_event_index]
		recurring := calendar_event_is_recurring(event)
		connected := event.source == .EventKit
		count := recurring ? 3 : 2
		cancel_index := count-1
		if recurring {
			occurrence_rect := calendar_ui_archive_button_rect(0, count)
			series_rect := calendar_ui_archive_button_rect(1, count)
			calendar_push_rect(vertices, occurrence_rect, button)
			calendar_push_rect(vertices, series_rect, theme.destructive)
			calendar_ui_add_control(
				connected ? "delete connected occurrence" : "archive occurrence",
				connected ? "delete occurrence" : "archive occurrence",
				occurrence_rect,
				.Archive_Occurrence,
			)
			calendar_ui_add_control(
				connected ? "delete connected future" : "archive series",
				connected ? "delete future" : "archive series",
				series_rect,
				.Archive_Series,
			)
		} else {
			archive_rect := calendar_ui_archive_button_rect(0, count)
			calendar_push_rect(vertices, archive_rect, theme.destructive)
			calendar_ui_add_control(
				connected ? "delete connected event" : "archive event",
				connected ? "delete event" : "archive event",
				archive_rect,
				.Archive_Occurrence,
			)
		}
		cancel_rect := calendar_ui_archive_button_rect(cancel_index, count)
		calendar_push_rect(vertices, cancel_rect, button)
		calendar_ui_add_control(
			connected ? "delete connected cancel" : "archive cancel",
			connected ? "cancel delete" : "cancel archive",
			cancel_rect,
			.Archive_Cancel,
		)
	}
	if calendar_ui.settings_open && !calendar_ui.shortcut_open {
		calendar_push_rect(
			vertices,
			{0, 0, calendar_ui.width, calendar_ui.height},
			theme.overlay,
		)
		modal := calendar_settings_rect()
		calendar_push_rect(vertices, modal, theme.header)
		search_rect := calendar_settings_search_rect()
		calendar_push_rect(vertices, search_rect, theme.control)
		if calendar_ui.settings_query_focused {
			calendar_push_border(vertices, search_rect, theme.focus)
		}
		calendar_ui_add_action_control(
			"settings search",
			"search settings",
			search_rect,
			{kind = .Settings_Search},
		)
		close_rect := calendar_settings_close_rect()
		calendar_push_rect(vertices, close_rect, theme.control)
		calendar_ui_add_action_control(
			"settings close",
			"close settings",
			close_rect,
			{kind = .Settings_Close},
		)
		categories := [3]Calendar_Settings_Category{
			.Styling,
			.Connected_Calendars,
			.Shortcuts,
		}
		for category, index in categories {
			rect := calendar_settings_category_rect(index)
			calendar_push_rect(vertices, rect, theme.control)
			if !calendar_settings_search_active() &&
			   category == calendar_ui.settings_category {
				calendar_push_border(vertices, rect, theme.focus)
			}
			calendar_ui_add_action_control(
				fmt.tprintf("settings category %s", calendar_settings_category_name(category)),
				fmt.tprintf("%s settings", calendar_settings_category_name(category)),
				rect,
				{kind = .Settings_Category, index = index},
			)
		}
		for descriptor, index in calendar_settings_result_descriptors() {
			if index >= 10 {break}
			rect := calendar_settings_result_rect(index)
			calendar_push_rect(vertices, rect, theme.raised)
			if descriptor.action.kind == .Set_Theme &&
			   descriptor.action.theme_id == calendar_ui.theme_id {
				calendar_push_border(vertices, rect, theme.focus)
			} else if descriptor.action.kind == .Toggle_Connected_Calendar &&
			          descriptor.action.index >= 0 &&
			          descriptor.action.index < len(calendar_eventkit_calendars) &&
			          calendar_connected_calendar_visible(
						calendar_eventkit_calendars[
							descriptor.action.index
						].identifier,
			          ) {
				calendar_push_border(vertices, rect, theme.focus)
			}
			calendar_ui_add_action_control(
				fmt.tprintf("setting:%d", descriptor.id),
				strings.to_lower(descriptor.title, context.temp_allocator),
				rect,
				descriptor.action,
			)
		}
	}
	if calendar_ui.shortcut_open {
		calendar_push_rect(
			vertices,
			{0, 0, calendar_ui.width, calendar_ui.height},
			theme.overlay,
		)
		modal := calendar_shortcut_modal_rect()
		calendar_push_rect(vertices, modal, theme.header)
		record_rect := calendar_shortcut_record_rect()
		calendar_push_rect(vertices, record_rect, theme.control)
		if calendar_ui.shortcut_listening {
			calendar_push_border(vertices, record_rect, theme.focus)
		} else {
			calendar_ui_add_action_control(
				"shortcut record",
				"record another shortcut",
				record_rect,
				{kind = .Shortcut_Record},
			)
		}
		save_rect := calendar_shortcut_action_rect(0)
		reset_rect := calendar_shortcut_action_rect(1)
		cancel_rect := calendar_shortcut_action_rect(2)
		save_enabled := calendar_ui.shortcut_candidate_valid &&
		                len(calendar_ui.shortcut_collision) == 0
		calendar_push_rect(
			vertices,
			save_rect,
			save_enabled ? theme.positive : theme.control,
		)
		calendar_push_rect(vertices, reset_rect, theme.control)
		calendar_push_rect(vertices, cancel_rect, theme.control)
		if save_enabled {
			calendar_ui_add_action_control(
				"shortcut save",
				"save shortcut",
				save_rect,
				{kind = .Shortcut_Save},
			)
		}
		calendar_ui_add_action_control(
			"shortcut reset",
			"reset shortcut",
			reset_rect,
			{kind = .Shortcut_Reset},
		)
		calendar_ui_add_action_control(
			"shortcut cancel",
			"cancel shortcut",
			cancel_rect,
			{kind = .Shortcut_Cancel},
		)
	}
	if command_palette.is_open(&calendar_ui.palette) {
		modal := calendar_ui_palette_rect()
		calendar_push_rect(
			vertices,
			modal,
			theme.overlay,
		)
		calendar_ui_add_action_control(
			"command palette search",
			"search commands",
			calendar_text_field_rect(.Command_Palette),
			{kind = .Command_Palette_Search},
		)
	}
	for index in 0..<4 {
		calendar_push_rect(
			vertices,
			calendar_ui_window_control_rect(index),
			button,
		)
	}
}

Calendar_Text_Run :: struct {
	line: rawptr,
	advance, ascent, descent, leading: f64,
}

Calendar_Text_Alignment :: enum {
	Start,
	Center,
	End,
}

Calendar_Icon_Point :: struct {
	point: Point,
	move: bool,
}

calendar_icon_xmark_points :: proc() -> [8]Calendar_Icon_Point {
	return {
		{{6.75827, 17.2426}, true},
		{{12.0009, 12}, false},
		{{17.2435, 6.75736}, true},
		{{12.0009, 12}, false},
		{{12.0009, 12}, true},
		{{6.75827, 6.75736}, false},
		{{12.0009, 12}, true},
		{{17.2435, 17.2426}, false},
	}
}

calendar_icon_minus_points :: proc() -> [2]Calendar_Icon_Point {
	return {
		{{6, 12}, true},
		{{18, 12}, false},
	}
}

calendar_icon_maximize_points :: proc() -> [12]Calendar_Icon_Point {
	return {
		{{7, 4}, true},
		{{4, 4}, false},
		{{4, 7}, false},
		{{17, 4}, true},
		{{20, 4}, false},
		{{20, 7}, false},
		{{7, 20}, true},
		{{4, 20}, false},
		{{4, 17}, false},
		{{17, 20}, true},
		{{20, 20}, false},
		{{20, 17}, false},
	}
}

calendar_text_run :: proc(
	font: rawptr,
	text: string,
	style := Calendar_Text_Style.Body,
) -> Calendar_Text_Run {
	if len(text) == 0 {return {}}
	bytes := transmute([]u8)text
	string_ref := CFStringCreateWithBytes(
		nil,
		raw_data(bytes),
		CF.Index(len(bytes)),
		CF.StringEncoding(0x08000100),
		false,
	)
	if string_ref == nil {return {}}
	defer CFRelease(string_ref)
	attributed := CFAttributedStringCreateMutable(nil, 0)
	if attributed == nil {return {}}
	defer CFRelease(attributed)
	CFAttributedStringReplaceString(attributed, {0, 0}, string_ref)
	range := CF.Range{0, CF.Index(CFStringGetLength(string_ref))}
	CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName, font)
	tracking := calendar_text_style_spec(style).tracking*calendar_ui.scale
	tracking_number := CFNumberCreate(nil, 13, &tracking)
	if tracking_number != nil {
		defer CFRelease(tracking_number)
		CFAttributedStringSetAttribute(
			attributed,
			range,
			kCTKernAttributeName,
			tracking_number,
		)
	}
	CFAttributedStringSetAttribute(
		attributed,
		range,
		kCTForegroundColorFromContextAttributeName,
		kCFBooleanTrue,
	)
	result: Calendar_Text_Run
	result.line = CTLineCreateWithAttributedString(attributed)
	if result.line != nil {
		result.advance = CTLineGetTypographicBounds(
			result.line,
			&result.ascent,
			&result.descent,
			&result.leading,
		)
	}
	return result
}

calendar_draw_text :: proc(
	ctx, font: rawptr,
	text: string,
	rect: Calendar_UI_Rect,
	color: [4]f64,
	inset := 8.0,
	alignment := Calendar_Text_Alignment.Start,
	style := Calendar_Text_Style.Body,
) {
	run := calendar_text_run(font, text, style)
	if run.line == nil {return}
	defer CFRelease(run.line)
	CGContextSaveGState(ctx)
	CGContextClipToRect(
		ctx,
		{
			{rect.x*calendar_ui.scale, rect.y*calendar_ui.scale},
			{rect.w*calendar_ui.scale, rect.h*calendar_ui.scale},
		},
	)
	CGContextSetRGBFillColor(ctx, color[0], color[1], color[2], color[3])
	x := (rect.x+inset)*calendar_ui.scale
	switch alignment {
	case .Center:
		x = rect.x*calendar_ui.scale +
		    (rect.w*calendar_ui.scale-run.advance)/2
	case .End:
		x = (rect.x+rect.w-inset)*calendar_ui.scale-run.advance
	case .Start:
	}
	y := rect.y*calendar_ui.scale +
	     (rect.h*calendar_ui.scale-(run.ascent+run.descent))/2 +
	     run.descent
	CGContextSetTextPosition(ctx, x, y)
	CTLineDraw(run.line, ctx)
	CGContextRestoreGState(ctx)
}

calendar_draw_numbered_action :: proc(
	ctx, font: rawptr,
	label: string,
	number: int,
	rect: Calendar_UI_Rect,
	label_color, number_color: [4]f64,
) {
	calendar_draw_text(
		ctx,
		font,
		fmt.tprintf("%d", number),
		{rect.x+8, rect.y, 28, rect.h},
		number_color,
		0,
	)
	calendar_draw_text(
		ctx,
		font,
		label,
		{rect.x+36, rect.y, rect.w-44, rect.h},
		label_color,
		0,
	)
}

calendar_fill_overlay_rect :: proc(
	ctx: rawptr,
	rect: Calendar_UI_Rect,
	color: [4]f64,
) {
	CGContextSetRGBFillColor(ctx, color[0], color[1], color[2], color[3])
	CGContextFillRect(
		ctx,
		{
			{rect.x*calendar_ui.scale, rect.y*calendar_ui.scale},
			{rect.w*calendar_ui.scale, rect.h*calendar_ui.scale},
		},
	)
}

calendar_fill_overlay_border :: proc(
	ctx: rawptr,
	rect: Calendar_UI_Rect,
	color: [4]f64,
) {
	calendar_fill_overlay_rect(ctx, {rect.x, rect.y, rect.w, 1}, color)
	calendar_fill_overlay_rect(
		ctx,
		{rect.x, rect.y+rect.h-1, rect.w, 1},
		color,
	)
	calendar_fill_overlay_rect(ctx, {rect.x, rect.y, 1, rect.h}, color)
	calendar_fill_overlay_rect(
		ctx,
		{rect.x+rect.w-1, rect.y, 1, rect.h},
		color,
	)
}

calendar_flash_badge_rect :: proc(
	target: flash.Target,
	label_length: int,
	view_width, view_height: f64,
) -> Calendar_UI_Rect {
	width := max(16, 8+f64(label_length)*8)
	height := 18.0
	rect := target.rect
	x, y := rect.x+2, rect.y+rect.h-height-2
	#partial switch target.anchor {
	case .Top_Right:
		x = rect.x+rect.w-width-2
	case .Bottom_Left:
		y = rect.y+2
	case .Bottom_Right:
		x, y = rect.x+rect.w-width-2, rect.y+2
	case .Center:
		x, y = rect.x+(rect.w-width)/2, rect.y+(rect.h-height)/2
	}
	x = min(max(x, 0), max(0, view_width-width))
	y = min(max(y, 0), max(0, view_height-height))
	return {x, y, width, height}
}

calendar_draw_flash_hints :: proc(ctx, font: rawptr) {
	if !flash.is_active(&calendar_ui.flash) {return}
	background := [4]f64{0.96, 0.94, 0.85, 1}
	foreground := [4]f64{0.025, 0.027, 0.026, 1}
	border := [4]f64{0.02, 0.02, 0.02, 1}
	selected_background := [4]f64{0.98, 0.35, 0.09, 1}
	selected_border := [4]f64{1.0, 0.55, 0.18, 1}
	for &hint in flash.visible_hints(&calendar_ui.flash) {
		badge := calendar_flash_badge_rect(
			hint.target,
			len(hint.label),
			calendar_ui.width,
			calendar_ui.height,
		)
		badge_background := hint.selected ? selected_background : background
		badge_border := hint.selected ? selected_border : border
		if hint.selected {
			target := hint.target.rect
			calendar_fill_overlay_border(
				ctx,
				{target.x, target.y, target.w, target.h},
				selected_border,
			)
		}
		calendar_fill_overlay_rect(ctx, badge, badge_background)
		calendar_fill_overlay_border(ctx, badge, badge_border)
		calendar_draw_text(
			ctx,
			font,
			hint.label,
			badge,
			foreground,
			0,
			.Center,
		)
	}
}

calendar_draw_icon_path :: proc(
	ctx: rawptr,
	rect: Calendar_UI_Rect,
	color: [4]f64,
	points: []Calendar_Icon_Point,
) {
	CGContextSaveGState(ctx)
	defer CGContextRestoreGState(ctx)
	CGContextClipToRect(
		ctx,
		{
			{rect.x*calendar_ui.scale, rect.y*calendar_ui.scale},
			{rect.w*calendar_ui.scale, rect.h*calendar_ui.scale},
		},
	)
	CGContextSetRGBStrokeColor(
		ctx,
		color[0],
		color[1],
		color[2],
		color[3],
	)
	CGContextSetLineWidth(
		ctx,
		1.5*calendar_ui.scale*min(rect.w, rect.h)/24,
	)
	CGContextSetLineCap(ctx, 1)
	CGContextSetLineJoin(ctx, 1)
	CGContextBeginPath(ctx)
	for command in points {
		x := (rect.x+command.point.x*rect.w/24)*calendar_ui.scale
		y := (rect.y+(24-command.point.y)*rect.h/24)*calendar_ui.scale
		if command.move {
			CGContextMoveToPoint(ctx, x, y)
		} else {
			CGContextAddLineToPoint(ctx, x, y)
		}
	}
	CGContextStrokePath(ctx)
}

calendar_icon_point :: proc(
	rect: Calendar_UI_Rect,
	x, y: f64,
) -> Point {
	return {
		(rect.x+x*rect.w/24)*calendar_ui.scale,
		(rect.y+(24-y)*rect.h/24)*calendar_ui.scale,
	}
}

calendar_draw_settings_icon :: proc(
	ctx: rawptr,
	rect: Calendar_UI_Rect,
	color: [4]f64,
) {
	CGContextSaveGState(ctx)
	defer CGContextRestoreGState(ctx)
	CGContextClipToRect(
		ctx,
		{
			{rect.x*calendar_ui.scale, rect.y*calendar_ui.scale},
			{rect.w*calendar_ui.scale, rect.h*calendar_ui.scale},
		},
	)
	CGContextSetRGBStrokeColor(
		ctx,
		color[0],
		color[1],
		color[2],
		color[3],
	)
	CGContextSetLineWidth(
		ctx,
		1.5*calendar_ui.scale*min(rect.w, rect.h)/24,
	)
	CGContextSetLineCap(ctx, 1)
	CGContextSetLineJoin(ctx, 1)
	CGContextBeginPath(ctx)
	p := calendar_icon_point(rect, 12, 15)
	CGContextMoveToPoint(ctx, p.x, p.y)
	c1 := calendar_icon_point(rect, 13.6569, 15)
	c2 := calendar_icon_point(rect, 15, 13.6569)
	p = calendar_icon_point(rect, 15, 12)
	CGContextAddCurveToPoint(ctx, c1.x, c1.y, c2.x, c2.y, p.x, p.y)
	c1 = calendar_icon_point(rect, 15, 10.3431)
	c2 = calendar_icon_point(rect, 13.6569, 9)
	p = calendar_icon_point(rect, 12, 9)
	CGContextAddCurveToPoint(ctx, c1.x, c1.y, c2.x, c2.y, p.x, p.y)
	c1 = calendar_icon_point(rect, 10.3431, 9)
	c2 = calendar_icon_point(rect, 9, 10.3431)
	p = calendar_icon_point(rect, 9, 12)
	CGContextAddCurveToPoint(ctx, c1.x, c1.y, c2.x, c2.y, p.x, p.y)
	c1 = calendar_icon_point(rect, 9, 13.6569)
	c2 = calendar_icon_point(rect, 10.3431, 15)
	p = calendar_icon_point(rect, 12, 15)
	CGContextAddCurveToPoint(ctx, c1.x, c1.y, c2.x, c2.y, p.x, p.y)
	CGContextClosePath(ctx)

	gear := [30]Point{
		{19.6224, 10.3954},
		{18.5247, 7.7448},
		{20, 6},
		{18, 4},
		{16.2647, 5.48295},
		{13.5578, 4.36974},
		{12.9353, 2},
		{10.981, 2},
		{10.3491, 4.40113},
		{7.70441, 5.51596},
		{6, 4},
		{4, 6},
		{5.45337, 7.78885},
		{4.3725, 10.4463},
		{2, 11},
		{2, 13},
		{4.40111, 13.6555},
		{5.51575, 16.2997},
		{4, 18},
		{6, 20},
		{7.79116, 18.5403},
		{10.397, 19.6123},
		{11, 22},
		{13, 22},
		{13.6045, 19.6132},
		{16.2551, 18.5155},
		{18.5159, 16.2494},
		{19.6139, 13.598},
		{21.9999, 12.9772},
		{22, 11},
	}
	p = calendar_icon_point(rect, gear[0].x, gear[0].y)
	CGContextMoveToPoint(ctx, p.x, p.y)
	for index in 1..<26 {
		p = calendar_icon_point(rect, gear[index].x, gear[index].y)
		CGContextAddLineToPoint(ctx, p.x, p.y)
	}
	c1 = calendar_icon_point(rect, 16.6969, 18.8313)
	c2 = calendar_icon_point(rect, 18, 20)
	p = calendar_icon_point(rect, 18, 20)
	CGContextAddCurveToPoint(ctx, c1.x, c1.y, c2.x, c2.y, p.x, p.y)
	p = calendar_icon_point(rect, 20, 18)
	CGContextAddLineToPoint(ctx, p.x, p.y)
	for index in 26..<len(gear) {
		p = calendar_icon_point(rect, gear[index].x, gear[index].y)
		CGContextAddLineToPoint(ctx, p.x, p.y)
	}
	p = calendar_icon_point(rect, 19.6224, 10.3954)
	CGContextAddLineToPoint(ctx, p.x, p.y)
	CGContextClosePath(ctx)
	CGContextStrokePath(ctx)
}

calendar_draw_window_controls :: proc(ctx: rawptr) {
	theme := calendar_theme(calendar_ui.theme_id)
	colors := [3][4]f64{
		calendar_color64(theme.destructive),
		calendar_color64(theme.warm),
		calendar_color64(theme.cool),
	}
	xmark := calendar_icon_xmark_points()
	calendar_draw_icon_path(
		ctx,
		calendar_ui_window_icon_rect(0),
		colors[0],
		xmark[:],
	)
	minus := calendar_icon_minus_points()
	calendar_draw_icon_path(
		ctx,
		calendar_ui_window_icon_rect(1),
		colors[1],
		minus[:],
	)
	maximize := calendar_icon_maximize_points()
	calendar_draw_icon_path(
		ctx,
		calendar_ui_window_icon_rect(2),
		colors[2],
		maximize[:],
	)
	calendar_draw_settings_icon(
		ctx,
		calendar_ui_settings_icon_rect(),
		calendar_color64(theme.text_soft),
	)
}

calendar_build_text_overlay :: proc(width, height: uint) -> []u8 {
	pixels := make([]u8, int(width*height*4))
	space := CGColorSpaceCreateDeviceRGB()
	ctx := CGBitmapContextCreate(
		raw_data(pixels),
		width,
		height,
		8,
		width*4,
		space,
		0x2002,
	)
	CGColorSpaceRelease(space)
	if ctx == nil {return pixels}
	defer CGContextRelease(ctx)
	CGContextClearRect(ctx, {{0, 0}, {f64(width), f64(height)}})
	font := calendar_system_monospaced_font_for_style(.Body)
	if font == nil {return pixels}
	defer CFRelease(font)
	theme := calendar_theme(calendar_ui.theme_id)
	ink := calendar_color64(theme.text)
	ink_soft := calendar_color64(theme.text_soft)
	muted := calendar_color64(theme.muted)
	inverse := calendar_color64(theme.inverse)
	calendar_draw_text(
		ctx,
		font,
		"hw_calendar / CONTINUOUS DAYS",
		calendar_ui_title_rect(),
		ink,
		0,
	)
	today_color := calendar_color64(theme.warm)
	search_color := calendar_color64(theme.cool)
	new_color := calendar_color64(theme.warm_strong)
	calendar_draw_text(ctx, font, "TODAY", calendar_ui_today_rect(), today_color, 0, .Center)
	calendar_draw_text(ctx, font, "SEARCH", calendar_ui_search_rect(), search_color, 0, .Center)
	calendar_draw_text(ctx, font, "NEW EVENT", calendar_ui_new_rect(), new_color, 0, .Center)
	now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
	anchor := ical_days_from_civil(now.year, now.month, now.day) +
	          i64(calendar_ui.day_offset)
	visible := calendar_ui_visible_day_count()
	weekdays := [7]string{"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"}
	for index in 0..<visible {
		day := ical_date_time_from_stamp((anchor+i64(index))*86400, true)
		rect := calendar_ui_day_rect(index)
		date_text := fmt.tprintf(
			"%s  %04d-%02d-%02d",
			weekdays[int(ical_weekday(day))],
			day.year,
			day.month,
			day.day,
		)
		calendar_draw_text(ctx, font, date_text, {rect.x+8, rect.y, 164, rect.h}, muted, 0)
		day_items := calendar_day_items(day)
		for item, item_index in day_items {
			if item_index >= 3 {break}
			event_rect := calendar_ui_event_rect(rect, item_index, min(3, len(day_items)))
			if item.kind == .Holiday {
				country, definition, found :=
					calendar_holiday_definition_for_occurrence(item.holiday)
				if found {
					calendar_draw_text(
						ctx,
						font,
						fmt.tprintf(
							"%s / %s",
							country.country_code,
							definition.name,
						),
						event_rect,
						ink,
						8,
					)
				}
				continue
			}
			time_text := "ALL DAY"
			if !item.event.start.is_date {
				time_text = fmt.tprintf(
					"%02d:%02d  %s",
					item.event.start.hour,
					item.event.start.minute,
					item.event.summary,
				)
			} else {
				time_text = fmt.tprintf("ALL DAY  %s", item.event.summary)
			}
			upper_categories := strings.to_upper(
				item.event.categories,
				context.temp_allocator,
			)
			has_accent_fill :=
				strings.contains(upper_categories, "PERSONAL") ||
				strings.contains(upper_categories, "WORK")
			text_color := ink
			if theme.dark || has_accent_fill {
				text_color = inverse
			}
			calendar_draw_text(ctx, font, time_text, event_rect, text_color)
		}
		if len(day_items) > 3 {
			calendar_draw_text(
				ctx,
				font,
				fmt.tprintf("+%d", len(day_items)-3),
				{rect.x+rect.w-42, rect.y, 38, rect.h},
				ink_soft,
				0,
			)
		}
	}
	calendar_draw_details(ctx, font, ink, muted)
	action_kinds := [6]Calendar_UI_Action{
		.Action_Edit,
		.Action_Open_URL,
		.Action_Archive,
		.Action_Complete,
		.Action_Confirm_Proposal,
		.Action_Reject_Proposal,
	}
	action_labels := [6]string{
		"EDIT",
		"OPEN URL",
		"DISMISS",
		"COMPLETE",
		"CONFIRM",
		"REJECT",
	}
	for action, action_index in action_kinds {
		label := action_labels[action_index]
		if action == .Action_Archive &&
		   calendar_ui.navigation_active &&
		   calendar_ui.navigation_kind == .Event &&
		   calendar_ui.navigation_event_index >= 0 &&
		   calendar_ui.navigation_event_index < len(calendar_ui.events) &&
		   calendar_ui.events[calendar_ui.navigation_event_index].source ==
				.EventKit {
			label = "DELETE"
		}
		rect := calendar_ui_action_rect(action_index)
		color := muted
		if calendar_ui_action_available(action) {color = ink}
		calendar_draw_numbered_action(
			ctx,
			font,
			label,
			11+action_index,
			rect,
			color,
			muted,
		)
	}
	if calendar_ui.editor_open {
		CGContextClearRect(
			ctx,
			{{0, 0}, {f64(width), f64(height)}},
		)
		modal := calendar_ui_editor_rect()
		title := "NEW EVENT"
		if calendar_ui.editor_event_index >= 0 {title = "EDIT EVENT"}
		calendar_draw_text(
			ctx,
			font,
			title,
			{modal.x+18, modal.y+modal.h-48, modal.w-36, 34},
			ink,
			0,
		)
		labels := [10]string{
			"SUMMARY",
			"START",
			"END",
			"LOCATION",
			"URL",
			"CATEGORIES",
			"DESCRIPTION",
			"TIME ZONE",
			"ALARMS",
			"RRULE",
		}
		values := [10]string{
			calendar_ui.editor_summary,
			calendar_ui.editor_start,
			calendar_ui.editor_end,
			calendar_ui.editor_location,
			calendar_ui.editor_url,
			calendar_ui.editor_categories,
			calendar_ui.editor_description,
			calendar_ui.editor_time_zone,
			calendar_ui.editor_alarms,
			calendar_ui.editor_rrule,
		}
		for field_index in 0..<10 {
			field_rect := calendar_ui_editor_field_rect(field_index)
			calendar_draw_text(
				ctx,
				font,
				labels[field_index],
				{field_rect.x-82, field_rect.y, 76, field_rect.h},
				muted,
				0,
			)
			calendar_draw_editable_text(
				ctx,
				font,
				calendar_text_editor_field(field_index),
				values[field_index],
				"",
				field_rect,
				ink,
				muted,
				calendar_color64(theme.focus),
			)
		}
		important_rect := Calendar_UI_Rect{
			modal.x+18,
			modal.y+20,
			112,
			34,
		}
		calendar_draw_text(
			ctx,
			font,
			calendar_ui.editor_important ? "IMPORTANT: YES" : "IMPORTANT: NO",
			important_rect,
			calendar_ui.editor_important ? calendar_color64(theme.important) : muted,
		)
		all_day_text_color := muted
		if calendar_ui.editor_all_day {
			all_day_text_color = calendar_color64(theme.important)
		}
		calendar_draw_text(
			ctx,
			font,
			calendar_ui.editor_all_day ? "ALL DAY: YES" : "ALL DAY: NO",
			calendar_ui_editor_all_day_rect(),
			all_day_text_color,
			8,
		)
		if calendar_ui_editor_can_select_calendar() {
			calendar_draw_text(
				ctx,
				font,
				fmt.tprintf(
					"CALENDAR: %s",
					calendar_ui_editor_calendar_title(),
				),
				calendar_ui_editor_calendar_rect(),
				muted,
				8,
			)
		}
		calendar_draw_text(
			ctx,
			font,
			"SAVE",
			calendar_ui_editor_button_rect(0),
			inverse,
		)
		calendar_draw_text(
			ctx,
			font,
			"CANCEL",
			calendar_ui_editor_button_rect(1),
			muted,
		)
		if calendar_ui.editor_event_index >= 0 {
			calendar_draw_text(
				ctx,
				font,
				"DELETE",
				calendar_ui_editor_button_rect(2),
				inverse,
			)
		}
		if len(calendar_ui.editor_error) > 0 {
			calendar_draw_text(
				ctx,
				font,
				calendar_ui.editor_error,
				{modal.x+18, modal.y+60, modal.w-36, 28},
				calendar_color64(theme.destructive),
				0,
			)
		}
	}
	if calendar_ui.archive_modal_open {
		backdrop := [4]f64{0.02, 0.02, 0.02, 0.28}
		if theme.dark {backdrop = [4]f64{0.0, 0.0, 0.0, 0.38}}
		calendar_fill_overlay_rect(
			ctx,
			{0, 0, calendar_ui.width, calendar_ui.height},
			backdrop,
		)
		modal := calendar_ui_archive_modal_rect()
		CGContextClearRect(
			ctx,
			{
				{modal.x*calendar_ui.scale, modal.y*calendar_ui.scale},
				{modal.w*calendar_ui.scale, modal.h*calendar_ui.scale},
			},
		)
		event := &calendar_ui.events[calendar_ui.navigation_event_index]
		recurring := calendar_event_is_recurring(event)
		connected := event.source == .EventKit
		dialog_title := connected ? "DELETE EVENT" : "ARCHIVE EVENT"
		calendar_draw_text(
			ctx,
			font,
			dialog_title,
			{modal.x+24, modal.y+modal.h-52, modal.w-48, 30},
			ink,
			0,
		)
		calendar_draw_text(
			ctx,
			font,
			event.summary,
			{modal.x+24, modal.y+modal.h-92, modal.w-48, 28},
			calendar_color64(theme.warm),
			0,
		)
		message := "ARCHIVED EVENTS ARE HIDDEN FROM THE CALENDAR AND REMINDERS"
		if connected {
			message = "EVENTKIT WILL DELETE THIS EVENT FROM ITS CONNECTED CALENDAR"
		}
		if recurring && connected {
			message = "CHOOSE THIS OCCURRENCE OR THIS AND FUTURE OCCURRENCES"
		} else if recurring {
			message = "CHOOSE WHETHER TO ARCHIVE THIS OCCURRENCE OR THE COMPLETE SERIES"
		}
		calendar_draw_text(
			ctx,
			font,
			message,
			{modal.x+24, modal.y+modal.h-128, modal.w-48, 24},
			muted,
			0,
		)
		count := recurring ? 3 : 2
		if recurring {
			calendar_draw_numbered_action(
				ctx,
				font,
				connected ? "DELETE OCCURRENCE" : "ARCHIVE OCCURRENCE",
				1,
				calendar_ui_archive_button_rect(0, count),
				ink,
				muted,
			)
			calendar_draw_numbered_action(
				ctx,
				font,
				connected ? "DELETE FUTURE" : "ARCHIVE SERIES",
				2,
				calendar_ui_archive_button_rect(1, count),
				inverse,
				inverse,
			)
		} else {
			calendar_draw_numbered_action(
				ctx,
				font,
				connected ? "DELETE" : "ARCHIVE",
				1,
				calendar_ui_archive_button_rect(0, count),
				inverse,
				inverse,
			)
		}
		calendar_draw_numbered_action(
			ctx,
			font,
			"CANCEL",
			count,
			calendar_ui_archive_button_rect(count-1, count),
			muted,
			muted,
		)
		if len(calendar_ui.archive_error) > 0 {
			calendar_draw_text(
				ctx,
				font,
				calendar_ui.archive_error,
				{modal.x+24, modal.y+62, modal.w-48, 24},
				calendar_color64(theme.destructive),
				0,
			)
		}
	}
	if calendar_ui.settings_open {
		calendar_fill_overlay_rect(
			ctx,
			{0, 0, calendar_ui.width, calendar_ui.height},
			calendar_color64(theme.overlay),
		)
		modal := calendar_settings_rect()
		CGContextClearRect(
			ctx,
			{
				{modal.x*calendar_ui.scale, modal.y*calendar_ui.scale},
				{modal.w*calendar_ui.scale, modal.h*calendar_ui.scale},
			},
		)
		calendar_draw_editable_text(
			ctx,
			font,
			.Settings_Search,
			calendar_ui.settings_query,
			"SEARCH SETTINGS",
			calendar_settings_search_rect(),
			ink,
			muted,
			calendar_color64(theme.focus),
		)
		xmark := calendar_icon_xmark_points()
		close_icon := calendar_settings_close_rect()
		calendar_draw_icon_path(
			ctx,
			{close_icon.x+5, close_icon.y+8, 18, 18},
			muted,
			xmark[:],
		)
		categories := [3]Calendar_Settings_Category{
			.Styling,
			.Connected_Calendars,
			.Shortcuts,
		}
		for category, index in categories {
			count := calendar_settings_category_match_count(category)
			color := muted
			if !calendar_settings_search_active() &&
			   category == calendar_ui.settings_category {
				color = ink
			}
			calendar_draw_text(
				ctx,
				font,
				fmt.tprintf(
					"%s  %02d",
					calendar_settings_category_name(category),
					count,
				),
				calendar_settings_category_rect(index),
				color,
			)
		}
		for descriptor, index in calendar_settings_result_descriptors() {
			if index >= 10 {break}
			rect := calendar_settings_result_rect(index)
			color := ink
			value := ""
			if descriptor.action.kind == .Set_Theme &&
			   descriptor.action.theme_id == calendar_ui.theme_id {
				value = "CURRENT"
			} else if descriptor.action.kind == .Configure_Flash {
				value = calendar_shortcut_display(calendar_ui.flash_leader)
			} else if descriptor.action.kind == .Request_Calendar_Access {
				value = strings.to_upper(
					calendar_eventkit_authorization_name(),
					context.temp_allocator,
				)
			} else if descriptor.action.kind == .Toggle_Connected_Calendar &&
			          descriptor.action.index >= 0 &&
			          descriptor.action.index < len(calendar_eventkit_calendars) {
				calendar := &calendar_eventkit_calendars[
					descriptor.action.index
				]
				value = calendar_connected_calendar_visible(
					calendar.identifier,
				) ? "VISIBLE" : "HIDDEN"
				if !calendar.writable {
					value = fmt.tprintf("%s · READ ONLY", value)
				}
			} else if descriptor.action.kind ==
			          .Set_Default_Connected_Calendar &&
			          descriptor.action.index >= 0 &&
			          descriptor.action.index < len(calendar_eventkit_calendars) {
				default_identifier, _ := calendar_connected_default_calendar(
					context.temp_allocator,
				)
				default_calendar := &calendar_eventkit_calendars[
					descriptor.action.index
				]
				if default_identifier == default_calendar.identifier {
					value = "DEFAULT"
				}
			}
			calendar_draw_text(
				ctx,
				font,
				descriptor.title,
				{rect.x+8, rect.y, rect.w*0.58, rect.h},
				color,
				0,
			)
			if len(value) > 0 {
				value_color := muted
				if descriptor.action.kind == .Set_Theme {
					value_color = calendar_color64(theme.focus)
				}
				calendar_draw_text(
					ctx,
					font,
					value,
					{rect.x+rect.w*0.60, rect.y, rect.w*0.38-8, rect.h},
					value_color,
					0,
					.End,
				)
			}
		}
		if len(calendar_ui.settings_error) > 0 {
			content := calendar_settings_content_rect()
			calendar_draw_text(
				ctx,
				font,
				calendar_ui.settings_error,
				{content.x, content.y, content.w, 24},
				calendar_color64(theme.destructive),
				0,
			)
		}
	}
	if calendar_ui.shortcut_open {
		calendar_fill_overlay_rect(
			ctx,
			{0, 0, calendar_ui.width, calendar_ui.height},
			calendar_color64(theme.overlay),
		)
		modal := calendar_shortcut_modal_rect()
		CGContextClearRect(
			ctx,
			{
				{modal.x*calendar_ui.scale, modal.y*calendar_ui.scale},
				{modal.w*calendar_ui.scale, modal.h*calendar_ui.scale},
			},
		)
		calendar_draw_text(
			ctx,
			font,
			"CONFIGURE FLASH LEADER",
			{modal.x+24, modal.y+modal.h-50, modal.w-48, 30},
			ink,
			0,
		)
		calendar_draw_text(
			ctx,
			font,
			"PRESS ONE KEY WITH ANY COMMAND, CONTROL, OPTION, OR SHIFT MODIFIERS",
			{modal.x+24, modal.y+modal.h-80, modal.w-48, 22},
			muted,
			0,
		)
		record_text := "PRESS A KEY…"
		if calendar_ui.shortcut_candidate_valid {
			record_text = calendar_shortcut_display(
				calendar_ui.shortcut_candidate,
			)
		} else if calendar_ui.shortcut_listening &&
		          calendar_ui.shortcut_live_modifiers != {} {
			preview := Calendar_Shortcut{
				kind = .Character,
				key = "…",
				modifiers = calendar_ui.shortcut_live_modifiers,
			}
			record_text = calendar_shortcut_display(preview)
		}
		calendar_draw_text(
			ctx,
			font,
			record_text,
			calendar_shortcut_record_rect(),
			calendar_ui.shortcut_listening ? calendar_color64(theme.focus) : ink,
			0,
			.Center,
		)
		status := calendar_ui.shortcut_collision
		if len(calendar_ui.shortcut_error) > 0 {
			status = calendar_ui.shortcut_error
		}
		if len(status) > 0 {
			calendar_draw_text(
				ctx,
				font,
				status,
				{modal.x+24, modal.y+64, modal.w-48, 20},
				calendar_color64(theme.destructive),
				0,
			)
		} else if calendar_ui.shortcut_candidate_valid {
			calendar_draw_text(
				ctx,
				font,
				"READY TO SAVE",
				{modal.x+24, modal.y+64, modal.w-48, 20},
				calendar_color64(theme.positive),
				0,
			)
		}
		save_color := muted
		if calendar_ui.shortcut_candidate_valid &&
		   len(calendar_ui.shortcut_collision) == 0 {
			save_color = ink
		}
		calendar_draw_numbered_action(
			ctx,
			font,
			"SAVE",
			1,
			calendar_shortcut_action_rect(0),
			save_color,
			muted,
		)
		calendar_draw_numbered_action(
			ctx,
			font,
			"RESET DEFAULT",
			2,
			calendar_shortcut_action_rect(1),
			ink,
			muted,
		)
		calendar_draw_numbered_action(
			ctx,
			font,
			"CANCEL",
			3,
			calendar_shortcut_action_rect(2),
			muted,
			muted,
		)
	}
	if command_palette.is_open(&calendar_ui.palette) {
		modal := calendar_ui_palette_rect()
		CGContextClearRect(
			ctx,
			{
				{modal.x*calendar_ui.scale, modal.y*calendar_ui.scale},
				{modal.w*calendar_ui.scale, modal.h*calendar_ui.scale},
			},
		)
		calendar_draw_editable_text(
			ctx,
			font,
			.Command_Palette,
			calendar_ui.palette_query,
			"SEARCH COMMANDS",
			calendar_text_field_rect(.Command_Palette),
			inverse,
			muted,
			calendar_color64(theme.focus),
		)
		for result, index in command_palette.visible_results(&calendar_ui.palette) {
			if index >= 10 {break}
			color := muted
			if result.available {color = ink_soft}
			if index == command_palette.selected_index(&calendar_ui.palette) {
				color = inverse
			}
			title := fmt.tprintf(
				"%-12s  %s",
				result.entry.category,
				result.entry.title,
			)
			if !result.available && len(result.entry.unavailable_reason) > 0 {
				title = fmt.tprintf(
					"%s  —  %s",
					title,
					result.entry.unavailable_reason,
				)
			}
			calendar_draw_text(
				ctx,
				font,
				title,
				{modal.x+16, modal.y+modal.h-84-f64(index)*34, modal.w-32, 30},
				color,
			)
		}
	}
	calendar_draw_flash_hints(ctx, font)
	calendar_draw_window_controls(ctx)
	return pixels
}

calendar_compile_pipelines :: proc() -> bool {
	source := `
#include <metal_stdlib>
using namespace metal;
struct SolidVertex { float x; float y; float r; float g; float b; float a; };
struct TextureVertex { float x; float y; float u; float v; float r; float g; float b; float a; };
struct SolidOut { float4 position [[position]]; float4 color; };
struct TextureOut { float4 position [[position]]; float2 uv; float4 color; };
vertex SolidOut solid_vertex(const device SolidVertex *v [[buffer(0)]], uint i [[vertex_id]]) {
	SolidOut o; o.position=float4(v[i].x,v[i].y,0,1); o.color=float4(v[i].r,v[i].g,v[i].b,v[i].a); return o;
}
fragment float4 solid_fragment(SolidOut in [[stage_in]]) { return in.color; }
vertex TextureOut texture_vertex(const device TextureVertex *v [[buffer(0)]], uint i [[vertex_id]]) {
	TextureOut o; o.position=float4(v[i].x,v[i].y,0,1); o.uv=float2(v[i].u,v[i].v); o.color=float4(v[i].r,v[i].g,v[i].b,v[i].a); return o;
}
fragment float4 texture_fragment(TextureOut in [[stage_in]], texture2d<float> image [[texture(0)]]) {
	constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
	return image.sample(s, in.uv) * in.color;
}`
	error: Id
	library := calendar_msg_id_id_error(
		calendar_ui.device,
		sel_registerName("newLibraryWithSource:options:error:"),
		nsstring(source),
		nil,
		&error,
	)
	if library == nil {return false}
	defer msg_void(library, sel_registerName("release"))
	solid_vertex := msg_id_id(library, sel_registerName("newFunctionWithName:"), nsstring("solid_vertex"))
	solid_fragment := msg_id_id(library, sel_registerName("newFunctionWithName:"), nsstring("solid_fragment"))
	texture_vertex := msg_id_id(library, sel_registerName("newFunctionWithName:"), nsstring("texture_vertex"))
	texture_fragment := msg_id_id(library, sel_registerName("newFunctionWithName:"), nsstring("texture_fragment"))
	defer msg_void(solid_vertex, sel_registerName("release"))
	defer msg_void(solid_fragment, sel_registerName("release"))
	defer msg_void(texture_vertex, sel_registerName("release"))
	defer msg_void(texture_fragment, sel_registerName("release"))
	desc := msg_id(objc_getClass("MTLRenderPipelineDescriptor"), sel_registerName("new"))
	defer msg_void(desc, sel_registerName("release"))
	msg_void_id(desc, sel_registerName("setVertexFunction:"), solid_vertex)
	msg_void_id(desc, sel_registerName("setFragmentFunction:"), solid_fragment)
	attachments := msg_id(desc, sel_registerName("colorAttachments"))
	index_send := transmute(proc "c" (Id, Sel, uint) -> Id)objc_send_address
	attachment := index_send(
		attachments,
		sel_registerName("objectAtIndexedSubscript:"),
		0,
	)
	msg_void_u(attachment, sel_registerName("setPixelFormat:"), 80)
	msg_void_bool(attachment, sel_registerName("setBlendingEnabled:"), true)
	msg_void_u(attachment, sel_registerName("setSourceRGBBlendFactor:"), 4)
	msg_void_u(attachment, sel_registerName("setDestinationRGBBlendFactor:"), 5)
	msg_void_u(attachment, sel_registerName("setSourceAlphaBlendFactor:"), 1)
	msg_void_u(attachment, sel_registerName("setDestinationAlphaBlendFactor:"), 5)
	calendar_ui.solid_pipeline = calendar_msg_id_id_error_2(
		calendar_ui.device,
		sel_registerName("newRenderPipelineStateWithDescriptor:error:"),
		desc,
		&error,
	)
	texture_desc := msg_id(objc_getClass("MTLRenderPipelineDescriptor"), sel_registerName("new"))
	defer msg_void(texture_desc, sel_registerName("release"))
	msg_void_id(texture_desc, sel_registerName("setVertexFunction:"), texture_vertex)
	msg_void_id(texture_desc, sel_registerName("setFragmentFunction:"), texture_fragment)
	texture_attachments := msg_id(texture_desc, sel_registerName("colorAttachments"))
	texture_attachment := index_send(
		texture_attachments,
		sel_registerName("objectAtIndexedSubscript:"),
		0,
	)
	msg_void_u(texture_attachment, sel_registerName("setPixelFormat:"), 80)
	msg_void_bool(texture_attachment, sel_registerName("setBlendingEnabled:"), true)
	msg_void_u(texture_attachment, sel_registerName("setSourceRGBBlendFactor:"), 1)
	msg_void_u(texture_attachment, sel_registerName("setDestinationRGBBlendFactor:"), 5)
	msg_void_u(texture_attachment, sel_registerName("setSourceAlphaBlendFactor:"), 1)
	msg_void_u(texture_attachment, sel_registerName("setDestinationAlphaBlendFactor:"), 5)
	calendar_ui.texture_pipeline = calendar_msg_id_id_error_2(
		calendar_ui.device,
		sel_registerName("newRenderPipelineStateWithDescriptor:error:"),
		texture_desc,
		&error,
	)
	return calendar_ui.solid_pipeline != nil && calendar_ui.texture_pipeline != nil
}

calendar_ensure_text_texture :: proc(width, height: uint) -> bool {
	if calendar_ui.text_texture != nil && calendar_ui.text_width == width &&
	   calendar_ui.text_height == height {
		return true
	}
	desc := msg_id_u_u_u_b(
		objc_getClass("MTLTextureDescriptor"),
		sel_registerName("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
		80,
		width,
		height,
		false,
	)
	texture := msg_id_id(calendar_ui.device, sel_registerName("newTextureWithDescriptor:"), desc)
	if texture == nil {return false}
	if calendar_ui.text_texture != nil {
		msg_void(calendar_ui.text_texture, sel_registerName("release"))
	}
	calendar_ui.text_texture = texture
	calendar_ui.text_width = width
	calendar_ui.text_height = height
	return true
}

calendar_texture_vertices :: proc(rect: Calendar_UI_Rect) -> [6]Calendar_Texture_Vertex {
	x0 := f32(rect.x/calendar_ui.width*2-1)
	x1 := f32((rect.x+rect.w)/calendar_ui.width*2-1)
	y0 := f32(rect.y/calendar_ui.height*2-1)
	y1 := f32((rect.y+rect.h)/calendar_ui.height*2-1)
	v0 := Calendar_Texture_Vertex{x0, y0, 0, 1, 1, 1, 1, 1}
	v1 := Calendar_Texture_Vertex{x1, y0, 1, 1, 1, 1, 1, 1}
	v2 := Calendar_Texture_Vertex{x1, y1, 1, 0, 1, 1, 1, 1}
	v3 := Calendar_Texture_Vertex{x0, y1, 0, 0, 1, 1, 1, 1}
	return {v0, v1, v2, v0, v2, v3}
}

calendar_render_frame :: proc() {
	if calendar_ui.layer == nil || calendar_ui.width <= 0 || calendar_ui.height <= 0 {return}
	drawable := msg_id(calendar_ui.layer, sel_registerName("nextDrawable"))
	if drawable == nil {return}
	texture := msg_id(drawable, sel_registerName("texture"))
	command_buffer := msg_id(calendar_ui.queue, sel_registerName("commandBuffer"))
	pass := msg_id(objc_getClass("MTLRenderPassDescriptor"), sel_registerName("renderPassDescriptor"))
	attachments := msg_id(pass, sel_registerName("colorAttachments"))
	index_send := transmute(proc "c" (Id, Sel, uint) -> Id)objc_send_address
	attachment := index_send(attachments, sel_registerName("objectAtIndexedSubscript:"), 0)
	msg_void_id(attachment, sel_registerName("setTexture:"), texture)
	msg_void_u(attachment, sel_registerName("setLoadAction:"), 2)
	msg_void_u(attachment, sel_registerName("setStoreAction:"), 1)
	active_theme := calendar_theme(calendar_ui.theme_id)
	clear_color := Calendar_MTL_Clear_Color{
		f64(active_theme.canvas[0]),
		f64(active_theme.canvas[1]),
		f64(active_theme.canvas[2]),
		1,
	}
	calendar_msg_void_clear_color(
		attachment,
		sel_registerName("setClearColor:"),
		clear_color,
	)
	encoder := msg_id_id(
		command_buffer,
		sel_registerName("renderCommandEncoderWithDescriptor:"),
		pass,
	)
	vertices := make([dynamic]Calendar_Solid_Vertex, context.temp_allocator)
	calendar_ui_clear_controls()
	window_actions := [3]Calendar_UI_Action{
		.Window_Close,
		.Window_Minimize,
		.Window_Zoom,
	}
	window_names := [3]string{
		"window close",
		"window minimize",
		"window zoom",
	}
	window_labels := [3]string{
		"close window",
		"minimize window",
		"zoom window",
	}
	for action, index in window_actions {
		calendar_ui_add_control(
			window_names[index],
			window_labels[index],
			calendar_ui_window_control_rect(index),
			action,
		)
	}
	if !calendar_ui.shortcut_open {
		calendar_ui_add_control(
			"settings",
			"settings",
			calendar_ui_settings_rect(),
			.Open_Settings,
		)
	}
	if !calendar_ui.editor_open && !calendar_ui.archive_modal_open &&
	   !calendar_ui.settings_open && !calendar_ui.shortcut_open {
		calendar_ui_add_control(
			"today",
			"today",
			calendar_ui_today_rect(),
			.Today,
		)
		calendar_ui_add_control(
			"search",
			"search calendar",
			calendar_ui_search_rect(),
			.Search,
		)
		calendar_ui_add_control(
			"new event",
			"new event",
			calendar_ui_new_rect(),
			.New_Event,
		)
	}
	calendar_build_geometry(&vertices)
	calendar_ui_rebuild_accessibility()
	msg_void_id(encoder, sel_registerName("setRenderPipelineState:"), calendar_ui.solid_pipeline)
	max_vertices := 168
	for start := 0; start < len(vertices); start += max_vertices {
		count := min(max_vertices, len(vertices)-start)
		batch := vertices[start:start+count]
		msg_void_ptr_u_u(
			encoder,
			sel_registerName("setVertexBytes:length:atIndex:"),
			raw_data(batch),
			uint(len(batch))*size_of(Calendar_Solid_Vertex),
			0,
		)
		msg_void_u_u_u(
			encoder,
			sel_registerName("drawPrimitives:vertexStart:vertexCount:"),
			3,
			0,
			uint(len(batch)),
		)
	}
	pixel_width := uint(max(1, calendar_ui.width*calendar_ui.scale))
	pixel_height := uint(max(1, calendar_ui.height*calendar_ui.scale))
	if calendar_ensure_text_texture(pixel_width, pixel_height) {
		pixels := calendar_build_text_overlay(pixel_width, pixel_height)
		calendar_msg_void_region(
			calendar_ui.text_texture,
			sel_registerName("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"),
			{{0, 0, 0}, {pixel_width, pixel_height, 1}},
			0,
			raw_data(pixels),
			pixel_width*4,
		)
		delete(pixels)
		texture_vertices := calendar_texture_vertices(
			{0, 0, calendar_ui.width, calendar_ui.height},
		)
		msg_void_id(encoder, sel_registerName("setRenderPipelineState:"), calendar_ui.texture_pipeline)
		msg_void_ptr_u_u(
			encoder,
			sel_registerName("setVertexBytes:length:atIndex:"),
			raw_data(texture_vertices[:]),
			size_of(texture_vertices),
			0,
		)
		msg_void_id_u(
			encoder,
			sel_registerName("setFragmentTexture:atIndex:"),
			calendar_ui.text_texture,
			0,
		)
		msg_void_u_u_u(
			encoder,
			sel_registerName("drawPrimitives:vertexStart:vertexCount:"),
			3,
			0,
			6,
		)
	}
	msg_void(encoder, sel_registerName("endEncoding"))
	msg_void_id(command_buffer, sel_registerName("presentDrawable:"), drawable)
	msg_void(command_buffer, sel_registerName("commit"))
	calendar_ui.frame_index += 1
	calendar_ui.needs_redraw = false
}

calendar_on_frame :: proc "c" (self: Id, command: Sel, timer: Id) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if calendar_eventkit_external_refresh_requested() {
		calendar_ui_reload_data()
	}
	if calendar_eventkit_consume_result() {
		calendar_ui_reload_data(false)
	}
	_ = calendar_expire_number_prefix_at(calendar_number_time_ms())
	now_stamp := time.to_unix_seconds(time.now())
	if calendar_ui.notification_reconcile_stamp == 0 ||
	   now_stamp-calendar_ui.notification_reconcile_stamp >= 3600 {
		calendar_notification_reconcile()
	}
	frame := msg_rect(calendar_ui.view, sel_registerName("bounds"))
	if frame.size.width != calendar_ui.width || frame.size.height != calendar_ui.height {
		calendar_ui.width = frame.size.width
		calendar_ui.height = frame.size.height
		flash.cancel(&calendar_ui.flash)
		calendar_ui.needs_redraw = true
	}
	window := msg_id(calendar_ui.view, sel_registerName("window"))
	if window != nil {
		scale := msg_f64(window, sel_registerName("backingScaleFactor"))
		if scale > 0 && scale != calendar_ui.scale {
			calendar_ui.scale = scale
			calendar_ui.needs_redraw = true
		}
	}
	calendar_msg_void_size(
		calendar_ui.layer,
		sel_registerName("setDrawableSize:"),
		{calendar_ui.width*calendar_ui.scale, calendar_ui.height*calendar_ui.scale},
	)
	if calendar_ui.needs_redraw {calendar_render_frame()}
}

calendar_register_accessibility_class :: proc() {
	class := objc_allocateClassPair(
		objc_getClass("NSAccessibilityElement"),
		"hw_calendar_AccessibilityElement",
		0,
	)
	class_addMethod(
		class,
		sel_registerName("accessibilityPerformPress"),
		rawptr(calendar_on_ax_press),
		"B@:",
	)
	class_addMethod(
		class,
		sel_registerName("accessibilityValue"),
		rawptr(calendar_on_ax_value),
		"@@:",
	)
	class_addMethod(
		class,
		sel_registerName("setAccessibilityValue:"),
		rawptr(calendar_on_ax_set_value),
		"v@:@",
	)
	objc_registerClassPair(class)
}

calendar_register_classes :: proc() -> Id {
	delegate_class := objc_allocateClassPair(
		objc_getClass("NSObject"),
		"hw_calendar_Delegate",
		0,
	)
	class_addMethod(delegate_class, sel_registerName("calendarFrame:"), rawptr(calendar_on_frame), "v@:@")
	class_addMethod(
		delegate_class,
		sel_registerName("calendarCLIRequest:"),
		rawptr(calendar_on_cli_ipc_request),
		"v@:@",
	)
	class_addMethod(
		delegate_class,
		sel_registerName("calendarEventStoreChanged:"),
		rawptr(calendar_eventkit_store_changed),
		"v@:@",
	)
	class_addMethod(
		delegate_class,
		sel_registerName("applicationShouldTerminateAfterLastWindowClosed:"),
		rawptr(calendar_should_terminate),
		"B@:@",
	)
	class_addMethod(
		delegate_class,
		sel_registerName("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:"),
		rawptr(calendar_notification_response),
		"v@:@@@",
	)
	class_addMethod(
		delegate_class,
		sel_registerName("userNotificationCenter:willPresentNotification:withCompletionHandler:"),
		rawptr(calendar_notification_foreground),
		"v@:@@@",
	)
	if notification_protocol := objc_getProtocol(
		"UNUserNotificationCenterDelegate",
	); notification_protocol != nil {
		class_addProtocol(delegate_class, notification_protocol)
	}
	objc_registerClassPair(delegate_class)
	calendar_ui.delegate = msg_id(delegate_class, sel_registerName("new"))
	view_class := objc_allocateClassPair(
		objc_getClass("NSView"),
		"hw_calendar_MetalView",
		0,
	)
	if protocol := objc_getProtocol("NSTextInputClient"); protocol != nil {
		class_addProtocol(view_class, protocol)
	}
	class_addMethod(view_class, sel_registerName("acceptsFirstResponder"), rawptr(calendar_on_accepts_first), "B@:")
	class_addMethod(view_class, sel_registerName("mouseDown:"), rawptr(calendar_on_mouse_down), "v@:@")
	class_addMethod(view_class, sel_registerName("mouseDragged:"), rawptr(calendar_on_mouse_dragged), "v@:@")
	class_addMethod(view_class, sel_registerName("mouseUp:"), rawptr(calendar_on_mouse_up), "v@:@")
	class_addMethod(view_class, sel_registerName("scrollWheel:"), rawptr(calendar_on_scroll), "v@:@")
	class_addMethod(view_class, sel_registerName("keyDown:"), rawptr(calendar_on_key_down), "v@:@")
	class_addMethod(view_class, sel_registerName("flagsChanged:"), rawptr(calendar_on_flags_changed), "v@:@")
	class_addMethod(view_class, sel_registerName("copy:"), rawptr(calendar_on_text_copy), "v@:@")
	class_addMethod(view_class, sel_registerName("cut:"), rawptr(calendar_on_text_cut), "v@:@")
	class_addMethod(view_class, sel_registerName("paste:"), rawptr(calendar_on_text_paste), "v@:@")
	class_addMethod(
		view_class,
		sel_registerName("selectAll:"),
		rawptr(calendar_on_text_select_all),
		"v@:@",
	)
	class_addMethod(
		view_class,
		sel_registerName("insertText:"),
		rawptr(calendar_on_text_insert_simple),
		"v@:@",
	)
	class_addMethod(
		view_class,
		sel_registerName("insertText:replacementRange:"),
		rawptr(calendar_on_text_insert),
		"v@:@{_NSRange=QQ}",
	)
	class_addMethod(
		view_class,
		sel_registerName("doCommandBySelector:"),
		rawptr(calendar_on_text_command),
		"v@::",
	)
	class_addMethod(
		view_class,
		sel_registerName("setMarkedText:selectedRange:replacementRange:"),
		rawptr(calendar_on_text_set_marked),
		"v@:@{_NSRange=QQ}{_NSRange=QQ}",
	)
	class_addMethod(view_class, sel_registerName("unmarkText"), rawptr(calendar_on_text_unmark), "v@:")
	class_addMethod(view_class, sel_registerName("hasMarkedText"), rawptr(calendar_on_text_has_marked), "B@:")
	class_addMethod(
		view_class,
		sel_registerName("markedRange"),
		rawptr(calendar_on_text_range),
		"{_NSRange=QQ}@:",
	)
	class_addMethod(
		view_class,
		sel_registerName("selectedRange"),
		rawptr(calendar_on_text_range),
		"{_NSRange=QQ}@:",
	)
	class_addMethod(
		view_class,
		sel_registerName("validAttributesForMarkedText"),
		rawptr(calendar_on_text_valid_attributes),
		"@@:",
	)
	class_addMethod(
		view_class,
		sel_registerName("attributedSubstringForProposedRange:actualRange:"),
		rawptr(calendar_on_text_attributed_substring),
		"@@:{_NSRange=QQ}^{_NSRange=QQ}",
	)
	class_addMethod(
		view_class,
		sel_registerName("characterIndexForPoint:"),
		rawptr(calendar_on_text_character_index),
		"Q@:{CGPoint=dd}",
	)
	class_addMethod(
		view_class,
		sel_registerName("firstRectForCharacterRange:actualRange:"),
		rawptr(calendar_on_text_first_rect),
		"{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}",
	)
	class_addMethod(
		view_class,
		sel_registerName("isAccessibilityElement"),
		rawptr(calendar_on_ax_is_element),
		"B@:",
	)
	class_addMethod(
		view_class,
		sel_registerName("accessibilityChildren"),
		rawptr(calendar_on_ax_children),
		"@@:",
	)
	objc_registerClassPair(view_class)
	return view_class
}

calendar_register_window_class :: proc() -> Id {
	window_class := objc_allocateClassPair(
		objc_getClass("NSWindow"),
		"hw_calendar_Window",
		0,
	)
	class_addMethod(
		window_class,
		sel_registerName("canBecomeKeyWindow"),
		rawptr(calendar_window_can_become_key),
		"B@:",
	)
	class_addMethod(
		window_class,
		sel_registerName("canBecomeMainWindow"),
		rawptr(calendar_window_can_become_key),
		"B@:",
	)
	objc_registerClassPair(window_class)
	return window_class
}

calendar_ui_destroy :: proc() {
	calendar_events_destroy(&calendar_ui.events)
	calendar_occurrences_destroy(&calendar_ui.occurrences)
	calendar_holiday_countries_destroy(&calendar_ui.holiday_countries)
	delete(calendar_ui.holiday_occurrences)
	calendar_ui_clear_controls()
	delete(calendar_ui.controls)
	delete(calendar_ui.palette_query)
	delete(calendar_ui.palette_actions)
	delete(calendar_ui.archive_error)
	delete(calendar_ui.settings_query)
	delete(calendar_ui.settings_error)
	delete(calendar_ui.shortcut_collision)
	delete(calendar_ui.shortcut_error)
	calendar_shortcut_destroy(&calendar_ui.shortcut_candidate)
	calendar_shortcut_destroy(&calendar_ui.flash_leader)
	text_input.destroy(&calendar_ui.input_state)
	calendar_ui_editor_clear()
	if calendar_ui.ax_children != nil {
		msg_void(calendar_ui.ax_children, sel_registerName("release"))
	}
	delete(calendar_ui.ax_bindings)
	flash.state_destroy(&calendar_ui.flash)
	command_palette.state_destroy(&calendar_ui.palette)
	command_palette.state_destroy(&calendar_ui.settings_search)
	objects := [5]Id{
		calendar_ui.text_texture,
		calendar_ui.solid_pipeline,
		calendar_ui.texture_pipeline,
		calendar_ui.queue,
		calendar_ui.delegate,
	}
	for object in objects {
		if object != nil {msg_void(object, sel_registerName("release"))}
	}
	calendar_ui = {}
}

calendar_launch_should_activate :: proc(
	value: string,
	launch_in_background := false,
) -> bool {
	if len(value) > 0 {return value != "0"}
	return !launch_in_background
}

calendar_gui_initialize :: proc() -> bool {
	if !objc_initialize() {
		fmt.eprintln("hw_calendar could not initialize the Objective-C runtime.")
		return false
	}
	calendar_ui.scale = 1
	calendar_ui.needs_redraw = true
	calendar_ui.theme_id = .HW_Light
	if theme, found := calendar_meta_get("interface_theme", context.temp_allocator);
	   found {
		if id, valid := calendar_theme_from_storage(theme); valid {
			calendar_ui.theme_id = id
			canonical := calendar_theme(id).storage_id
			if theme != canonical {
				_ = calendar_meta_set("interface_theme", canonical)
			}
		}
	}
	calendar_ui.flash_leader = calendar_shortcut_clone(
		calendar_shortcut_default(),
	)
	if binding, found := calendar_meta_get("flash_leader", context.temp_allocator);
	   found {
		if decoded, valid := calendar_shortcut_deserialize(binding); valid {
			calendar_shortcut_destroy(&calendar_ui.flash_leader)
			calendar_ui.flash_leader = decoded
		}
	}
	calendar_ui.controls = make([dynamic]Calendar_UI_Control)
	calendar_ui.palette_actions = make([dynamic]Calendar_App_Action)
	calendar_ui.ax_bindings = make([dynamic]Calendar_UI_AX_Binding)
	calendar_ui.promoted_holiday_country_index = -1
	calendar_ui.promoted_holiday_definition_index = -1
	calendar_ui_clear_navigation_selection()
	flash.state_init(&calendar_ui.flash)
	if error := command_palette.state_init(
		&calendar_ui.palette,
		search_reserve_size = 64*1024*1024,
		search_commit_size = 64*1024,
	); error != nil {
		fmt.eprintln("hw_calendar could not initialize search.")
		return false
	}
	if error := command_palette.state_init(
		&calendar_ui.settings_search,
		search_reserve_size = 8*1024*1024,
		search_commit_size = 64*1024,
	); error != nil {
		fmt.eprintln("hw_calendar could not initialize Settings search.")
		return false
	}
	calendar_ui.holiday_countries = calendar_holiday_countries_load()
	app := msg_id(objc_getClass("NSApplication"), sel_registerName("sharedApplication"))
	calendar_register_accessibility_class()
	view_class := calendar_register_classes()
	window_class := calendar_register_window_class()
	calendar_ui.app = app
	calendar_ui_reload_data()
	msg_void_i(app, sel_registerName("setActivationPolicy:"), 0)
	msg_void_id(app, sel_registerName("setDelegate:"), calendar_ui.delegate)
	frame := Rect{{120, 100}, {CALENDAR_DEFAULT_WINDOW_WIDTH, CALENDAR_DEFAULT_WINDOW_HEIGHT}}
	calendar_ui.window = msg_id_rect_u_u_b(
		msg_id(window_class, sel_registerName("alloc")),
		sel_registerName("initWithContentRect:styleMask:backing:defer:"),
		frame,
		CALENDAR_WINDOW_STYLE,
		2,
		false,
	)
	msg_void_id(calendar_ui.window, sel_registerName("setTitle:"), nsstring("hw_calendar"))
	msg_void_bool(calendar_ui.window, sel_registerName("setOpaque:"), true)
	msg_void_bool(calendar_ui.window, sel_registerName("setHasShadow:"), false)
	calendar_msg_void_size(
		calendar_ui.window,
		sel_registerName("setMinSize:"),
		{CALENDAR_WINDOW_MIN_WIDTH, CALENDAR_WINDOW_MIN_HEIGHT},
	)
	msg_void_bool(calendar_ui.window, sel_registerName("setAcceptsMouseMovedEvents:"), true)
	calendar_ui.view = msg_id_rect(
		msg_id(view_class, sel_registerName("alloc")),
		sel_registerName("initWithFrame:"),
		Rect{{0, 0}, frame.size},
	)
	msg_void_id(calendar_ui.window, sel_registerName("setContentView:"), calendar_ui.view)
	calendar_ui.device = MTLCreateSystemDefaultDevice()
	if calendar_ui.device == nil {
		fmt.eprintln("hw_calendar requires a Metal device.")
		return false
	}
	calendar_ui.queue = msg_id(calendar_ui.device, sel_registerName("newCommandQueue"))
	calendar_ui.layer = msg_id(objc_getClass("CAMetalLayer"), sel_registerName("layer"))
	msg_void_id(calendar_ui.layer, sel_registerName("setDevice:"), calendar_ui.device)
	msg_void_u(calendar_ui.layer, sel_registerName("setPixelFormat:"), 80)
	msg_void_bool(calendar_ui.layer, sel_registerName("setFramebufferOnly:"), true)
	msg_void_bool(calendar_ui.view, sel_registerName("setWantsLayer:"), true)
	msg_void_id(calendar_ui.view, sel_registerName("setLayer:"), calendar_ui.layer)
	if !calendar_compile_pipelines() {
		fmt.eprintln("hw_calendar could not compile its Metal pipelines.")
		return false
	}
	timer_send := transmute(proc "c" (
		Id, Sel, f64, Id, Sel, Id, bool,
	) -> Id)objc_send_address
	frame_timer := timer_send(
		objc_getClass("NSTimer"),
		sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
		1.0/60.0,
		calendar_ui.delegate,
		sel_registerName("calendarFrame:"),
		nil,
		true,
	)
	main_run_loop := msg_id(
		objc_getClass("NSRunLoop"),
		sel_registerName("mainRunLoop"),
	)
	msg_void_id_id(
		main_run_loop,
		sel_registerName("addTimer:forMode:"),
		frame_timer,
		nsstring("NSEventTrackingRunLoopMode"),
	)
	msg_void_id(calendar_ui.window, sel_registerName("makeFirstResponder:"), calendar_ui.view)
	if calendar_launch_should_activate(
		os.get_env("HW_CALENDAR_ACTIVATE_ON_LAUNCH"),
	) {
		msg_void_id(calendar_ui.window, sel_registerName("makeKeyAndOrderFront:"), nil)
		msg_void_i(app, sel_registerName("activateIgnoringOtherApps:"), 1)
	} else {
		msg_void_id(calendar_ui.window, sel_registerName("orderBack:"), nil)
	}
	if !calendar_cli_ipc_server_start() {
		fmt.eprintln("hw_calendar could not start its local control socket.")
		return false
	}
	calendar_notification_initialize()
	return true
}

calendar_gui_shutdown :: proc() {
	calendar_cli_ipc_server_stop()
	calendar_ui_destroy()
}

run_calendar_gui :: proc() {
	if !calendar_gui_initialize() {return}
	defer calendar_gui_shutdown()
	app := calendar_ui.app
	msg_void(app, sel_registerName("run"))
}
