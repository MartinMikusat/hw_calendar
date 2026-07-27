package main

import "core:os"
import "core:strings"

Id :: rawptr
Sel :: rawptr

Point :: struct {x, y: f64}
Size :: struct {width, height: f64}
Rect :: struct {origin: Point, size: Size}

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

objc_send_address: rawptr

objc_initialize :: proc() -> bool {
	if objc_send_address != nil {return true}
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

msg_id_id :: proc(receiver: Id, selector: Sel, value: Id) -> Id {
	p := transmute(proc "c" (Id, Sel, Id) -> Id)objc_send_address
	return p(receiver, selector, value)
}

msg_id_id_id :: proc(receiver: Id, selector: Sel, a, b: Id) -> Id {
	p := transmute(proc "c" (Id, Sel, Id, Id) -> Id)objc_send_address
	return p(receiver, selector, a, b)
}

msg_void_id :: proc(receiver: Id, selector: Sel, value: Id) {
	p := transmute(proc "c" (Id, Sel, Id))objc_send_address
	p(receiver, selector, value)
}

msg_void_id_id :: proc(receiver: Id, selector: Sel, a, b: Id) {
	p := transmute(proc "c" (Id, Sel, Id, Id))objc_send_address
	p(receiver, selector, a, b)
}

msg_void_i :: proc(receiver: Id, selector: Sel, value: int) {
	p := transmute(proc "c" (Id, Sel, int))objc_send_address
	p(receiver, selector, value)
}

msg_void_u :: proc(receiver: Id, selector: Sel, value: uint) {
	p := transmute(proc "c" (Id, Sel, uint))objc_send_address
	p(receiver, selector, value)
}

msg_void_bool :: proc(receiver: Id, selector: Sel, value: bool) {
	p := transmute(proc "c" (Id, Sel, bool))objc_send_address
	p(receiver, selector, value)
}

msg_id_rect :: proc(receiver: Id, selector: Sel, value: Rect) -> Id {
	p := transmute(proc "c" (Id, Sel, Rect) -> Id)objc_send_address
	return p(receiver, selector, value)
}

msg_id_rect_u_u_b :: proc(
	receiver: Id,
	selector: Sel,
	rect: Rect,
	style, backing: uint,
	defer_window: bool,
) -> Id {
	p := transmute(proc "c" (Id, Sel, Rect, uint, uint, bool) -> Id)objc_send_address
	return p(receiver, selector, rect, style, backing, defer_window)
}

msg_rect :: proc(receiver: Id, selector: Sel) -> Rect {
	p := transmute(proc "c" (Id, Sel) -> Rect)objc_send_address
	return p(receiver, selector)
}

msg_point :: proc(receiver: Id, selector: Sel) -> Point {
	p := transmute(proc "c" (Id, Sel) -> Point)objc_send_address
	return p(receiver, selector)
}

msg_f64 :: proc(receiver: Id, selector: Sel) -> f64 {
	p := transmute(proc "c" (Id, Sel) -> f64)objc_send_address
	return p(receiver, selector)
}

msg_id_u_u_u_b :: proc(
	receiver: Id,
	selector: Sel,
	a, b, c: uint,
	d: bool,
) -> Id {
	p := transmute(proc "c" (Id, Sel, uint, uint, uint, bool) -> Id)objc_send_address
	return p(receiver, selector, a, b, c, d)
}

msg_void_ptr_u_u :: proc(
	receiver: Id,
	selector: Sel,
	value: rawptr,
	length, index: uint,
) {
	p := transmute(proc "c" (Id, Sel, rawptr, uint, uint))objc_send_address
	p(receiver, selector, value, length, index)
}

msg_void_id_u :: proc(receiver: Id, selector: Sel, value: Id, index: uint) {
	p := transmute(proc "c" (Id, Sel, Id, uint))objc_send_address
	p(receiver, selector, value, index)
}

msg_void_u_u_u :: proc(receiver: Id, selector: Sel, a, b, c: uint) {
	p := transmute(proc "c" (Id, Sel, uint, uint, uint))objc_send_address
	p(receiver, selector, a, b, c)
}

nsstring :: proc(value: string) -> Id {
	if len(value) == 0 {
		return msg_id(objc_getClass("NSString"), sel_registerName("string"))
	}
	c_value := strings.clone_to_cstring(value, context.temp_allocator)
	p := transmute(proc "c" (Id, Sel, cstring) -> Id)objc_send_address
	return p(objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), c_value)
}
