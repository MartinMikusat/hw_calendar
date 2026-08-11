package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:time"

NOTIFICATION_QUEUE_LIMIT :: 48
NOTIFICATION_SNOOZE_SECONDS :: 600
NOTIFICATION_CATEGORY :: "HW_EVENT_REMINDER"
NOTIFICATION_SNOOZE_ACTION :: "HW_SNOOZE"
NOTIFICATION_PENDING_META :: "notification.pending-identifiers.v1"
NOTIFICATION_RECONCILE_SECONDS :: 3600

Calendar_Notification_Authorization :: enum int {
	Not_Determined,
	Denied,
	Authorized,
	Provisional,
	Ephemeral,
}

calendar_notification_authorization: Calendar_Notification_Authorization
calendar_notification_center: Id
calendar_notification_callbacks_pending: int
calendar_notification_direct_mode: int
calendar_notification_reconcile_after_settings: int
calendar_notification_authorization_request_pending: int

Calendar_Block_Descriptor :: struct {
	reserved: uint,
	size: uint,
}

Calendar_Auth_Block :: struct {
	isa: ^intrinsics.objc_class,
	flags: u32,
	reserved: u32,
	invoke: proc "c" (block: ^Calendar_Auth_Block, granted: bool, error: Id),
	descriptor: ^Calendar_Block_Descriptor,
}

Calendar_Settings_Block :: struct {
	isa: ^intrinsics.objc_class,
	flags: u32,
	reserved: u32,
	invoke: proc "c" (block: ^Calendar_Settings_Block, settings: Id),
	descriptor: ^Calendar_Block_Descriptor,
}

Calendar_Add_Block :: struct {
	isa: ^intrinsics.objc_class,
	flags: u32,
	reserved: u32,
	invoke: proc "c" (block: ^Calendar_Add_Block, error: Id),
	descriptor: ^Calendar_Block_Descriptor,
}

Calendar_Response_Completion_Block :: struct {
	isa: ^intrinsics.objc_class,
	flags: u32,
	reserved: u32,
	invoke: proc "c" (block: ^Calendar_Response_Completion_Block),
	descriptor: rawptr,
}

Calendar_Presentation_Completion_Block :: struct {
	isa: ^intrinsics.objc_class,
	flags: u32,
	reserved: u32,
	invoke: proc "c" (block: ^Calendar_Presentation_Completion_Block, options: uint),
	descriptor: rawptr,
}

foreign import calendar_blocks "system:System"
foreign calendar_blocks {
	_NSConcreteGlobalBlock: intrinsics.objc_class
}

calendar_auth_descriptor := Calendar_Block_Descriptor{
	size = size_of(Calendar_Auth_Block),
}
calendar_settings_descriptor := Calendar_Block_Descriptor{
	size = size_of(Calendar_Settings_Block),
}
calendar_add_descriptor := Calendar_Block_Descriptor{
	size = size_of(Calendar_Add_Block),
}
calendar_auth_block: Calendar_Auth_Block
calendar_settings_block: Calendar_Settings_Block
calendar_add_block: Calendar_Add_Block

calendar_notification_authorization_get :: proc() -> Calendar_Notification_Authorization {
	return intrinsics.atomic_load(&calendar_notification_authorization)
}

calendar_notification_authorization_set :: proc(value: Calendar_Notification_Authorization) {
	intrinsics.atomic_store(&calendar_notification_authorization, value)
}

calendar_notification_callback_begin :: proc() {
	intrinsics.atomic_add(&calendar_notification_callbacks_pending, 1)
}

calendar_notification_callback_end :: proc() {
	intrinsics.atomic_sub(&calendar_notification_callbacks_pending, 1)
}

calendar_notification_authorization_name :: proc() -> string {
	switch calendar_notification_authorization_get() {
	case .Not_Determined: return "not_determined"
	case .Denied: return "denied"
	case .Authorized: return "authorized"
	case .Provisional: return "provisional"
	case .Ephemeral: return "ephemeral"
	}
	return "unknown"
}

calendar_notification_queue_reconcile :: proc() {
	if intrinsics.atomic_load(&calendar_notification_direct_mode) != 0 {
		calendar_notification_reconcile()
		return
	}
	if calendar_ui.delegate == nil {return}
	calendar_cli_msg_void_sel_id_bool(
		calendar_ui.delegate,
		sel_registerName("performSelectorOnMainThread:withObject:waitUntilDone:"),
		sel_registerName("calendarNotificationReconcile:"),
		nil,
		false,
	)
}

calendar_notification_auth_completed :: proc "c" (
	block: ^Calendar_Auth_Block,
	granted: bool,
	error: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	intrinsics.atomic_store(&calendar_notification_authorization_request_pending, 0)
	if error != nil || !granted {
		calendar_notification_authorization_set(.Denied)
	} else {
		calendar_notification_authorization_set(.Authorized)
	}
	calendar_notification_queue_reconcile()
	calendar_notification_callback_end()
}

calendar_notification_settings_completed :: proc "c" (
	block: ^Calendar_Settings_Block,
	settings: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if settings != nil {
		status := calendar_msg_uint(settings, sel_registerName("authorizationStatus"))
		switch status {
		case 1: calendar_notification_authorization_set(.Denied)
		case 2: calendar_notification_authorization_set(.Authorized)
		case 3: calendar_notification_authorization_set(.Provisional)
		case 4: calendar_notification_authorization_set(.Ephemeral)
		case: calendar_notification_authorization_set(.Not_Determined)
		}
	}
	if intrinsics.atomic_load(&calendar_notification_reconcile_after_settings) != 0 {
		calendar_notification_queue_reconcile()
	}
	calendar_notification_callback_end()
}

calendar_notification_add_completed :: proc "c" (
	block: ^Calendar_Add_Block,
	error: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if error != nil {
		fmt.eprintln("[hw_calendar] notification request could not be scheduled")
	}
	calendar_notification_callback_end()
}

calendar_notification_prepare_blocks :: proc() {
	BLOCK_IS_GLOBAL :: u32(1 << 28)
	calendar_auth_block = {
		isa = &_NSConcreteGlobalBlock,
		flags = BLOCK_IS_GLOBAL,
		invoke = calendar_notification_auth_completed,
		descriptor = &calendar_auth_descriptor,
	}
	calendar_settings_block = {
		isa = &_NSConcreteGlobalBlock,
		flags = BLOCK_IS_GLOBAL,
		invoke = calendar_notification_settings_completed,
		descriptor = &calendar_settings_descriptor,
	}
	calendar_add_block = {
		isa = &_NSConcreteGlobalBlock,
		flags = BLOCK_IS_GLOBAL,
		invoke = calendar_notification_add_completed,
		descriptor = &calendar_add_descriptor,
	}
}

calendar_msg_id_id_u :: proc(
	receiver: Id,
	selector: Sel,
	a, b: Id,
	options: uint,
) -> Id {
	p := transmute(proc "c" (Id, Sel, Id, Id, uint) -> Id)objc_send_address
	return p(receiver, selector, a, b, options)
}

calendar_msg_id_id_id_u :: proc(
	receiver: Id,
	selector: Sel,
	a, b, c: Id,
	options: uint,
) -> Id {
	p := transmute(proc "c" (Id, Sel, Id, Id, Id, uint) -> Id)objc_send_address
	return p(receiver, selector, a, b, c, options)
}

calendar_msg_id_id_id :: proc(
	receiver: Id,
	selector: Sel,
	a, b, c: Id,
) -> Id {
	p := transmute(proc "c" (Id, Sel, Id, Id, Id) -> Id)objc_send_address
	return p(receiver, selector, a, b, c)
}

calendar_msg_id_f64_bool :: proc(
	receiver: Id,
	selector: Sel,
	seconds: f64,
	repeats: bool,
) -> Id {
	p := transmute(proc "c" (Id, Sel, f64, bool) -> Id)objc_send_address
	return p(receiver, selector, seconds, repeats)
}

calendar_notification_register_category :: proc() {
	snooze := calendar_msg_id_id_u(
		objc_getClass("UNNotificationAction"),
		sel_registerName("actionWithIdentifier:title:options:"),
		nsstring(NOTIFICATION_SNOOZE_ACTION),
		nsstring("Snooze 10 Minutes"),
		0,
	)
	actions := msg_id_id(
		objc_getClass("NSArray"),
		sel_registerName("arrayWithObject:"),
		snooze,
	)
	empty := msg_id(objc_getClass("NSArray"), sel_registerName("array"))
	category := calendar_msg_id_id_id_u(
		objc_getClass("UNNotificationCategory"),
		sel_registerName("categoryWithIdentifier:actions:intentIdentifiers:options:"),
		nsstring(NOTIFICATION_CATEGORY),
		actions,
		empty,
		0,
	)
	categories := msg_id_id(
		objc_getClass("NSSet"),
		sel_registerName("setWithObject:"),
		category,
	)
	msg_void_id(
		calendar_notification_center,
		sel_registerName("setNotificationCategories:"),
		categories,
	)
}

calendar_notification_request_authorization :: proc() {
	if calendar_notification_center == nil ||
	   calendar_notification_authorization_get() != .Not_Determined ||
	   intrinsics.atomic_load(&calendar_notification_authorization_request_pending) != 0 {
		return
	}
	p := transmute(proc "c" (Id, Sel, uint, ^Calendar_Auth_Block))objc_send_address
	intrinsics.atomic_store(&calendar_notification_authorization_request_pending, 1)
	calendar_notification_callback_begin()
	p(
		calendar_notification_center,
		sel_registerName("requestAuthorizationWithOptions:completionHandler:"),
		6, // sound | alert
		&calendar_auth_block,
	)
}

Calendar_Notification_Candidate :: struct {
	identifier: string,
	uid: string,
	recurrence_id: string,
	start_value: string,
	title: string,
	body: string,
	fire_stamp: i64,
}

calendar_notification_candidates_destroy :: proc(
	values: ^[dynamic]Calendar_Notification_Candidate,
) {
	for &value in values^ {
		delete(value.identifier)
		delete(value.uid)
		delete(value.recurrence_id)
		delete(value.start_value)
		delete(value.title)
		delete(value.body)
	}
	delete(values^)
	values^ = nil
}

calendar_notification_candidate_compare :: proc(
	a, b: Calendar_Notification_Candidate,
) -> int {
	if a.fire_stamp < b.fire_stamp {return -1}
	if a.fire_stamp > b.fire_stamp {return 1}
	if a.identifier < b.identifier {return -1}
	if a.identifier > b.identifier {return 1}
	return 0
}

calendar_notification_schedule_candidate :: proc(
	candidate: ^Calendar_Notification_Candidate,
	now_stamp: i64,
) -> bool {
	if candidate == nil || candidate.fire_stamp <= now_stamp {return false}
	content := msg_id(objc_getClass("UNMutableNotificationContent"), sel_registerName("new"))
	if content == nil {return false}
	defer msg_void(content, sel_registerName("release"))
	msg_void_id(content, sel_registerName("setTitle:"), nsstring(candidate.title))
	msg_void_id(content, sel_registerName("setBody:"), nsstring(candidate.body))
	msg_void_id(
		content,
		sel_registerName("setSound:"),
		msg_id(objc_getClass("UNNotificationSound"), sel_registerName("defaultSound")),
	)
	msg_void_id(
		content,
		sel_registerName("setCategoryIdentifier:"),
		nsstring(NOTIFICATION_CATEGORY),
	)
	user_info := msg_id(objc_getClass("NSMutableDictionary"), sel_registerName("dictionary"))
	msg_void_id_id := transmute(proc "c" (Id, Sel, Id, Id))objc_send_address
	msg_void_id_id(
		user_info,
		sel_registerName("setObject:forKey:"),
		nsstring(candidate.uid),
		nsstring("uid"),
	)
	msg_void_id_id(
		user_info,
		sel_registerName("setObject:forKey:"),
		nsstring(candidate.recurrence_id),
		nsstring("recurrence_id"),
	)
	msg_void_id_id(
		user_info,
		sel_registerName("setObject:forKey:"),
		nsstring(candidate.start_value),
		nsstring("start"),
	)
	msg_void_id(content, sel_registerName("setUserInfo:"), user_info)
	seconds := f64(candidate.fire_stamp-now_stamp)
	trigger := calendar_msg_id_f64_bool(
		objc_getClass("UNTimeIntervalNotificationTrigger"),
		sel_registerName("triggerWithTimeInterval:repeats:"),
		max(1, seconds),
		false,
	)
	request := calendar_msg_id_id_id(
		objc_getClass("UNNotificationRequest"),
		sel_registerName("requestWithIdentifier:content:trigger:"),
		nsstring(candidate.identifier),
		content,
		trigger,
	)
	add := transmute(proc "c" (Id, Sel, Id, ^Calendar_Add_Block))objc_send_address
	calendar_notification_callback_begin()
	add(
		calendar_notification_center,
		sel_registerName("addNotificationRequest:withCompletionHandler:"),
		request,
		&calendar_add_block,
	)
	return true
}

calendar_notification_remove_registered_requests :: proc() {
	registered, found := calendar_meta_get(
		NOTIFICATION_PENDING_META,
		context.temp_allocator,
	)
	if !found {
		msg_void(
			calendar_notification_center,
			sel_registerName("removeAllPendingNotificationRequests"),
		)
		_ = calendar_meta_set(NOTIFICATION_PENDING_META, "")
		return
	}
	defer delete(registered, context.temp_allocator)
	if len(registered) == 0 {return}
	identifiers := strings.split(registered, "\n", context.temp_allocator)
	defer delete(identifiers, context.temp_allocator)
	array := msg_id(objc_getClass("NSMutableArray"), sel_registerName("array"))
	for identifier in identifiers {
		if len(identifier) > 0 {
			msg_void_id(array, sel_registerName("addObject:"), nsstring(identifier))
		}
	}
	msg_void_id(
		calendar_notification_center,
		sel_registerName("removePendingNotificationRequestsWithIdentifiers:"),
		array,
	)
}

calendar_notification_store_registered_requests :: proc(
	candidates: []Calendar_Notification_Candidate,
	count: int,
) {
	if count <= 0 {
		_ = calendar_meta_set(NOTIFICATION_PENDING_META, "")
		return
	}
	identifiers := make([]string, count, context.temp_allocator)
	defer delete(identifiers, context.temp_allocator)
	for index in 0..<count {identifiers[index] = candidates[index].identifier}
	joined := strings.join(identifiers, "\n", context.temp_allocator)
	defer delete(joined, context.temp_allocator)
	_ = calendar_meta_set(NOTIFICATION_PENDING_META, joined)
}

calendar_notification_can_schedule :: proc() -> bool {
	status := calendar_notification_authorization_get()
	return status == .Authorized || status == .Provisional || status == .Ephemeral
}

calendar_notification_reconcile :: proc() {
	if calendar_notification_center == nil || calendar_database == nil {return}
	now_stamp := time.to_unix_seconds(time.now())
	calendar_ui.notification_reconcile_stamp = now_stamp
	calendar_ui.notification_next_reconcile_stamp =
		now_stamp+NOTIFICATION_RECONCILE_SECONDS
	entries := agenda_entries_list("", "", "")
	defer agenda_entries_destroy(&entries)
	candidates := make([dynamic]Calendar_Notification_Candidate)
	defer calendar_notification_candidates_destroy(&candidates)
	for &entry in entries {
		if entry.state != "active" || len(entry.reminder_at) == 0 {continue}
		fire_stamp, parsed := strconv.parse_i64(entry.reminder_at)
		if !parsed || fire_stamp <= now_stamp {continue}
		start_value := entry.start_at
		if len(start_value) == 0 {start_value = entry.due_at}
		append(&candidates, Calendar_Notification_Candidate{
			identifier = fmt.tprintf("hw_calendar/%d/%d", entry.id, fire_stamp),
			uid = fmt.tprintf("agenda-%d", entry.id),
			start_value = strings.clone(start_value),
			title = strings.clone(entry.original_text),
			body = strings.clone("Confirmed agenda reminder"),
			fire_stamp = fire_stamp,
		})
	}
	sort.merge_sort_proc(candidates[:], calendar_notification_candidate_compare)
	calendar_notification_remove_registered_requests()
	if len(candidates) == 0 {
		calendar_notification_store_registered_requests(nil, 0)
		return
	}
	if calendar_notification_authorization_get() == .Not_Determined {
		calendar_notification_store_registered_requests(nil, 0)
		calendar_notification_request_authorization()
		return
	}
	if !calendar_notification_can_schedule() {
		calendar_notification_store_registered_requests(nil, 0)
		return
	}
	scheduled_count := min(len(candidates), NOTIFICATION_QUEUE_LIMIT)
	for index in 0..<scheduled_count {
		if !calendar_notification_schedule_candidate(&candidates[index], now_stamp) {
			scheduled_count = index
			break
		}
	}
	calendar_notification_store_registered_requests(candidates[:], scheduled_count)
	if scheduled_count > 0 {
		calendar_ui.notification_next_reconcile_stamp = min(
			calendar_ui.notification_next_reconcile_stamp,
			candidates[0].fire_stamp+1,
		)
	}
}

calendar_notification_snooze_content :: proc(content: Id) {
	if content == nil {return}
	identifier := fmt.tprintf(
		"hw_calendar/snooze/%d",
		time.to_unix_nanoseconds(time.now()),
	)
	trigger := calendar_msg_id_f64_bool(
		objc_getClass("UNTimeIntervalNotificationTrigger"),
		sel_registerName("triggerWithTimeInterval:repeats:"),
		NOTIFICATION_SNOOZE_SECONDS,
		false,
	)
	request := calendar_msg_id_id_id(
		objc_getClass("UNNotificationRequest"),
		sel_registerName("requestWithIdentifier:content:trigger:"),
		nsstring(identifier),
		content,
		trigger,
	)
	add := transmute(proc "c" (Id, Sel, Id, ^Calendar_Add_Block))objc_send_address
	calendar_notification_callback_begin()
	add(
		calendar_notification_center,
		sel_registerName("addNotificationRequest:withCompletionHandler:"),
		request,
		&calendar_add_block,
	)
}

calendar_notification_reconcile_on_main :: proc "c" (
	self: Id,
	command: Sel,
	sender: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	calendar_notification_reconcile()
}

calendar_notification_response :: proc "c" (
	self: Id,
	command: Sel,
	center: Id,
	response: Id,
	completion: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	action := msg_id(response, sel_registerName("actionIdentifier"))
	action_text := calendar_msg_cstring(action, sel_registerName("UTF8String"))
	notification := msg_id(response, sel_registerName("notification"))
	request := msg_id(notification, sel_registerName("request"))
	content := msg_id(request, sel_registerName("content"))
	if action_text != nil && string(action_text) == NOTIFICATION_SNOOZE_ACTION {
		calendar_notification_snooze_content(content)
	} else {
		user_info := msg_id(content, sel_registerName("userInfo"))
		start_value := msg_id_id(
			user_info,
			sel_registerName("objectForKey:"),
			nsstring("start"),
		)
		start_text := calendar_msg_cstring(
			start_value,
			sel_registerName("UTF8String"),
		)
		if start_text != nil {
			if start_stamp, ok := strconv.parse_i64(string(start_text)); ok {
				calendar_ui.day_offset = calendar_ui_day_offset_for_stamp(
					start_stamp,
					time.to_unix_seconds(time.now()),
				)
				calendar_ui_reload_data()
				calendar_ui.needs_redraw = true
			}
		}
	}
	if completion != nil {
		block := transmute(^Calendar_Response_Completion_Block)completion
		block.invoke(block)
	}
}

calendar_notification_foreground :: proc "c" (
	self: Id,
	command: Sel,
	center: Id,
	notification: Id,
	completion: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if completion != nil {
		block := transmute(^Calendar_Presentation_Completion_Block)completion
		block.invoke(block, 26) // banner | list | sound
	}
}

calendar_notification_initialize :: proc(reconcile_after_settings := true) {
	if !objc_initialize() {return}
	calendar_notification_prepare_blocks()
	intrinsics.atomic_store(
		&calendar_notification_reconcile_after_settings,
		int(reconcile_after_settings),
	)
	calendar_notification_center = msg_id(
		objc_getClass("UNUserNotificationCenter"),
		sel_registerName("currentNotificationCenter"),
	)
	if calendar_notification_center == nil {return}
	calendar_ui.notification_next_reconcile_stamp =
		time.to_unix_seconds(time.now())+NOTIFICATION_RECONCILE_SECONDS
	if calendar_ui.delegate != nil {
		msg_void_id(
			calendar_notification_center,
			sel_registerName("setDelegate:"),
			calendar_ui.delegate,
		)
	}
	calendar_notification_register_category()
	settings := transmute(proc "c" (
		Id, Sel, ^Calendar_Settings_Block,
	))objc_send_address
	calendar_notification_callback_begin()
	settings(
		calendar_notification_center,
		sel_registerName("getNotificationSettingsWithCompletionHandler:"),
		&calendar_settings_block,
	)
}

calendar_notification_wait_for_callbacks :: proc() -> bool {
	for _ in 0..<500 {
		if intrinsics.atomic_load(&calendar_notification_callbacks_pending) == 0 {
			return true
		}
		time.sleep(10*time.Millisecond)
	}
	return intrinsics.atomic_load(&calendar_notification_callbacks_pending) == 0
}

calendar_notification_initialize_direct :: proc(reconcile_after_settings: bool) -> bool {
	intrinsics.atomic_store(&calendar_notification_direct_mode, 1)
	calendar_notification_initialize(reconcile_after_settings)
	completed := calendar_notification_wait_for_callbacks()
	intrinsics.atomic_store(&calendar_notification_direct_mode, 0)
	if !completed {
		fmt.eprintln("[hw_calendar] notification synchronization timed out")
	}
	return calendar_notification_center != nil && completed
}
