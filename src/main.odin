package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:log"
import "core:strings"

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
    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)
    
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
    
    free_all(context.temp_allocator)
}

repl :: proc() {
    buffer: [1024]byte
   
    for {
        fmt.print(">  ")

        bytes_written, err := os.read(os.stdin, buffer[:])
        if err != nil {
            fmt.println(err)
            break
        }
        str := string(buffer[:bytes_written])
        trimmed := strings.trim_space(str) 
        
        if len(trimmed) == 0 do break
        
        interpret(str)
        free_all(context.temp_allocator)
    }
}

run_file :: proc (path: string) {
    source, err := os.read_entire_file_or_err(path)
    
    if err != nil {
        fmt.eprintf("Could not open file \"%v\". Error: %v\n", path, err)
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