package main

free_object :: proc(object: ^Obj) {
    switch object.type {
        case .String:
            obj_string := cast(^ObjString) object
            delete(obj_string.chars)
            free(obj_string)
        case: // unreachable
    }
}

free_objects :: proc() {
    object := vm.objects
    
    for object != nil {
        next :=  object.next
        free_object(object)
        object = next
    }
}