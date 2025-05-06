package main

//import "core:log"
//import "core:fmt"
//import "core:os"
import "core:log"
import utf8 "core:unicode/utf8"
import strconv "core:strconv"

Parser :: struct {
    current: Token,
    previous: Token,
    hadError: bool,
    panicMode: bool,
}

Precedence :: enum {
    NONE,
    ASSIGNMENT,  // =
    OR,          // or
    AND,         // and
    EQUALITY,    // == !=
    COMPARISON,  // < > <= >=
    TERM,        // + -
    FACTOR,      // * /
    UNARY,       // ! -
    CALL,        // . ()
    PRIMARY,
}

ParseFn :: #type proc()

ParseRule :: struct {
    prefix: ParseFn,
    infix: ParseFn,
    precedence: Precedence
}

parser: Parser
compilingChunk: ^Chunk

@private
current_chunk :: proc() -> ^Chunk {
    return compilingChunk
}

compile :: proc(source: string, chunk: ^Chunk) -> bool {
    init_scanner(source)
    compilingChunk = chunk
    
    parser.hadError = false
    parser.panicMode = false
    
    advance()
    expression()
    consume(.EOF, "Expect end of expression")
    
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
        
        error_at_current(utf8.runes_to_string(parser.current.value))
    }
}

error_at_current :: proc(message: string) {
    error_at(&parser.previous, message)
}

error :: proc(message: string) {
    error_at(&parser.previous, message)
}

error_at :: proc(token: ^Token, message: string) {
    if parser.panicMode  { return }
    parser.panicMode = true
    log.errorf("[line %v] Error", token.line)
    
    if token.type == .EOF {
        log.errorf(" at end")
    } else if token.type != .ERROR {
        log.errorf(" at '%v'", token.value)
    }
    
    log.errorf(": %v\n", message)
    parser.hadError = true
}

consume :: proc(type: TokenType, message: string) {
    if parser.current.type == type {
        advance()
        return
    }
    
    error_at_current(message)
}

emit_byte :: proc(byte: u8) {
    write_chunk(current_chunk(), byte, parser.previous.line)
}

emit_bytes :: proc(byte1: u8, byte2: u8) {
    emit_byte(byte1)
    emit_byte(byte2)
}

end_compiler :: proc() {
    emit_return()
    
    when DEBUG_PRINT_CODE {
        if !parser.hadError {
            disassemble_chunk(current_chunk(), "code")
        }
    }
}

@private
binary :: proc() {
    operator_type := parser.previous.type
    rule := get_rule(operator_type)
    parse_precedence(cast(Precedence)(cast(int)rule.precedence + 1))
    
    #partial switch operator_type {
        case .PLUS: emit_byte(cast(u8)OpCode.ADD)
        case .MINUS: emit_byte(cast(u8)OpCode.SUBTRACT)
        case .STAR: emit_byte(cast(u8)OpCode.MULTIPLY)
        case .SLASH: emit_byte(cast(u8)OpCode.DIVIDE)
        case: return
    }
}

@private
grouping :: proc() {
    expression()
    consume(TokenType.RIGHT_PAREN, "Expect ')' after expression.")
}

@private
number :: proc() {
    value := strconv.atof(utf8.runes_to_string(parser.previous.value))
    emit_constant(value)
}

@private
unary :: proc() {
    operator_type := parser.previous.type
    
    parse_precedence(.UNARY)
    
    #partial switch operator_type {
        case .MINUS:
            emit_byte(cast(u8)OpCode.NEGATE)
        case: return
    }
}

@(rodata)
rules := []ParseRule {
    TokenType.LEFT_PAREN    = ParseRule{ grouping, nil,    .NONE },
    TokenType.RIGHT_PAREN   = ParseRule{ nil,      nil,    .NONE },
    TokenType.LEFT_BRACE    = ParseRule{ nil,      nil,    .NONE },
    TokenType.RIGHT_BRACE   = ParseRule{ nil,      nil,    .NONE },
    TokenType.COMMA         = ParseRule{ nil,      nil,    .NONE },
    TokenType.DOT           = ParseRule{ nil,      nil,    .NONE },
    TokenType.MINUS         = ParseRule{ unary,    binary, .TERM },
    TokenType.PLUS          = ParseRule{ nil,      binary, .TERM },
    TokenType.SEMICOLON     = ParseRule{ nil,      nil,    .NONE },
    TokenType.SLASH         = ParseRule{ nil,      binary, .FACTOR },
    TokenType.STAR          = ParseRule{ nil,      binary, .FACTOR },
    TokenType.BANG          = ParseRule{ nil,      nil,    .NONE },
    TokenType.BANG_EQUAL    = ParseRule{ nil,      nil,    .NONE },
    TokenType.EQUAL         = ParseRule{ nil,      nil,    .NONE },
    TokenType.EQUAL_EQUAL   = ParseRule{ nil,      nil,    .NONE },
    TokenType.GREATER       = ParseRule{ nil,      nil,    .NONE },
    TokenType.GREATER_EQUAL = ParseRule{ nil,      nil,    .NONE },
    TokenType.LESS          = ParseRule{ nil,      nil,    .NONE },
    TokenType.LESS_EQUAL    = ParseRule{ nil,      nil,    .NONE },
    TokenType.IDENTIFIER    = ParseRule{ nil,      nil,    .NONE },
    TokenType.STRING        = ParseRule{ nil,      nil,    .NONE },
    TokenType.NUMBER        = ParseRule{ number,      nil,    .NONE },
    TokenType.AND           = ParseRule{ nil,      nil,    .NONE },
    TokenType.CLASS         = ParseRule{ nil,      nil,    .NONE },
    TokenType.ELSE          = ParseRule{ nil,      nil,    .NONE },
    TokenType.FALSE         = ParseRule{ nil,      nil,    .NONE },
    TokenType.FOR           = ParseRule{ nil,      nil,    .NONE },
    TokenType.FUN           = ParseRule{ nil,      nil,    .NONE },
    TokenType.IF            = ParseRule{ nil,      nil,    .NONE },
    TokenType.NIL           = ParseRule{ nil,      nil,    .NONE },
    TokenType.OR            = ParseRule{ nil,      nil,    .NONE },
    TokenType.PRINT         = ParseRule{ nil,      nil,    .NONE },
    TokenType.RETURN        = ParseRule{ nil,      nil,    .NONE },
    TokenType.SUPER         = ParseRule{ nil,      nil,    .NONE },
    TokenType.THIS          = ParseRule{ nil,      nil,    .NONE },
    TokenType.TRUE          = ParseRule{ nil,      nil,    .NONE },
    TokenType.VAR           = ParseRule{ nil,      nil,    .NONE },
    TokenType.WHILE         = ParseRule{ nil,      nil,    .NONE },
    TokenType.ERROR         = ParseRule{ nil,      nil,    .NONE },
    TokenType.EOF           = ParseRule{ nil,      nil,    .NONE },
}

@private
parse_precedence :: proc(precedence: Precedence) {
    advance()
    
    prefix_rule := get_rule(parser.previous.type).prefix
    if prefix_rule == nil {
        error("Expect expression.")
        return
    }
    
    prefix_rule()
    
    for precedence <= get_rule(parser.current.type).precedence {
        advance()
        infix_rule := get_rule(parser.previous.type).infix
        infix_rule()
    }
}

get_rule :: proc(type: TokenType) -> ^ParseRule {
    return &rules[type]
}

emit_return :: proc() {
    write_chunk(current_chunk(), OpCode.RETURN, parser.previous.line)
}

U8_MAX :: cast(int)max(u8)

@private
make_constant :: proc(value: Value) -> u8 {
    constant := add_constant(current_chunk(), value)
    if constant > U8_MAX {
        error("Too many constants in one chunk.")
        return 0
    }
    
    return cast(u8)constant
}

@private
emit_constant :: proc(value: Value) {
    emit_bytes(cast(u8)OpCode.CONSTANT, make_constant(value))
}

@private
expression :: proc() {
    parse_precedence(.ASSIGNMENT)
}