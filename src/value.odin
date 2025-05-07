package main

import "core:fmt"

ValueType :: enum {
    BOOL,
    NIL,
    NUMBER,
}

Value :: struct {
    type: ValueType,
    variant: union {
        bool,
        f64,
    },
}

IS_BOOL   :: #force_inline proc(value: Value) -> bool { return value.type == .BOOL }
IS_NIL    :: #force_inline proc(value: Value) -> bool { return value.type == .NIL }
IS_NUMBER :: #force_inline proc(value: Value) -> bool { return value.type == .NUMBER }

AS_BOOL   :: #force_inline proc(value: Value) -> bool { return value.variant.(bool) }
AS_NUMBER :: #force_inline proc(value: Value) -> f64  { return value.variant.(f64) }

BOOL_VAL   :: #force_inline proc(value: bool) -> Value { return Value{.BOOL, value}}
NIL_VAL    :: #force_inline proc()            -> Value { return Value{.NIL, nil}}
NUMBER_VAL :: #force_inline proc(value: f64)  -> Value { return Value{.NUMBER, value}}

print_value :: proc(value: Value) {
    fmt.print(value.variant)
}

values_equal :: proc(a, b: Value) -> bool {
    if a.type != b.type { return false }
    switch a.type {
        case .BOOL:   return AS_BOOL(a) == AS_BOOL(b)
        case .NIL:    return true
        case .NUMBER: return AS_NUMBER(a) == AS_NUMBER(b)
        case: return false // unreachable
    }
}