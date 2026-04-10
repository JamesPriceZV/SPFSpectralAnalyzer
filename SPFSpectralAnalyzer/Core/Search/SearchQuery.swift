import Foundation

// MARK: - Search Field Identifiers

/// Recognized field prefixes for qualified search terms.
enum SearchField: String, CaseIterable, Sendable {
    // Dataset-level fields
    case name
    case file        // alias for name
    case role
    case spf
    case date
    case spectra
    case memo
    case instrument
    case hash
    case path

    // Spectrum-level fields
    case tag
    case plate
    case irr
    case sample
}

// MARK: - Comparison Operators

/// Comparison operator for numeric and date fields.
enum ComparisonOp: Sendable {
    case equal
    case lessThan
    case greaterThan
    case lessOrEqual
    case greaterOrEqual
    case contains
}

// MARK: - Search Term

/// A single parsed search term: an optional field qualifier, an operator, and a value.
struct SearchTerm: Sendable {
    let field: SearchField?   // nil = search all text fields
    let op: ComparisonOp      // defaults to .contains for text
    let value: String         // lowercased raw value
    let isExactPhrase: Bool   // was this from a quoted string?
}

// MARK: - AST

/// Boolean expression tree for search queries.
indirect enum SearchExpression: Sendable {
    case term(SearchTerm)
    case and(SearchExpression, SearchExpression)
    case or(SearchExpression, SearchExpression)
    case not(SearchExpression)
}

// MARK: - SearchQuery

/// A parsed, ready-to-evaluate search query.
struct SearchQuery: Sendable {
    let expression: SearchExpression?
    let rawText: String

    /// True if the query is empty or whitespace-only.
    var isEmpty: Bool { expression == nil }

    /// Parse a search string into a SearchQuery.
    static func parse(_ text: String) -> SearchQuery {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchQuery(expression: nil, rawText: text) }
        let tokens = Tokenizer.tokenize(trimmed)
        guard !tokens.isEmpty else { return SearchQuery(expression: nil, rawText: text) }
        var parser = Parser(tokens: tokens)
        let expr = parser.parseOrExpr()
        return SearchQuery(expression: expr, rawText: text)
    }

    /// Evaluate this query against a searchable record.
    func matches(_ record: SearchableRecord) -> Bool {
        guard let expression else { return true }
        return Self.evaluate(expression, against: record)
    }

    // MARK: - Evaluation

    private static func evaluate(_ expr: SearchExpression, against record: SearchableRecord) -> Bool {
        switch expr {
        case .term(let term):
            return evaluateTerm(term, against: record)
        case .and(let lhs, let rhs):
            return evaluate(lhs, against: record) && evaluate(rhs, against: record)
        case .or(let lhs, let rhs):
            return evaluate(lhs, against: record) || evaluate(rhs, against: record)
        case .not(let inner):
            return !evaluate(inner, against: record)
        }
    }

    private static func evaluateTerm(_ term: SearchTerm, against record: SearchableRecord) -> Bool {
        // Unqualified term: search allText (always case insensitive)
        guard let field = term.field else {
            let text = record.allText
            return text.localizedCaseInsensitiveContains(term.value)
        }

        // Numeric comparison fields
        if term.op != .contains, let recordValue = record.numericValue(for: field) {
            guard let queryValue = Double(term.value) else { return false }
            return applyComparison(term.op, lhs: recordValue, rhs: queryValue)
        }

        // Date comparison fields
        if term.op != .contains, let recordDate = record.dateValue(for: field) {
            guard let queryDate = parseDate(term.value) else { return false }
            let recordDay = Calendar.current.startOfDay(for: recordDate)
            let queryDay = Calendar.current.startOfDay(for: queryDate)
            return applyDateComparison(term.op, lhs: recordDay, rhs: queryDay)
        }

        // Text fields: check values(for:)
        guard let values = record.values(for: field) else { return false }
        let queryLower = term.value.lowercased()

        // Numeric fields with .contains: try numeric comparison, else substring
        if let recordNum = record.numericValue(for: field), let queryNum = Double(term.value) {
            return recordNum == queryNum
        }

        for value in values {
            let valueLower = value.lowercased()
            if term.isExactPhrase {
                if valueLower == queryLower { return true }
            } else {
                // For role-like fields, allow prefix matching (e.g., "ref" matches "reference")
                if valueLower.contains(queryLower) { return true }
            }
        }
        return false
    }

    private static func applyComparison(_ op: ComparisonOp, lhs: Double, rhs: Double) -> Bool {
        switch op {
        case .equal:          return lhs == rhs
        case .lessThan:       return lhs < rhs
        case .greaterThan:    return lhs > rhs
        case .lessOrEqual:    return lhs <= rhs
        case .greaterOrEqual: return lhs >= rhs
        case .contains:       return lhs == rhs
        }
    }

    private static func applyDateComparison(_ op: ComparisonOp, lhs: Date, rhs: Date) -> Bool {
        switch op {
        case .equal:          return lhs == rhs
        case .lessThan:       return lhs < rhs
        case .greaterThan:    return lhs > rhs
        case .lessOrEqual:    return lhs <= rhs
        case .greaterOrEqual: return lhs >= rhs
        case .contains:       return lhs == rhs
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
    }
}

// MARK: - Tokenizer

private enum Token: Sendable {
    case word(String)
    case quoted(String)
    case colon
    case lparen
    case rparen
    case andOp
    case orOp
    case notOp
    case minus
    case comparison(ComparisonOp)
}

private enum Tokenizer {
    static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // Skip whitespace
            if c.isWhitespace {
                i += 1
                continue
            }

            // Quoted string
            if c == "\"" {
                i += 1
                var str = ""
                while i < chars.count && chars[i] != "\"" {
                    str.append(chars[i])
                    i += 1
                }
                if i < chars.count { i += 1 } // consume closing quote
                tokens.append(.quoted(str))
                continue
            }

            // Parentheses
            if c == "(" { tokens.append(.lparen); i += 1; continue }
            if c == ")" { tokens.append(.rparen); i += 1; continue }

            // Colon
            if c == ":" { tokens.append(.colon); i += 1; continue }

            // Comparison operators: >=, <=, >, <, =
            if c == ">" {
                if i + 1 < chars.count && chars[i + 1] == "=" {
                    tokens.append(.comparison(.greaterOrEqual)); i += 2
                } else {
                    tokens.append(.comparison(.greaterThan)); i += 1
                }
                continue
            }
            if c == "<" {
                if i + 1 < chars.count && chars[i + 1] == "=" {
                    tokens.append(.comparison(.lessOrEqual)); i += 2
                } else {
                    tokens.append(.comparison(.lessThan)); i += 1
                }
                continue
            }
            if c == "=" { tokens.append(.comparison(.equal)); i += 1; continue }

            // Minus (NOT shorthand) - only if at start or after whitespace
            if c == "-" {
                let prevIsSpace = (i == 0) || chars[i - 1].isWhitespace || chars[i - 1] == "("
                if prevIsSpace {
                    tokens.append(.minus); i += 1; continue
                }
            }

            // "!" as NOT shorthand (like "-")
            if c == "!" {
                let prevIsSpace = (i == 0) || chars[i - 1].isWhitespace || chars[i - 1] == "("
                if prevIsSpace {
                    tokens.append(.notOp); i += 1; continue
                }
            }

            // "&" / "&&" as AND operator
            if c == "&" {
                if i + 1 < chars.count && chars[i + 1] == "&" {
                    tokens.append(.andOp); i += 2
                } else {
                    tokens.append(.andOp); i += 1
                }
                continue
            }

            // "|" / "||" as OR operator
            if c == "|" {
                if i + 1 < chars.count && chars[i + 1] == "|" {
                    tokens.append(.orOp); i += 2
                } else {
                    tokens.append(.orOp); i += 1
                }
                continue
            }

            // Word (non-whitespace, non-special)
            var word = ""
            while i < chars.count && !chars[i].isWhitespace
                    && chars[i] != ":" && chars[i] != "(" && chars[i] != ")"
                    && chars[i] != "\"" && chars[i] != ">" && chars[i] != "<" && chars[i] != "="
                    && chars[i] != "&" && chars[i] != "|" && chars[i] != "!" {
                word.append(chars[i])
                i += 1
            }

            if !word.isEmpty {
                let upper = word.uppercased()
                if upper == "AND" { tokens.append(.andOp) }
                else if upper == "OR" { tokens.append(.orOp) }
                else if upper == "NOT" { tokens.append(.notOp) }
                else { tokens.append(.word(word)) }
            }
        }

        return tokens
    }
}

// MARK: - Parser (Recursive Descent)

/// Recursive descent parser for boolean search expressions.
///
/// Grammar:
///   or_expr   = and_expr ( "OR" and_expr )*
///   and_expr  = not_expr ( "AND"? not_expr )*
///   not_expr  = "NOT" atom | "-" atom | atom
///   atom      = field_filter | quoted_string | bare_word | "(" or_expr ")"
///   field_filter = word ":" (comparison? (word | quoted_string))
private struct Parser {
    let tokens: [Token]
    var pos: Int = 0

    var atEnd: Bool { pos >= tokens.count }

    mutating func peek() -> Token? {
        guard pos < tokens.count else { return nil }
        return tokens[pos]
    }

    mutating func advance() -> Token? {
        guard pos < tokens.count else { return nil }
        let t = tokens[pos]
        pos += 1
        return t
    }

    // MARK: - or_expr

    mutating func parseOrExpr() -> SearchExpression? {
        guard var lhs = parseAndExpr() else { return nil }
        while case .orOp = peek() ?? .lparen {
            _ = advance() // consume OR
            guard let rhs = parseAndExpr() else { break }
            lhs = .or(lhs, rhs)
        }
        return lhs
    }

    // MARK: - and_expr

    mutating func parseAndExpr() -> SearchExpression? {
        guard var lhs = parseNotExpr() else { return nil }
        while !atEnd {
            // Explicit AND
            if case .andOp = peek() ?? .lparen {
                _ = advance() // consume AND
                guard let rhs = parseNotExpr() else { break }
                lhs = .and(lhs, rhs)
                continue
            }
            // Implicit AND: next token is NOT an OR, not a closing paren, not end
            if let next = peek() {
                switch next {
                case .orOp, .rparen:
                    return lhs
                default:
                    break
                }
            } else {
                break
            }
            guard let rhs = parseNotExpr() else { break }
            lhs = .and(lhs, rhs)
        }
        return lhs
    }

    // MARK: - not_expr

    mutating func parseNotExpr() -> SearchExpression? {
        if case .notOp = peek() ?? .lparen {
            _ = advance() // consume NOT
            guard let inner = parseAtom() else { return nil }
            return .not(inner)
        }
        if case .minus = peek() ?? .lparen {
            _ = advance() // consume -
            guard let inner = parseAtom() else { return nil }
            return .not(inner)
        }
        return parseAtom()
    }

    // MARK: - atom

    mutating func parseAtom() -> SearchExpression? {
        guard let token = peek() else { return nil }

        switch token {
        case .lparen:
            _ = advance() // consume (
            let expr = parseOrExpr()
            // consume ) if present
            if case .rparen = peek() ?? .lparen {
                _ = advance()
            }
            return expr

        case .word(let word):
            _ = advance()
            // Check if this is a field:value pair
            if case .colon = peek() ?? .lparen {
                if let field = SearchField(rawValue: word.lowercased()) {
                    _ = advance() // consume :
                    return parseFieldValue(field: field)
                }
                // Unknown field name: treat "word:" as a bare term
                // Consume the colon and any value, concatenate as text
                _ = advance() // consume :
                let rest = consumeValueText()
                return .term(SearchTerm(field: nil, op: .contains, value: (word + ":" + rest).lowercased(), isExactPhrase: false))
            }
            return .term(SearchTerm(field: nil, op: .contains, value: word.lowercased(), isExactPhrase: false))

        case .quoted(let phrase):
            _ = advance()
            return .term(SearchTerm(field: nil, op: .contains, value: phrase.lowercased(), isExactPhrase: true))

        default:
            // Consume unexpected token to avoid infinite loop
            _ = advance()
            return nil
        }
    }

    // MARK: - Field Value Parsing

    mutating func parseFieldValue(field: SearchField) -> SearchExpression? {
        // Check for comparison operator
        if case .comparison(let op) = peek() ?? .lparen {
            _ = advance() // consume comparison
            let value = consumeValueText()
            guard !value.isEmpty else {
                return .term(SearchTerm(field: field, op: op, value: "", isExactPhrase: false))
            }
            return .term(SearchTerm(field: field, op: op, value: value.lowercased(), isExactPhrase: false))
        }

        // Quoted value
        if case .quoted(let phrase) = peek() ?? .lparen {
            _ = advance()
            return .term(SearchTerm(field: field, op: .contains, value: phrase.lowercased(), isExactPhrase: true))
        }

        // Bare word value
        let value = consumeValueText()
        if value.isEmpty {
            // Incomplete field filter like "role:" - treat as bare text
            return .term(SearchTerm(field: nil, op: .contains, value: (field.rawValue + ":").lowercased(), isExactPhrase: false))
        }
        return .term(SearchTerm(field: field, op: .contains, value: value.lowercased(), isExactPhrase: false))
    }

    /// Consume the next word token as a value string. Returns empty if no word available.
    mutating func consumeValueText() -> String {
        if case .word(let w) = peek() ?? .lparen {
            _ = advance()
            return w
        }
        return ""
    }
}
