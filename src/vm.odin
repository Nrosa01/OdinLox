package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"

STACK_MAX :: 256

InterpretResult :: enum
{
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
}

VM :: struct {
    chunk: ^Chunk,
    ip: []u8,
    stack: [STACK_MAX]Value,
    stack_top: u16,
    globals: Table,
    strings: Table,
    objects: ^Obj,
}

@(private = "package")
vm: VM

init_vm :: proc() {
    reset_stack()
}

free_vm :: proc() {
    free_objects()
    free_table(&vm.globals)
    free_table(&vm.strings)
}

@(private = "file")
reset_stack :: proc() {
    vm.stack_top = 0
}

@(private = "file")
runtime_error :: proc(format: string, args: ..any) {
    log.errorf(format, ..args)

    instruction_index := len(vm.chunk.code) - len(vm.ip) - 1
    line := vm.chunk.lines[instruction_index]
    log.errorf("[line %v] in script\n", line)
    reset_stack()
}

interpret :: proc(source: string) -> InterpretResult {
    chunk: Chunk
    defer free_chunk(&chunk)

    if !compile(source, &chunk) {
        return .COMPILE_ERROR
    }

    vm.chunk = &chunk
    vm.ip = vm.chunk.code[:]

    // Surprisingly, it seems that "run" executes before the deferred statament
    // This is pretty useful and allows cleaner code
    return run()
}

@(private = "file")
run :: proc() -> InterpretResult {
    read_byte :: proc() -> u8 {
        byte := vm.ip[0]
        vm.ip = vm.ip[1:]
        return byte
    }

    read_constant :: proc() -> Value {
        return vm.chunk.constants[read_byte()]
    }

    read_string :: proc() -> ^ObjString {
        return AS_STRING(read_constant())
    }

    for {
        when DEBUG_TRACE_EXECUTION {
            fmt.printf("          ")
            for i in 0 ..< vm.stack_top {
                fmt.printf("[ ")
                print_value(vm.stack[i])
                fmt.printf(" ]")
            }
            fmt.println()
            disassemble_instruction(vm.chunk, len(vm.chunk.code) - len(vm.ip))
        }

        instruction := cast(OpCode) read_byte()
        switch instruction {
        case .PRINT:
            print_value(pop())
            fmt.println()
        case .RETURN:
            return .OK
        case .CONSTANT:
            constant := read_constant()
            push(constant)
        case .NIL: push(NIL_VAL())
        case .TRUE: push(BOOL_VAL(true))
        case .FALSE: push(BOOL_VAL(false))
        case .POP: pop()
        case .GET_LOCAL:
            slot := read_byte()
            push(vm.stack[slot])
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
            vm.stack[slot] = peek(0)
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
peek :: proc(distance: u16) -> Value {
    return vm.stack[vm.stack_top - 1 - distance]
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