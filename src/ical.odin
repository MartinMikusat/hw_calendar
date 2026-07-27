package main

import "core:fmt"
import "core:strconv"
import "core:strings"

ICAL_MAX_IMPORT_BYTES :: 64 * 1024 * 1024
ICAL_MAX_EXPANSION_RESULTS :: 100_000
ICAL_MAX_PERIOD_CANDIDATES :: 200_000
ICAL_MAX_PERIODS :: 1_000_000

ICal_Severity :: enum {
	Info,
	Warning,
	Error,
}

ICal_Diagnostic :: struct {
	severity: ICal_Severity,
	line: int,
	code: string,
	message: string,
}

ICal_Parameter :: struct {
	name: string,
	values: [dynamic]string,
	raw: string,
	dirty: bool,
}

ICal_Property :: struct {
	name: string,
	parameters: [dynamic]ICal_Parameter,
	value: string,
	raw: string,
	line: int,
	dirty: bool,
}

ICal_Component :: struct {
	name: string,
	properties: [dynamic]ICal_Property,
	children: [dynamic]ICal_Component,
	raw_begin: string,
	raw_end: string,
	line: int,
	dirty: bool,
}

ICal_Document :: struct {
	components: [dynamic]ICal_Component,
	diagnostics: [dynamic]ICal_Diagnostic,
	source: string,
}

ical_upper :: proc(value: string, allocator := context.allocator) -> string {
	return strings.to_upper(value, allocator)
}

ical_equal_name :: proc(a, b: string) -> bool {
	return strings.equal_fold(a, b)
}

ical_clone :: proc(value: string, allocator := context.allocator) -> string {
	result, error := strings.clone(value, allocator)
	if error != nil {return ""}
	return result
}

ical_parameter_destroy :: proc(parameter: ^ICal_Parameter, allocator := context.allocator) {
	if parameter == nil {return}
	delete(parameter.name, allocator)
	for value in parameter.values {delete(value, allocator)}
	delete(parameter.values)
	delete(parameter.raw, allocator)
	parameter^ = {}
}

ical_property_destroy :: proc(property: ^ICal_Property, allocator := context.allocator) {
	if property == nil {return}
	delete(property.name, allocator)
	for &parameter in property.parameters {ical_parameter_destroy(&parameter, allocator)}
	delete(property.parameters)
	delete(property.value, allocator)
	delete(property.raw, allocator)
	property^ = {}
}

ical_component_destroy :: proc(component: ^ICal_Component, allocator := context.allocator) {
	if component == nil {return}
	delete(component.name, allocator)
	for &property in component.properties {ical_property_destroy(&property, allocator)}
	for &child in component.children {ical_component_destroy(&child, allocator)}
	delete(component.properties)
	delete(component.children)
	delete(component.raw_begin, allocator)
	delete(component.raw_end, allocator)
	component^ = {}
}

ical_document_destroy :: proc(document: ^ICal_Document, allocator := context.allocator) {
	if document == nil {return}
	for &component in document.components {ical_component_destroy(&component, allocator)}
	for &diagnostic in document.diagnostics {
		delete(diagnostic.code, allocator)
		delete(diagnostic.message, allocator)
	}
	delete(document.components)
	delete(document.diagnostics)
	delete(document.source, allocator)
	document^ = {}
}

ical_add_diagnostic :: proc(
	document: ^ICal_Document,
	severity: ICal_Severity,
	line: int,
	code, message: string,
	allocator := context.allocator,
) {
	append(&document.diagnostics, ICal_Diagnostic{
		severity = severity,
		line = line,
		code = ical_clone(code, allocator),
		message = ical_clone(message, allocator),
	})
}

ical_find_unquoted :: proc(value: string, target: u8) -> int {
	quoted := false
	escaped := false
	for index in 0..<len(value) {
		byte := value[index]
		if escaped {
			escaped = false
			continue
		}
		if byte == '\\' {
			escaped = true
			continue
		}
		if byte == '"' {
			quoted = !quoted
			continue
		}
		if byte == target && !quoted {return index}
	}
	return -1
}

ical_split_unquoted :: proc(
	value: string,
	separator: u8,
	allocator := context.allocator,
) -> [dynamic]string {
	result := make([dynamic]string, allocator)
	start := 0
	quoted := false
	escaped := false
	for index in 0..<len(value) {
		byte := value[index]
		if escaped {
			escaped = false
			continue
		}
		if byte == '\\' {
			escaped = true
			continue
		}
		if byte == '"' {
			quoted = !quoted
			continue
		}
		if byte == separator && !quoted {
			append(&result, ical_clone(value[start:index], allocator))
			start = index + 1
		}
	}
	append(&result, ical_clone(value[start:], allocator))
	return result
}

ical_unquote_parameter :: proc(value: string, allocator := context.allocator) -> string {
	source := value
	if len(source) >= 2 && source[0] == '"' && source[len(source)-1] == '"' {
		source = source[1:len(source)-1]
	}
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	escaped := false
	for index in 0..<len(source) {
		byte := source[index]
		if escaped {
			strings.write_byte(&builder, byte)
			escaped = false
		} else if byte == '\\' {
			escaped = true
		} else {
			strings.write_byte(&builder, byte)
		}
	}
	if escaped {strings.write_byte(&builder, '\\')}
	return strings.to_string(builder)
}

ical_parse_property :: proc(
	line: string,
	line_number: int,
	document: ^ICal_Document,
	allocator := context.allocator,
) -> (ICal_Property, bool) {
	colon := ical_find_unquoted(line, ':')
	if colon <= 0 {
		ical_add_diagnostic(
			document,
			.Error,
			line_number,
			"invalid_content_line",
			"The content line does not contain a property name and value.",
			allocator,
		)
		return {}, false
	}
	head := line[:colon]
	value := line[colon+1:]
	segments := ical_split_unquoted(head, ';', context.temp_allocator)
	if len(segments) == 0 || len(strings.trim_space(segments[0])) == 0 {
		ical_add_diagnostic(
			document,
			.Error,
			line_number,
			"missing_property_name",
			"The content line has no property name.",
			allocator,
		)
		return {}, false
	}
	property := ICal_Property{
		name = ical_upper(strings.trim_space(segments[0]), allocator),
		parameters = make([dynamic]ICal_Parameter, allocator),
		value = ical_clone(value, allocator),
		raw = ical_clone(line, allocator),
		line = line_number,
	}
	for segment in segments[1:] {
		equals := ical_find_unquoted(segment, '=')
		if equals <= 0 {
			ical_add_diagnostic(
				document,
				.Warning,
				line_number,
				"invalid_parameter",
				"The property parameter does not contain a name and value.",
				allocator,
			)
			continue
		}
		parameter := ICal_Parameter{
			name = ical_upper(strings.trim_space(segment[:equals]), allocator),
			values = make([dynamic]string, allocator),
			raw = ical_clone(segment, allocator),
		}
		values := ical_split_unquoted(segment[equals+1:], ',', context.temp_allocator)
		for parameter_value in values {
			append(
				&parameter.values,
				ical_unquote_parameter(strings.trim_space(parameter_value), allocator),
			)
		}
		append(&property.parameters, parameter)
	}
	return property, true
}

ICal_Logical_Line :: struct {
	text: string,
	line: int,
}

ical_unfold_lines :: proc(
	input: string,
	document: ^ICal_Document,
	allocator := context.allocator,
) -> [dynamic]ICal_Logical_Line {
	lines := make([dynamic]ICal_Logical_Line, allocator)
	builder: strings.Builder
	has_builder := false
	current_line := 1
	logical_line := 1
	start := 0
	for index := 0; index <= len(input); index += 1 {
		if index < len(input) && input[index] != '\n' {continue}
		if index == len(input) && start == len(input) {break}
		end := index
		if end > start && input[end-1] == '\r' {end -= 1}
		physical := input[start:end]
		continued := len(physical) > 0 &&
		             (physical[0] == ' ' || physical[0] == '\t')
		if continued && has_builder {
			strings.write_string(&builder, physical[1:])
		} else {
			if has_builder {
				append(&lines, ICal_Logical_Line{
					text = strings.to_string(builder),
					line = logical_line,
				})
				builder = {}
				has_builder = false
			}
			strings.builder_init(&builder, allocator)
			strings.write_string(&builder, physical)
			has_builder = true
			logical_line = current_line
		}
		start = index + 1
		current_line += 1
	}
	if has_builder {
		append(&lines, ICal_Logical_Line{
			text = strings.to_string(builder),
			line = logical_line,
		})
	}
	return lines
}

ical_parse :: proc(input: string, allocator := context.allocator) -> ICal_Document {
	document := ICal_Document{
		components = make([dynamic]ICal_Component, allocator),
		diagnostics = make([dynamic]ICal_Diagnostic, allocator),
		source = ical_clone(input, allocator),
	}
	if len(input) > ICAL_MAX_IMPORT_BYTES {
		ical_add_diagnostic(
			&document,
			.Error,
			0,
			"file_too_large",
			"The iCalendar input exceeds the 64 MiB limit.",
			allocator,
		)
		return document
	}
	lines := ical_unfold_lines(input, &document, context.temp_allocator)
	defer {
		for line in lines {delete(line.text, context.temp_allocator)}
		delete(lines)
	}
	stack := make([dynamic]^ICal_Component, context.temp_allocator)
	defer delete(stack)
	for logical in lines {
		line := logical.text
		if len(line) == 0 {continue}
		property, parsed := ical_parse_property(line, logical.line, &document, allocator)
		if !parsed {continue}
		if property.name == "BEGIN" {
			component_name := ical_upper(strings.trim_space(property.value), allocator)
			component := ICal_Component{
				name = component_name,
				properties = make([dynamic]ICal_Property, allocator),
				children = make([dynamic]ICal_Component, allocator),
				raw_begin = ical_clone(line, allocator),
				line = logical.line,
			}
			if len(stack) == 0 {
				append(&document.components, component)
				append(&stack, &document.components[len(document.components)-1])
			} else {
				parent := stack[len(stack)-1]
				append(&parent.children, component)
				append(&stack, &parent.children[len(parent.children)-1])
			}
			ical_property_destroy(&property, allocator)
			continue
		}
		if property.name == "END" {
			end_name := strings.trim_space(property.value)
			if len(stack) == 0 {
				ical_add_diagnostic(
					&document,
					.Error,
					logical.line,
					"unexpected_end",
					"The END line has no open component.",
					allocator,
				)
			} else {
				current := stack[len(stack)-1]
				if !strings.equal_fold(current.name, end_name) {
					ical_add_diagnostic(
						&document,
						.Error,
						logical.line,
						"mismatched_end",
						fmt.tprintf(
							"END:%s does not match BEGIN:%s.",
							end_name,
							current.name,
						),
						allocator,
					)
				}
				current.raw_end = ical_clone(line, allocator)
				resize(&stack, len(stack)-1)
			}
			ical_property_destroy(&property, allocator)
			continue
		}
		if len(stack) == 0 {
			ical_add_diagnostic(
				&document,
				.Error,
				logical.line,
				"property_outside_component",
				"The property is outside a component.",
				allocator,
			)
			ical_property_destroy(&property, allocator)
			continue
		}
		append(&stack[len(stack)-1].properties, property)
	}
	for component in stack {
		ical_add_diagnostic(
			&document,
			.Error,
			component.line,
			"unterminated_component",
			fmt.tprintf("The %s component has no END line.", component.name),
			allocator,
		)
	}
	ical_validate(&document, allocator)
	return document
}

ical_property_parameter :: proc(property: ^ICal_Property, name: string) -> ^ICal_Parameter {
	if property == nil {return nil}
	for &parameter in property.parameters {
		if ical_equal_name(parameter.name, name) {return &parameter}
	}
	return nil
}

ical_component_property :: proc(component: ^ICal_Component, name: string) -> ^ICal_Property {
	if component == nil {return nil}
	for &property in component.properties {
		if ical_equal_name(property.name, name) {return &property}
	}
	return nil
}

ical_component_properties :: proc(
	component: ^ICal_Component,
	name: string,
	allocator := context.allocator,
) -> [dynamic]^ICal_Property {
	result := make([dynamic]^ICal_Property, allocator)
	if component == nil {return result}
	for &property in component.properties {
		if ical_equal_name(property.name, name) {append(&result, &property)}
	}
	return result
}

ical_component_remove_properties :: proc(
	component: ^ICal_Component,
	name: string,
	allocator := context.allocator,
) {
	if component == nil {return}
	for index := len(component.properties)-1; index >= 0; index -= 1 {
		if !ical_equal_name(component.properties[index].name, name) {continue}
		ical_property_destroy(&component.properties[index], allocator)
		for move := index; move+1 < len(component.properties); move += 1 {
			component.properties[move] = component.properties[move+1]
		}
		resize(&component.properties, len(component.properties)-1)
		component.dirty = true
	}
}

ical_component_set_property :: proc(
	component: ^ICal_Component,
	name, value: string,
	remove_when_empty := false,
	allocator := context.allocator,
) -> ^ICal_Property {
	if component == nil {return nil}
	if remove_when_empty && len(value) == 0 {
		ical_component_remove_properties(component, name, allocator)
		return nil
	}
	property := ical_component_property(component, name)
	if property == nil {
		append(&component.properties, ICal_Property{
			name = ical_upper(name, allocator),
			parameters = make([dynamic]ICal_Parameter, allocator),
			value = ical_clone(value, allocator),
			dirty = true,
		})
		component.dirty = true
		return &component.properties[len(component.properties)-1]
	}
	delete(property.value, allocator)
	property.value = ical_clone(value, allocator)
	property.dirty = true
	return property
}

ical_property_set_parameter :: proc(
	property: ^ICal_Property,
	name, value: string,
	allocator := context.allocator,
) {
	if property == nil {return}
	parameter := ical_property_parameter(property, name)
	if parameter == nil {
		append(&property.parameters, ICal_Parameter{
			name = ical_upper(name, allocator),
			values = make([dynamic]string, allocator),
			dirty = true,
		})
		parameter = &property.parameters[len(property.parameters)-1]
	}
	for parameter_value in parameter.values {
		delete(parameter_value, allocator)
	}
	clear(&parameter.values)
	append(&parameter.values, ical_clone(value, allocator))
	parameter.dirty = true
	property.dirty = true
}

ical_property_remove_parameter :: proc(
	property: ^ICal_Property,
	name: string,
	allocator := context.allocator,
) {
	if property == nil {return}
	for index := len(property.parameters)-1; index >= 0; index -= 1 {
		if !ical_equal_name(property.parameters[index].name, name) {continue}
		ical_parameter_destroy(&property.parameters[index], allocator)
		for move := index; move+1 < len(property.parameters); move += 1 {
			property.parameters[move] = property.parameters[move+1]
		}
		resize(&property.parameters, len(property.parameters)-1)
		property.dirty = true
	}
}

ical_known_component :: proc(name: string) -> bool {
	switch name {
	case "VCALENDAR", "VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY",
	     "VTIMEZONE", "STANDARD", "DAYLIGHT", "VALARM":
		return true
	}
	return strings.has_prefix(name, "X-")
}

ical_property_count :: proc(component: ^ICal_Component, name: string) -> int {
	count := 0
	for &property in component.properties {
		if ical_equal_name(property.name, name) {count += 1}
	}
	return count
}

ical_require_once :: proc(
	document: ^ICal_Document,
	component: ^ICal_Component,
	name: string,
	allocator := context.allocator,
) {
	count := ical_property_count(component, name)
	if count != 1 {
		ical_add_diagnostic(
			document,
			.Error,
			component.line,
			"property_cardinality",
			fmt.tprintf("%s requires exactly one %s property.", component.name, name),
			allocator,
		)
	}
}

ical_validate_component :: proc(
	document: ^ICal_Document,
	component: ^ICal_Component,
	parent_name := "",
	allocator := context.allocator,
) {
	if !ical_known_component(component.name) {
		ical_add_diagnostic(
			document,
			.Info,
			component.line,
			"iana_component",
			fmt.tprintf("The %s component is preserved as an extension.", component.name),
			allocator,
		)
	}
	switch component.name {
	case "VCALENDAR":
		ical_require_once(document, component, "PRODID", allocator)
		ical_require_once(document, component, "VERSION", allocator)
	case "VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY":
		ical_require_once(document, component, "UID", allocator)
		ical_require_once(document, component, "DTSTAMP", allocator)
	case "VTIMEZONE":
		ical_require_once(document, component, "TZID", allocator)
	case "STANDARD", "DAYLIGHT":
		ical_require_once(document, component, "DTSTART", allocator)
		ical_require_once(document, component, "TZOFFSETFROM", allocator)
		ical_require_once(document, component, "TZOFFSETTO", allocator)
	case "VALARM":
		ical_require_once(document, component, "ACTION", allocator)
		ical_require_once(document, component, "TRIGGER", allocator)
		repeat_count := ical_property_count(component, "REPEAT")
		duration_count := ical_property_count(component, "DURATION")
		if repeat_count != duration_count {
			ical_add_diagnostic(
				document,
				.Error,
				component.line,
				"alarm_repeat_pair",
				"VALARM requires REPEAT and DURATION together.",
				allocator,
			)
		}
	}
	if component.name != "VCALENDAR" && len(parent_name) == 0 {
		ical_add_diagnostic(
			document,
			.Error,
			component.line,
			"invalid_root_component",
			"VCALENDAR must contain top-level calendar components.",
			allocator,
		)
	}
	for &child in component.children {
		valid_child := false
		switch component.name {
		case "VCALENDAR":
			valid_child = child.name == "VEVENT" || child.name == "VTODO" ||
			              child.name == "VJOURNAL" || child.name == "VFREEBUSY" ||
			              child.name == "VTIMEZONE" || strings.has_prefix(child.name, "X-")
		case "VEVENT", "VTODO":
			valid_child = child.name == "VALARM" || strings.has_prefix(child.name, "X-")
		case "VTIMEZONE":
			valid_child = child.name == "STANDARD" || child.name == "DAYLIGHT"
		case:
			valid_child = strings.has_prefix(child.name, "X-")
		}
		if !valid_child {
			ical_add_diagnostic(
				document,
				.Error,
				child.line,
				"invalid_component_nesting",
				fmt.tprintf("%s cannot contain %s.", component.name, child.name),
				allocator,
			)
		}
		ical_validate_component(document, &child, component.name, allocator)
	}
}

ical_validate :: proc(document: ^ICal_Document, allocator := context.allocator) {
	for &component in document.components {
		ical_validate_component(document, &component, "", allocator)
	}
}

ical_needs_parameter_quotes :: proc(value: string) -> bool {
	for index in 0..<len(value) {
		byte := value[index]
		if byte == ':' || byte == ';' || byte == ',' || byte == '"' ||
		   byte == ' ' || byte == '\t' {
			return true
		}
	}
	return false
}

ical_write_parameter_value :: proc(builder: ^strings.Builder, value: string) {
	if !ical_needs_parameter_quotes(value) {
		strings.write_string(builder, value)
		return
	}
	strings.write_byte(builder, '"')
	for index in 0..<len(value) {
		byte := value[index]
		if byte == '"' || byte == '\\' {strings.write_byte(builder, '\\')}
		strings.write_byte(builder, byte)
	}
	strings.write_byte(builder, '"')
}

ical_canonical_property :: proc(
	property: ^ICal_Property,
	allocator := context.allocator,
) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	strings.write_string(&builder, strings.to_upper(property.name, context.temp_allocator))
	for &parameter in property.parameters {
		strings.write_byte(&builder, ';')
		strings.write_string(
			&builder,
			strings.to_upper(parameter.name, context.temp_allocator),
		)
		strings.write_byte(&builder, '=')
		for value, index in parameter.values {
			if index > 0 {strings.write_byte(&builder, ',')}
			ical_write_parameter_value(&builder, value)
		}
	}
	strings.write_byte(&builder, ':')
	strings.write_string(&builder, property.value)
	return strings.to_string(builder)
}

ical_fold_line :: proc(
	builder: ^strings.Builder,
	line: string,
	first_limit := 75,
) {
	if len(line) == 0 {
		strings.write_string(builder, "\r\n")
		return
	}
	start := 0
	limit := first_limit
	for start < len(line) {
		end := min(len(line), start + limit)
		for end > start && end < len(line) && (line[end] & 0xc0) == 0x80 {
			end -= 1
		}
		if end == start {end = min(len(line), start + limit)}
		if start > 0 {strings.write_byte(builder, ' ')}
		strings.write_string(builder, line[start:end])
		strings.write_string(builder, "\r\n")
		start = end
		limit = 74
	}
}

ical_serialize_component :: proc(builder: ^strings.Builder, component: ^ICal_Component) {
	begin_line := component.raw_begin
	if component.dirty || len(begin_line) == 0 {
		begin_line = fmt.tprintf("BEGIN:%s", component.name)
	}
	ical_fold_line(builder, begin_line)
	for &property in component.properties {
		line := property.raw
		if property.dirty || len(line) == 0 {
			line = ical_canonical_property(&property, context.temp_allocator)
		}
		ical_fold_line(builder, line)
	}
	for &child in component.children {ical_serialize_component(builder, &child)}
	end_line := component.raw_end
	if component.dirty || len(end_line) == 0 {
		end_line = fmt.tprintf("END:%s", component.name)
	}
	ical_fold_line(builder, end_line)
}

ical_component_is_dirty :: proc(component: ^ICal_Component) -> bool {
	if component == nil {return false}
	if component.dirty {return true}
	for &property in component.properties {
		if property.dirty {return true}
		for parameter in property.parameters {
			if parameter.dirty {return true}
		}
	}
	for &child in component.children {
		if ical_component_is_dirty(&child) {return true}
	}
	return false
}

ical_serialize :: proc(
	document: ^ICal_Document,
	allocator := context.allocator,
) -> string {
	if document != nil && len(document.source) > 0 {
		dirty := false
		for &component in document.components {
			if ical_component_is_dirty(&component) {
				dirty = true
				break
			}
		}
		if !dirty {return ical_clone(document.source, allocator)}
	}
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	for &component in document.components {
		ical_serialize_component(&builder, &component)
	}
	return strings.to_string(builder)
}

ical_unescape_text :: proc(value: string, allocator := context.allocator) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	escaped := false
	for index in 0..<len(value) {
		byte := value[index]
		if escaped {
			switch byte {
			case 'n', 'N': strings.write_byte(&builder, '\n')
			case '\\', ',', ';': strings.write_byte(&builder, byte)
			case: strings.write_byte(&builder, byte)
			}
			escaped = false
		} else if byte == '\\' {
			escaped = true
		} else {
			strings.write_byte(&builder, byte)
		}
	}
	if escaped {strings.write_byte(&builder, '\\')}
	return strings.to_string(builder)
}

ical_escape_text :: proc(value: string, allocator := context.allocator) -> string {
	builder: strings.Builder
	strings.builder_init(&builder, allocator)
	for index in 0..<len(value) {
		byte := value[index]
		switch byte {
		case '\\': strings.write_string(&builder, "\\\\")
		case '\n': strings.write_string(&builder, "\\n")
		case ',': strings.write_string(&builder, "\\,")
		case ';': strings.write_string(&builder, "\\;")
		case: strings.write_byte(&builder, byte)
		}
	}
	return strings.to_string(builder)
}

ical_parse_int :: proc(value: string) -> (int, bool) {
	parsed, ok := strconv.parse_int(strings.trim_space(value))
	return parsed, ok
}
