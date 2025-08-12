package main

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import time "core:time"

FRAMES_MAX :: 64
STACK_MAX :: FRAMES_MAX * cast(u32) max(u8)

CallFrame :: struct {
    closure: ^ObjClosure,
    ip: int,
    slots: []Value,
}

InterpretResult :: enum
{
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
}

VM :: struct {
    frames: [FRAMES_MAX]CallFrame,
    frame_count: int,
    init_string: ^ObjString,
    open_upvalues: ^ObjUpvalue,
    stack: [STACK_MAX]Value,
    stack_top: u32,
    globals: Table,
    strings: Table,
    objects: ^Obj,
    gray_stack: [dynamic]^Obj,
    gray_count: int,
    bytes_allocated: int,
    next_gc: int,
}

@(private = "package")
vm: VM

clock_native :: proc(arg_count: u8, args: []Value) -> Value {
    return NUMBER_VAL(cast(f64)(time.now()._nsec) / cast(f64)(time.Second))
}

init_vm :: proc() {
    reset_stack()
    vm.init_string = copy_string("init")
    define_native("clock", clock_native)
    vm.next_gc = 1024*1024
}

free_vm :: proc() {
    vm.init_string = nil
    free_objects()
    free_table(&vm.globals)
    free_table(&vm.strings)
}

@(private = "file")
reset_stack :: proc() {
    vm.stack_top = 0
    vm.frame_count = 0
}

@(private = "file")
runtime_error :: proc(format: string, args: ..any) {
    log.errorf(format, ..args)

    for i := vm.frame_count - 1; i >= 0; i -= 1 {
        frame := &vm.frames[i]
        function := frame.closure.function
        instruction_index := len(function.chunk.code) - frame.ip - 1
        line := function.chunk.lines[instruction_index]
        name := function.name.str if function.name != nil else "script"
        log.errorf("[line %v] in %v()\n", line, name)
    }
    
    reset_stack()
}

@(private = "file")
define_native :: proc(name: string, function: NativeFn) {
    push(OBJ_VAL(copy_string(name)))
    push(OBJ_VAL(new_native(function)))
    table_set(&vm.globals, AS_STRING(vm.stack[0]), vm.stack[1])
    pop()
    pop()
}

interpret :: proc(source: string) -> InterpretResult {
    function := compile(source)
    if function == nil do return .COMPILE_ERROR

    push(OBJ_VAL(function))
    closure := new_closure(function)
    pop()
    push(OBJ_VAL(closure))
    call(closure, 0)

    return run()
}

@(private = "file")
run :: proc() -> InterpretResult {
    read_byte :: proc() -> u8 {
        frame := &vm.frames[vm.frame_count - 1]
        byte := frame.closure.function.chunk.code[frame.ip]
        frame.ip += 1
        return byte
    }

    read_constant :: proc() -> Value {
        frame := &vm.frames[vm.frame_count - 1]
        return frame.closure.function.chunk.constants[read_byte()]
    }

    read_string :: proc() -> ^ObjString { return AS_STRING(read_constant()) }

    read_short :: proc() -> u16 {
        frame := &vm.frames[vm.frame_count - 1]
        frame.ip += 2
        return u16((frame.closure.function.chunk.code[frame.ip - 2] << 8) | frame.closure.function.chunk.code[frame.ip - 1])
    }

    frame := &vm.frames[vm.frame_count - 1]
    
    for {
        when DEBUG_TRACE_EXECUTION {
            fmt.printf("          ")
            for i in 0 ..< vm.stack_top {
                fmt.printf("[ ")
                print_value(vm.stack[i])
                fmt.printf(" ]")
            }
            fmt.println()
            disassemble_instruction(frame.closure.function.chunk, frame.ip)
        }

        instruction := cast(OpCode) read_byte()
        switch instruction {
        case .PRINT:
            print_value(pop())
            fmt.println()
        case .JUMP:
            offset := read_short()
            frame.ip += int(offset)
        case .JUMP_IF_FALSE:
            offset := read_short()
            if is_falsey(peek(0)) do frame.ip += int(offset)
        case .LOOP:
            offset := read_short()
            frame.ip -= int(offset)
        case .CALL:
            arg_count := read_byte()
            if !call_value(peek(u32(arg_count)), arg_count) {
                return .RUNTIME_ERROR
            }
            frame = &vm.frames[vm.frame_count - 1]
        case .INVOKE:
            method := read_string()
            arg_count := read_byte()
            if !invoke(method, arg_count) do return .RUNTIME_ERROR
            frame = &vm.frames[vm.frame_count - 1]
        case .CLOSURE:
            function := AS_FUNCTION(read_constant())
            closure := new_closure(function)
            push(OBJ_VAL(closure))
        
            for i in 0..<closure.upvalue_count {
                is_local := bool(read_byte())
                index := read_byte()
                if is_local do closure.upvalues[i] = capture_upvalue(&frame.slots[index])
                else do closure.upvalues[i] = frame.closure.upvalues[index]
            }
        case .CLOSE_UPVALUE:
            close_upvalues(&vm.stack[vm.stack_top - 1])
            pop()
        case .RETURN:
            result := pop()
            close_upvalues(&frame.slots[0])
            vm.frame_count -= 1
            if vm.frame_count == 0 {
                pop()
                return .OK
            }

            vm.stack_top -= u32(frame.closure.function.arity) + 1
            push(result)
            frame = &vm.frames[vm.frame_count - 1]
        case .CLASS:
            push(OBJ_VAL(new_class(read_string())))
        case .METHOD:
            define_method(read_string())
        case .CONSTANT:
            constant := read_constant()
            push(constant)
        case .NIL: push(NIL_VAL())
        case .TRUE: push(BOOL_VAL(true))
        case .FALSE: push(BOOL_VAL(false))
        case .POP: pop()
        case .GET_LOCAL:
            slot := read_byte()
            push(frame.slots[slot])
        case .GET_GLOBAL:
            name := read_string()
            value: Value
            ok: bool
            if value, ok = table_get(&vm.globals, name); !ok {
                runtime_error("Undefined variable '%s'.", name.str)
                return .RUNTIME_ERROR
            }
            push(value)
        case .DEFINE_GLOBAL:
            name := read_string()
            table_set(&vm.globals, name, peek(0))
            pop()
        case .SET_LOCAL:
            slot := read_byte()
            frame.slots[slot] = peek(0)
        case .SET_GLOBAL:
            name := read_string()
            if table_set(&vm.globals, name, peek(0)) {
                table_delete(&vm.globals, name)
                runtime_error("Undefined variable '%s'.", name.str)
                return .RUNTIME_ERROR
            }
        case .GET_UPVALUE:
            slot := read_byte()
            push(frame.closure.upvalues[slot].location^)
        case .SET_UPVALUE:
            slot := read_byte()
            frame.closure.upvalues[slot].location^ = peek(0)
        case .GET_PROPERTY:
            if (!IS_INSTANCE(peek(0))) {
                runtime_error("Only instances have properties.")
                return .RUNTIME_ERROR
            }
            
            instance := AS_INSTANCE(peek(0))
            name := read_string()
            
            
            if value, exists := table_get(&instance.fields, name); exists {
                pop()
                push(value)
                break
            }
            
            if !bind_method(instance.class, name) {
                return .RUNTIME_ERROR
            }
        case .SET_PROPERTY:
            if (!IS_INSTANCE(peek(1))) {
                runtime_error("Only instances have fields.")
                return .RUNTIME_ERROR
            }
        
            instance := AS_INSTANCE(peek(1))
            table_set(&instance.fields, read_string(), peek(0))
            value := pop()
            pop()
            push(value)
        case .EQUAL:
            a := pop()
            b := pop()
            push(BOOL_VAL(values_equal(a, b)))
        case .GREATER:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(BOOL_VAL(a > b))
        case .LESS:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(BOOL_VAL(a < b))
        case .ADD:
            if IS_STRING(peek(0)) && IS_STRING(peek(1)) {
                concatenate()
            } else if (IS_NUMBER(peek(0)) && IS_NUMBER(peek(1))) {
                b := AS_NUMBER(pop())
                a := AS_NUMBER(pop())
                push(NUMBER_VAL(a + b))
            } else {
                runtime_error("Operands must be two numbers or two strings.")
                return .RUNTIME_ERROR
            }
        case .SUBTRACT:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(NUMBER_VAL(a - b))
        case .MULTIPLY:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(NUMBER_VAL(a * b))
        case .DIVIDE:
            check_numbers() or_return
            b := AS_NUMBER(pop())
            a := AS_NUMBER(pop())
            push(NUMBER_VAL(a / b))
        case .NOT:
            push(BOOL_VAL(is_falsey(pop())))
        case .NEGATE:
            if !IS_NUMBER(peek(0)) {
                runtime_error("Operand must be a number.")
                return .RUNTIME_ERROR
            }
            push(NUMBER_VAL(-AS_NUMBER(pop())))
        case:
            return .OK
        }
    }
}

@(private = "file")
check_numbers :: proc() -> InterpretResult {
    if !IS_NUMBER(peek(0)) || !IS_NUMBER(peek(1)) {
        runtime_error("Operands must be numbers.")
        return .RUNTIME_ERROR
    }

    return nil
}

@(private = "package")
push :: proc(value: Value) {
    vm.stack[vm.stack_top] = value
    vm.stack_top += 1
}

@(private = "package")
pop :: proc() -> Value {
    vm.stack_top -= 1
    return vm.stack[vm.stack_top]
}

@(private = "file")
peek :: proc(distance: u32) -> Value {
    return vm.stack[vm.stack_top - 1 - distance]
}

@(private = "file")
call :: proc(closure: ^ObjClosure, arg_count: u8) -> bool {
    if arg_count != closure.function.arity {
        runtime_error("Expected %v arguments but got %v", closure.function.arity, arg_count)
        return false
    }
    
    if vm.frame_count == FRAMES_MAX {
        runtime_error("Stack overflow.")
        return false
    }

    frame := &vm.frames[vm.frame_count]
    vm.frame_count += 1
    frame.closure = closure
    frame.ip = 0
    frame.slots = vm.stack[vm.stack_top - u32(arg_count) - 1:]
    return true
}

@(private = "file")
call_value :: proc(callee: Value, arg_count: u8) -> bool {
    if IS_OBJ(callee) {
        #partial switch AS_OBJ(callee).type {
            case .Bound_Method:
                bound := AS_BOUND_METHOD(callee)
                vm.stack[vm.stack_top -u32(arg_count) - 1] = bound.receiver
                return call(bound.method, arg_count)
            case .Class:
                class := AS_CLASS(callee)
                vm.stack[vm.stack_top -u32(arg_count) - 1] = OBJ_VAL(new_instance(class))
                if initializer, exists := table_get(&class.methods, vm.init_string); exists {
                   return call(AS_CLOSURE(initializer), arg_count)
                } else if arg_count != 0 {
                    runtime_error("Expected 0 arguments but got %v.", arg_count)
                    return false
                }
                return true
            case .Closure: return call(AS_CLOSURE(callee), arg_count)
            case .Native: 
                native := AS_NATIVE(callee).function
                result := native(arg_count, vm.stack[vm.stack_top - u32(arg_count):])
                vm.stack_top -= u32(arg_count) + 1
                push(result)
                return true
        }
    }
    
    runtime_error("Can only call functions and classes.")
    return false
}

@(private = "file")
invoke_from_class :: proc(class: ^ObjClass, name: ^ObjString, arg_count: u8) -> bool {
    method, exists := table_get(&class.methods, name);
    
    if !exists {
        runtime_error("Undefined property '%v'.", name.str)
        return false
    }
    
    return call(AS_CLOSURE(method), arg_count)
}

@(private = "file")
invoke :: proc(name: ^ObjString, arg_count: u8) -> bool {
    receiver := peek(u32(arg_count))
    
    if !IS_INSTANCE(receiver) {
        runtime_error("Only instances have methods.")
        return false
    }
    
    instance := AS_INSTANCE(receiver)
    if value, exists := table_get(&instance.fields, name); exists {
        vm.stack[vm.stack_top -u32(arg_count) - 1] = value
        return call_value(value, arg_count)
     }
    return invoke_from_class(instance.class, name, arg_count)
}

@(private = "file")
bind_method :: proc(class: ^ObjClass, name: ^ObjString) -> bool {
    if method, exists := table_get(&class.methods, name); !exists {
        runtime_error("Undefined property '%v'.", name.str)
        return false
    } else {
        bound := new_bound_method(peek(0), AS_CLOSURE(method))
        pop()
        push(OBJ_VAL(bound))
        return true
    }
}

@(private = "file")
capture_upvalue :: proc(local: ^Value) -> ^ObjUpvalue {
    previous_upvalue: ^ObjUpvalue
    upvalue := vm.open_upvalues
    
    for upvalue != nil && upvalue.location > local {
        previous_upvalue = upvalue
        upvalue = upvalue.next_upvalue
    }
    
    if upvalue != nil && upvalue.location == local do return upvalue
    
    created_upvalue := new_upvalue(local)
    created_upvalue.next_upvalue = upvalue
    
    if previous_upvalue == nil do vm.open_upvalues = created_upvalue
    else do previous_upvalue.next_upvalue = created_upvalue
    
    return created_upvalue
}

@(private = "file")
close_upvalues :: proc(last: ^Value) {
    for vm.open_upvalues != nil && vm.open_upvalues.location >= last {
        upvalue := vm.open_upvalues
        upvalue.closed = upvalue.location^
        upvalue.location = &upvalue.closed
        vm.open_upvalues = upvalue.next_upvalue
    }
}

@(private = "file")
define_method :: proc(name: ^ObjString) {
    method := peek(0)
    class := AS_CLASS(peek(1))
    table_set(&class.methods, name, method)
    pop()
}

is_falsey :: proc(value: Value) -> bool {
    return IS_NIL(value) || (IS_BOOL(value) && !AS_BOOL(value))
}

@(private = "file")
concatenate :: proc() {
    b_string := AS_STRING(peek(0)).str
    a_string := AS_STRING(peek(1)).str

    result := OBJ_VAL(take_string(strings.concatenate([]string{ a_string, b_string })))
    pop()
    pop()
    push(result)
}