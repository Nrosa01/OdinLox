package main

import "core:fmt"
import "core:mem"
import "core:slice"

when NAN_BOXING {
    Value      :: distinct u64

    SIGN_BIT    : u64 : 0x8000000000000000
    QNAN        : u64 : 0x7ffc000000000000

    TAG_NIL    :: 1 // 01
    TAG_FALSE  :: 2 // 10
    TAG_TRUE   :: 3 // 11

    FALSE_VAL   : u64 : QNAN | TAG_FALSE
    TRUE_VAL    : u64 : QNAN | TAG_TRUE
    NIL_VAL     : Value : transmute(Value) (QNAN | TAG_NIL)
    
    IS_BOOL    :: proc "contextless" (value: Value)    -> bool { return (u64(value) | 1) == TRUE_VAL }
    IS_NUMBER  :: proc "contextless" (value: Value)    -> bool { return (u64(value) & QNAN) != QNAN }
    IS_NIL     :: proc "contextless" (value: Value)    -> bool { return (value) == NIL_VAL }
    IS_OBJ     :: proc "contextless" (value: Value)    -> bool { return (u64(value) & (QNAN | SIGN_BIT)) == (QNAN | SIGN_BIT)}
    
    AS_BOOL    :: proc "contextless" (value: Value)    -> bool { return u64(value) == TRUE_VAL }
    AS_NUMBER  :: proc "contextless" (value: Value)    -> f64  { return transmute(f64) value }
    AS_OBJ     :: proc "contextless" (value: Value)    -> ^Obj { return cast(^Obj) uintptr(u64(value) & ~(SIGN_BIT | QNAN)) }

    BOOL_VAL   :: proc "contextless" (b: bool)         -> Value { return Value(TRUE_VAL) if b else Value(FALSE_VAL) }
    NUMBER_VAL :: proc "contextless" (num: f64)        -> Value { return transmute(Value) num }
    OBJ_VAL    :: proc "contextless" (obj: ^Obj)       -> Value { return Value(SIGN_BIT | QNAN | cast(u64) uintptr(obj))}

    print_value :: proc(value: Value) {
        if (IS_BOOL(value)) {
            fmt.printf("true" if AS_BOOL(value) else "false")
        } else if (IS_NIL(value)) {
            fmt.printf("nil")
        } else if (IS_NUMBER(value)) {
            fmt.printf("%v", AS_NUMBER(value))
        } else if (IS_OBJ(value)) {
            print_object(value)
        }
    }

    values_equal :: proc(a, b: Value) -> bool {
        if (IS_NUMBER(a) && IS_NUMBER(b)) {
            return AS_NUMBER(a) == AS_NUMBER(b)
        }
        
        return a == b
    }
} else {
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
    IS_OBJ    :: #force_inline proc "contextless" (value: Value) -> bool { return value.type == .OBJ }

    AS_OBJ    :: #force_inline proc "contextless" (value: Value) -> ^Obj { return value.variant.(^Obj) }
    AS_BOOL   :: #force_inline proc "contextless" (value: Value) -> bool { return value.variant.(bool) }
    AS_NUMBER :: #force_inline proc "contextless" (value: Value) -> f64  { return value.variant.(f64) }

    BOOL_VAL   :: #force_inline proc "contextless" (value: bool) -> Value { return Value{.BOOL, value}}
    NIL_VAL    ::                                                   Value {.NIL, nil}
    NUMBER_VAL :: #force_inline proc "contextless" (value: f64)  -> Value { return Value{.NUMBER, value}}
    OBJ_VAL :: #force_inline proc "contextless" (value: ^Obj)    -> Value { return Value{.OBJ, value}}

    print_value :: proc(value: Value) {
        #partial switch value.type {
        case .OBJ: print_object(value)
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
}