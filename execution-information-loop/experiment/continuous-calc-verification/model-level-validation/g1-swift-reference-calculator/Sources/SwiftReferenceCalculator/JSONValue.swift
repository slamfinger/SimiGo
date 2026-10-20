import Foundation

/// Minimal strict JSON value used by the reference calculator.
///
/// Hand-rolled on purpose: the contract fixes a byte-exact canonical form
/// (sorted keys by Unicode scalar, compact separators, UTF-8 without escapes),
/// and Foundation's serializer does not guarantee that form.
public enum JSONValue: Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int64)
    case boolean(Bool)
    case null
    /// A number literal that is not a signed 64-bit integer (fraction, exponent,
    /// or out of range). Kept verbatim so the contract layer can reject it with a
    /// stable code instead of failing the whole request.
    case numericLiteral(String)
}

public struct JSONParseError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public struct JSONParser {
    private let bytes: [UInt8]
    private var index: Int = 0

    private init(_ text: String) {
        self.bytes = Array(text.utf8)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(text)
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else {
            throw JSONParseError("trailing bytes at offset \(parser.index)")
        }
        return value
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            default:
                return
            }
        }
    }

    private mutating func expect(_ literal: String) throws {
        let expected = Array(literal.utf8)
        guard index + expected.count <= bytes.count else {
            throw JSONParseError("truncated literal at offset \(index)")
        }
        for offset in 0..<expected.count where bytes[index + offset] != expected[offset] {
            throw JSONParseError("invalid literal at offset \(index)")
        }
        index += expected.count
    }

    private mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard index < bytes.count else {
            throw JSONParseError("unexpected end of input")
        }
        switch bytes[index] {
        case 0x7B:
            return try parseObject()
        case 0x5B:
            return try parseArray()
        case 0x22:
            return .string(try parseString())
        case 0x74:
            try expect("true")
            return .boolean(true)
        case 0x66:
            try expect("false")
            return .boolean(false)
        case 0x6E:
            try expect("null")
            return .null
        case 0x2D:
            return try parseNumber()
        default:
            if isDigit(bytes[index]) {
                return try parseNumber()
            }
            throw JSONParseError("unexpected byte at offset \(index)")
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        index += 1
        var result: [String: JSONValue] = [:]
        skipWhitespace()
        if index < bytes.count, bytes[index] == 0x7D {
            index += 1
            return .object(result)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw JSONParseError("object key must be a string at offset \(index)")
            }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x3A else {
                throw JSONParseError("missing ':' at offset \(index)")
            }
            index += 1
            let value = try parseValue()
            guard result[key] == nil else {
                throw JSONParseError("duplicate object key \(key)")
            }
            result[key] = value
            skipWhitespace()
            guard index < bytes.count else {
                throw JSONParseError("unterminated object")
            }
            if bytes[index] == 0x2C {
                index += 1
                continue
            }
            if bytes[index] == 0x7D {
                index += 1
                return .object(result)
            }
            throw JSONParseError("expected ',' or '}' at offset \(index)")
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        index += 1
        var result: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == 0x5D {
            index += 1
            return .array(result)
        }
        while true {
            result.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else {
                throw JSONParseError("unterminated array")
            }
            if bytes[index] == 0x2C {
                index += 1
                continue
            }
            if bytes[index] == 0x5D {
                index += 1
                return .array(result)
            }
            throw JSONParseError("expected ',' or ']' at offset \(index)")
        }
    }

    private mutating func parseString() throws -> String {
        guard index < bytes.count, bytes[index] == 0x22 else {
            throw JSONParseError("expected string at offset \(index)")
        }
        index += 1
        var output = String()
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22 {
                index += 1
                return output
            }
            if byte == 0x5C {
                index += 1
                guard index < bytes.count else {
                    throw JSONParseError("truncated escape")
                }
                switch bytes[index] {
                case 0x22: output.append("\""); index += 1
                case 0x5C: output.append("\\"); index += 1
                case 0x2F: output.append("/"); index += 1
                case 0x62: output.append("\u{08}"); index += 1
                case 0x66: output.append("\u{0C}"); index += 1
                case 0x6E: output.append("\n"); index += 1
                case 0x72: output.append("\r"); index += 1
                case 0x74: output.append("\t"); index += 1
                case 0x75:
                    index += 1
                    let unit = try parseHex4()
                    var scalarValue = UInt32(unit)
                    if unit >= 0xD800 && unit <= 0xDBFF {
                        guard index + 1 < bytes.count, bytes[index] == 0x5C, bytes[index + 1] == 0x75 else {
                            throw JSONParseError("high surrogate without low surrogate")
                        }
                        index += 2
                        let low = try parseHex4()
                        guard low >= 0xDC00 && low <= 0xDFFF else {
                            throw JSONParseError("invalid low surrogate")
                        }
                        scalarValue = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
                    } else if unit >= 0xDC00 && unit <= 0xDFFF {
                        throw JSONParseError("lone low surrogate")
                    }
                    guard let scalar = UnicodeScalar(scalarValue) else {
                        throw JSONParseError("invalid unicode scalar")
                    }
                    output.append(Character(scalar))
                default:
                    throw JSONParseError("unsupported escape at offset \(index)")
                }
                continue
            }
            if byte < 0x20 {
                throw JSONParseError("unescaped control character at offset \(index)")
            }
            let start = index
            while index < bytes.count {
                let current = bytes[index]
                if current == 0x22 || current == 0x5C || current < 0x20 { break }
                index += 1
            }
            output.append(String(decoding: bytes[start..<index], as: UTF8.self))
        }
        throw JSONParseError("unterminated string")
    }

    private mutating func parseHex4() throws -> UInt16 {
        guard index + 4 <= bytes.count else {
            throw JSONParseError("truncated \\u escape")
        }
        var value: UInt16 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt16
            switch byte {
            case 0x30...0x39: digit = UInt16(byte - 0x30)
            case 0x41...0x46: digit = UInt16(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt16(byte - 0x61 + 10)
            default: throw JSONParseError("invalid hex digit")
            }
            value = value * 16 + digit
            index += 1
        }
        return value
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        if bytes[index] == 0x2D { index += 1 }
        guard index < bytes.count else {
            throw JSONParseError("truncated number")
        }
        if bytes[index] == 0x30 {
            index += 1
        } else if bytes[index] >= 0x31 && bytes[index] <= 0x39 {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        } else {
            throw JSONParseError("invalid number at offset \(index)")
        }
        var isInteger = true
        if index < bytes.count, bytes[index] == 0x2E {
            isInteger = false
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw JSONParseError("missing fraction digits")
            }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            isInteger = false
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw JSONParseError("missing exponent digits")
            }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        let raw = String(decoding: bytes[start..<index], as: UTF8.self)
        if isInteger, let value = Int64(raw) {
            return .integer(value)
        }
        return .numericLiteral(raw)
    }
}

public struct CanonicalJSONError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public enum CanonicalJSON {
    public static func encode(_ value: JSONValue) throws -> String {
        var output = String()
        try write(value, into: &output)
        return output
    }

    public static func bytes(_ value: JSONValue) throws -> [UInt8] {
        Array(try encode(value).utf8)
    }

    /// Key order is Unicode scalar order, matching Python's `sort_keys=True`.
    public static func scalarLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.unicodeScalars).map { $0.value }
        let right = Array(rhs.unicodeScalars).map { $0.value }
        for offset in 0..<min(left.count, right.count) where left[offset] != right[offset] {
            return left[offset] < right[offset]
        }
        return left.count < right.count
    }

    private static func write(_ value: JSONValue, into output: inout String) throws {
        switch value {
        case .object(let object):
            output.append("{")
            let keys = object.keys.sorted(by: scalarLess)
            for (offset, key) in keys.enumerated() {
                if offset > 0 { output.append(",") }
                writeString(key, into: &output)
                output.append(":")
                guard let member = object[key] else {
                    throw CanonicalJSONError("object lost key \(key)")
                }
                try write(member, into: &output)
            }
            output.append("}")
        case .array(let array):
            output.append("[")
            for (offset, element) in array.enumerated() {
                if offset > 0 { output.append(",") }
                try write(element, into: &output)
            }
            output.append("]")
        case .string(let text):
            writeString(text, into: &output)
        case .integer(let number):
            output.append(String(number))
        case .boolean(let flag):
            output.append(flag ? "true" : "false")
        case .null:
            output.append("null")
        case .numericLiteral(let raw):
            throw CanonicalJSONError("non-integer number \(raw) is outside the contract's JSON domain")
        }
    }

    private static func writeString(_ text: String, into output: inout String) {
        output.append("\"")
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: output.append("\\\"")
            case 0x5C: output.append("\\\\")
            case 0x08: output.append("\\b")
            case 0x0C: output.append("\\f")
            case 0x0A: output.append("\\n")
            case 0x0D: output.append("\\r")
            case 0x09: output.append("\\t")
            default:
                if scalar.value < 0x20 {
                    output.append(String(format: "\\u%04x", scalar.value))
                } else {
                    output.append(Character(scalar))
                }
            }
        }
        output.append("\"")
    }
}
