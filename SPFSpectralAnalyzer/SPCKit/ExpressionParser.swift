// ExpressionParser.swift
// SPCKit
//
// Lightweight recursive-descent parser for user-supplied transform expressions.
// Supports: +, -, *, /, ^ (power), unary minus, parentheses,
//           variables x and y, numeric literals, and common math functions.
// No external dependencies.
//
// Usage:
//   let compiled = try ExpressionParser.compile("y * 2.5 + sin(x)")
//   let result   = try compiled.evaluate(x: 1024.0, y: 0.85)

@preconcurrency import Foundation

// MARK: - Public API

nonisolated public struct CompiledExpression: Sendable {
    /// The original source string, stored for audit log display.
    public let source: String
    fileprivate let root: ExprNode

public func evaluate(x: Double, y: Double) throws -> Double {
        try root.evaluate(x: x, y: y)
    }
}

nonisolated public enum ExpressionParser {
    /// Parses the expression string and returns a compiled, reusable evaluator.
    /// Throws `TransformError.expressionParseError` on syntax errors.
public static func compile(_ source: String) throws -> CompiledExpression {
        var lexer  = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let root   = try parser.parse()
        return CompiledExpression(source: source, root: root)
    }
}

// MARK: - AST nodes

nonisolated indirect enum ExprNode: Sendable {
    case number(Double)
    case variable(String)              // "x" or "y"
    case unaryMinus(ExprNode)
    case binaryOp(Character, ExprNode, ExprNode)
    case call(String, ExprNode)        // sin(x), cos(x), abs(y), sqrt(x), log(y), exp(x)

func evaluate(x: Double, y: Double) throws -> Double {
        switch self {
        case let .number(v):
            return v
        case let .variable(name):
            switch name {
            case "x": return x
            case "y": return y
            case "pi": return Double.pi
            case "e":  return M_E
            default: throw TransformError.expressionEvaluationError("Unknown variable '\(name)'")
            }
        case let .unaryMinus(n):
            return try -n.evaluate(x: x, y: y)
        case let .binaryOp(op, lhs, rhs):
            let l = try lhs.evaluate(x: x, y: y)
            let r = try rhs.evaluate(x: x, y: y)
            switch op {
            case "+": return l + r
            case "-": return l - r
            case "*": return l * r
            case "/":
                guard r != 0 else {
                    throw TransformError.expressionEvaluationError("Division by zero")
                }
                return l / r
            case "^": return pow(l, r)
            default:  throw TransformError.expressionEvaluationError("Unknown operator '\(op)'")
            }
        case let .call(fn, arg):
            let v = try arg.evaluate(x: x, y: y)
            switch fn {
            case "sin":   return sin(v)
            case "cos":   return cos(v)
            case "tan":   return tan(v)
            case "asin":  return asin(v)
            case "acos":  return acos(v)
            case "atan":  return atan(v)
            case "sqrt":
                guard v >= 0 else {
                    throw TransformError.expressionEvaluationError("sqrt of negative number")
                }
                return sqrt(v)
            case "abs":   return abs(v)
            case "log":
                guard v > 0 else {
                    throw TransformError.expressionEvaluationError("log of non-positive number")
                }
                return log10(v)
            case "ln":
                guard v > 0 else {
                    throw TransformError.expressionEvaluationError("ln of non-positive number")
                }
                return log(v)
            case "exp":   return exp(v)
            case "floor": return floor(v)
            case "ceil":  return ceil(v)
            case "round": return v.rounded()
            default:
                throw TransformError.expressionEvaluationError("Unknown function '\(fn)'")
            }
        }
    }
}

// MARK: - Lexer

nonisolated private enum Token: Sendable {
    case number(Double)
    case ident(String)
    case op(Character)
    case lparen, rparen
    case eof
}

nonisolated private struct Lexer {
    let source: [Character]
    var pos: Int = 0

init(source: String) {
        self.source = Array(source)
    }

mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        while pos < source.count {
            let ch = source[pos]
            if ch.isWhitespace { pos += 1; continue }
            if ch.isNumber || ch == "." {
                tokens.append(try readNumber())
                continue
            }
            if ch.isLetter || ch == "_" {
                tokens.append(readIdent())
                continue
            }
            switch ch {
            case "+", "-", "*", "/", "^":
                tokens.append(.op(ch)); pos += 1
            case "(":
                tokens.append(.lparen); pos += 1
            case ")":
                tokens.append(.rparen); pos += 1
            default:
                throw TransformError.expressionParseError("Unexpected character '\(ch)'")
            }
        }
        tokens.append(.eof)
        return tokens
    }

private mutating func readNumber() throws -> Token {
        var s = ""
        while pos < source.count && (source[pos].isNumber || source[pos] == "." || source[pos] == "e" || source[pos] == "E") {
            s.append(source[pos]); pos += 1
            // handle exponent sign: 1e-5
            if (source[pos - 1] == "e" || source[pos - 1] == "E") && pos < source.count
               && (source[pos] == "+" || source[pos] == "-") {
                s.append(source[pos]); pos += 1
            }
        }
        guard let v = Double(s) else {
            throw TransformError.expressionParseError("Invalid number literal '\(s)'")
        }
        return .number(v)
    }

private mutating func readIdent() -> Token {
        var s = ""
        while pos < source.count && (source[pos].isLetter || source[pos].isNumber || source[pos] == "_") {
            s.append(source[pos]); pos += 1
        }
        return .ident(s)
    }
}

// MARK: - Recursive-descent parser

// Grammar (precedence climbing):
//   expr   → term (('+' | '-') term)*
//   term   → factor (('*' | '/') factor)*
//   factor → base ('^' factor)?
//   base   → '-' base | '(' expr ')' | ident '(' expr ')' | ident | number

nonisolated private struct Parser {
    let tokens: [Token]
    var pos: Int = 0

var current: Token { tokens[pos] }

mutating func parse() throws -> ExprNode {
        let node = try parseExpr()
        guard case .eof = current else {
            throw TransformError.expressionParseError("Unexpected token after expression")
        }
        return node
    }

    // expr → term (('+' | '-') term)*
private mutating func parseExpr() throws -> ExprNode {
        var node = try parseTerm()
        while true {
            if case let .op(op) = current, op == "+" || op == "-" {
                pos += 1
                let rhs = try parseTerm()
                node = .binaryOp(op, node, rhs)
            } else { break }
        }
        return node
    }

    // term → factor (('*' | '/') factor)*
private mutating func parseTerm() throws -> ExprNode {
        var node = try parseFactor()
        while true {
            if case let .op(op) = current, op == "*" || op == "/" {
                pos += 1
                let rhs = try parseFactor()
                node = .binaryOp(op, node, rhs)
            } else { break }
        }
        return node
    }

    // factor → base ('^' factor)?   (right-associative)
private mutating func parseFactor() throws -> ExprNode {
        let node = try parseBase()
        if case let .op(op) = current, op == "^" {
            pos += 1
            let exp = try parseFactor()
            return .binaryOp(op, node, exp)
        }
        return node
    }

    // base → '-' base | '(' expr ')' | ident '(' expr ')' | ident | number
private mutating func parseBase() throws -> ExprNode {
        switch current {
        case let .number(v):
            pos += 1
            return .number(v)

        case let .ident(name):
            pos += 1
            // Function call?
            if case .lparen = current {
                pos += 1
                let arg = try parseExpr()
                guard case .rparen = current else {
                    throw TransformError.expressionParseError("Expected ')' after function argument")
                }
                pos += 1
                return .call(name, arg)
            }
            return .variable(name)

        case .lparen:
            pos += 1
            let node = try parseExpr()
            guard case .rparen = current else {
                throw TransformError.expressionParseError("Expected ')'")
            }
            pos += 1
            return node

        case let .op(op) where op == "-":
            pos += 1
            return .unaryMinus(try parseBase())

        default:
            throw TransformError.expressionParseError("Unexpected token in expression")
        }
    }
}
