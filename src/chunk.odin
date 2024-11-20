package main

OpCode :: enum u8 {
    OP_CONSTANT,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NEGATE,
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

writeChunk_OpCode :: proc(chunk: ^Chunk, code: OpCode, line: int) {
    append(&chunk.code, cast(u8)code)
    append(&chunk.lines, line)
}

writeChunk_Int :: proc(chunk: ^Chunk, byte: int, line: int) {
    append(&chunk.code, cast(u8)byte)
    append(&chunk.lines, line)
}

writeChunk :: proc {
    writeChunk_OpCode,
    writeChunk_Int,
}

addConstant :: proc(chunk: ^Chunk, value: Value) -> int {
    append(&chunk.constants, value)
    return len(chunk.constants) - 1
}
