package main

import "core:slice"
import "core:fmt"
import utf8 "core:unicode/utf8"

OBJ_TYPE :: #force_inline proc(obj: Value) -> ObjType { return AS_OBJ(obj).type }

AS_STRING :: #force_inline proc(value: Value) -> ^ObjString { return cast(^ObjString)AS_OBJ(value) }
IS_STRING :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, ObjType.String) }
 
ObjType :: enum {
    String
}

Obj :: struct {
    type: ObjType,
    next: ^Obj,
}

ObjString :: struct {
    using obj: Obj,
    chars: []rune
}

@(private = "file")
is_obj_type :: proc(value: Value, type: ObjType) -> bool { return IS_OBJ(value) && AS_OBJ(value).type == type}

print_object :: proc(object: ^Obj) {
    switch object.type {
        case .String:
            runes := (cast(^ObjString)object).chars
            fmt.print(utf8.runes_to_string(runes))
        case: fmt.print(object)
    }
}

copy_string :: proc(chars: []rune) -> ^ObjString {
    duplicate := make([]rune, len(chars))
    copy(duplicate, chars)
    return allocate_string(duplicate)
}

allocate_string :: proc(chars: []rune) -> ^ObjString {
    obj_string := cast(^ObjString) allocate_object(ObjString, .String)
    obj_string.chars = chars
    return obj_string
}

allocate_object :: proc($T: typeid, type: ObjType) -> ^T {
    object := new(T)
    object.type = type
    object.next = vm.objects
    vm.objects = object
    return object
}