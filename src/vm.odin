package main

import "core:fmt"

DEBUG_TRACE_EXECUTION :: true
STACK_MAX :: 256

InterpretResult :: enum
{
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
}

VM :: struct {
    chunk: ^Chunk,
    ip: []u8,
    stack: [STACK_MAX]Value,
    stackTop: u16,
}

@private
vm: VM

initVM :: proc() {
    resetStack()
}

freeVM :: proc() {
    
}

@private
resetStack :: proc() {
    vm.stackTop = 0
}

interpret :: proc(chunk: ^Chunk) -> InterpretResult {
    vm.chunk = chunk
    vm.ip = vm.chunk.code[:]
    return run()
}

@private
run :: proc() -> InterpretResult {
    readByte :: proc() -> (b: u8) {
        b = vm.ip[0]
        vm.ip = vm.ip[1:]
        return
    }

    readConstant :: proc() -> Value {
        return vm.chunk.constants[readByte()]
    }

    for {
        when DEBUG_TRACE_EXECUTION {
            fmt.printf("          ")
            for i in 0..<vm.stackTop {
                fmt.printf("[ ")
                printValue(vm.stack[i])
                fmt.printf(" ]")
            }
            fmt.println()
            disassembleInstruction(vm.chunk,  len(vm.chunk.code) - len(vm.ip))
        }
        
        instruction := cast(OpCode) readByte() 
        switch instruction {
        case .OP_RETURN:
            printValue(pop())
            fmt.println()
            return InterpretResult.INTERPRET_OK
        case .OP_ADD:
            b := pop()
            a := pop()
            push(a + b)
        case .OP_SUBTRACT:
            b := pop()
            a := pop()
            push(a - b)
        case .OP_MULTIPLY:
            b := pop()
            a := pop()
            push(a * b)
        case .OP_DIVIDE:
            b := pop()
            a := pop()
            push(a / b)
        case .OP_CONSTANT:
            constant := readConstant()
            push(constant)
        case .OP_NEGATE:
            push(-pop())
        case:
            return InterpretResult.INTERPRET_OK         
        }
    }
}

@private
push :: proc(value: Value) {
    vm.stack[vm.stackTop] = value
    vm.stackTop += 1
}

@private
pop :: proc() -> Value {
    vm.stackTop -= 1
    return vm.stack[vm.stackTop]
}