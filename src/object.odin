package main

import "core:slice"
import "core:fmt"
import "core:unicode/utf8"
import "core:strings"
import "core:hash"

OBJ_TYPE :: #force_inline proc(obj: Value) -> ObjType { return AS_OBJ(obj).type }

// You could perfectly use generic functions instead of creating one per object type. But I like how this
// makes the code more readable and quick to type.
AS_BOUND_METHOD :: #force_inline proc(value: Value) -> ^ObjBoundMethod { return as_obj_type(value, ^ObjBoundMethod) }
IS_BOUND_METHOD :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Bound_Method) }

AS_INSTANCE :: #force_inline proc(value: Value) -> ^ObjInstance { return as_obj_type(value, ^ObjInstance) }
IS_INSTANCE :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Instance) }

AS_CLASS :: #force_inline proc(value: Value) -> ^ObjClass { return as_obj_type(value, ^ObjClass) }
IS_CLASS :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Class) }

AS_CLOSURE :: #force_inline proc(value: Value) -> ^ObjClosure { return as_obj_type(value, ^ObjClosure) }
IS_CLOSURE :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Closure) }

AS_FUNCTION :: #force_inline proc(value: Value) -> ^ObjFunction { return as_obj_type(value, ^ObjFunction) }
IS_FUNCTION :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Function) }

AS_NATIVE   :: #force_inline proc(value: Value) -> ^ObjNative { return as_obj_type(value, ^ObjNative) }
IS_NATIVE   :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .Native)}

AS_STRING :: #force_inline proc(value: Value) -> ^ObjString { return as_obj_type(value, ^ObjString) }
IS_STRING :: #force_inline proc(value: Value) -> bool { return is_obj_type(value, .String) }
 

ObjType :: enum {
    Bound_Method,
    Class,
    Closure,
    Function,
    Instance,
    Native,
    String,
    Upvalue,
}

Obj :: struct {
    type: ObjType,
    is_marked: bool,
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

ObjClass :: struct {
    using boj: Obj,
    name: ^ObjString,
    methods: Table,
}

ObjInstance :: struct {
    using obj: Obj,
    class: ^ObjClass,
    fields: Table
}

ObjBoundMethod :: struct {
    using obj: Obj,
    receiver: Value,
    method: ^ObjClosure,
}

new_bound_method :: proc(receiver: Value, method: ^ObjClosure) -> ^ObjBoundMethod {
    bound := allocate_object(ObjBoundMethod, .Bound_Method)
    bound.receiver = receiver
    bound.method = method
    return bound
}

new_upvalue :: proc(slot: ^Value) -> ^ObjUpvalue {
    upvalue := allocate_object(ObjUpvalue, .Upvalue)
    upvalue.location = slot
    return upvalue
}

new_class :: proc(name: ^ObjString) -> ^ObjClass {
    class := allocate_object(ObjClass, .Class)
    class.name = name
    return class
}

new_instance :: proc(class: ^ObjClass) -> ^ObjInstance {
    instance := allocate_object(ObjInstance, .Instance)
    instance.class = class
    return instance
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
        case .Bound_Method: print_function(AS_BOUND_METHOD(value).method.function)
        case .Class: fmt.printf("%v", AS_CLASS(value).name.str)
        case .Closure: print_function(AS_CLOSURE(value).function)
        case .Function: print_function(AS_FUNCTION(value))
        case .Instance: fmt.printf("%v instance", AS_INSTANCE(value).class.name.str)
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
    push(OBJ_VAL(obj_string))
    table_set(&vm.strings, obj_string, NIL_VAL)
    pop()
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

    when DEBUG_STRESS_GC do collect_garbage()
    else {
        vm.bytes_allocated += size_of(T)
        if (vm.bytes_allocated > vm.next_gc) {
            collect_garbage()
        }
    }
    
    when DEBUG_LOG_GC do fmt.printf("%v allocate %v for %d", object, size_of(type), type)
    return object
}