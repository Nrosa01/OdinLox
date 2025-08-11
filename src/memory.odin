package main

import fmt "core:fmt"
import log "core:log"

GC_HEAP_GROW_FACTOR :: 2

free_object :: proc(object: ^Obj) {
    when DEBUG_LOG_GC do log.debugf("%v free type %d", object, object.type)
    
    switch object.type {
        case .Class:
            free(object)
        case .Closure: 
            free(object)
        case .Function:
            function := cast(^ObjFunction) object
            free_chunk(&function.chunk)
            free(object)
        case .Instance:
            instance := cast(^ObjInstance) object
            free_table(&instance.fields)
            free(object)
        case .Native: 
            free(object)
        case .String:
            obj_string := cast(^ObjString) object
            delete(obj_string.str)
            free(obj_string)
        case .Upvalue:
            closure := cast(^ObjClosure) object
            delete(closure.upvalues)
            free(object)
        case: // unreachable
    }
}

free_objects :: proc() {
    object := vm.objects
    
    for object != nil {
        next := object.next
        free_object(object)
        object = next
    }
    
    delete(vm.gray_stack)
}

mark_object :: proc(object: ^Obj) {
    if object == nil do return
    if object.is_marked do return
    
    when DEBUG_LOG_GC {
        log.debugf("%p mark ", object)
        print_value(OBJ_VAL(object))
        log.debugf("\n")
    }
    
    object.is_marked = true
    append(&vm.gray_stack, object)
    vm.gray_count += 1
}

mark_value :: proc(value: Value) {
    if IS_OBJ(value) do mark_object(AS_OBJ(value))
}

mark_array :: proc(array: [dynamic]Value) {
    for value in array do mark_value(value)
}

blacken_object :: proc(object: ^Obj) {
    when DEBUG_LOG_GC {
        log.debugf("%p blacken ", object)
        print_value(OBJ_VAL(object))
        log.debugf("\n")
    }
    
    switch object.type {
        case .Class:
            class := cast(^ObjClass) object
            mark_object(class.name)
        case .Closure:
            closure := cast(^ObjClosure)object
            mark_object(closure.function)
            for upvalue in closure.upvalues do mark_object(upvalue)
        case .Function:
            function := cast(^ObjFunction)object
            mark_object(function.name)
            mark_array(function.chunk.constants)
        case .Instance:
            instance := cast(^ObjInstance) object
            mark_object(instance.class)
            mark_table(&instance.fields)
        case .Upvalue: mark_value((cast(^ObjUpvalue)object).closed)
        case .Native, .String:
        case:
    }    
}

mark_roots :: proc() {
    for i in 0..<vm.stack_top do mark_value(vm.stack[i])
    
    for i in 0..<vm.frame_count do mark_object(vm.frames[i].closure)
    
    for upvalue := vm.open_upvalues; upvalue != nil; upvalue = upvalue.next_upvalue {
        mark_object(upvalue)
    }
    
    mark_table(&vm.globals)
    mark_compiler_roots()
}

trace_references :: proc() {
    for vm.gray_count > 0 {
        vm.gray_count -= 1
        object := vm.gray_stack[vm.gray_count]
        blacken_object(object)
    }    
    
    clear(&vm.gray_stack)
}

sweep :: proc() {
    previous: ^Obj
    object := vm.objects
    
    for object != nil {
        if object.is_marked {
            object.is_marked = false
            previous = object
            object = object.next
        } else {
            unreached := object
            object = object.next
            if previous != nil {
                previous.next = object
            } else {
                vm.objects = object
            }
            
            free_object(unreached)
        }
    }
}

collect_garbage :: proc() {
    when DEBUG_LOG_GC {
        log.debugf("-- GC Begins")
        before := vm.bytes_allocated
    }
    
    mark_roots()
    trace_references()
    table_remove_white(&vm.strings)
    sweep()

    vm.next_gc = vm.bytes_allocated * GC_HEAP_GROW_FACTOR
    
    when DEBUG_LOG_GC {
        log.debugf("   collected %v bytes (from %v to %v) next at %v", before - vm.bytes_allocated, before, vm.bytes_allocated, vm.next_gc)
        log.debugf("-- GC Ends")
    }
}