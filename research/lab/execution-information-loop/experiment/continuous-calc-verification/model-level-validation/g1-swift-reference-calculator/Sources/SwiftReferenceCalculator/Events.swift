import Foundation

/// Append-only JSONL event sink.
///
/// One `started` and exactly one terminal (`completed`/`failed`) per invocation.
/// The file is the independently inspectable evidence the G1 gate requires.
public struct EventLog {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func append(_ record: [String: JSONValue]) throws {
        let line = try CanonicalJSON.encode(.object(record)) + "\n"
        let url = URL(fileURLWithPath: path)
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }
}
