package main

OpCode :: enum u8 {
    OP_CONSTANT,
    OP_RETURN,
}

Chunk :: struct
{
    code : [dynamic]u8,
    lines: [dynamic]int,
    constants: [dynamic]Value,
}

freeChunk :: proc(c: ^Chunk) {
    delete(c.code)
    delete(c.lines)
    delete(c.constants)
}

writeChunk :: proc(chunk: ^Chunk, byte: u8, line: int) {
    append(&chunk.code, byte)
    append(&chunk.lines, line)
}

addConstant :: proc(chunk: ^Chunk, value: Value) -> int {
    append(&chunk.constants, value)
    return len(chunk.constants) - 1
}
