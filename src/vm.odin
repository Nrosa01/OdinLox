package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import time "core:time"

FRAMES_MAX :: 64
STACK_MAX :: FRAMES_MAX * cast(u32) max(u8)

CallFrame :: struct {
    function: ^ObjFunction,
    ip: int,
    slots: []Value,
}

InterpretResult :: enum
{
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
}

VM :: struct {
    frames: [FRAMES_MAX]CallFrame,
    frame_count: int,
    stack: [STACK_MAX]Value,
    stack_top: u32,
    globals: Table,
    strings: Table,
    objects: ^Obj,
}

@(private = "package")
vm: VM

clock_native :: proc(arg_count: u8, args: []Value) -> Value {
    return NUMBER_VAL(cast(f64)(time.now()._nsec) / cast(f64)(time.Second))
}

init_vm :: proc() {
    reset_stack()
    define_native("clock", clock_native)
}

free_vm :: proc() {
    free_objects()
    free_table(&vm.globals)
    free_table(&vm.strings)
}

@(private = "file")
reset_stack :: proc() {
    vm.stack_top = 0
    vm.frame_count = 0
}

@(private = "file")
runtime_error :: proc(format: string, args: ..any) {
    log.errorf(format, ..args)

    for i := vm.frame_count - 1; i >= 0; i -= 1 {
        frame := &vm.frames[i]
        function := frame.function
        instruction_index := len(function.chunk.code) - frame.ip - 1
        line := function.chunk.lines[instruction_index]
        name := function.name.str if function.name != nil else "script"
        log.errorf("[line %v] in %v()\n", line, name)
    }
    
    reset_stack()
}

@(private = "file")
define_native :: proc(name: string, function: NativeFn) {
    push(OBJ_VAL(copy_string(name)))
    push(OBJ_VAL(new_native(function)))
    table_set(&vm.globals, AS_STRING(vm.stack[0]), vm.stack[1])
    pop()
    pop()
}

interpret :: proc(source: string) -> InterpretResult {
    function := compile(source)
    if function == nil do return .COMPILE_ERROR

    push(OBJ_VAL(function))
    call(function, 0)

    return run()
}

@(private = "file")
run :: proc() -> InterpretResult {
    read_byte :: proc() -> u8 {
        frame := &vm.frames[vm.frame_count - 1]
        byte := frame.function.chunk.code[frame.ip]
        frame.ip += 1
        return byte
    }

    read_constant :: proc() -> Value {
        frame := &vm.frames[vm.frame_count - 1]
        return frame.function.chunk.constants[read_byte()]
 }

    read_string :: proc() -> ^ObjString { return AS_STRING(read_constant()) }

    read_short :: proc() -> u16 {
        frame := &vm.frames[vm.frame_count - 1]
        frame.ip += 2
        return u16((frame.function.chunk.code[frame.ip - 2] << 8) | frame.function.chunk.code[frame.ip - 1])
    }

    frame := &vm.frames[vm.frame_count - 1]
    
    for {
        when DEBUG_TRACE_EXECUTION {
            fmt.printf("          ")
            for i in 0 ..< vm.stack_top {
                fmt.printf("[ ")
                print_value(vm.stack[i])
                fmt.printf(" ]")
            }
            fmt.println()
            disassemble_instruction(frame.function.chunk, frame.ip)
        }

        instruction := cast(OpCode) read_byte()
        switch instruction {
        case .PRINT:
            print_value(pop())
            fmt.println()
        case .JUMP:
            offset := read_short()
            frame.ip += int(offset)
        case .JUMP_IF_FALSE:
            offset := read_short()
            if is_falsey(peek(0)) do frame.ip += int(offset)
        case .LOOP:
            offset := read_short()
            frame.ip -= int(offset)
        case .CALL:
            arg_count := read_byte()
            if !call_value(peek(u32(arg_count)), arg_count) {
                return .RUNTIME_ERROR
            }
            frame = &vm.frames[vm.frame_count - 1]
        case .RETURN:
            result := pop()
            vm.frame_count -= 1
            if vm.frame_count == 0 {
                pop()
                return .OK
            }

            // vm.stack_top = frame.slots
            vm.stack_top -= u32(frame.function.arity) + 1
            push(result)
            frame = &vm.frames[vm.frame_count - 1]
        case .CONSTANT:
            constant := read_constant()
            push(constant)
        case .NIL: push(NIL_VAL())
        case .TRUE: push(BOOL_VAL(true))
        case .FALSE: push(BOOL_VAL(false))
        case .POP: pop()
        case .GET_LOCAL:
            slot := read_byte()
            push(frame.slots[slot])
        case .GET_GLOBAL:
            name := read_string()
            value: Value
            ok: bool
            if value, ok = table_get(&vm.globals, name); !ok {
                runtime_error("Undefined variable '%s'.", name.str)
                return .RUNTIME_ERROR
            }
            push(value)
        case .DEFINE_GLOBAL:
            name := read_string()
            table_set(&vm.globals, name, peek(0))
            pop()
        case .SET_LOCAL:
            slot := read_byte()
            frame.slots[slot] = peek(0)
        case .SET_GLOBAL:
            name := read_string()
            if table_set(&vm.globals, name, peek(0)) {
                table_delete(&vm.globals, name)
                runtime_error("Undefined variable '%s'.", name.str)
                return .RUNTIME_ERROR
            }
        case .EQUAL:
            a := pop()
            b := pop()
            push(BOOL_VAL(values_equal(a, b)))
        case .GREATER:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(BOOL_VAL(a > b))
        case .LESS:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(BOOL_VAL(a < b))
        case .ADD:
            if IS_STRING(peek(0)) && IS_STRING(peek(1)) {
                concatenate()
            } else if (IS_NUMBER(peek(0)) && IS_NUMBER(peek(1))) {
                b := AS_NUMBER(pop())
                a := AS_NUMBER(pop())
                push(NUMBER_VAL(a + b))
            } else {
                runtime_error("Operands must be two numbers or two strings.")
                return .RUNTIME_ERROR
            }
        case .SUBTRACT:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(NUMBER_VAL(a - b))
        case .MULTIPLY:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(NUMBER_VAL(a * b))
        case .DIVIDE:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(NUMBER_VAL(a / b))
        case .NOT:
            push(BOOL_VAL(is_falsey(pop())))
        case .NEGATE:
            if !IS_NUMBER(peek(0)) {
                runtime_error("Operand must be a number.")
                return .RUNTIME_ERROR
            }
            push(NUMBER_VAL(-AS_NUMBER(pop())))
        case:
            return .OK
        }
    }
}

@(private = "file")
check_numbers :: proc() -> InterpretResult {
    if !IS_NUMBER(peek(0)) || !IS_NUMBER(peek(1)) {
        runtime_error("Operands must be numbers.")
        return .RUNTIME_ERROR
    }

    return nil
}

@(private = "file")
push :: proc(value: Value) {
    vm.stack[vm.stack_top] = value
    vm.stack_top += 1
}

@(private = "file")
pop :: proc() -> Value {
    vm.stack_top -= 1
    return vm.stack[vm.stack_top]
}

@(private = "file")
peek :: proc(distance: u32) -> Value {
    return vm.stack[vm.stack_top - 1 - distance]
}

@(private = "file")
call :: proc(function: ^ObjFunction, arg_count: u8) -> bool {
    if arg_count != function.arity {
        runtime_error("Expected %v arguments but got %v", function.arity, arg_count)
        return false
    }
    
    if vm.frame_count == FRAMES_MAX {
        runtime_error("Stack overflow.")
        return false
    }

    frame := &vm.frames[vm.frame_count]
    vm.frame_count += 1
    frame.function = function
    frame.ip = 0
    frame.slots = vm.stack[vm.stack_top - u32(arg_count) - 1:]
    return true
}

@(private = "file")
call_value :: proc(callee: Value, arg_count: u8) -> bool {
    if IS_OBJ(callee) {
        #partial switch AS_OBJ(callee).type {
            case .Function: return call(AS_FUNCTION(callee), arg_count)
            case .Native: 
                native := AS_NATIVE(callee).function
                result := native(arg_count, vm.stack[vm.stack_top - u32(arg_count):])
                vm.stack_top -= u32(arg_count) + 1
                push(result)
                return true
        }
    }
    
    runtime_error("Can only call functions and classes.")
    return false
}

is_falsey :: proc(value: Value) -> bool {
    return IS_NIL(value) || (IS_BOOL(value) && !AS_BOOL(value))
}

@(private = "file")
concatenate :: proc() {
    b_string := AS_STRING(pop()).str
    a_string := AS_STRING(pop()).str

    push(OBJ_VAL(take_string(strings.concatenate([]string{ a_string, b_string }))))
}