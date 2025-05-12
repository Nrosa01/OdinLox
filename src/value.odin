package main

import "core:fmt"
import "core:mem"
import "core:slice"

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

IS_BOOL   :: #force_inline proc "contextless" (value: Value) -> bool { return value.type == .BOOL }
IS_NIL    :: #force_inline proc "contextless" (value: Value) -> bool { return value.type == .NIL }
IS_NUMBER :: #force_inline proc "contextless" (value: Value) -> bool { return value.type == .NUMBER }
IS_OBJ :: #force_inline proc "contextless" (value: Value) -> bool { return value.type == .OBJ }

AS_OBJ    :: #force_inline proc "contextless" (value: Value) -> ^Obj { return value.variant.(^Obj) }
AS_BOOL   :: #force_inline proc "contextless" (value: Value) -> bool { return value.variant.(bool) }
AS_NUMBER :: #force_inline proc "contextless" (value: Value) -> f64  { return value.variant.(f64) }

BOOL_VAL   :: #force_inline proc "contextless" (value: bool) -> Value { return Value{.BOOL, value}}
NIL_VAL    :: #force_inline proc "contextless" ()            -> Value { return Value{.NIL, nil}}
NUMBER_VAL :: #force_inline proc "contextless" (value: f64)  -> Value { return Value{.NUMBER, value}}
OBJ_VAL :: #force_inline proc "contextless" (value: ^Obj)  -> Value { return Value{.OBJ, value}}

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
        case .OBJ: return AS_OBJ(a) == AS_OBJ(b)
        case: return false // unreachable
    }
}