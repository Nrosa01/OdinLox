package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:bufio"
import "core:io"

main :: proc() {
    when DEBUG_TRACE_EXECUTION {
        fmt.printf("Debugging mode\n")
        trace_mem(execute)
    } else {
        fmt.printf("Release mode\n")
        execute()
    }
}

execute :: proc() {
    init_vm()
    defer(free_vm())
    
    args := os.args
    argsLen := len(args)
    if argsLen == 1 {
        repl()
    } else if argsLen == 2 {
        run_file(args[1])
    } else {
        fmt.eprintln("Usage: clox [path]")
        os.exit(64)
    }
}

repl :: proc() {
    buffer: [1024]u8
    reader: bufio.Reader
    bufio.reader_init_with_buf(&reader, io.to_reader(os.stream_from_handle(os.stdin)), buffer[:])
    for {
        fmt.print(">  ")

        buffer, err := bufio.reader_read_slice(&reader, '\n')
        if err != nil {
            fmt.println(err)
            break
        }
        interpret(string(buffer[:]))
    }
}

run_file :: proc (path: string) {
    source, err := os.read_entire_file(path)
    
    if err {
        fmt.eprintf("Couldn not open file \"%v\".\n", path)
        os.exit(74)
    }
    
    defer delete(source)
    result := interpret(string(source[:]))

    if result == InterpretResult.COMPILE_ERROR { os.exit(65) }
    if result == InterpretResult.RUNTIME_ERROR { os.exit(70) }
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