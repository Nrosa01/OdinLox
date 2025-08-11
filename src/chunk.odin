package main

OpCode :: enum u8 {
    CONSTANT,
    NIL,
    TRUE, 
    FALSE,
    POP,
    GET_LOCAL,
    GET_GLOBAL,
    DEFINE_GLOBAL,
    GET_UPVALUE,
    SET_UPVALUE,
    GET_PROPERTY,
    SET_PROPERTY,
    SET_LOCAL,
    SET_GLOBAL,
    EQUAL,
    GREATER,
    LESS,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    NOT,
    NEGATE,
    PRINT,
    JUMP,
    JUMP_IF_FALSE,
    LOOP,
    CALL,
    CLOSURE,
    CLOSE_UPVALUE,
    RETURN,
    CLASS,
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
    push(value)
    append(&chunk.constants, value)
    pop()
    return len(chunk.constants) - 1
}
