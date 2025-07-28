package main

import "core:slice"
import "core:fmt"
import "core:unicode/utf8"
import "core:strings"
import "core:hash"

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
    str: string,
    hash: u32,
}

@(private = "file")
is_obj_type :: proc(value: Value, type: ObjType) -> bool { return IS_OBJ(value) && AS_OBJ(value).type == type}

print_object :: proc(object: ^Obj) {
    switch object.type {
        case .String: fmt.printf("\"%v\"", (cast(^ObjString)object).str)
        case: fmt.print(object)
    }
}

copy_string :: proc(str: string) -> ^ObjString {
    duplicate := strings.clone(str) or_else panic("Couldn't copy string.")
    hash := hash_string(duplicate)

    interned := table_find_string(&vm.strings, str, hash)
    if interned != nil {
        delete(duplicate)
        return interned
    }

    return allocate_string(duplicate, hash)
}


allocate_string :: proc(str: string, hash: u32) -> ^ObjString {
    obj_string := cast(^ObjString) allocate_object(ObjString, .String)
    obj_string.str = str
    obj_string.hash = hash
    table_set(&vm.strings, obj_string, NIL_VAL())
    return obj_string
}

hash_string :: proc "contextless" (str: string) -> u32 {
    bytes := transmute([]u8)str
    return hash.fnv32a(bytes) // I'm not using the book algorithm as it's the same as this
}

take_string :: proc(str: string) -> ^ObjString {
    hash := hash_string(str)

    interned := table_find_string(&vm.strings, str, hash)
    if interned != nil {
        delete(str)
        return interned
    }
    
    return allocate_string(str, hash)
}

allocate_object :: proc($T: typeid, type: ObjType) -> ^T {
    object := new(T)
    object.type = type
    object.next = vm.objects
    vm.objects = object
    return object
}