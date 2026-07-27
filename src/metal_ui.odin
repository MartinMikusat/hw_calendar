package main

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:strings"
import "core:time"
import CF "core:sys/darwin/CoreFoundation"
import command_palette "command_palette:."
import flash "flash:."
import hot_reload "../dev/hot_reload_contract"

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
	CGContextStrokePath :: proc "c" (ctx: rawptr) ---
	CGContextSetTextPosition :: proc "c" (ctx: rawptr, x, y: f64) ---
	CGContextSaveGState :: proc "c" (ctx: rawptr) ---
	CGContextRestoreGState :: proc "c" (ctx: rawptr) ---
	CGContextClipToRect :: proc "c" (ctx: rawptr, rect: Rect) ---
}

foreign import core_text "system:CoreText.framework"
foreign core_text {
	CTFontCreateWithName :: proc "c" (
		name: rawptr,
		size: f64,
		transform: rawptr,
	) -> rawptr ---
	CTLineCreateWithAttributedString :: proc "c" (string: rawptr) -> rawptr ---
	CTLineGetTypographicBounds :: proc "c" (
		line: rawptr,
		ascent, descent, leading: ^f64,
	) -> f64 ---
	CTLineDraw :: proc "c" (line, ctx: rawptr) ---
	kCTFontAttributeName: rawptr
	kCTForegroundColorFromContextAttributeName: rawptr
}

foreign import calendar_core_foundation "system:CoreFoundation.framework"
foreign calendar_core_foundation {
	CFStringCreateWithBytes :: proc "c" (
		allocator: CF.TypeRef,
		bytes: [^]u8,
		count: CF.Index,
		encoding: CF.StringEncoding,
		external: b8,
	) -> CF.String ---
	CFStringGetLength :: proc "c" (string: rawptr) -> int ---
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
	Today,
	Search,
	New_Event,
	Open_Event,
	Editor_Field,
	Editor_Important,
	Editor_Save,
	Editor_Delete,
	Editor_Cancel,
}

Calendar_UI_Control :: struct {
	id: u64,
	name: string,
	label: string,
	rect: Calendar_UI_Rect,
	action: Calendar_UI_Action,
	event_index: int,
}

Calendar_UI_AX_Binding :: struct {
	element: Id,
	control_id: u64,
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
	frame_index: int,
	notification_reconcile_stamp: i64,
	day_offset: int,
	events: [dynamic]Calendar_Event,
	occurrences: [dynamic]Calendar_Occurrence,
	controls: [dynamic]Calendar_UI_Control,
	flash: flash.State,
	palette: command_palette.State,
	palette_query: string,
	palette_event_indices: [dynamic]int,
	editor_open: bool,
	editor_event_index: int,
	editor_field: int,
	editor_summary: string,
	editor_start: string,
	editor_end: string,
	editor_location: string,
	editor_categories: string,
	editor_description: string,
	editor_rrule: string,
	editor_error: string,
	editor_important: bool,
	ax_children: Id,
	ax_bindings: [dynamic]Calendar_UI_AX_Binding,
}

calendar_ui: Calendar_UI_State

CALENDAR_HEADER_HEIGHT :: 40.0
CALENDAR_HEADER_CONTROL_HEIGHT :: 30.0
CALENDAR_DAY_ROW_HEIGHT :: 28.0
CALENDAR_DAY_ROW_PITCH :: 30.0
CALENDAR_DAY_TOP_GAP :: 4.0
CALENDAR_WINDOW_STYLE :: uint(14)
CALENDAR_WINDOW_MINIMIZE_STYLE :: uint(15)
CALENDAR_WINDOW_RESIZE_INSET :: 6.0
CALENDAR_WINDOW_MIN_WIDTH :: 640.0
CALENDAR_WINDOW_MIN_HEIGHT :: 480.0

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
) {
	append(&calendar_ui.controls, Calendar_UI_Control{
		id = calendar_control_id(name),
		name = strings.clone(name),
		label = strings.clone(label),
		rect = rect,
		action = action,
		event_index = event_index,
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
	switch control.action {
	case .Window_Close: return "Close window"
	case .Window_Minimize: return "Minimize window"
	case .Window_Zoom: return "Zoom window"
	case .Today: return "Jump to today"
	case .Search: return "Search events"
	case .New_Event: return "New event"
	case .Open_Event:
		if control.event_index >= 0 &&
		   control.event_index < len(calendar_ui.events) {
			return fmt.tprintf(
				"Open event %s",
				calendar_ui.events[control.event_index].summary,
			)
		}
		return "Open event"
	case .Editor_Field:
		labels := [7]string{
			"Event summary",
			"Event start",
			"Event end",
			"Event location",
			"Event categories",
			"Event description",
			"Event recurrence rule",
		}
		if control.event_index >= 0 && control.event_index < len(labels) {
			return labels[control.event_index]
		}
	case .Editor_Important: return "Important event"
	case .Editor_Save: return "Save event"
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
	if control.action == .Editor_Field {
		value := calendar_ui_editor_field_text(control.event_index)
		if value != nil {return nsstring(value^)}
	}
	if control.action == .Editor_Important {
		return calendar_msg_id_bool(
			objc_getClass("NSNumber"),
			sel_registerName("numberWithBool:"),
			calendar_ui.editor_important,
		)
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
	if control == nil || control.action != .Editor_Field {return}
	text_value := calendar_ui_editor_field_text(control.event_index)
	if text_value == nil {return}
	utf8 := calendar_msg_cstring(value, sel_registerName("UTF8String"))
	if utf8 == nil {return}
	delete(text_value^)
	text_value^ = strings.clone(string(utf8))
	calendar_ui.editor_field = control.event_index
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
	element_class := objc_getClass("HWCalendarAccessibilityElement")
	for &control in calendar_ui.controls {
		if calendar_ui.editor_open &&
		   !calendar_ui_is_window_action(control.action) &&
		   control.action != .Editor_Field &&
		   control.action != .Editor_Important &&
		   control.action != .Editor_Save &&
		   control.action != .Editor_Delete &&
		   control.action != .Editor_Cancel {
			continue
		}
		element := msg_id(element_class, sel_registerName("new"))
		role := "AXButton"
		if control.action == .Editor_Field {role = "AXTextField"}
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
		if control.action == .Editor_Field {
			if value := calendar_ui_editor_field_text(control.event_index);
			   value != nil {
				msg_void_id(
					element,
					sel_registerName("setAccessibilityValue:"),
					nsstring(value^),
				)
			}
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
		122,
		calendar_ui.height-CALENDAR_HEADER_CONTROL_HEIGHT-1,
		360,
		CALENDAR_HEADER_CONTROL_HEIGHT,
	}
}

calendar_ui_window_control_rect :: proc(index: int) -> Calendar_UI_Rect {
	return {
		38*f64(index),
		calendar_ui.height-CALENDAR_HEADER_CONTROL_HEIGHT-1,
		30,
		CALENDAR_HEADER_CONTROL_HEIGHT,
	}
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

calendar_ui_visible_day_count :: proc() -> int {
	available := calendar_ui.height-CALENDAR_HEADER_HEIGHT-CALENDAR_DAY_TOP_GAP
	return max(1, int(available/CALENDAR_DAY_ROW_PITCH)+1)
}

calendar_ui_day_rect :: proc(index: int) -> Calendar_UI_Rect {
	return {
		12,
		calendar_ui.height-CALENDAR_HEADER_HEIGHT-CALENDAR_DAY_TOP_GAP -
		CALENDAR_DAY_ROW_PITCH*f64(index)-CALENDAR_DAY_ROW_HEIGHT,
		calendar_ui.width-24,
		CALENDAR_DAY_ROW_HEIGHT,
	}
}

calendar_ui_event_rect :: proc(
	day_rect: Calendar_UI_Rect,
	index: int,
) -> Calendar_UI_Rect {
	return {
		day_rect.x+178+f64(index)*max(120, (day_rect.w-190)/3),
		day_rect.y+3,
		max(110, (day_rect.w-202)/3),
		day_rect.h-6,
	}
}

calendar_ui_reload_data :: proc() {
	calendar_events_destroy(&calendar_ui.events)
	calendar_occurrences_destroy(&calendar_ui.occurrences)
	events, loaded := calendar_events_load()
	if !loaded {return}
	calendar_ui.events = events
	now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
	anchor_days := ical_days_from_civil(now.year, now.month, now.day) +
	               i64(calendar_ui.day_offset)
	range_start := ical_date_time_from_stamp((anchor_days-7)*86400, true)
	range_end := ical_date_time_from_stamp((anchor_days+60)*86400, true)
	occurrences, _ := calendar_expand_events(
		calendar_ui.events[:],
		range_start,
		range_end,
		1_000,
	)
	calendar_ui.occurrences = occurrences
}

calendar_ui_begin_flash :: proc() {
	targets := make(
		[dynamic]flash.Target,
		0,
		len(calendar_ui.controls),
		context.temp_allocator,
	)
	for control in calendar_ui.controls {
		if calendar_ui.editor_open &&
		   !calendar_ui_is_window_action(control.action) &&
		   control.action != .Editor_Field &&
		   control.action != .Editor_Important &&
		   control.action != .Editor_Save &&
		   control.action != .Editor_Delete &&
		   control.action != .Editor_Cancel {
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

calendar_ui_open_palette :: proc() {
	if command_palette.is_open(&calendar_ui.palette) {
		command_palette.close(&calendar_ui.palette)
		calendar_ui.palette_query = ""
		clear(&calendar_ui.palette_event_indices)
		calendar_ui.needs_redraw = true
		return
	}
	entries := make(
		[dynamic]command_palette.Entry,
		context.temp_allocator,
	)
	clear(&calendar_ui.palette_event_indices)
	append(&entries, command_palette.Entry{
		id = 1,
		title = "Today",
		category = "Command",
		keywords = []string{"jump", "current", "date"},
	})
	append(&calendar_ui.palette_event_indices, -1)
	for &event, event_index in calendar_ui.events {
		if len(event.recurrence_id) > 0 ||
		   strings.equal_fold(event.status, "CANCELLED") {
			continue
		}
		append(&entries, command_palette.Entry{
			id = command_palette.Entry_ID(len(entries)+1),
			title = event.summary,
			subtitle = event.location,
			category = "Event",
			keywords = []string{event.description, event.categories, event.uid, event.url},
		})
		append(&calendar_ui.palette_event_indices, event_index)
	}
	search_error := command_palette.open(&calendar_ui.palette, entries[:], 0)
	if search_error != .None {
		clear(&calendar_ui.palette_event_indices)
		fmt.eprintln("[hw_calendar] command palette rejected invalid UTF-8")
		calendar_ui.needs_redraw = true
		return
	}
	calendar_ui.palette_query = ""
	calendar_ui.needs_redraw = true
}

calendar_ui_activate_palette :: proc() {
	id, activated := command_palette.activate_selected(&calendar_ui.palette)
	if !activated {return}
	index := int(id)-1
	if index <= 0 {
		calendar_ui.day_offset = 0
	} else if index < len(calendar_ui.palette_event_indices) {
		event_index := calendar_ui.palette_event_indices[index]
		if event_index >= 0 {
			start, ok := ical_parse_date_time(calendar_ui.events[event_index].dtstart)
			if ok {
				now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
				calendar_ui.day_offset = int(
					ical_days_from_civil(start.year, start.month, start.day) -
					ical_days_from_civil(now.year, now.month, now.day),
				)
			}
		}
	}
	command_palette.close(&calendar_ui.palette)
	calendar_ui.palette_query = ""
	calendar_ui_reload_data()
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
	return {
		modal.x+150,
		modal.y+modal.h-86-f64(index)*48,
		modal.w-174,
		34,
	}
}

calendar_ui_editor_button_rect :: proc(index: int) -> Calendar_UI_Rect {
	modal := calendar_ui_editor_rect()
	return {modal.x+150+f64(index)*112, modal.y+20, 100, 34}
}

calendar_ui_editor_clear :: proc() {
	delete(calendar_ui.editor_summary)
	delete(calendar_ui.editor_start)
	delete(calendar_ui.editor_end)
	delete(calendar_ui.editor_location)
	delete(calendar_ui.editor_categories)
	delete(calendar_ui.editor_description)
	delete(calendar_ui.editor_rrule)
	delete(calendar_ui.editor_error)
	calendar_ui.editor_summary = ""
	calendar_ui.editor_start = ""
	calendar_ui.editor_end = ""
	calendar_ui.editor_location = ""
	calendar_ui.editor_categories = ""
	calendar_ui.editor_description = ""
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
		calendar_ui.editor_summary = strings.clone(event.summary)
		calendar_ui.editor_start = strings.clone(event.dtstart)
		calendar_ui.editor_end = strings.clone(event.dtend)
		calendar_ui.editor_location = strings.clone(event.location)
		calendar_ui.editor_categories = strings.clone(event.categories)
		calendar_ui.editor_description = strings.clone(event.description)
		calendar_ui.editor_rrule = strings.clone(event.rrule)
		calendar_ui.editor_important = event.important
	} else {
		now := ical_date_time_from_stamp(time.to_unix_seconds(time.now()), true)
		day := ical_days_from_civil(now.year, now.month, now.day) +
		       i64(calendar_ui.day_offset)
		start := ical_date_time_from_stamp(day*86400+9*3600)
		end := ical_date_time_from_stamp(day*86400+10*3600)
		calendar_ui.editor_start = ical_format_date_time(start)
		calendar_ui.editor_end = ical_format_date_time(end)
		calendar_ui.editor_important = false
	}
	flash.cancel(&calendar_ui.flash)
	command_palette.close(&calendar_ui.palette)
	calendar_ui.needs_redraw = true
}

calendar_ui_editor_close :: proc() {
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
	case 4: return &calendar_ui.editor_categories
	case 5: return &calendar_ui.editor_description
	case 6: return &calendar_ui.editor_rrule
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
		calendar_ui_editor_set_error("SUMMARY IS REQUIRED")
		return
	}
	input := Calendar_Event_Input{
		schema_version = 1,
		summary = calendar_ui.editor_summary,
		description = calendar_ui.editor_description,
		location = calendar_ui.editor_location,
		important = calendar_ui.editor_important,
		dtstart = calendar_ui.editor_start,
		dtend = calendar_ui.editor_end,
		rrule = calendar_ui.editor_rrule,
	}
	if len(calendar_ui.editor_categories) > 0 {
		input.categories = []string{calendar_ui.editor_categories}
	}
	if calendar_ui.editor_event_index >= 0 &&
	   calendar_ui.editor_event_index < len(calendar_ui.events) {
		event := &calendar_ui.events[calendar_ui.editor_event_index]
		input.uid = event.uid
		input.recurrence_id = event.recurrence_id
		input.url = event.url
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

calendar_ui_activate_control :: proc(id: u64) {
	for control in calendar_ui.controls {
		if control.id != id {continue}
		switch control.action {
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
			msg_void_id(calendar_ui.window, sel_registerName("zoom:"), nil)
		case .Today:
			calendar_ui.day_offset = 0
			calendar_ui_reload_data()
		case .Search:
			calendar_ui_open_palette()
		case .New_Event:
			calendar_ui_editor_open()
		case .Open_Event:
			if control.event_index >= 0 &&
			   control.event_index < len(calendar_ui.events) {
				calendar_ui_editor_open(control.event_index)
			}
		case .Editor_Field:
			calendar_ui.editor_field = control.event_index
		case .Editor_Important:
			calendar_ui.editor_important = !calendar_ui.editor_important
		case .Editor_Save:
			calendar_ui_editor_commit()
		case .Editor_Delete:
			calendar_ui_editor_commit(true)
		case .Editor_Cancel:
			calendar_ui_editor_close()
		case .None:
		}
		break
	}
	calendar_ui.needs_redraw = true
}

calendar_ui_click :: proc(point: Point) -> bool {
	flash.cancel(&calendar_ui.flash)
	for index := len(calendar_ui.controls)-1; index >= 0; index -= 1 {
		control := calendar_ui.controls[index]
		if calendar_ui_contains(control.rect, point) {
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
	if calendar_ui.resize_edges == 0 {return}
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
	if calendar_ui_click(point) {return}
	if calendar_ui_contains(calendar_ui_header_rect(), point) {
		msg_void_id(
			calendar_ui.window,
			sel_registerName("performWindowDragWithEvent:"),
			event,
		)
	}
}

calendar_on_scroll :: proc "c" (self: Id, command: Sel, event: Id) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	flash.cancel(&calendar_ui.flash)
	if calendar_ui.editor_open {return}
	delta := msg_f64(event, sel_registerName("scrollingDeltaY"))
	if delta == 0 {delta = msg_f64(event, sel_registerName("deltaY"))}
	if delta > 0 {
		calendar_ui.day_offset -= max(1, int(delta/12))
	} else if delta < 0 {
		calendar_ui.day_offset += max(1, int(-delta/12))
	}
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
	if calendar_ui.editor_open {
		switch key_code {
		case 53:
			calendar_ui_editor_close()
		case 48:
			calendar_ui.editor_field = (calendar_ui.editor_field+1)%7
		case 36:
			calendar_ui_editor_commit()
		case 51:
			value := calendar_ui_editor_field_text(calendar_ui.editor_field)
			if value != nil && len(value^) > 0 {
				next := strings.clone(
					value^[:calendar_utf8_previous_boundary(value^)],
				)
				delete(value^)
				value^ = next
			}
		case:
			if len(text) > 0 && text[0] >= 0x20 {
				value := calendar_ui_editor_field_text(calendar_ui.editor_field)
				if value != nil {
					next := fmt.tprintf("%s%s", value^, text)
					delete(value^)
					value^ = strings.clone(next)
				}
			}
		}
		calendar_ui.needs_redraw = true
		return
	}
	if control_down && (text == "k" || text == "K") {
		calendar_ui_open_palette()
		return
	}
	if command_palette.is_open(&calendar_ui.palette) {
		switch key_code {
		case 53:
			command_palette.close(&calendar_ui.palette)
			calendar_ui.palette_query = ""
		case 36:
			calendar_ui_activate_palette()
			return
		case 125: command_palette.move_selection(&calendar_ui.palette, 1)
		case 126: command_palette.move_selection(&calendar_ui.palette, -1)
		case 51:
			if len(calendar_ui.palette_query) > 0 {
				next := strings.clone(
					calendar_ui.palette_query[
						:calendar_utf8_previous_boundary(
							calendar_ui.palette_query,
						)
					],
				)
				_ = calendar_ui_set_palette_query(next)
				delete(next)
			}
		case:
			if len(text) == 1 && text[0] >= 0x20 {
				next := fmt.tprintf("%s%s", calendar_ui.palette_query, text)
				_ = calendar_ui_set_palette_query(next)
			}
		}
		calendar_ui.needs_redraw = true
		return
	}
	if flash.is_active(&calendar_ui.flash) {
		if key_code == 53 {
			flash.cancel(&calendar_ui.flash)
		} else if key_code == 48 {
			flash.cycle_selection(&calendar_ui.flash, .Next)
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
	if text == "/" {
		calendar_ui_begin_flash()
	} else if key_code == 125 {
		calendar_ui.day_offset += 1
		calendar_ui_reload_data()
		calendar_ui.needs_redraw = true
	} else if key_code == 126 {
		calendar_ui.day_offset -= 1
		calendar_ui_reload_data()
		calendar_ui.needs_redraw = true
	}
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

calendar_build_geometry :: proc(vertices: ^[dynamic]Calendar_Solid_Vertex) {
	chassis := [4]f32{0.026, 0.028, 0.027, 1}
	header := [4]f32{0.018, 0.020, 0.019, 1}
	row := [4]f32{0.041, 0.044, 0.042, 1}
	row_alt := [4]f32{0.052, 0.055, 0.052, 1}
	important := [4]f32{0.15, 0.061, 0.032, 1}
	button := [4]f32{0.052, 0.055, 0.052, 1}
	orange := [4]f32{0.91, 0.31, 0.075, 1}
	cyan := [4]f32{0.27, 0.72, 0.73, 1}
	calendar_push_rect(vertices, {0, 0, calendar_ui.width, calendar_ui.height}, chassis)
	calendar_push_rect(vertices, calendar_ui_header_rect(), header)
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
		day_events := calendar_occurrences_for_day(day)
		is_important := false
		for occurrence in day_events {
			if occurrence.important {is_important = true}
		}
		color := row
		if index%2 == 1 {color = row_alt}
		if is_important {color = important}
		calendar_push_rect(vertices, rect, color)
		if ical_days_from_civil(day.year, day.month, day.day) ==
		   ical_days_from_civil(now.year, now.month, now.day) {
			calendar_push_border(vertices, rect, orange)
		}
		for occurrence, event_index in day_events {
			if event_index >= 3 {break}
			event_rect := calendar_ui_event_rect(rect, event_index)
			event_color := [4]f32{0.075, 0.081, 0.076, 1}
			upper_categories := strings.to_upper(
				occurrence.categories,
				context.temp_allocator,
			)
			personal := strings.contains(upper_categories, "PERSONAL")
			work := strings.contains(upper_categories, "WORK")
			if personal {event_color = [4]f32{0.17, 0.070, 0.035, 1}}
			if work {event_color = [4]f32{0.035, 0.12, 0.12, 1}}
			calendar_push_rect(vertices, event_rect, event_color)
			if personal && work {
				calendar_push_rect(
					vertices,
					{event_rect.x, event_rect.y, 4, event_rect.h},
					orange,
				)
				calendar_push_rect(
					vertices,
					{event_rect.x+4, event_rect.y, 4, event_rect.h},
					cyan,
				)
			}
			if !calendar_ui.editor_open {
				calendar_ui_add_control(
					fmt.tprintf(
						"event:%s:%s",
						occurrence.uid,
						occurrence.recurrence_id,
					),
					"event",
					event_rect,
					.Open_Event,
					occurrence.event_index,
				)
			}
		}
	}
	if command_palette.is_open(&calendar_ui.palette) {
		calendar_push_rect(
			vertices,
			{calendar_ui.width*0.15, calendar_ui.height*0.2, calendar_ui.width*0.7, calendar_ui.height*0.65},
			[4]f32{0.031, 0.034, 0.032, 1},
		)
	}
	if calendar_ui.editor_open {
		calendar_push_rect(
			vertices,
			{0, 0, calendar_ui.width, calendar_ui.height},
			[4]f32{0.012, 0.013, 0.012, 1},
		)
		modal := calendar_ui_editor_rect()
		calendar_push_rect(vertices, modal, [4]f32{0.025, 0.028, 0.026, 1})
		for field_index in 0..<7 {
			field_rect := calendar_ui_editor_field_rect(field_index)
			calendar_push_rect(
				vertices,
				field_rect,
				[4]f32{0.052, 0.056, 0.052, 1},
			)
			if field_index == calendar_ui.editor_field {
				calendar_push_border(vertices, field_rect, cyan)
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
			modal.x+150,
			modal.y+modal.h-86-7*48,
			190,
			34,
		}
		important_color := [4]f32{0.052, 0.056, 0.052, 1}
		if calendar_ui.editor_important {
			important_color = [4]f32{0.15, 0.061, 0.032, 1}
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
		save_rect := calendar_ui_editor_button_rect(0)
		cancel_rect := calendar_ui_editor_button_rect(1)
		calendar_push_rect(vertices, save_rect, [4]f32{0.035, 0.12, 0.12, 1})
		calendar_push_rect(vertices, cancel_rect, [4]f32{0.052, 0.056, 0.052, 1})
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
				[4]f32{0.17, 0.070, 0.035, 1},
			)
			calendar_ui_add_control(
				"editor delete",
				"delete",
				delete_rect,
				.Editor_Delete,
			)
		}
	}
	for index in 0..<3 {
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

calendar_text_run :: proc(font: rawptr, text: string) -> Calendar_Text_Run {
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
) {
	run := calendar_text_run(font, text)
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

calendar_draw_window_controls :: proc(ctx: rawptr) {
	colors := [3][4]f64{
		{0.98, 0.35, 0.09, 1},
		{0.47, 0.49, 0.46, 1},
		{0.27, 0.72, 0.73, 1},
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
	font_text := "Iosevka"
	font_name := CFStringCreateWithBytes(
		nil,
		raw_data(transmute([]u8)font_text),
		CF.Index(len(font_text)),
		CF.StringEncoding(0x08000100),
		false,
	)
	font := CTFontCreateWithName(font_name, 11*calendar_ui.scale, nil)
	CFRelease(font_name)
	if font == nil {return pixels}
	defer CFRelease(font)
	bright := [4]f64{0.97, 0.95, 0.88, 1}
	muted := [4]f64{0.47, 0.49, 0.46, 1}
	orange := [4]f64{0.98, 0.35, 0.09, 1}
	cyan := [4]f64{0.27, 0.72, 0.73, 1}
	calendar_draw_text(
		ctx,
		font,
		"HW CALENDAR / CONTINUOUS DAYS",
		calendar_ui_title_rect(),
		bright,
		0,
	)
	calendar_draw_text(ctx, font, "TODAY", calendar_ui_today_rect(), muted, 14)
	calendar_draw_text(ctx, font, "SEARCH", calendar_ui_search_rect(), cyan, 14)
	calendar_draw_text(ctx, font, "NEW EVENT", calendar_ui_new_rect(), orange, 10)
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
		day_events := calendar_occurrences_for_day(day)
		for occurrence, event_index in day_events {
			if event_index >= 3 {break}
			event_rect := calendar_ui_event_rect(rect, event_index)
			time_text := "ALL DAY"
			if !occurrence.start.is_date {
				time_text = fmt.tprintf(
					"%02d:%02d  %s",
					occurrence.start.hour,
					occurrence.start.minute,
					occurrence.summary,
				)
			} else {
				time_text = fmt.tprintf("ALL DAY  %s", occurrence.summary)
			}
			calendar_draw_text(ctx, font, time_text, event_rect, bright)
		}
		if len(day_events) > 3 {
			calendar_draw_text(
				ctx,
				font,
				fmt.tprintf("+%d", len(day_events)-3),
				{rect.x+rect.w-42, rect.y, 38, rect.h},
				orange,
				0,
			)
		}
	}
	calendar_draw_flash_hints(ctx, font)
	if command_palette.is_open(&calendar_ui.palette) {
		modal := Calendar_UI_Rect{
			calendar_ui.width*0.15,
			calendar_ui.height*0.2,
			calendar_ui.width*0.7,
			calendar_ui.height*0.65,
		}
		calendar_draw_text(ctx, font, fmt.tprintf("> %s", calendar_ui.palette_query), {modal.x+16, modal.y+modal.h-48, modal.w-32, 34}, bright)
		for result, index in command_palette.visible_results(&calendar_ui.palette) {
			if index >= 10 {break}
			color := muted
			if index == command_palette.selected_index(&calendar_ui.palette) {color = orange}
			calendar_draw_text(
				ctx,
				font,
				fmt.tprintf("%-10s  %s", result.entry.category, result.entry.title),
				{modal.x+16, modal.y+modal.h-84-f64(index)*34, modal.w-32, 30},
				color,
			)
		}
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
			bright,
			0,
		)
		labels := [7]string{
			"SUMMARY",
			"START",
			"END",
			"LOCATION",
			"CATEGORIES",
			"DESCRIPTION",
			"RRULE",
		}
		values := [7]string{
			calendar_ui.editor_summary,
			calendar_ui.editor_start,
			calendar_ui.editor_end,
			calendar_ui.editor_location,
			calendar_ui.editor_categories,
			calendar_ui.editor_description,
			calendar_ui.editor_rrule,
		}
		for field_index in 0..<7 {
			field_rect := calendar_ui_editor_field_rect(field_index)
			calendar_draw_text(
				ctx,
				font,
				labels[field_index],
				{modal.x+18, field_rect.y, 120, field_rect.h},
				muted,
				0,
			)
			calendar_draw_text(
				ctx,
				font,
				values[field_index],
				field_rect,
				bright,
			)
		}
		important_rect := Calendar_UI_Rect{
			modal.x+150,
			modal.y+modal.h-86-7*48,
			190,
			34,
		}
		calendar_draw_text(
			ctx,
			font,
			calendar_ui.editor_important ? "IMPORTANT: YES" : "IMPORTANT: NO",
			important_rect,
			calendar_ui.editor_important ? orange : muted,
		)
		calendar_draw_text(
			ctx,
			font,
			"SAVE",
			calendar_ui_editor_button_rect(0),
			cyan,
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
				orange,
			)
		}
		if len(calendar_ui.editor_error) > 0 {
			calendar_draw_text(
				ctx,
				font,
				calendar_ui.editor_error,
				{modal.x+18, modal.y+60, modal.w-36, 28},
				orange,
				0,
			)
		}
	}
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
	calendar_msg_void_clear_color(
		attachment,
		sel_registerName("setClearColor:"),
		{0.026, 0.028, 0.027, 1},
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
	if !calendar_ui.editor_open {
		calendar_ui_add_control(
			"today",
			"today",
			calendar_ui_today_rect(),
			.Today,
		)
		calendar_ui_add_control(
			"search",
			"search events",
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
		"HWCalendarAccessibilityElement",
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
		"HWCalendarDelegate",
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
		"HWCalendarMetalView",
		0,
	)
	class_addMethod(view_class, sel_registerName("acceptsFirstResponder"), rawptr(calendar_on_accepts_first), "B@:")
	class_addMethod(view_class, sel_registerName("mouseDown:"), rawptr(calendar_on_mouse_down), "v@:@")
	class_addMethod(view_class, sel_registerName("mouseDragged:"), rawptr(calendar_on_mouse_dragged), "v@:@")
	class_addMethod(view_class, sel_registerName("mouseUp:"), rawptr(calendar_on_mouse_up), "v@:@")
	class_addMethod(view_class, sel_registerName("scrollWheel:"), rawptr(calendar_on_scroll), "v@:@")
	class_addMethod(view_class, sel_registerName("keyDown:"), rawptr(calendar_on_key_down), "v@:@")
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
		"HWCalendarWindow",
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
	calendar_ui_clear_controls()
	delete(calendar_ui.controls)
	delete(calendar_ui.palette_query)
	delete(calendar_ui.palette_event_indices)
	calendar_ui_editor_clear()
	if calendar_ui.ax_children != nil {
		msg_void(calendar_ui.ax_children, sel_registerName("release"))
	}
	delete(calendar_ui.ax_bindings)
	flash.state_destroy(&calendar_ui.flash)
	command_palette.state_destroy(&calendar_ui.palette)
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

calendar_gui_initialize :: proc(
	services: ^hot_reload.Host_Services = nil,
) -> bool {
	if !objc_initialize() {
		fmt.eprintln("HW Calendar could not initialize the Objective-C runtime.")
		return false
	}
	calendar_ui.scale = 1
	calendar_ui.needs_redraw = true
	calendar_ui.controls = make([dynamic]Calendar_UI_Control)
	calendar_ui.palette_event_indices = make([dynamic]int)
	calendar_ui.ax_bindings = make([dynamic]Calendar_UI_AX_Binding)
	flash.state_init(&calendar_ui.flash)
	if error := command_palette.state_init(
		&calendar_ui.palette,
		search_reserve_size = 64*1024*1024,
		search_commit_size = 64*1024,
	); error != nil {
		fmt.eprintln("HW Calendar could not initialize search.")
		return false
	}
	calendar_ui_reload_data()
	app := Id(nil)
	view_class := Id(nil)
	window_class := Id(nil)
	if services == nil {
		app = msg_id(objc_getClass("NSApplication"), sel_registerName("sharedApplication"))
		calendar_register_accessibility_class()
		view_class = calendar_register_classes()
		window_class = calendar_register_window_class()
	} else {
		app = Id(services.app)
		calendar_ui.delegate = Id(services.delegate)
		view_class = Id(services.view_class)
		window_class = Id(services.window_class)
	}
	calendar_ui.app = app
	msg_void_i(app, sel_registerName("setActivationPolicy:"), 0)
	msg_void_id(app, sel_registerName("setDelegate:"), calendar_ui.delegate)
	frame := Rect{{120, 100}, {896, 760}}
	calendar_ui.window = msg_id_rect_u_u_b(
		msg_id(window_class, sel_registerName("alloc")),
		sel_registerName("initWithContentRect:styleMask:backing:defer:"),
		frame,
		CALENDAR_WINDOW_STYLE,
		2,
		false,
	)
	msg_void_id(calendar_ui.window, sel_registerName("setTitle:"), nsstring("HW Calendar"))
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
		fmt.eprintln("HW Calendar requires a Metal device.")
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
		fmt.eprintln("HW Calendar could not compile its Metal pipelines.")
		return false
	}
	if services == nil {
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
	}
	msg_void_id(calendar_ui.window, sel_registerName("makeFirstResponder:"), calendar_ui.view)
	msg_void_id(calendar_ui.window, sel_registerName("makeKeyAndOrderFront:"), nil)
	msg_void_i(app, sel_registerName("activateIgnoringOtherApps:"), 1)
	if !calendar_cli_ipc_server_start() {
		fmt.eprintln("HW Calendar could not start its local control socket.")
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
