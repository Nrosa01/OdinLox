package main

import "core:fmt"

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

interpret :: proc(source: string) -> InterpretResult {
    chunk: Chunk
    defer free_chunk(&chunk)
    
    if !compile(source, &chunk) {
        free_chunk(&chunk)
        return .COMPILE_ERROR
    }
 
    vm.chunk = &chunk
    vm.ip = vm.chunk.code[:]

    // Surprisingly, it seems that "run" executes before the deferred statament
    // This is pretty useful and allows cleaner code
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
            disassemble_instruction(vm.chunk,  len(vm.chunk.code) - len(vm.ip))
        }
        
        instruction := cast(OpCode) readByte() 
        switch instruction {
        case .RETURN:
            printValue(pop())
            fmt.println()
            return InterpretResult.OK
        case .ADD:
            b := pop()
            a := pop()
            push(a + b)
        case .SUBTRACT:
            b := pop()
            a := pop()
            push(a - b)
        case .MULTIPLY:
            b := pop()
            a := pop()
            push(a * b)
        case .DIVIDE:
            b := pop()
            a := pop()
            push(a / b)
        case .CONSTANT:
            constant := readConstant()
            push(constant)
        case .NEGATE:
            push(-pop())
        case:
            return InterpretResult.OK         
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