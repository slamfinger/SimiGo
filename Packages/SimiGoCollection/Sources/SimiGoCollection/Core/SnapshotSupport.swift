import Foundation

/// Shared reading support for whole-file snapshot carriers.
///
/// A snapshot adapter has three jobs that are identical for every carrier: read
/// the bytes, decide whether the document is even its own, and turn whatever
/// timestamp the carrier stamps into the one form the delivery sink already
/// parses. Keeping those here means an adapter's own file states only what is
/// specific to that carrier's document shape.
public enum SnapshotReadError: Error, Equatable, CustomStringConvertible {
    /// The bytes could not be read or not parsed. This is a different fact from
    /// "this is not my carrier", which is `foreignDocument`.
    case unreadable(path: String, detail: String)
    /// The document parsed but belongs to another carrier, or is not a document
    /// this adapter can interpret. Surfaced as an error rather than an empty
    /// import so a mis-routed file cannot be recorded as "nothing to collect".
    case foreignDocument(path: String, detail: String)

    public var description: String {
        switch self {
        case .unreadable(path: let path, detail: let detail):
            return "snapshot is unreadable at \(path): \(detail)"
        case .foreignDocument(path: let path, detail: let detail):
            return "snapshot is not this carrier at \(path): \(detail)"
        }
    }
}

/// Typed reads over `JSONSerialization` output.
///
/// Deliberately nil-returning: a missing or wrongly-typed field is an observed
/// absence, and every caller has to decide what that absence means for its
/// carrier. A defaulting accessor would turn "the carrier never said" into a
/// value that downstream grading could mistake for evidence.
enum SnapshotJSON {
    static func document(_ data: Data, path: String = "<bytes>") throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SnapshotReadError.unreadable(path: path, detail: String(describing: error))
        }
    }

    static func object(_ value: Any?) -> [String: Any]? {
        if let value = value as? [String: Any] { return value }
        if let value = value as? NSDictionary {
            return value.reduce(into: [String: Any]()) { result, entry in
                if let key = entry.key as? String { result[key] = entry.value }
            }
        }
        return nil
    }

    static func array(_ value: Any?) -> [Any]? {
        if let value = value as? [Any] { return value }
        if let value = value as? NSArray { return Array(value) }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    /// `JSONSerialization` hands numbers and booleans over as `NSNumber`, and
    /// Swift bridging answers `as? Bool` for the number 1 — which would let a
    /// numeric field read as a flag. The CoreFoundation type identity is what
    /// separates the two, so every numeric accessor checks it first.
    private static func number(_ value: Any?) -> NSNumber? {
        guard let value = value as? NSNumber else { return nil }
        return CFGetTypeID(value) == CFNumberGetTypeID() ? value : nil
    }

    static func integer(_ value: Any?) -> Int? {
        guard let value else { return nil }
        return number(value).flatMap { Int(exactly: $0.int64Value) }
    }

    static func double(_ value: Any?) -> Double? {
        number(value)?.doubleValue
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber else { return nil }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }

    /// The document's own identifier, or nil when the carrier never states one.
    static func identifier(_ value: Any?) -> String? {
        if let text = string(value), !text.isEmpty { return text }
        if let number = integer(value) { return String(number) }
        return nil
    }
}

/// Carrier stamps normalized to one wire form.
///
/// `QoderExternalTurnSink.date(from:)` accepts ISO 8601 with fractional seconds
/// and without, so that is the only shape this bridge may emit. Carriers differ:
/// the flat export uses epoch seconds, AI Studio uses milliseconds with `Z`,
/// DeepSeek uses microseconds with a numeric offset. Normalizing here keeps a
/// provider's choice of stamp from silently becoming `Date()` at delivery time.
public enum SnapshotTimestamp {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Formats ISO 8601 cannot express: a numeric offset combined with a
    /// fractional part of a fixed width.
    private static let textual: [DateFormatter] = {
        var made: [DateFormatter] = []
        for pattern in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = pattern
            made.append(formatter)
        }
        return made
    }()

    /// The one form the sink parses, or nil when the stamp is not a moment.
    /// nil is preserved rather than substituted so a caller cannot read a
    /// missing stamp as "the collector observed now".
    public static func normalize(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if let date = fractional.date(from: text) { return fractional.string(from: date) }
        if let date = plain.date(from: text) { return fractional.string(from: date) }
        for formatter in textual {
            if let date = formatter.date(from: text) { return fractional.string(from: date) }
        }
        return nil
    }

    /// Epoch seconds, as the flat message export stamps them. A value that is
    /// not a plausible moment yields nil instead of a wrapped date: a stamp in
    /// milliseconds reads as year 56,000, and importing that is worse than
    /// importing no timestamp.
    public static func epochSeconds(_ value: Double?) -> String? {
        guard let value, value > 0, value < 4_102_444_800 else { return nil }
        return fractional.string(from: Date(timeIntervalSince1970: value))
    }
}

/// Reading and shape checks shared by every snapshot adapter.
enum SnapshotShape {
    /// The bytes of one document. Only the file name travels into the error: an
    /// absolute path embeds the owner's home directory, and real exports have
    /// been observed to carry it in the file name itself.
    static func bytes(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw SnapshotReadError.unreadable(
                path: url.lastPathComponent, detail: String(describing: error))
        }
    }

    /// The parsed document as an object, or a distinguishing error.
    static func object(from data: Data, path: String) throws -> [String: Any] {
        let value = try SnapshotJSON.document(data, path: path)
        guard let object = SnapshotJSON.object(value) else {
            throw SnapshotReadError.foreignDocument(
                path: path, detail: "top level is not a JSON object")
        }
        return object
    }

    static func array(from data: Data, path: String) throws -> [Any] {
        let value = try SnapshotJSON.document(data, path: path)
        guard let array = SnapshotJSON.array(value) else {
            throw SnapshotReadError.foreignDocument(
                path: path, detail: "top level is not a JSON array")
        }
        return array
    }

    /// Recognition is a structural question, never an extension question.
    static func matches(_ data: Data, _ check: (Any) -> Bool) -> Bool {
        guard let value = try? SnapshotJSON.document(data) else { return false }
        return check(value)
    }
}

/// Text that a carrier states, or nil when it states nothing usable. Deciding
/// "usable" here keeps one rule for every adapter: an empty or whitespace-only
/// field is an absence, and importing it as content would claim an answer that
/// the carrier never recorded. The returned text is never trimmed.
enum SnapshotText {
    static func usable(_ value: Any?) -> String? {
        guard let text = SnapshotJSON.string(value),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }
}

/// Locator used in diagnostics so a report points at the row rather than only
/// at the file.
enum SnapshotLocator {
    static func describe(file: String, sessionID: String?, part: String) -> String {
        if let sessionID { return "\(file)#\(sessionID)/\(part)" }
        return "\(file)#\(part)"
    }
}
