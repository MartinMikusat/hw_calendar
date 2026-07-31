package main

// These unavailable adapters keep inactive legacy UI branches type-correct.
// No product action can initialize or call an external calendar service.

Calendar_EventKit_Authorization :: enum {Not_Determined, Restricted, Denied, Write_Only, Full_Access}
Calendar_EventKit_Source_Type :: enum {Unknown}
Calendar_EventKit_Calendar :: struct {
	identifier, title, source_identifier, source_title, color: string,
	source_type: Calendar_EventKit_Source_Type,
	writable, subscribed: bool,
}
Calendar_EventKit_Mutation_Kind :: enum {Create, Update, Delete}
Calendar_EventKit_Mutation :: struct {
	kind: Calendar_EventKit_Mutation_Kind,
	calendar_identifier, summary, description, location, url, categories: string,
	dtstart, dtend, time_zone, rrule, opaque_id, expected_version: string,
	alarm_offsets: []i64,
	replace_alarms, important, future, whole_series: bool,
}
Calendar_EventKit_Result :: struct {
	mutation_succeeded: bool,
	error, mutation_opaque_id, verified_version: string,
	verified_event: Calendar_Event,
}

calendar_eventkit_authorization: Calendar_EventKit_Authorization = .Denied
calendar_eventkit_calendars: [dynamic]Calendar_EventKit_Calendar
calendar_eventkit_initialized := false
calendar_eventkit_last_error := ""

calendar_eventkit_authorization_name :: proc() -> string {return "unavailable"}
calendar_eventkit_source_type_name :: proc(_: Calendar_EventKit_Source_Type) -> string {return "unavailable"}
calendar_eventkit_request_access :: proc() -> bool {return false}
calendar_eventkit_refresh_cache_sync :: proc(_: i64, _: i64) -> bool {return false}
calendar_eventkit_clear_error :: proc() {}
calendar_eventkit_external_refresh_requested :: proc() -> bool {return false}
calendar_eventkit_consume_result :: proc() -> bool {return false}
calendar_eventkit_store_changed :: proc "c" (_: Id, _: Sel, _: Id) {}
calendar_eventkit_local_alarm_offsets :: proc(_: ^Calendar_Event) -> string {return ""}
calendar_eventkit_parse_alarm_offsets :: proc(_: string) -> ([]i64, bool) {return nil, true}
calendar_eventkit_queue_create :: proc(_: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: bool) -> bool {return false}
calendar_eventkit_queue_update :: proc(_: ^Calendar_Event, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: string, _: bool) -> bool {return false}
calendar_eventkit_queue_delete :: proc(_: ^Calendar_Event, _ := false) -> bool {return false}
calendar_eventkit_queue_copy :: proc(_: ^Calendar_Event, _: string) -> bool {return false}
calendar_eventkit_mutation_from_event :: proc(_: ^Calendar_Event, kind: Calendar_EventKit_Mutation_Kind) -> Calendar_EventKit_Mutation {return {kind=kind}}
calendar_eventkit_execute_mutation :: proc(_: Calendar_EventKit_Mutation) -> (Calendar_EventKit_Result, bool) {return {}, false}
calendar_eventkit_result_destroy :: proc(_: ^Calendar_EventKit_Result) {}
