package main

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import "core:unicode/utf8/utf8string"

String :: utf8string.String

Scanner :: struct
{
    buffer: String,
    start: int,
    current: int,
    line: int,
}

Token :: struct {
    type: TokenType,
    value: []rune,
    line: int,
}

TokenType :: enum {
// Single-character tokens.
    LEFT_PAREN, RIGHT_PAREN,
    LEFT_BRACE, RIGHT_BRACE,
    COMMA, DOT, MINUS, PLUS,
    SEMICOLON, SLASH, STAR,

    // One or two character tokens.
    BANG, BANG_EQUAL,
    EQUAL, EQUAL_EQUAL,
    GREATER, GREATER_EQUAL,
    LESS, LESS_EQUAL,

    // Literals
    IDENTIFIER, STRING, NUMBER,

    // Keywords
    AND, CLASS, ELSE, FALSE,
    FOR, FUN, IF, NIL, OR,
    PRINT, RETURN, SUPER, THIS,
    TRUE, VAR, WHILE,

    ERROR, EOF,
}

scanner: Scanner

init_scanner :: proc(source: string) {
    utf8string.init(&scanner.buffer, source)
    scanner.start = 0
    scanner.current = 0
    scanner.line = 1
}

scan_token :: proc() -> Token {
    skip_whitespace()
    scanner.start = scanner.current
    
    if is_at_end() {
        return make_token(.EOF)
    }

    c := advance()
    if unicode.is_letter(c) { return identifier() }
    if unicode.is_digit(c) { return number_literal() }
    
    switch c {
    case '(': return make_token(.LEFT_PAREN)
    case ')': return make_token(.RIGHT_PAREN)
    case '{': return make_token(.LEFT_BRACE)
    case '}': return make_token(.RIGHT_BRACE)
    case ';': return make_token(.SEMICOLON)
    case ',': return make_token(.COMMA)
    case '.': return make_token(.DOT)
    case '-': return make_token(.MINUS)
    case '+': return make_token(.PLUS)
    case '/': return make_token(.SLASH)
    case '*': return make_token(.STAR)
    case '!': return make_token(.EQUAL_EQUAL if match('=') else .BANG)
    case '=': return make_token(.BANG_EQUAL if match('=') else .EQUAL)
    case '<': return make_token(.LESS_EQUAL if match('=') else .LESS)
    case '>': return make_token(.GREATER_EQUAL if match('=') else .GREATER)
    case '"': return string_literal()
    }

    return error_token("Unexpected character.")
}

@(private = "file")
advance :: proc() -> rune {
    scanner.current += 1
    return utf8string.at(&scanner.buffer, scanner.current - 1)
}

@private
match :: proc(expected: rune) -> bool {
    if is_at_end() { return false }
    if utf8string.at(&scanner.buffer, scanner.current) != expected { return false }
    scanner.current += 1
    return true
}

@private
is_at_end :: proc() -> bool {
    return scanner.current >= utf8string.len(&scanner.buffer)-1
}

@private
make_token :: proc(type: TokenType) -> Token {
    return Token {
        type = type,
        value = utf8.string_to_runes(utf8string.slice(&scanner.buffer, scanner.start, scanner.current)),
        line = scanner.line,
    }
}

@private
error_token :: proc(message: string) -> Token {
    return Token {
        type = .ERROR,
        value = utf8.string_to_runes(message),
        line = scanner.line,
    }
}

@private
skip_whitespace :: proc() {
    for {
        if is_at_end() { return }
        c := peek()
        switch c {
        case ' ', '\r', '\t': advance()
        case '\n': {
                scanner.line += 1
                advance()
        }
        case '/': {
            next_rune := peek_next()
            if next_rune != ' ' {
                if next_rune == '/' {
                    // A comment goes until the end of the line.
                    for peek() != '\n' && !is_at_end() { advance() }
                } else {
                    return
                }
            } else { return }
        }
        case: return
        }
    }
}

@private
peek :: proc() -> rune {
    return utf8string.at(&scanner.buffer, scanner.current)
}

@private
peek_next :: proc() -> rune {
    if is_at_end() { return ' ' }
    return utf8string.at(&scanner.buffer, scanner.current + 1)
}

@private
string_literal :: proc() -> Token {
    for peek() != '"' && !is_at_end() {
        if peek() == '\n' { scanner.line += 1 }
        advance()
    }

    if is_at_end() { return error_token("Unterminated string.") }
    
    // The closing quote
    advance()
    return make_token(.STRING)
}

@private
number_literal :: proc() -> Token {
    for unicode.is_digit(peek()) { advance() }
    
    // Look for a fractional part
    if peek() == '.' && unicode.is_digit(peek_next()) {
        advance()
        
        for unicode.is_digit(peek()) { advance() }
    }
    
    return make_token(.NUMBER)
}

@private
identifier :: proc() -> Token {
    for unicode.is_letter(peek()) || unicode.is_digit(peek()) {
        advance()
    }
    return make_token(identifier_type())
}

@private
identifier_type :: proc() -> TokenType {
    switch utf8string.at(&scanner.buffer, scanner.start) {
    case 'a': return check_keyword("and", .AND)
    case 'c': return check_keyword("class", .CLASS)
    case 'e': return check_keyword("else", .ELSE)
    case 'f': {
        if scanner.current - scanner.start > 1 {
            switch utf8string.at(&scanner.buffer, scanner.start + 1) {
            case 'a': return check_keyword("false", .FALSE)
            case 'o': return check_keyword("for", .FOR)
            case 'u': return check_keyword("fun", .FUN)
            }
        }
    }
    case 'i': return check_keyword("if", .IF)
    case 'n': return check_keyword("nil", .NIL)
    case 'o': return check_keyword("or", .OR)
    case 'p': return check_keyword("print", .PRINT)
    case 'r': return check_keyword("return", .RETURN)
    case 's': return check_keyword("super", .SUPER)
    case 't': {
        if scanner.current - scanner.start > 1 {
            switch utf8string.at(&scanner.buffer, scanner.start + 1) {
            case 'h': return check_keyword("this", .THIS)
            case 'r': return check_keyword("true", .TRUE)
            }
        }
    }
    case 'v': return check_keyword("var", .VAR)
    case 'w': return check_keyword("while", .WHILE)
    }
    return .IDENTIFIER

}

@private
check_keyword :: proc(keyword: string, type: TokenType) -> TokenType {
    slice := utf8string.slice(&scanner.buffer, scanner.start, scanner.start + len(keyword))
    if strings.compare(string(slice), keyword) == 0 {
        return type
    }

    return .IDENTIFIER
}