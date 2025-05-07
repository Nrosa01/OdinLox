package main

import "core:fmt"
import "core:mem"
import slice "core:slice"

ValueType :: enum {
    BOOL,
    NIL,
    NUMBER,
    OBJ,
}

Value :: struct {
    type: ValueType,
    variant: union {
        bool,
        f64,
        ^Obj
    },
}

IS_BOOL   :: #force_inline proc(value: Value) -> bool { return value.type == .BOOL }
IS_NIL    :: #force_inline proc(value: Value) -> bool { return value.type == .NIL }
IS_NUMBER :: #force_inline proc(value: Value) -> bool { return value.type == .NUMBER }
IS_OBJ :: #force_inline proc(value: Value) -> bool { return value.type == .OBJ }

AS_OBJ    :: #force_inline proc(value: Value) -> ^Obj { return value.variant.(^Obj) }
AS_BOOL   :: #force_inline proc(value: Value) -> bool { return value.variant.(bool) }
AS_NUMBER :: #force_inline proc(value: Value) -> f64  { return value.variant.(f64) }

BOOL_VAL   :: #force_inline proc(value: bool) -> Value { return Value{.BOOL, value}}
NIL_VAL    :: #force_inline proc()            -> Value { return Value{.NIL, nil}}
NUMBER_VAL :: #force_inline proc(value: f64)  -> Value { return Value{.NUMBER, value}}
OBJ_VAL :: #force_inline proc(value: ^Obj)  -> Value { return Value{.OBJ, value}}

print_value :: proc(value: Value) {
    #partial switch value.type {
        case .OBJ: print_object(AS_OBJ(value))
        case: fmt.print(value.variant)
    }
}

values_equal :: proc(a, b: Value) -> bool {
    if a.type != b.type do return false
    switch a.type {
        case .BOOL:   return AS_BOOL(a) == AS_BOOL(b)
        case .NIL:    return true
        case .NUMBER: return AS_NUMBER(a) == AS_NUMBER(b)
        case .OBJ:
            obj_string_a := cast(^ObjString) AS_OBJ(a)
            obj_string_b := cast(^ObjString) AS_OBJ(b)
            return obj_string_a.str == obj_string_b.str
        case: return false // unreachable
    }
}