package main

import "core:fmt"

disassemble_chunk :: proc(chunk: ^Chunk, name: string){
    fmt.printf("== %s ==\n", name)

    offset := 0
    for offset < len(chunk.code) {
        offset = disassemble_instruction(chunk, offset)
    }
}

disassemble_instruction :: proc(chunk: ^Chunk, offset: int) -> int{
    fmt.printf("%04d ", offset)
    
    if offset > 0 && chunk.lines[offset] == chunk.lines[offset-1]{
        fmt.printf("   | ")
    } else
    {
        fmt.printf("%4d ", chunk.lines[offset])
    }
    
    instruction := cast(OpCode)chunk.code[offset]
    switch instruction {
    case .PRINT:
        return simple_instruction(.PRINT, offset)
    case .RETURN:
        return simple_instruction(.RETURN, offset)
    case .CONSTANT:
        return constant_instruction(.CONSTANT, chunk, offset)
    case .NIL: 
        return simple_instruction(.NIL, offset)
    case .TRUE:
        return simple_instruction(.TRUE, offset)
    case .FALSE:
        return simple_instruction(.FALSE, offset)
    case .POP:
        return simple_instruction(.POP, offset)
    case .GET_LOCAL:
        return byte_instruction(.GET_LOCAL, chunk, offset)
    case .SET_LOCAL:
        return byte_instruction(.SET_LOCAL, chunk, offset)
    case .GET_GLOBAL:
        return constant_instruction(.GET_GLOBAL, chunk, offset)
    case .SET_GLOBAL:
        return constant_instruction(.SET_GLOBAL, chunk, offset)
    case .DEFINE_GLOBAL:
        return constant_instruction(.DEFINE_GLOBAL, chunk, offset)
    case .EQUAL: 
        return simple_instruction(.EQUAL, offset)
    case .GREATER:
        return simple_instruction(.GREATER, offset)
    case .LESS:
        return simple_instruction(.LESS, offset)
    case .ADD:
        return simple_instruction(.ADD, offset)
    case .SUBTRACT:
        return simple_instruction(.SUBTRACT, offset)
    case .MULTIPLY:
        return simple_instruction(.MULTIPLY, offset)
    case .DIVIDE:
        return simple_instruction(.DIVIDE, offset)
    case .NOT:
        return simple_instruction(.NOT, offset)
    case .NEGATE:
        return simple_instruction(.NEGATE, offset)
    case:
        fmt.printf("Unknown opcode %d\n", instruction)
        return offset+1
    }
}

@(private = "file")
simple_instruction :: proc(name: OpCode, offset: int) -> int {
    fmt.printf("%s\n", name)
    return offset + 1
}

@(private = "file")
byte_instruction :: proc(name: OpCode, chunk: ^Chunk, offset: int) -> int {
    slot := chunk.code[offset + 1]
    buf: [32]u8
    name_str := fmt.bprintf(buf[:], "%v", name)
    fmt.printf("%-16v %v '", name_str, slot)
    return offset + 2
}

@(private = "file")
constant_instruction :: proc(name: OpCode, chunk: ^Chunk, offset: int) -> int {
    constant := chunk.code[offset + 1]
    buf: [32]u8
    name_str := fmt.bprintf(buf[:], "%v", name)
    fmt.printf("%-16v %v '", name_str, constant)
    print_value(chunk.constants[constant])
    fmt.printf("'\n")
    return offset + 2
}