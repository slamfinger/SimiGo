import Foundation
import SimiGoCollection

/// One-shot turn reconstruction for a single Qoder transcript file.
///
/// The collector (`CollectionRunner`) scans a whole root and only closes a turn
/// when the *next* anchor arrives — correct for a live tail, useless when the
/// session is over and the last turn has no successor. This tool reads one file
/// to EOF, flushes the open turn with `.endOfInput`, and prints the events the
/// collector would have emitted as JSON.
///
/// It deliberately prints events rather than a hand-built summary: the
/// grading (human prompt vs automated turn, interrupted, file-order
/// attribution, "no answer candidate") is the package's decision, and a second
/// shape here would let the caller disagree with the sink.
///
/// It also reports the `simigo_chat_round` calls the model made **inside each
/// turn**, attributed by line range. That attribution is the whole point of
/// printing it here: the reply the user saw and the text the model handed to
/// the tool are not always the same string (Qoder renders one and stores the
/// other), so a caller matching them by text alone both misses writes and
/// invents gaps. A call inside the turn is a structural fact; text is a fallback
/// for a write that was made one turn late.
///
///   simigo-qoder-turns --transcript=/path/to/<session>.jsonl

/// One `simigo_chat_round` call, with the turn it was made in.
struct CallRecord: Encodable {
    let turnID: String
    let turnIndex: Int?
    let requestID: String?
    let sessionID: String?
    let assistant: String
}

/// Any SimiGo MCP tool the model called inside the turn, by short name
/// (`simigo_project_note`, `simigo_is_search`, …). A turn that recorded its
/// content through another channel is not a missed round, and text alone cannot
/// tell the difference.
struct ToolRecord: Encodable {
    let turnID: String
    let name: String
}

struct Output: Encodable {
    let path: String
    /// Unparsable lines. A count rather than a `ParseFailure` event: that type
    /// has no public initializer, and a caller-side stand-in would be a second
    /// shape for the same fact.
    let unparsableLines: Int
    let events: [CollectionEvent]
    let calls: [CallRecord]
    let tools: [ToolRecord]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("simigo-qoder-turns: \(message)\n".utf8))
    exit(2)
}

let arguments = CommandLine.arguments.dropFirst()
guard
    let transcript = arguments.first(where: { $0.hasPrefix("--transcript=") })?
        .split(separator: "=", maxSplits: 1).last.map(String.init),
    !transcript.isEmpty
else {
    fail("usage: simigo-qoder-turns --transcript=<file.jsonl>")
}

let url = URL(fileURLWithPath: transcript)
guard let data = FileManager.default.contents(atPath: url.path) else {
    fail("cannot read \(url.path)")
}

let sessionID = url.deletingPathExtension().lastPathComponent
let accumulator = TurnAccumulator(
    context: TurnAccumulator.Context(
        projectID: url.deletingLastPathComponent().lastPathComponent,
        sessionID: sessionID, path: url.path, isSubagent: false))

var events: [CollectionEvent] = []
var unparsableLines = 0
var segmentLine: Int64 = 0
var lines: [(line: Int64, data: Data)] = []
for line in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
    segmentLine += 1
    guard !line.isEmpty else {
        continue
    }
    let bytes = Data(line)
    lines.append((segmentLine, bytes))
    do {
        events.append(
            contentsOf: accumulator.ingest(
                try TranscriptLineParser.parse(bytes), segmentLine: segmentLine))
    } catch {
        unparsableLines += 1
    }
}
accumulator.flushCurrentTurn(boundary: .endOfInput, into: &events)

/// Turn boundaries, from the events the package just produced.
var spans: [(turnID: String, from: Int64, to: Int64)] = []
for event in events {
    guard case .turn(let record) = event else { continue }
    spans.append((record.anchor.id, record.firstSegmentLine, record.lastSegmentLine))
}
spans.sort { $0.from < $1.from }

var calls: [CallRecord] = []
var tools: [ToolRecord] = []
for entry in lines {
    guard
        let span = spans.last(where: { $0.from <= entry.line }),
        entry.line <= span.to
    else { continue }
    guard let object = try? JSONSerialization.jsonObject(with: entry.data),
        let json = object as? [String: Any],
        json["type"] as? String == "assistant",
        let message = json["message"] as? [String: Any],
        let blocks = message["content"] as? [[String: Any]]
    else { continue }
    for block in blocks where block["type"] as? String == "tool_use" {
        let input = block["input"] as? [String: Any]
        // Two shapes reach here: the lazy `mcp_call` wrapper (tool name and
        // arguments nested in `input`) and a directly exposed MCP tool (the
        // block's own `name` is the tool, `input` is the arguments). Reading
        // only one of them would turn every write made through the other into
        // "the model never wrote this round".
        let short: String
        let arguments: [String: Any]
        if let nested = input?["toolName"] as? String {
            short = nested.components(separatedBy: "__").last ?? nested
            arguments = input?["arguments"] as? [String: Any] ?? [:]
        } else if let direct = block["name"] as? String, direct.contains("simigo") {
            short = direct.components(separatedBy: "__").last ?? direct
            arguments = input ?? [:]
        } else {
            continue
        }
        if short.hasPrefix("simigo") {
            tools.append(ToolRecord(turnID: span.turnID, name: short))
        }
        guard short == "simigo_chat_round",
            let assistant = arguments["assistant"] as? String,
            !assistant.isEmpty
        else { continue }
        calls.append(
            CallRecord(
                turnID: span.turnID,
                turnIndex: arguments["turn_index"] as? Int,
                requestID: arguments["request_id"] as? String,
                sessionID: arguments["session_id"] as? String,
                assistant: assistant))
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(
    try encoder.encode(
        Output(
            path: url.path, unparsableLines: unparsableLines, events: events,
            calls: calls, tools: tools)))
