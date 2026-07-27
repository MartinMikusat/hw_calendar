package main

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import "core:os"
import os2 "core:os/os2"
import "core:strings"
import "core:sync"
import hot_reload "../hot_reload_contract"

Id :: rawptr
Sel :: rawptr

foreign import objc "system:objc"
foreign objc {
	objc_getClass :: proc "c" (name: cstring) -> Id ---
	objc_getProtocol :: proc "c" (name: cstring) -> Id ---
	sel_registerName :: proc "c" (name: cstring) -> Sel ---
	objc_allocateClassPair :: proc "c" (superclass: Id, name: cstring, extra: uint) -> Id ---
	objc_registerClassPair :: proc "c" (cls: Id) ---
	class_addMethod :: proc "c" (cls: Id, name: Sel, imp: rawptr, types: cstring) -> bool ---
	class_addProtocol :: proc "c" (cls: Id, protocol: Id) -> bool ---
}

Loaded_Module :: struct {
	api:         ^hot_reload.Module_API,
	library:     dynlib.Library,
	shadow_path: string,
	write_time:  os.File_Time,
	generation:  int,
}

objc_send_address: rawptr
module_path: string
current_module: Loaded_Module
loaded_modules: [dynamic]Loaded_Module
services: hot_reload.Host_Services
reload_mutex: sync.Mutex
snapshot: rawptr
last_failed_write: os.File_Time
has_failed_write: bool
restart_requested: bool

objc_initialize :: proc() -> bool {
	handle := os.dlopen("/usr/lib/libobjc.A.dylib", os.RTLD_NOW)
	if handle == nil {return false}
	objc_send_address = os.dlsym(handle, "objc_msgSend")
	return objc_send_address != nil
}

msg_id :: proc(receiver: Id, selector: Sel) -> Id {
	p := transmute(proc "c" (Id, Sel) -> Id)objc_send_address
	return p(receiver, selector)
}

msg_void :: proc(receiver: Id, selector: Sel) {
	p := transmute(proc "c" (Id, Sel))objc_send_address
	p(receiver, selector)
}

msg_void_id :: proc(receiver: Id, selector: Sel, value: Id) {
	p := transmute(proc "c" (Id, Sel, Id))objc_send_address
	p(receiver, selector, value)
}

callback :: proc "contextless" (kind: hot_reload.Callback) -> rawptr {
	if current_module.api == nil {return nil}
	return current_module.api.callbacks[int(kind)]
}

host_frame :: proc "c" (self: Id, command: Sel, timer: Id) {
	context = runtime.default_context()
	host_try_reload()
	if restart_requested {return}
	if p := callback(.Frame); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, timer)
	}
}

host_cli_request :: proc "c" (self: Id, command: Sel, sender: Id) {
	if p := callback(.CLI_Request); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, sender)
	}
}

host_should_terminate :: proc "c" (self: Id, command: Sel, app: Id) -> bool {
	if p := callback(.Should_Terminate); p != nil {
		return (transmute(proc "c" (Id, Sel, Id) -> bool)p)(self, command, app)
	}
	return true
}

host_notification_response :: proc "c" (
	self: Id,
	command: Sel,
	center, response, completion: Id,
) {
	sync.mutex_lock(&reload_mutex)
	defer sync.mutex_unlock(&reload_mutex)
	if p := callback(.Notification_Response); p != nil {
		(transmute(proc "c" (Id, Sel, Id, Id, Id))p)(
			self,
			command,
			center,
			response,
			completion,
		)
	}
}

host_notification_foreground :: proc "c" (
	self: Id,
	command: Sel,
	center, notification, completion: Id,
) {
	sync.mutex_lock(&reload_mutex)
	defer sync.mutex_unlock(&reload_mutex)
	if p := callback(.Notification_Foreground); p != nil {
		(transmute(proc "c" (Id, Sel, Id, Id, Id))p)(
			self,
			command,
			center,
			notification,
			completion,
		)
	}
}

host_ax_press :: proc "c" (self: Id, command: Sel) -> bool {
	if p := callback(.AX_Press); p != nil {
		return (transmute(proc "c" (Id, Sel) -> bool)p)(self, command)
	}
	return false
}

host_ax_value :: proc "c" (self: Id, command: Sel) -> Id {
	if p := callback(.AX_Value); p != nil {
		return (transmute(proc "c" (Id, Sel) -> Id)p)(self, command)
	}
	return nil
}

host_ax_set_value :: proc "c" (self: Id, command: Sel, value: Id) {
	if p := callback(.AX_Set_Value); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, value)
	}
}

host_ax_children :: proc "c" (self: Id, command: Sel) -> Id {
	if p := callback(.AX_Children); p != nil {
		return (transmute(proc "c" (Id, Sel) -> Id)p)(self, command)
	}
	return nil
}

host_ax_is_element :: proc "c" (self: Id, command: Sel) -> bool {
	if p := callback(.AX_Is_Element); p != nil {
		return (transmute(proc "c" (Id, Sel) -> bool)p)(self, command)
	}
	return false
}

host_accepts_first :: proc "c" (self: Id, command: Sel) -> bool {
	if p := callback(.Accepts_First); p != nil {
		return (transmute(proc "c" (Id, Sel) -> bool)p)(self, command)
	}
	return true
}

host_mouse_down :: proc "c" (self: Id, command: Sel, event: Id) {
	if p := callback(.Mouse_Down); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, event)
	}
}

host_mouse_dragged :: proc "c" (self: Id, command: Sel, event: Id) {
	if p := callback(.Mouse_Dragged); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, event)
	}
}

host_mouse_up :: proc "c" (self: Id, command: Sel, event: Id) {
	if p := callback(.Mouse_Up); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, event)
	}
}

host_scroll :: proc "c" (self: Id, command: Sel, event: Id) {
	if p := callback(.Scroll); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, event)
	}
}

host_key_down :: proc "c" (self: Id, command: Sel, event: Id) {
	if p := callback(.Key_Down); p != nil {
		(transmute(proc "c" (Id, Sel, Id))p)(self, command, event)
	}
}

host_window_can_become_key :: proc "c" (self: Id, command: Sel) -> bool {
	if p := callback(.Window_Can_Become_Key); p != nil {
		return (transmute(proc "c" (Id, Sel) -> bool)p)(self, command)
	}
	return true
}

register_classes :: proc() -> bool {
	delegate_class := objc_allocateClassPair(
		objc_getClass("NSObject"),
		"HWCalendarDelegate",
		0,
	)
	if delegate_class == nil {return false}
	class_addMethod(delegate_class, sel_registerName("calendarFrame:"), rawptr(host_frame), "v@:@")
	class_addMethod(delegate_class, sel_registerName("calendarCLIRequest:"), rawptr(host_cli_request), "v@:@")
	class_addMethod(
		delegate_class,
		sel_registerName("applicationShouldTerminateAfterLastWindowClosed:"),
		rawptr(host_should_terminate),
		"B@:@",
	)
	class_addMethod(
		delegate_class,
		sel_registerName("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:"),
		rawptr(host_notification_response),
		"v@:@@@",
	)
	class_addMethod(
		delegate_class,
		sel_registerName("userNotificationCenter:willPresentNotification:withCompletionHandler:"),
		rawptr(host_notification_foreground),
		"v@:@@@",
	)
	if protocol := objc_getProtocol("UNUserNotificationCenterDelegate"); protocol != nil {
		class_addProtocol(delegate_class, protocol)
	}
	objc_registerClassPair(delegate_class)
	services.delegate = msg_id(delegate_class, sel_registerName("new"))

	view_class := objc_allocateClassPair(
		objc_getClass("NSView"),
		"HWCalendarMetalView",
		0,
	)
	if view_class == nil {return false}
	class_addMethod(view_class, sel_registerName("acceptsFirstResponder"), rawptr(host_accepts_first), "B@:")
	class_addMethod(view_class, sel_registerName("mouseDown:"), rawptr(host_mouse_down), "v@:@")
	class_addMethod(view_class, sel_registerName("mouseDragged:"), rawptr(host_mouse_dragged), "v@:@")
	class_addMethod(view_class, sel_registerName("mouseUp:"), rawptr(host_mouse_up), "v@:@")
	class_addMethod(view_class, sel_registerName("scrollWheel:"), rawptr(host_scroll), "v@:@")
	class_addMethod(view_class, sel_registerName("keyDown:"), rawptr(host_key_down), "v@:@")
	class_addMethod(view_class, sel_registerName("isAccessibilityElement"), rawptr(host_ax_is_element), "B@:")
	class_addMethod(view_class, sel_registerName("accessibilityChildren"), rawptr(host_ax_children), "@@:")
	objc_registerClassPair(view_class)
	services.view_class = view_class

	ax_class := objc_allocateClassPair(
		objc_getClass("NSAccessibilityElement"),
		"HWCalendarAccessibilityElement",
		0,
	)
	if ax_class == nil {return false}
	class_addMethod(ax_class, sel_registerName("accessibilityPerformPress"), rawptr(host_ax_press), "B@:")
	class_addMethod(ax_class, sel_registerName("accessibilityValue"), rawptr(host_ax_value), "@@:")
	class_addMethod(ax_class, sel_registerName("setAccessibilityValue:"), rawptr(host_ax_set_value), "v@:@")
	objc_registerClassPair(ax_class)
	services.accessibility_class = ax_class

	window_class := objc_allocateClassPair(
		objc_getClass("NSWindow"),
		"HWCalendarWindow",
		0,
	)
	if window_class == nil {return false}
	class_addMethod(window_class, sel_registerName("canBecomeKeyWindow"), rawptr(host_window_can_become_key), "B@:")
	class_addMethod(window_class, sel_registerName("canBecomeMainWindow"), rawptr(host_window_can_become_key), "B@:")
	objc_registerClassPair(window_class)
	services.window_class = window_class
	return true
}

load_module :: proc(generation: int) -> (Loaded_Module, bool) {
	write_time, write_error := os.last_write_time_by_name(module_path)
	if write_error != os.ERROR_NONE {return {}, false}
	shadow_path := strings.clone(fmt.tprintf("%s.generation-%d", module_path, generation))
	if copy_error := os2.copy_file(shadow_path, module_path); copy_error != nil {
		delete(shadow_path)
		return {}, false
	}
	library, loaded := dynlib.load_library(shadow_path)
	if !loaded {
		_ = os.remove(shadow_path)
		delete(shadow_path)
		return {}, false
	}
	getter_address, found := dynlib.symbol_address(
		library,
		"calendar_hot_reload_get_api",
	)
	if !found {
		_ = dynlib.unload_library(library)
		_ = os.remove(shadow_path)
		delete(shadow_path)
		return {}, false
	}
	getter := transmute(proc "c" () -> ^hot_reload.Module_API)getter_address
	api := getter()
	if api == nil {
		_ = dynlib.unload_library(library)
		_ = os.remove(shadow_path)
		delete(shadow_path)
		return {}, false
	}
	return {
		api = api,
		library = library,
		shadow_path = shadow_path,
		write_time = write_time,
		generation = generation,
	}, true
}

discard_module :: proc(module: ^Loaded_Module) {
	if module.library != nil {_ = dynlib.unload_library(module.library)}
	if len(module.shadow_path) > 0 {
		_ = os.remove(module.shadow_path)
		delete(module.shadow_path)
	}
	module^ = {}
}

request_restart :: proc(reason: string) {
	fmt.printf("[hw_calendar] %s; restarting the hot-reload host\n", reason)
	restart_requested = true
	msg_void_id(Id(services.app), sel_registerName("stop:"), nil)
}

host_try_reload :: proc() {
	write_time, write_error := os.last_write_time_by_name(module_path)
	if write_error != os.ERROR_NONE || write_time == current_module.write_time {return}
	if has_failed_write && write_time == last_failed_write {return}
	can_reload := transmute(proc "c" () -> bool)current_module.api.can_reload
	if can_reload == nil || !can_reload() {return}

	sync.mutex_lock(&reload_mutex)
	defer sync.mutex_unlock(&reload_mutex)

	candidate, loaded := load_module(current_module.generation + 1)
	if !loaded {
		last_failed_write = write_time
		has_failed_write = true
		fmt.eprintln("[hw_calendar] reload module could not be loaded; keeping the current generation")
		return
	}
	if candidate.api.api_version != hot_reload.API_VERSION {
		discard_module(&candidate)
		request_restart("hot-reload API changed")
		return
	}
	if candidate.api.state_version != current_module.api.state_version ||
	   candidate.api.snapshot_size != current_module.api.snapshot_size ||
	   candidate.api.snapshot_align != current_module.api.snapshot_align {
		discard_module(&candidate)
		request_restart("hot-reload state layout changed")
		return
	}

	before_swap := transmute(proc "c" ())current_module.api.before_swap
	capture := transmute(proc "c" (rawptr))current_module.api.capture
	stage := transmute(proc "c" (rawptr, ^hot_reload.Host_Services) -> bool)candidate.api.stage
	commit_current := transmute(proc "c" ())current_module.api.commit
	if before_swap == nil || capture == nil || stage == nil {
		discard_module(&candidate)
		last_failed_write = write_time
		has_failed_write = true
		return
	}
	before_swap()
	capture(snapshot)
	if !stage(snapshot, &services) {
		if commit_current != nil {commit_current()}
		discard_module(&candidate)
		last_failed_write = write_time
		has_failed_write = true
		fmt.eprintln("[hw_calendar] reload staging failed; keeping the current generation")
		return
	}

	append(&loaded_modules, candidate)
	current_module = candidate
	commit := transmute(proc "c" ())current_module.api.commit
	if commit != nil {commit()}
	has_failed_write = false
	fmt.printf("[hw_calendar] hot reloaded generation %d\n", current_module.generation)
}

run_cli :: proc(host_args: []string) -> int {
	module, loaded := load_module(0)
	if !loaded || module.api.api_version != hot_reload.API_VERSION {
		if loaded {discard_module(&module)}
		fmt.eprintln("[hw_calendar] could not load the development CLI module")
		return 1
	}
	defer discard_module(&module)
	cli_main := transmute(proc "c" ([^]cstring, int) -> i32)module.api.cli_main
	if cli_main == nil {return 1}
	args := make([]cstring, len(host_args), context.temp_allocator)
	for value, index in host_args {
		args[index] = strings.clone_to_cstring(value, context.temp_allocator)
	}
	return int(cli_main(raw_data(args), len(args)))
}

run_gui :: proc() -> int {
	first, loaded := load_module(1)
	if !loaded || first.api.api_version != hot_reload.API_VERSION {
		if loaded {discard_module(&first)}
		fmt.eprintln("[hw_calendar] could not load the initial hot-reload module")
		return 1
	}
	current_module = first
	loaded_modules = make([dynamic]Loaded_Module)
	append(&loaded_modules, first)

	if !objc_initialize() || !register_classes() {
		fmt.eprintln("[hw_calendar] could not initialize the hot-reload AppKit host")
		return 1
	}
	services.app = msg_id(objc_getClass("NSApplication"), sel_registerName("sharedApplication"))
	services.launch_in_background = true
	initialize := transmute(proc "c" (^hot_reload.Host_Services) -> bool)current_module.api.initialize
	if initialize == nil || !initialize(&services) {
		fmt.eprintln("[hw_calendar] could not initialize the application module")
		return 1
	}
	snapshot = mem.alloc(
		current_module.api.snapshot_size,
		current_module.api.snapshot_align,
	) or_else nil
	if snapshot == nil {return 1}
	defer mem.free(snapshot)

	timer_send := transmute(proc "c" (
		Id, Sel, f64, Id, Sel, Id, bool,
	) -> Id)objc_send_address
	frame_timer := timer_send(
		objc_getClass("NSTimer"),
		sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
		1.0/60.0,
		Id(services.delegate),
		sel_registerName("calendarFrame:"),
		nil,
		true,
	)
	main_run_loop := msg_id(objc_getClass("NSRunLoop"), sel_registerName("mainRunLoop"))
	p := transmute(proc "c" (Id, Sel, Id, Id))objc_send_address
	p(
		main_run_loop,
		sel_registerName("addTimer:forMode:"),
		frame_timer,
		msg_id_id_string(objc_getClass("NSString"), "stringWithUTF8String:", "NSEventTrackingRunLoopMode"),
	)
	msg_void(Id(services.app), sel_registerName("run"))

	shutdown := transmute(proc "c" ())current_module.api.shutdown
	if shutdown != nil {shutdown()}
	for &module in loaded_modules {
		discard_module(&module)
	}
	delete(loaded_modules)
	if restart_requested {return hot_reload.RESTART_EXIT_CODE}
	return 0
}

msg_id_id_string :: proc(receiver: Id, selector_name, value: string) -> Id {
	selector := sel_registerName(strings.clone_to_cstring(selector_name, context.temp_allocator))
	c_value := strings.clone_to_cstring(value, context.temp_allocator)
	p := transmute(proc "c" (Id, Sel, cstring) -> Id)objc_send_address
	return p(receiver, selector, c_value)
}

main :: proc() {
	host_args := make([]string, len(os.args))
	for value, index in os.args {
		host_args[index] = strings.clone(value)
	}
	module_path = os.get_env("HW_HOT_RELOAD_MODULE")
	if len(module_path) == 0 {
		fmt.eprintln("[hw_calendar] HW_HOT_RELOAD_MODULE is not set")
		os.exit(2)
	}
	exit_code := 0
	if len(host_args) > 1 {
		exit_code = run_cli(host_args)
	} else {
		exit_code = run_gui()
	}
	os.exit(exit_code)
}
