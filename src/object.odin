package main

import "core:slice"
import "core:fmt"
import utf8 "core:unicode/utf8"
import strings "core:strings"

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
    str: string
}

@(private = "file")
is_obj_type :: proc(value: Value, type: ObjType) -> bool { return IS_OBJ(value) && AS_OBJ(value).type == type}

print_object :: proc(object: ^Obj) {
    switch object.type {
        case .String: fmt.print((cast(^ObjString)object).str)
        case: fmt.print(object)
    }
}

copy_string :: proc(str: string) -> ^ObjString {
    duplicate := strings.clone(str) or_else panic("Couldn't copy string.")
    return allocate_string(duplicate)
}

allocate_string :: proc(str: string) -> ^ObjString {
    obj_string := cast(^ObjString) allocate_object(ObjString, .String)
    obj_string.str = str
    return obj_string
}

allocate_object :: proc($T: typeid, type: ObjType) -> ^T {
    object := new(T)
    object.type = type
    object.next = vm.objects
    vm.objects = object
    return object
}