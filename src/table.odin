package main

import "core:mem"
import "core:strings"
import fmt "core:fmt"

TABLE_MAX_LOAD :: 0.75

Table :: struct {
    count: int,
    capacity: int,
    entries: []Entry,
}

Entry :: struct {
    key: ^ObjString,
    value: Value,
}

free_table :: proc(table: ^Table) {
    table.count = 0
    table.capacity = 0
    delete(table.entries)
}

table_set :: proc (table: ^Table, key: ^ObjString, value: Value) -> bool {
    if f32(table.count + 1) > f32(table.capacity) * TABLE_MAX_LOAD {
        capacity := grow_capacity(table.capacity)
        adjust_capacity(table, capacity)
    }

    entry := find_entry(table.entries, table.capacity, key)
    is_new_key := entry.key == nil
    if is_new_key && IS_NIL(entry.value) do table.count += 1
    
    entry.key = key
    entry.value = value
    return is_new_key
}

table_delete :: proc(table: ^Table, key: ^ObjString) -> bool {
    if table.count == 0 do return false
    
    entry := find_entry(table.entries, table.capacity, key)
    if entry.key == nil do return false
    
    // Tombstone
    entry.key = nil
    entry.value = BOOL_VAL(true)
    return true
}

table_add_all :: proc(from: ^Table, to: ^Table) {
    for i in 0..<from.capacity {
        if entry := &from.entries[i]; entry.key != nil {
            table_set(to, entry.key, entry.value)
        }
    }
}

table_find_string :: proc(table: ^Table, str: string, hash: u32) -> ^ObjString {
    if table.count == 0 do return nil 

    index := hash & u32(table.capacity - 1)
    for {
        entry := &table.entries[index]
        if entry.key == nil {
            if IS_NIL(entry.value) do return nil
        } else if len(entry.key.str) == len(str) && entry.key.hash == hash && strings.compare(entry.key.str, str) == 0 {
            return entry.key
        }

        index = (index + 1) & u32(table.capacity - 1)
    }
}

table_remove_white :: proc(table: ^Table) {
    for i in 0..<table.capacity {
        entry := table.entries[i]
        if entry.key != nil && !entry.key.is_marked {
            table_delete(table, entry.key)
        }  
    }
}

mark_table :: proc (table: ^Table) {
    for i in 0..<table.capacity {
        entry := &table.entries[i]
        mark_object(entry.key)
        mark_value(entry.value)
    }
}

@(private = "file", require_results)
find_entry :: proc "contextless" (entries: []Entry, capacity: int, key: ^ObjString) -> ^Entry {
    index := key.hash & u32(capacity - 1)
    tombstone: ^Entry = nil

    for {
        entry := &entries[index]

        if entry.key == nil {
            if IS_NIL(entry.value) {
                return tombstone if tombstone != nil else entry
            } else {
                if tombstone == nil do tombstone = entry
            }
        } else if entry.key == key {
            return entry
        }

        index = (index + 1) & u32(capacity - 1)
    }
}

table_get :: proc "contextless" (table: ^Table, key: ^ObjString) -> (Value, bool) {
    // No need to check if key is nil
    if table.count == 0 do return {}, false

    entry := find_entry(table.entries, table.capacity, key)
    if entry.key == nil do return {}, false
    
    return entry.value, true
}

adjust_capacity :: proc(table: ^Table, capacity: int) {
    entries := make([]Entry, capacity)
    for i in 0..<capacity {
        entries[i].key = nil
        entries[i].value = NIL_VAL
    }
    
    table.count = 0
    for i in 0..<table.capacity {
        entry := &table.entries[i]
        if entry.key == nil do continue
        
        dest := find_entry(entries, capacity, entry.key)
        dest.key = entry.key
        dest.value = entry.value
        table.count += 1
    }
    
    delete(table.entries)
    table.entries = entries
    table.capacity = capacity
}

grow_capacity :: proc(capacity: int) -> int {
    return 8 if capacity < 8 else capacity * 2
}