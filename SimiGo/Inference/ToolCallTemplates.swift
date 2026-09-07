import Foundation
import MLXLMCommon

/// Defines a strategy for detecting and parsing tool calls from a raw text stream.
/// nonisolated: Inference decode streams are consumed in non-main-actor contexts.
public nonisolated protocol ToolCallTemplate: Sendable {
    var name: String { get }
    
    /// The minimum number of characters we must hold back to ensure an opening tag can be fully recognized.
    var maxOpenHoldback: Int { get }
    
    /// Scans the buffer for the start of a tool call. 
    /// Returns the range of the opening tag if found.
    func findOpenTag(in buffer: String) -> Range<String.Index>?
    
    /// Scans the buffer for the end of a tool call. 
    /// Returns the range of the closing tag if found.
    func findCloseTag(in buffer: String) -> Range<String.Index>?
    
    /// Parses the content from the start of the open tag to the end of the close tag.
    /// - Parameters:
    ///   - fullText: The text starting from the beginning of the detected open tag.
    ///   - openTagRange: The range of the opening tag within `fullText`.
    ///   - closeTagRange: The range of the closing tag within `fullText`, or nil if unclosed.
    func parse(fullText: String, openTagRange: Range<String.Index>, closeTagRange: Range<String.Index>?) -> ParsedToolCall?
}

// MARK: - XML Implementation

public struct XMLToolCallTemplate: ToolCallTemplate {
    public let name = "XML (<tool_call>)"
    private static let openTag = "<tool_call>"
    private static let closeTag = "</tool_call>"
    
    public var maxOpenHoldback: Int { Self.openTag.count - 1 }
    public var maxCloseHoldback: Int { Self.closeTag.count - 1 }

    public func findOpenTag(in buffer: String) -> Range<String.Index>? {
        buffer.range(of: Self.openTag)
    }

    public func findCloseTag(in buffer: String) -> Range<String.Index>? {
        buffer.range(of: Self.closeTag)
    }

    public func parse(fullText: String, openTagRange: Range<String.Index>, closeTagRange: Range<String.Index>?) -> ParsedToolCall? {
        let contentStart = openTagRange.upperBound
        let contentEnd = closeTagRange?.lowerBound ?? fullText.endIndex
        let body = String(fullText[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let rawName = dictionary["name"] as? String else {
            return nil
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, dictionary.keys.contains("arguments") else { return nil }

        let rawArguments = dictionary["arguments"]
        let argumentDictionary: [String: Any]

        if let dictionary = rawArguments as? [String: Any] {
            argumentDictionary = dictionary
        } else if let argumentString = rawArguments as? String {
            let trimmedArgs = argumentString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let argData = trimmedArgs.data(using: .utf8),
                  let argObj = try? JSONSerialization.jsonObject(with: argData),
                  let dict = argObj as? [String: Any] else { return nil }
            argumentDictionary = dict
        } else {
            return nil
        }

        guard JSONSerialization.isValidJSONObject(argumentDictionary),
              let argData = try? JSONSerialization.data(withJSONObject: argumentDictionary, options: [.sortedKeys]),
              let normalizedArgs = try? JSONDecoder().decode([String: JSONValue].self, from: argData) else {
            return nil
        }

        let callId = (dictionary["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? UUID().uuidString
        return ParsedToolCall(id: callId, name: name, arguments: normalizedArgs)
    }
}

// MARK: - Attribute Implementation

public struct AttributeToolCallTemplate: ToolCallTemplate {
    public let name = "Attribute (<function=...)"
    
    private static let openPrefix = "<function="
    private static let closeTag = "</function>"
    
    // Regex for <function=NAME>
    private static let openRegex = try! NSRegularExpression(pattern: #"<function=([^>]+)>"#, options: [])
    
    // Regex for multiple parameters: <parameter=KEY> VALUE
    // Uses non-greedy match [\s\S]*? to capture content including newlines and '<'
    // Stops at the next parameter tag, the closing function tag, or end of buffer.
    private static let paramRegex = try! NSRegularExpression(
        pattern: #"<parameter=([^>]+)>\s*([\s\S]*?)(?=\s*<parameter=|</function>|$)"#,
        options: []
    )

    public var maxOpenHoldback: Int { Self.openPrefix.count - 1 }
    public var maxCloseHoldback: Int { Self.closeTag.count - 1 }

    public func findOpenTag(in buffer: String) -> Range<String.Index>? {
        let nsRange = NSRange(buffer.startIndex..., in: buffer)
        if let match = Self.openRegex.firstMatch(in: buffer, options: [], range: nsRange),
           let range = Range(match.range, in: buffer) {
            return range
        }
        return nil
    }

    public func findCloseTag(in buffer: String) -> Range<String.Index>? {
        buffer.range(of: Self.closeTag)
    }

    public func parse(fullText: String, openTagRange: Range<String.Index>, closeTagRange: Range<String.Index>?) -> ParsedToolCall? {
        let nsRange = NSRange(fullText.startIndex..., in: fullText)
        
        // 1. Extract function name from opening tag
        guard let openMatch = Self.openRegex.firstMatch(in: fullText, options: [], range: nsRange),
              let nameRange = Range(openMatch.range(at: 1), in: fullText) else {
            return nil
        }
        let functionName = String(fullText[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. Define content area between <function=...> and </function>
        let contentStart = openTagRange.upperBound
        let contentEnd = closeTagRange?.lowerBound ?? fullText.endIndex
        let body = String(fullText[contentStart..<contentEnd])
        
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }

        // 3. Multi-parameter scanning
        var arguments: [String: JSONValue] = [:]
        let bodyRange = NSRange(body.startIndex..., in: body)
        let matches = Self.paramRegex.matches(in: body, options: [], range: bodyRange)
        
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: body),
                  let valRange = Range(match.range(at: 2), in: body) else { continue }
            
            let key = String(body[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(body[valRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !key.isEmpty {
                arguments[key] = .string(value)
            }
        }

        guard !arguments.isEmpty else { return nil }

        return ParsedToolCall(
            id: UUID().uuidString,
            name: functionName,
            arguments: arguments
        )
    }
}

// MARK: - Registry

public enum ToolCallTemplates {
    public nonisolated static let xml = XMLToolCallTemplate()
    public nonisolated static let attribute = AttributeToolCallTemplate()

    public nonisolated static let all: [any ToolCallTemplate] = [
        xml,
        attribute
    ]
}
