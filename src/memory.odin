package main

free_object :: proc(object: ^Obj) {
    switch object.type {
        case .Closure: 
            free(object)
        case .Function:
            function := cast(^ObjFunction) object
            free_chunk(&function.chunk)
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
}