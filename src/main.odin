package main

import "core:fmt"
import "core:mem"

main :: proc() {
    when ODIN_DEBUG {
        fmt.printf("Debugging mode\n")
        trace_mem(execute)
    } else {
        fmt.printf("Release mode\n")
        execute()
    }
}

execute :: proc() {
    initVM()
    defer(freeVM())
    chunk: Chunk
    defer(freeChunk(&chunk))
    
    constant := addConstant(&chunk, 1.2)
    writeChunk(&chunk, OpCode.OP_CONSTANT, 123)
    writeChunk(&chunk, constant, 123)

    constant = addConstant(&chunk, 3.4)
    writeChunk(&chunk, OpCode.OP_CONSTANT, 123)
    writeChunk(&chunk, constant, 123)

    writeChunk(&chunk, OpCode.OP_ADD, 123)

    constant = addConstant(&chunk, 5.6)
    writeChunk(&chunk, OpCode.OP_CONSTANT, 123)
    writeChunk(&chunk, constant, 123)

    writeChunk(&chunk, OpCode.OP_DIVIDE, 123)
    writeChunk(&chunk, OpCode.OP_NEGATE, 123)
    
    writeChunk(&chunk, OpCode.OP_RETURN, 123)
    // disassembleChunk(&chunk, "test chunk")
    interpret(&chunk)
}

trace_mem :: proc(procedure: proc()) {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)

    procedure()
    
    for _, leak in track.allocation_map {
        fmt.printf("%v leaked %m\n", leak.location, leak.size)
    }
    for bad_free in track.bad_free_array {
        fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
    }
}