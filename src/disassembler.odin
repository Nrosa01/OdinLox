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
        fmt.printf("  | ")
    } else
    {
        fmt.printf("%3d ", chunk.lines[offset])
    }
    
    instruction := cast(OpCode)chunk.code[offset]
    switch instruction {
    case .PRINT:
        return simple_instruction("OP_PRINT", offset)
    case .RETURN:
        return simple_instruction("OP_RETURN", offset)
    case .CONSTANT:
        return constant_instruction("OP_CONSTANT", chunk, offset)
    case .NIL: 
        return simple_instruction("OP_NIL", offset)
    case .TRUE:
        return simple_instruction("OP_TRUE", offset)
    case .FALSE:
        return simple_instruction("OP_FALSE", offset)
    case .POP:
        return simple_instruction("OP_POP", offset)
    case .GET_GLOBAL:
        return constant_instruction("OP_GET_GLOBAL", chunk, offset)
    case .SET_GLOBAL:
        return constant_instruction("OP_SET_GLOBAL", chunk, offset)
    case .DEFINE_GLOBAL:
        return constant_instruction("OP_DEFINE_GLOBAL", chunk, offset)
    case .EQUAL: 
        return simple_instruction("OP_EQUAL", offset)
    case .GREATER:
        return simple_instruction("OP_GREATER", offset)
    case .LESS:
        return simple_instruction("OP_LESS", offset)
    case .ADD:
        return simple_instruction("OP_ADD", offset)
    case .SUBTRACT:
        return simple_instruction("OP_SUBTRACT", offset)
    case .MULTIPLY:
        return simple_instruction("OP_MULTIPLY", offset)
    case .DIVIDE:
        return simple_instruction("OP_DIVIDE", offset)
    case .NOT:
        return simple_instruction("OP_NOT", offset)
    case .NEGATE:
        return simple_instruction("OP_NEGATE", offset)
    case:
        fmt.printf("Unknown opcode %d\n", instruction)
        return offset+1
    }
}

@(private = "file")
simple_instruction :: proc(name: string, offset: int) -> int {
    fmt.printf("%s\n", name)
    return offset + 1
}

@(private = "file")
constant_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
    constant := chunk.code[offset + 1]
    fmt.printf("%s %v '", name, constant)
    print_value(chunk.constants[constant])
    fmt.printf("'\n")
    return offset + 2
}