package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:sort"
import "core:strings"
import "core:time"

NOTIFICATION_QUEUE_LIMIT :: 48
NOTIFICATION_SNOOZE_SECONDS :: 600
NOTIFICATION_CATEGORY :: "HW_EVENT_REMINDER"
NOTIFICATION_SNOOZE_ACTION :: "HW_SNOOZE"

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
calendar_auth_block: Calendar_Auth_Block
calendar_settings_block: Calendar_Settings_Block

calendar_notification_authorization_name :: proc() -> string {
	switch calendar_notification_authorization {
	case .Not_Determined: return "not_determined"
	case .Denied: return "denied"
	case .Authorized: return "authorized"
	case .Provisional: return "provisional"
	case .Ephemeral: return "ephemeral"
	}
	return "unknown"
}

calendar_notification_auth_completed :: proc "c" (
	block: ^Calendar_Auth_Block,
	granted: bool,
	error: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if calendar_notification_callbacks_pending > 0 {
		calendar_notification_callbacks_pending -= 1
	}
	if error != nil || !granted {
		calendar_notification_authorization = .Denied
	} else {
		calendar_notification_authorization = .Authorized
	}
}

calendar_notification_settings_completed :: proc "c" (
	block: ^Calendar_Settings_Block,
	settings: Id,
) {
	context = runtime.default_context()
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if calendar_notification_callbacks_pending > 0 {
		calendar_notification_callbacks_pending -= 1
	}
	if settings == nil {return}
	status := calendar_msg_uint(settings, sel_registerName("authorizationStatus"))
	switch status {
	case 1: calendar_notification_authorization = .Denied
	case 2: calendar_notification_authorization = .Authorized
	case 3: calendar_notification_authorization = .Provisional
	case 4: calendar_notification_authorization = .Ephemeral
	case: calendar_notification_authorization = .Not_Determined
	}
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
	   calendar_notification_authorization != .Not_Determined {
		return
	}
	p := transmute(proc "c" (Id, Sel, uint, ^Calendar_Auth_Block))objc_send_address
	calendar_notification_callbacks_pending += 1
	p(
		calendar_notification_center,
		sel_registerName("requestAuthorizationWithOptions:completionHandler:"),
		6, // sound | alert
		&calendar_auth_block,
	)
}

calendar_msg_id_f64 :: proc(receiver: Id, selector: Sel, value: f64) -> Id {
	p := transmute(proc "c" (Id, Sel, f64) -> Id)objc_send_address
	return p(receiver, selector, value)
}

calendar_msg_int_id :: proc(receiver: Id, selector: Sel, value: Id) -> int {
	p := transmute(proc "c" (Id, Sel, Id) -> int)objc_send_address
	return p(receiver, selector, value)
}

calendar_notification_absolute_stamp :: proc(
	component: ^ICal_Component,
	property_name: string,
	value: ICal_Date_Time,
) -> i64 {
	civil_stamp := ical_date_time_stamp(value)
	if value.utc || objc_send_address == nil {return civil_stamp}
	timezone: Id
	property := ical_component_property(component, property_name)
	if parameter := ical_property_parameter(property, "TZID");
	   parameter != nil && len(parameter.values) > 0 {
		timezone = msg_id_id(
			objc_getClass("NSTimeZone"),
			sel_registerName("timeZoneWithName:"),
			nsstring(parameter.values[0]),
		)
	}
	if timezone == nil {
		timezone = msg_id(
			objc_getClass("NSTimeZone"),
			sel_registerName("localTimeZone"),
		)
	}
	absolute := civil_stamp
	for _ in 0..<2 {
		date := calendar_msg_id_f64(
			objc_getClass("NSDate"),
			sel_registerName("dateWithTimeIntervalSince1970:"),
			f64(absolute),
		)
		offset := calendar_msg_int_id(
			timezone,
			sel_registerName("secondsFromGMTForDate:"),
			date,
		)
		absolute = civil_stamp-i64(offset)
	}
	return absolute
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

calendar_notification_collect :: proc(
	events: []Calendar_Event,
	occurrences: []Calendar_Occurrence,
	now_stamp: i64,
) -> [dynamic]Calendar_Notification_Candidate {
	result := make([dynamic]Calendar_Notification_Candidate)
	for occurrence in occurrences {
		if occurrence.event_index < 0 || occurrence.event_index >= len(events) {continue}
		event := &events[occurrence.event_index]
		if event.archived {continue}
		document, component, parsed := calendar_event_component(
			event,
			context.temp_allocator,
		)
		if !parsed {
			ical_document_destroy(&document, context.temp_allocator)
			continue
		}
		for &alarm, alarm_index in component.children {
			if alarm.name != "VALARM" {continue}
			action := strings.to_upper(
				calendar_property_value(&alarm, "ACTION"),
				context.temp_allocator,
			)
			if action != "DISPLAY" {continue}
			trigger := ical_component_property(&alarm, "TRIGGER")
			if trigger == nil {continue}
			offset, duration_ok := ical_parse_duration_seconds(trigger.value)
			fire_stamp := i64(0)
			if duration_ok {
				base_stamp := calendar_notification_absolute_stamp(
					component,
					"DTSTART",
					occurrence.start,
				)
				if related := ical_property_parameter(trigger, "RELATED");
				   related != nil && len(related.values) > 0 &&
				   strings.equal_fold(related.values[0], "END") {
					base_stamp = calendar_notification_absolute_stamp(
						component,
						"DTEND",
						occurrence.end,
					)
				}
				fire_stamp = base_stamp + offset
			} else if absolute, ok := ical_parse_date_time(trigger.value); ok {
				fire_stamp = ical_date_time_stamp(absolute)
			} else {
				continue
			}
			repeat_count := 0
			repeat_duration := i64(0)
			if repeat_value := calendar_property_value(&alarm, "REPEAT");
			   len(repeat_value) > 0 {
				repeat_count, _ = ical_parse_int(repeat_value)
			}
			if duration_value := calendar_property_value(&alarm, "DURATION");
			   len(duration_value) > 0 {
				repeat_duration, _ = ical_parse_duration_seconds(duration_value)
			}
			if repeat_count < 0 || repeat_duration <= 0 {
				repeat_count = 0
			}
			for repeat_index in 0..=repeat_count {
				candidate_stamp := fire_stamp + i64(repeat_index)*repeat_duration
				if candidate_stamp <= now_stamp {continue}
				body := fmt.tprintf(
					"Starts %04d-%02d-%02d at %02d:%02d",
					occurrence.start.year,
					occurrence.start.month,
					occurrence.start.day,
					occurrence.start.hour,
					occurrence.start.minute,
				)
				if len(occurrence.location) > 0 {
					body = fmt.tprintf("%s · %s", body, occurrence.location)
				}
				identifier := fmt.tprintf(
					"hw-calendar/%s/%s/%d/%d",
					occurrence.uid,
					occurrence.recurrence_id,
					alarm_index,
					candidate_stamp,
				)
				append(&result, Calendar_Notification_Candidate{
					identifier = strings.clone(identifier),
					uid = strings.clone(occurrence.uid),
					recurrence_id = strings.clone(occurrence.recurrence_id),
					start_value = ical_format_date_time(occurrence.start),
					title = strings.clone(occurrence.summary),
					body = strings.clone(body),
					fire_stamp = candidate_stamp,
				})
			}
		}
		ical_document_destroy(&document, context.temp_allocator)
	}
	sort.merge_sort_proc(result[:], calendar_notification_candidate_compare)
	return result
}

calendar_notification_schedule_candidate :: proc(
	candidate: ^Calendar_Notification_Candidate,
	now_stamp: i64,
) {
	if candidate == nil || candidate.fire_stamp <= now_stamp {return}
	content := msg_id(objc_getClass("UNMutableNotificationContent"), sel_registerName("new"))
	if content == nil {return}
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
	add := transmute(proc "c" (Id, Sel, Id, Id))objc_send_address
	add(
		calendar_notification_center,
		sel_registerName("addNotificationRequest:withCompletionHandler:"),
		request,
		nil,
	)
}

calendar_notification_reconcile :: proc() {
	if calendar_notification_center == nil || calendar_database == nil {return}
	calendar_ui.notification_reconcile_stamp =
		time.to_unix_seconds(time.now())
	events, loaded := calendar_events_load()
	if !loaded {return}
	defer calendar_events_destroy(&events)
	now_stamp := time.to_unix_seconds(time.now())
	start := ical_date_time_from_stamp(now_stamp)
	end := ical_date_time_from_stamp(now_stamp+366*86400)
	occurrences, _ := calendar_expand_events(events[:], start, end, 2_000)
	defer calendar_occurrences_destroy(&occurrences)
	candidates := calendar_notification_collect(events[:], occurrences[:], now_stamp)
	defer calendar_notification_candidates_destroy(&candidates)
	msg_void(
		calendar_notification_center,
		sel_registerName("removeAllPendingNotificationRequests"),
	)
	if len(candidates) == 0 {return}
	calendar_notification_request_authorization()
	for index in 0..<min(len(candidates), NOTIFICATION_QUEUE_LIMIT) {
		calendar_notification_schedule_candidate(&candidates[index], now_stamp)
	}
}

calendar_notification_snooze_content :: proc(content: Id) {
	if content == nil {return}
	identifier := fmt.tprintf(
		"hw-calendar/snooze/%d",
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
	add := transmute(proc "c" (Id, Sel, Id, Id))objc_send_address
	add(
		calendar_notification_center,
		sel_registerName("addNotificationRequest:withCompletionHandler:"),
		request,
		nil,
	)
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
			if start, ok := ical_parse_date_time(string(start_text)); ok {
				now := ical_date_time_from_stamp(
					time.to_unix_seconds(time.now()),
					true,
				)
				calendar_ui.day_offset = int(
					ical_days_from_civil(start.year, start.month, start.day) -
					ical_days_from_civil(now.year, now.month, now.day),
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

calendar_notification_initialize :: proc() {
	if !objc_initialize() {return}
	calendar_notification_prepare_blocks()
	calendar_notification_center = msg_id(
		objc_getClass("UNUserNotificationCenter"),
		sel_registerName("currentNotificationCenter"),
	)
	if calendar_notification_center == nil {return}
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
	calendar_notification_callbacks_pending += 1
	settings(
		calendar_notification_center,
		sel_registerName("getNotificationSettingsWithCompletionHandler:"),
		&calendar_settings_block,
	)
	calendar_notification_reconcile()
}
