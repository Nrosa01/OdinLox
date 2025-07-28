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

Local :: struct {
    name: Token,
    depth: int,
}

Compiler :: struct {
    locals: [U8_MAX + 1]Local,
    local_count: int,
    scope_depth: int,
}

parser: Parser
current: ^Compiler
compilingChunk: ^Chunk

@(private = "file")
current_chunk :: proc() -> ^Chunk {
    return compilingChunk
}

compile :: proc(source: string, chunk: ^Chunk) -> bool {
    init_scanner(source)
    compiler: Compiler
    init_compiler(&compiler)
    compilingChunk = chunk

    parser.hadError = false
    parser.panic_mode = false

    advance()

    for !match(.EOF) {
        declaration()
    }

    end_compiler()
    return !parser.hadError
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

end_compiler :: proc() {
    emit_return()

    when DEBUG_PRINT_CODE {
        if !parser.hadError {
            disassemble_chunk(current_chunk(), "code")
        }
    }
}

@(private = "file")
begin_scope :: proc() {
    current.scope_depth += 1
}

@(private = "file")
end_scope :: proc() {
    current.scope_depth -= 1

    for current.local_count > 0 && current.locals[current.local_count - 1].depth > current.scope_depth {
        emit_byte(OpCode.POP)
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
    TokenType.LEFT_PAREN    = ParseRule{ grouping, nil, .NONE },
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
    TokenType.AND           = ParseRule{ nil, nil, .NONE },
    TokenType.CLASS         = ParseRule{ nil, nil, .NONE },
    TokenType.ELSE          = ParseRule{ nil, nil, .NONE },
    TokenType.FALSE         = ParseRule{ literal, nil, .NONE },
    TokenType.FOR           = ParseRule{ nil, nil, .NONE },
    TokenType.FUN           = ParseRule{ nil, nil, .NONE },
    TokenType.IF            = ParseRule{ nil, nil, .NONE },
    TokenType.NIL           = ParseRule{ literal, nil, .NONE },
    TokenType.OR            = ParseRule{ nil, nil, .NONE },
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

get_rule :: proc(type: TokenType) -> ^ParseRule {
    return &rules[type]
}

emit_return :: proc() {
    write_chunk(current_chunk(), OpCode.RETURN, parser.previous.line)
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

init_compiler :: proc(compiler: ^Compiler) {
    compiler.local_count = 0
    compiler.scope_depth = 0
    current = compiler
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
print_statement :: proc() {
    expression()
    consume(.SEMICOLON, "Expect ';' after value.")
    emit_byte(OpCode.PRINT)
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
    if match(.VAR) {
        var_declaration()
    } else {
        statement()
    }


    if parser.panic_mode {
        syncronize()
    }
}

@(private = "file")
statement :: proc() {
    if match(.PRINT) {
        print_statement()
    } else if  match(.LEFT_BRACE) {
        begin_scope()
        block()
        end_scope()
    } else {
        expression_statement()
    }
}