package main

import "core:slice"
import "core:fmt"
import "core:unicode/utf8"
import "core:strings"
import "core:hash"

OBJ_TYPE :: #force_inline proc(obj: Value) -> ObjType { return AS_OBJ(obj).type }

AS_CLOSURE :: #force_inline proc(value: Value) -> ^ObjClosure { return as_obj_type(value, ^ObjClosure) }
IS_CLOSURE :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Closure) }

AS_FUNCTION :: #force_inline proc(value: Value) -> ^ObjFunction { return as_obj_type(value, ^ObjFunction) }
IS_FUNCTION :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Function) }

AS_NATIVE   :: #force_inline proc(value: Value) -> ^ObjNative { return as_obj_type(value, ^ObjNative) }
IS_NATIVE   :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Native)}

AS_STRING :: #force_inline proc(value: Value) -> ^ObjString { return as_obj_type(value, ^ObjString) }
IS_STRING :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .String) }
 

ObjType :: enum {
    Closure,
    Function,
    Native,
    String,
    Upvalue,
}

Obj :: struct {
    type: ObjType,
    next: ^Obj,
}

ObjFunction :: struct {
    using obj: Obj,
    arity: u8,
    upvalue_count: int,
    chunk: Chunk,
    name: ^ObjString,
}

NativeFn :: proc(arg_count: u8, args: []Value) -> Value

ObjNative :: struct {
    using obj: Obj, 
    function: NativeFn
}

ObjString :: struct {
    using obj: Obj,
    str: string,
    hash: u32,
}

ObjUpvalue :: struct {
    using obj: Obj,
    location: ^Value,
    closed: Value,
    next_upvalue: ^ObjUpvalue,
}

ObjClosure :: struct {
    using obj: Obj,
    function: ^ObjFunction,
    upvalues: [dynamic]^ObjUpvalue,
    upvalue_count: int,
}

new_upvalue :: proc(slot: ^Value) -> ^ObjUpvalue {
    upvalue := allocate_object(ObjUpvalue, .Upvalue)
    upvalue.location = slot
    return upvalue
}

new_closure :: proc(function: ^ObjFunction) -> ^ObjClosure {
    upvalues := make([dynamic]^ObjUpvalue, function.upvalue_count)
    closure := allocate_object(ObjClosure, .Closure)
    closure.function = function
    closure.upvalues = upvalues
    closure.upvalue_count = function.upvalue_count
    return closure
}

new_function :: proc() -> ^ObjFunction {
    return allocate_object(ObjFunction, .Function)
}

new_native :: proc(function: NativeFn) -> ^ObjNative {
    native := allocate_object(ObjNative, .Native)
    native.function = function
    return native
}

@(private = "file")
as_obj_type :: proc(value: Value, $type: typeid) -> type { return cast(type)AS_OBJ(value)}

@(private = "file")
is_obj_type :: proc(value: Value, type: ObjType) -> bool { return IS_OBJ(value) && AS_OBJ(value).type == type}

print_object :: proc(value: Value) {
    switch AS_OBJ(value).type {
        case .Closure: print_function(AS_CLOSURE(value).function)
        case .Function: print_function(AS_FUNCTION(value))
        case .Native: fmt.printf("<native fn>")
        case .String: fmt.printf("\"%v\"", AS_STRING(value).str)
        case .Upvalue: fmt.printf("upvalue")
        case: fmt.print(value)
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

print_function :: proc(function: ^ObjFunction) {
    if function.name == nil {
        fmt.printf("<scripts>")
        return
    }
    
    fmt.printf("<fn %v>", function.name.str)
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