package main

//import "core:log"
//import "core:fmt"
//import "core:os"
import "core:log"
import "core:unicode/utf8"
import "core:strconv"
import "core:strings"
import "core:fmt"

Parser :: struct {
    current: Token,
    previous: Token,
    hadError: bool,
    panic_mode: bool,
}

Precedence :: enum {
    NONE,
    ASSIGNMENT, // =
    OR, // or
    AND, // and
    EQUALITY, // == !=
    COMPARISON, // < > <= >=
    TERM, // + -
    FACTOR, // * /
    UNARY, // ! -
    CALL, // . ()
    PRIMARY,
}

ParseFn :: #type proc(can_assign: bool)

ParseRule :: struct {
    prefix: ParseFn,
    infix: ParseFn,
    precedence: Precedence
}

U8_MAX :: cast(int)max(u8)
U16_MAX :: cast(int)max(u16)

Local :: struct {
    name: Token,
    depth: int,
    is_captured: bool,
}

Upvalue :: struct {
    index: u8,
    is_local: bool
}

FunctionType :: enum {
    FUNCTION, SCRIPT
}

Compiler :: struct {
    enclosing: ^Compiler,
    function: ^ObjFunction,
    type: FunctionType,
    locals: [U8_MAX + 1]Local,
    local_count: int,
    upvalues: [U8_MAX]Upvalue,
    scope_depth: int,
}

parser: Parser
current: ^Compiler
compilingChunk: ^Chunk

current_chunk :: proc() -> ^Chunk {
    return &current.function.chunk
}

compile :: proc(source: string) -> ^ObjFunction {
    init_scanner(source)
    compiler: Compiler
    init_compiler(&compiler, .SCRIPT)

    parser.hadError = false
    parser.panic_mode = false

    advance()

    for !match(.EOF) {
        declaration()
    }

    consume(.EOF, "Expect end of expression.")
    function := end_compiler()
    return parser.hadError ? nil : function
}

mark_compiler_roots :: proc() {
    compiler := current
    for compiler != nil {
        mark_object(compiler.function)
        compiler = compiler.enclosing
    }
}

advance :: proc() {
    parser.previous = parser.current

    for {
        parser.current = scan_token()
        if parser.current.type != .ERROR {
            break
        }

        error_at_current(parser.current.value)
    }
}

error_at_current :: proc(message: string) {
    error_at(&parser.previous, message)
}

error :: proc(message: string, loc := #caller_location) {
    error_at(&parser.previous, message, loc)
}

error_at :: proc(token: ^Token, message: string, loc := #caller_location) {
    if parser.panic_mode  {
        return
    }
    parser.panic_mode = true

    str_builder := strings.builder_make()
    defer strings.builder_destroy(&str_builder)

    fmt.sbprintf(&str_builder, "[line %v] Error", token.line)

    if token.type == .EOF do strings.write_string(&str_builder, " at end")
    else if token.type != .ERROR do fmt.sbprintf(&str_builder , " at '%v'", token.value)

    fmt.sbprintf(&str_builder, ": %v", message)

    log.error(strings.to_string(str_builder), location = loc)
    parser.hadError = true
}

consume :: proc(type: TokenType, message: string) {
    if parser.current.type == type {
        advance()
        return
    }

    error_at_current(message)
}

check :: proc(type: TokenType) -> bool {
    return parser.current.type == type
}

match :: proc(type: TokenType) -> bool {
    if !check(type) {
        return false
    }
    advance()
    return true
}

emit_byte_u8 :: proc(byte: u8) {
    write_chunk(current_chunk(), byte, parser.previous.line)
}

emit_byte_op_code :: proc(code: OpCode) {
    emit_byte(cast(u8)code)
}

emit_byte :: proc {
    emit_byte_u8,
    emit_byte_op_code
}

emit_bytes_u8 :: proc(byte1: OpCode, byte2: u8) {
    emit_byte(byte1)
    emit_byte(byte2)
}

emit_bytes_op_code :: proc(code1, code2: OpCode) {
    emit_byte(code1)
    emit_byte(code2)
}

emit_bytes :: proc {
    emit_bytes_u8,
    emit_bytes_op_code
}

emit_loop :: proc(loop_start: int) {
    emit_byte(OpCode.LOOP)

    offset := len(current_chunk().code) - loop_start + 2
    if offset > U16_MAX do error("Loop body too large.")

    emit_byte(u8((offset >> 8) & 0xff))
    emit_byte(u8(offset & 0xff))
}

emit_jump :: proc(instruction: OpCode) -> int {
    emit_byte(instruction)
    emit_byte(0xff)
    emit_byte(0xff)
    return len(current_chunk().code) - 2
}

end_compiler :: proc() -> ^ObjFunction {
    emit_return()
    function := current.function
    
    when DEBUG_PRINT_CODE {
        if !parser.hadError {
            disassemble_chunk(current_chunk(), function.name != nil ? function.name.str : "<script>")
        }
    }
    
    current = current.enclosing
    return function
}

@(private = "file")
begin_scope :: proc() {
    current.scope_depth += 1
}

@(private = "file")
end_scope :: proc() {
    current.scope_depth -= 1

    for current.local_count > 0 && current.locals[current.local_count - 1].depth > current.scope_depth {
        if current.locals[current.local_count - 1].is_captured do emit_byte(OpCode.CLOSE_UPVALUE)
        else do emit_byte(OpCode.POP)
                
        current.local_count -= 1
    }
}

@(private = "file")
binary :: proc(can_assign: bool) {
    operator_type := parser.previous.type
    rule := get_rule(operator_type)
    parse_precedence(cast(Precedence)(cast(int)rule.precedence + 1))

    #partial switch operator_type {
    case .BANG_EQUAL: emit_bytes(OpCode.EQUAL, OpCode.NOT)
    case .EQUAL_EQUAL: emit_byte(OpCode.EQUAL)
    case .GREATER: emit_byte(OpCode.GREATER)
    case .GREATER_EQUAL: emit_bytes(OpCode.LESS, OpCode.NOT)
    case .LESS: emit_byte(OpCode.LESS)
    case .LESS_EQUAL: emit_bytes(OpCode.GREATER, OpCode.NOT)
    case .PLUS: emit_byte(OpCode.ADD)
    case .MINUS: emit_byte(OpCode.SUBTRACT)
    case .STAR: emit_byte(OpCode.MULTIPLY)
    case .SLASH: emit_byte(OpCode.DIVIDE)
    case: return
    }
}

@(private = "file")
call :: proc(can_assign: bool) {
    arg_count := argument_list()
    emit_bytes(.CALL, arg_count)
}

@(private = "file")
literal :: proc(can_assign: bool) {
    #partial switch parser.previous.type {
    case .FALSE: emit_byte(OpCode.FALSE)
    case .NIL: emit_byte(OpCode.NIL)
    case .TRUE: emit_byte(OpCode.TRUE)
    case: return // unreachable
    }
}

@(private = "file")
grouping :: proc(can_assign: bool) {
    expression()
    consume(TokenType.RIGHT_PAREN, "Expect ')' after expression.")
}

@(private = "file")
number :: proc(can_assign: bool) {
    value := strconv.atof(parser.previous.value)
    emit_constant(NUMBER_VAL(value))
}

@(private = "file")
or_ :: proc(can_assign: bool) {
    else_jump := emit_jump(.JUMP_IF_FALSE)
    end_jump := emit_jump(.JUMP)

    patch_jump(else_jump)
    emit_byte(OpCode.POP)

    parse_precedence(.OR)
    patch_jump(end_jump)
}

@(private = "file")
string_proc :: proc(can_assign: bool) {
    runes := parser.previous.value[1:len(parser.previous.value) - 1] // removes the "" from the string literal
    emit_constant(OBJ_VAL(copy_string(runes)))
}

@(private = "file")
named_variable :: proc(name: ^Token, can_assign: bool) {
    get_op, set_op: OpCode
    arg := resolve_local(current, name)
    if arg != -1 {
        get_op = .GET_LOCAL
        set_op = .SET_LOCAL
    } else if arg = resolve_upvalue(current, name); arg != - 1 {
        get_op = .GET_UPVALUE
        set_op = .SET_UPVALUE
    } else {
        arg = int(identifier_constant(name))
        get_op = .GET_GLOBAL
        set_op = .SET_GLOBAL
    }

    if can_assign && match(.EQUAL) {
        expression()
        emit_bytes(set_op, u8(arg))
    } else {
        emit_bytes(get_op, u8(arg))
    }
}

@(private = "file")
variable :: proc(can_assign: bool) {
    named_variable(&parser.previous, can_assign)
}

@(private = "file")
unary :: proc(can_assign: bool) {
    operator_type := parser.previous.type

    parse_precedence(.UNARY)

    #partial switch operator_type {
    case .BANG: emit_byte(OpCode.NOT)
    case .MINUS: emit_byte(OpCode.NEGATE)
    case: return
    }
}

@(rodata)
rules := []ParseRule {
    TokenType.LEFT_PAREN    = ParseRule{ grouping, call, .CALL },
    TokenType.RIGHT_PAREN   = ParseRule{ nil, nil, .NONE },
    TokenType.LEFT_BRACE    = ParseRule{ nil, nil, .NONE },
    TokenType.RIGHT_BRACE   = ParseRule{ nil, nil, .NONE },
    TokenType.COMMA         = ParseRule{ nil, nil, .NONE },
    TokenType.DOT           = ParseRule{ nil, nil, .NONE },
    TokenType.MINUS         = ParseRule{ unary, binary, .TERM },
    TokenType.PLUS          = ParseRule{ nil, binary, .TERM },
    TokenType.SEMICOLON     = ParseRule{ nil, nil, .NONE },
    TokenType.SLASH         = ParseRule{ nil, binary, .FACTOR },
    TokenType.STAR          = ParseRule{ nil, binary, .FACTOR },
    TokenType.BANG          = ParseRule{ unary, nil, .NONE },
    TokenType.BANG_EQUAL    = ParseRule{ nil, binary, .EQUALITY },
    TokenType.EQUAL         = ParseRule{ nil, nil, .NONE },
    TokenType.EQUAL_EQUAL   = ParseRule{ nil, binary, .EQUALITY },
    TokenType.GREATER       = ParseRule{ nil, binary, .COMPARISON },
    TokenType.GREATER_EQUAL = ParseRule{ nil, binary, .COMPARISON },
    TokenType.LESS          = ParseRule{ nil, binary, .COMPARISON },
    TokenType.LESS_EQUAL    = ParseRule{ nil, binary, .COMPARISON },
    TokenType.IDENTIFIER    = ParseRule{ variable, nil, .NONE },
    TokenType.STRING        = ParseRule{ string_proc, nil, .NONE },
    TokenType.NUMBER        = ParseRule{ number, nil, .NONE },
    TokenType.AND           = ParseRule{ nil, and_, .AND },
    TokenType.CLASS         = ParseRule{ nil, nil, .NONE },
    TokenType.ELSE          = ParseRule{ nil, nil, .NONE },
    TokenType.FALSE         = ParseRule{ literal, nil, .NONE },
    TokenType.FOR           = ParseRule{ nil, nil, .NONE },
    TokenType.FUN           = ParseRule{ nil, nil, .NONE },
    TokenType.IF            = ParseRule{ nil, nil, .NONE },
    TokenType.NIL           = ParseRule{ literal, nil, .NONE },
    TokenType.OR            = ParseRule{ nil, or_, .OR },
    TokenType.PRINT         = ParseRule{ nil, nil, .NONE },
    TokenType.RETURN        = ParseRule{ nil, nil, .NONE },
    TokenType.SUPER         = ParseRule{ nil, nil, .NONE },
    TokenType.THIS          = ParseRule{ nil, nil, .NONE },
    TokenType.TRUE          = ParseRule{ literal, nil, .NONE },
    TokenType.VAR           = ParseRule{ nil, nil, .NONE },
    TokenType.WHILE         = ParseRule{ nil, nil, .NONE },
    TokenType.ERROR         = ParseRule{ nil, nil, .NONE },
    TokenType.EOF           = ParseRule{ nil, nil, .NONE },
}

@(private = "file")
parse_precedence :: proc(precedence: Precedence) {
    advance()
    prefix_rule := get_rule(parser.previous.type).prefix
    if prefix_rule == nil {
        error("Expect expression.")
        return
    }

    can_assign := precedence <= .ASSIGNMENT
    prefix_rule(can_assign)

    for precedence <= get_rule(parser.current.type).precedence {
        advance()
        infix_rule := get_rule(parser.previous.type).infix
        infix_rule(can_assign)
    }

    if can_assign && match(.EQUAL) {
        error("Invalid assignment target.")
    }
}

@(private = "file")
identifier_constant :: proc(name: ^Token) -> u8 {
    return make_constant(OBJ_VAL(copy_string(name.value)))
}

@(private = "file")
identifiers_equal :: proc(a:  ^Token, b: ^Token) -> bool {
    if len(a.value) != len(b.value) do return false
    return strings.compare(a.value, b.value) == 0
}

@(private = "file")
resolve_local :: proc(compiler: ^Compiler, name: ^Token) -> int {
    for i := compiler.local_count - 1; i >= 0; i -= 1 {
        local := &compiler.locals[i]
        if identifiers_equal(name, &local.name) {
            if local.depth == -1 do error("Can't read local variable in its own initializer.")
            return i
        }
    }

    return -1
}

@(private = "file")
add_upvalue :: proc(compiler: ^Compiler, index: u8, is_local: bool) -> int {
    upvalue_count := compiler.function.upvalue_count
    
    for i in 0..<upvalue_count {
        upvalue := &compiler.upvalues[i]
        if upvalue.index == index && upvalue.is_local == is_local do return i
    }

    if upvalue_count == U8_MAX {
        error("Too many closure variables in function.")
        return 0
    }
    
    compiler.upvalues[upvalue_count].is_local = is_local
    compiler.upvalues[upvalue_count].index = index
    
    compiler.function.upvalue_count += 1
    return upvalue_count
}

@(private = "file")
resolve_upvalue :: proc(compiler: ^Compiler, name: ^Token) -> int {
    if compiler.enclosing == nil do return -1
    
    local := resolve_local(compiler.enclosing, name)
    if local != -1 {
        compiler.enclosing.locals[local].is_captured = true
        return add_upvalue(compiler, cast(u8)local, true)  
    } 
    
    if upvalue := resolve_upvalue(compiler.enclosing, name); upvalue != -1 {
        return add_upvalue(compiler, cast(u8)upvalue, false)
    }
    
    return -1
}

@(private = "file")
add_local :: proc(name: Token) {
    if current.local_count == U8_MAX + 1 {
        error("Too many local variables in function.")
        return
    }

    local := &current.locals[current.local_count]
    current.local_count += 1

    local.name = name
    local.depth = -1
}

@(private = "file")
declare_variable :: proc() {
    if current.scope_depth == 0 do return

    name := &parser.previous

    for i := current.local_count - 1; i >= 0; i -= 1 {
        local := &current.locals[i]
        if local.depth != -1 && local.depth < current.scope_depth do break

        if identifiers_equal(name, &local.name) do error("Already a variable with this name in this scope.")
    }

    add_local(name^)
}

@(private = "file")
parse_variable :: proc(error_message: string) -> u8 {
    consume(.IDENTIFIER, error_message)

    declare_variable()
    if current.scope_depth > 0 do return 0

    return identifier_constant(&parser.previous)
}

@(private = "file")
mark_initialized :: proc() {
    if current.scope_depth == 0 do return
    current.locals[current.local_count - 1].depth = current.scope_depth
}

@(private = "file")
define_variable :: proc(global: u8) {
    if current.scope_depth > 0 {
        mark_initialized()
        return
    }

    emit_bytes(.DEFINE_GLOBAL, global)
}

@(private = "file")
argument_list :: proc() -> u8 {
    arg_count := 0
    if !check(.RIGHT_PAREN) {
        for {
            expression()
            if arg_count == 255 do error("Can't have more than 255 arguments")
            arg_count += 1
            if !match(.COMMA) do break
        }
    }
    consume(.RIGHT_PAREN, "Expect ')' after arguments.")
    return cast(u8)arg_count
}

@(private = "file")
and_ :: proc(can_assign: bool) {
    end_jump := emit_jump(.JUMP_IF_FALSE)

    emit_byte(OpCode.POP)
    parse_precedence(.AND)

    patch_jump(end_jump)
}

get_rule :: proc(type: TokenType) -> ^ParseRule {
    return &rules[type]
}

emit_return :: proc() {
    emit_byte(OpCode.NIL)
    emit_byte(OpCode.RETURN)
}

@(private = "file")
make_constant :: proc(value: Value) -> u8 {
    constant := add_constant(current_chunk(), value)
    if constant > U8_MAX {
        error("Too many constants in one chunk.")
        return 0
    }

    return cast(u8)constant
}

@(private = "file")
emit_constant :: proc(value: Value) {
    emit_bytes(.CONSTANT, make_constant(value))
}

@(private = "file")
patch_jump :: proc(offset: int) {
// -2 to adjust for the bytecode for the jump offset itself.
    jump := len(current_chunk().code) - offset - 2

    if jump > U16_MAX do error("Too much code to jump over.")

    current_chunk().code[offset] = u8((jump >> 8) & 0xff)
    current_chunk().code[offset + 1] = u8(jump & 0xff)
}

init_compiler :: proc(compiler: ^Compiler, type: FunctionType) {
    compiler.enclosing = current
    compiler.function = nil
    compiler.type = type
    compiler.function = new_function()
    current = compiler
    
    if type != .SCRIPT do current.function.name = copy_string(parser.previous.value)
    
    local := &current.locals[current.local_count]
    current.local_count += 1
    local.depth = 0
    local.name.value = ""
}

@(private = "file")
expression :: proc() {
    parse_precedence(.ASSIGNMENT)
}

@(private = "file")
block :: proc() {
    for !check(.RIGHT_BRACE) && !check(.EOF) do declaration()

    consume(.RIGHT_BRACE, "Expect '}' after block.")
}

@(private = "file")
function :: proc(type: FunctionType) {
    compiler: Compiler
    init_compiler(&compiler, type)
    begin_scope()

    consume(.LEFT_PAREN, "Expect '(' after function name.")
    if !check(.RIGHT_PAREN) {
        for {
            current.function.arity += 1
            if current.function.arity > 255 {
                error_at_current("Can't have more than 255 parameters.")
            }
            
            constant := parse_variable("Expect parameter name.");
            define_variable(constant)
            if !match(.COMMA) do break
        }
    }
    
    
    
    consume(.RIGHT_PAREN, "Expect ')' after parameters.")
    consume(.LEFT_BRACE, "Expect '{' before function body.")
    block()
    
    function := end_compiler()
    emit_bytes(.CLOSURE, make_constant(OBJ_VAL(function)))
    
    for i in 0..<function.upvalue_count {
        emit_byte(compiler.upvalues[i].is_local ? 1 : 0)
        emit_byte(compiler.upvalues[i].index)
    }
}

@(private = "file")
fun_declaration :: proc() {
    global := parse_variable("Expect function name.")
    mark_initialized()
    function(.FUNCTION)
    define_variable(global)
}

@(private = "file")
var_declaration :: proc() {
    global := parse_variable("Expect variable name.")

    if match(.EQUAL) {
        expression()
    } else {
        emit_byte(OpCode.NIL)
    }

    consume(.SEMICOLON, "Expect ';' after variable declaration.")

    define_variable(global)
}

@(private = "file")
expression_statement :: proc() {
    expression()
    consume(.SEMICOLON, "Expect ';' after expression")
    emit_byte(OpCode.POP)
}

@(private = "file")
for_statement :: proc() {
    begin_scope()
    consume(.LEFT_PAREN, "Expect '(' after 'for'.")
    if (match(.SEMICOLON)) {
    // No initializer.
    } else if (match(.VAR)) {
        var_declaration()
    } else {
        expression_statement()
    }

    loop_start := len(current_chunk().code)
    exit_jump := -1
    if !match(.SEMICOLON) {
        expression()
        consume(.SEMICOLON, "Expect ';' after loop condition.")

        // Jump out of the loop if the condition is false.
        exit_jump = emit_jump(.JUMP_IF_FALSE)
        emit_byte(OpCode.POP) // Condition.
    }


    if !match(.RIGHT_PAREN) {
        body_jump := emit_jump(.JUMP)
        increment_start := len(current_chunk().code)
        expression()
        emit_byte(OpCode.POP)
        consume(.RIGHT_PAREN, "Expect ')' after for clauses.")

        emit_loop(loop_start)
        loop_start = increment_start
        patch_jump(body_jump)
    }

    statement()
    emit_loop(loop_start)

    if exit_jump != -1 {
        patch_jump(exit_jump)
        emit_byte(OpCode.POP)
    }

    end_scope()
}

@(private = "file")
if_statement :: proc() {
    consume(.LEFT_PAREN, "Expect '(' after 'if'.")
    expression()
    consume(.RIGHT_PAREN, "Expect ')' after condition.")

    then_jump := emit_jump(.JUMP_IF_FALSE)
    emit_byte(OpCode.POP)
    statement()

    else_jump := emit_jump(.JUMP)

    patch_jump(then_jump)
    emit_byte(OpCode.POP)

    if(match(.ELSE)) do statement()
    patch_jump(else_jump)
}

@(private = "file")
print_statement :: proc() {
    expression()
    consume(.SEMICOLON, "Expect ';' after value.")
    emit_byte(OpCode.PRINT)
}

@(private = "file")
return_statement :: proc() {
    if current.type == .SCRIPT do error("Can't return from top-level code.")
    
    if match(.SEMICOLON) do emit_return()
    else {
        expression()
        consume(.SEMICOLON, "Expect ';' after return value.")
        emit_byte(OpCode.RETURN)
    }
}

@(private = "file")
while_statement :: proc() {
    loop_start := len(current_chunk().code)
    consume(.LEFT_PAREN, "Expect '(' after 'while'.")
    expression()
    consume(.RIGHT_PAREN, "Expect ')' after condition.")

    exit_jump := emit_jump(.JUMP_IF_FALSE)
    emit_byte(OpCode.POP)
    statement()
    emit_loop(loop_start)

    patch_jump(exit_jump)
    emit_byte(OpCode.POP)
}

@(private = "file")
syncronize :: proc() {
    parser.panic_mode = false

    for parser.current.type != .EOF {
        if parser.previous.type == .SEMICOLON {
            return
        }
        #partial switch parser.current.type {
        case .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN:
            return
        case:
            return
        }
    }

    advance()
}

@(private = "file")
declaration :: proc() {
    if match(.FUN) {
      fun_declaration()  
    } else if match(.VAR) {
        var_declaration()
    } else {
        statement()
    }


    if parser.panic_mode do syncronize()
}

@(private = "file")
statement :: proc() {
    if match(.PRINT) {
        print_statement()
    } else if  match(.FOR) {
        for_statement()
    } else if  match(.IF) {
        if_statement()
    } else if  match(.RETURN) {
        return_statement()
    } else if  match(.WHILE) {
        while_statement()
    } else if  match(.LEFT_BRACE) {
        begin_scope()
        block()
        end_scope()
    } else {
        expression_statement()
    }
}