﻿package main

OpCode :: enum u8 {
    CONSTANT,
    NIL,
    TRUE, 
    FALSE,
    EQUAL,
    GREATER,
    LESS,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    NOT,
    NEGATE,
    RETURN,
}

Chunk :: struct
{
    code : [dynamic]u8,
    lines: [dynamic]int,
    constants: [dynamic]Value,
}

free_chunk :: proc(c: ^Chunk) {
    delete(c.code)
    delete(c.lines)
    delete(c.constants)
}

@(private = "file")
write_chunk_proc :: proc(chunk: ^Chunk, byte: u8, line: int) {
    append(&chunk.code, byte)
    append(&chunk.lines, line)
}

@(private = "file")
write_chunk_op_code :: proc(chunk: ^Chunk, code: OpCode, line: int) {
    write_chunk_proc(chunk, cast(u8)code, line)
}

write_chunk_byte :: proc(chunk: ^Chunk, byte: u8, line: int){
    write_chunk_proc(chunk, byte, line)
}

@(private = "file")
write_chunk_int :: proc(chunk: ^Chunk, code: int, line: int) {
    write_chunk_proc(chunk, cast(u8)code, line)
}

write_chunk :: proc {
    write_chunk_op_code,
    write_chunk_byte,
    write_chunk_int,
}

add_constant :: proc(chunk: ^Chunk, value: Value) -> int {
    append(&chunk.constants, value)
    return len(chunk.constants) - 1
}
