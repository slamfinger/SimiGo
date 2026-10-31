import Foundation

/// Durable read position for one transcript file.
///
/// `offset` is always a line boundary, so a restart never re-parses a partial
/// line twice. `fingerprint` is a digest of the bytes immediately before
/// `offset`; together with `inode` it detects a rewritten or replaced file that
/// merely kept its size, which a size-only cursor would silently trust.
///
/// `resumeOffset` is the start of the line that opened the still-open turn (or
/// `offset` when no turn is open). A cold tailer re-reads from there so turn
/// state is rebuilt from the transcript itself instead of a serialized
/// checkpoint: parent chain, compaction boundary, message snapshots, terminals,
/// and interrupt marks all replay deterministically from the same source.
public struct QoderFileCursor: Codable, Sendable, Equatable {
    public var path: String
    public var projectID: String
    public var sessionID: String
    public var isSubagent: Bool
    public var inode: UInt64
    public var offset: Int64
    public var segmentLines: Int64
    public var resumeOffset: Int64
    /// Segment lines consumed before the line at `resumeOffset`, so replay
    /// continues numbering as if the file had been read in one pass.
    public var resumeSegmentLines: Int64
    public var fingerprint: String
    public var updatedAt: Date

    public init(
        path: String, projectID: String, sessionID: String, isSubagent: Bool,
        inode: UInt64, offset: Int64, segmentLines: Int64,
        resumeOffset: Int64? = nil, resumeSegmentLines: Int64? = nil,
        fingerprint: String, updatedAt: Date
    ) {
        self.path = path
        self.projectID = projectID
        self.sessionID = sessionID
        self.isSubagent = isSubagent
        self.inode = inode
        self.offset = offset
        self.segmentLines = segmentLines
        self.resumeOffset = resumeOffset ?? offset
        self.resumeSegmentLines = resumeSegmentLines ?? segmentLines
        self.fingerprint = fingerprint
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case path, projectID, sessionID, isSubagent, inode, offset, segmentLines
        case resumeOffset, resumeSegmentLines, fingerprint, updatedAt
    }

    /// Cursors written before the resume point existed carry no open-turn
    /// information; they decode to "no replay" rather than re-reading history.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        projectID = try container.decode(String.self, forKey: .projectID)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        isSubagent = try container.decode(Bool.self, forKey: .isSubagent)
        inode = try container.decode(UInt64.self, forKey: .inode)
        offset = try container.decode(Int64.self, forKey: .offset)
        segmentLines = try container.decode(Int64.self, forKey: .segmentLines)
        resumeOffset =
            try container.decodeIfPresent(Int64.self, forKey: .resumeOffset) ?? offset
        resumeSegmentLines =
            try container.decodeIfPresent(Int64.self, forKey: .resumeSegmentLines)
            ?? segmentLines
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct QoderCursorState: Codable, Sendable, Equatable {
    /// Files that already existed at this instant are opened at EOF, never
    /// backfilled. Files created afterwards are read from their first byte.
    public var initializedAt: Date
    public var cursors: [String: QoderFileCursor]

    public init(initializedAt: Date, cursors: [String: QoderFileCursor] = [:]) {
        self.initializedAt = initializedAt
        self.cursors = cursors
    }
}

/// Pre-inbox cursor format. It is read once when a Slice 2 state directory is
/// migrated into the durable inbox; everything after that uses the inbox.
///
/// Loading distinguishes absence from damage: a missing file is a first start,
/// while an unreadable or undecodable one throws. Treating damage as absence
/// would let the collector silently re-baseline transcripts whose contents
/// were never reliably delivered.
public final class QoderFileCursorStore {
    public let fileURL: URL

    public init(directoryURL: URL) {
        self.fileURL = directoryURL.appendingPathComponent("cursor.json")
    }

    public func load() throws -> QoderCursorState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path, detail: String(describing: error))
        }
        do {
            return try JSONDecoder().decode(QoderCursorState.self, from: data)
        } catch {
            throw QoderCollectionStateError.corruptLegacyCursor(
                path: fileURL.path, detail: String(describing: error))
        }
    }

    public func save(_ state: QoderCursorState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

public struct QoderTranscriptFile: Sendable, Equatable {
    public let path: String
    public let projectID: String
    public let sessionID: String
    public let isSubagent: Bool
    public let size: Int64
    public let inode: UInt64
    public let creationDate: Date?
    public let modificationDate: Date?
}

/// Finds the transcript files Qoder itself writes:
///   <root>/<project>/<session>.jsonl
///   <root>/<project>/<session>/subagents/<agent>.jsonl
public struct QoderTranscriptScanner {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func scan() -> [QoderTranscriptFile] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .creationDateKey, .contentModificationDateKey,
        ]
        guard
            let projects = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles])
        else { return [] }

        var files: [QoderTranscriptFile] = []
        for project in projects {
            guard let projectValues = try? project.resourceValues(forKeys: keys),
                projectValues.isDirectory == true, projectValues.isSymbolicLink != true
            else { continue }
            let projectID = project.lastPathComponent
            let children =
                (try? fileManager.contentsOfDirectory(
                    at: project, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles])) ?? []
            for child in children {
                guard let values = try? child.resourceValues(forKeys: keys),
                    values.isSymbolicLink != true
                else { continue }
                if values.isRegularFile == true, child.pathExtension == "jsonl" {
                    if let file = makeFile(
                        child, values: values, projectID: projectID,
                        sessionID: child.deletingPathExtension().lastPathComponent,
                        isSubagent: false)
                    {
                        files.append(file)
                    }
                } else if values.isDirectory == true {
                    let subagents = child.appendingPathComponent("subagents", isDirectory: true)
                    let agents =
                        (try? fileManager.contentsOfDirectory(
                            at: subagents, includingPropertiesForKeys: Array(keys),
                            options: [.skipsHiddenFiles])) ?? []
                    for agent in agents where agent.pathExtension == "jsonl" {
                        guard let agentValues = try? agent.resourceValues(forKeys: keys),
                            agentValues.isRegularFile == true,
                            agentValues.isSymbolicLink != true
                        else { continue }
                        if let file = makeFile(
                            agent, values: agentValues, projectID: projectID,
                            sessionID: child.lastPathComponent, isSubagent: true)
                        {
                            files.append(file)
                        }
                    }
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func makeFile(
        _ url: URL, values: URLResourceValues, projectID: String, sessionID: String,
        isSubagent: Bool
    ) -> QoderTranscriptFile? {
        guard let size = values.fileSize,
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileNumber = attributes[.systemFileNumber] as? NSNumber
        else { return nil }
        return QoderTranscriptFile(
            path: url.path, projectID: projectID, sessionID: sessionID,
            isSubagent: isSubagent, size: Int64(size), inode: fileNumber.uint64Value,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate)
    }
}

public struct QoderPollReport: Sendable, Equatable {
    public var scannedFiles = 0
    public var baselinedFiles = 0
    public var newFilesFromStart = 0
    public var resetFiles = 0
    public var readFiles = 0
    public var readBytes: Int64 = 0
    /// Bytes re-read from the open turn's anchor to rebuild accumulator state
    /// after a cold start; a subset of `readBytes`.
    public var replayedBytes: Int64 = 0
    public var deliveredEvents = 0
    public var parseFailures = 0
    /// Candidates the durable inbox inserted; replay of an already committed
    /// batch reports the same events as duplicates instead.
    public var persistedCandidates = 0
    public var duplicateCandidates = 0
    /// Candidates handed to the delivery sink during this poll.
    public var deliveredCandidates = 0
    public var stateChanged = false
    public var errors: [String] = []

    public init() {}
}

/// Forward-only incremental reader over Qoder transcripts.
///
/// Every poll: discover files, verify each cursor still describes the same
/// file, read at most `maxBytesPerPoll` of complete lines, rebuild turns, and
/// hand the events to a sink. A file's cursor advances only after the sink
/// accepted that file's events; a sink failure drops the in-memory turn state
/// and leaves the cursor where it was, so the next poll replays the same bytes
/// instead of silently losing a turn.
public final class QoderTranscriptTailer {
    public typealias Sink = ([QoderCollectionEvent]) throws -> Void

    public let scanRoot: URL
    public let maxBytesPerPoll: Int
    public let maxLineBytes: Int

    private let scanner: QoderTranscriptScanner
    private var state: QoderCursorState
    private var accumulators: [String: QoderTurnAccumulator] = [:]

    public init(
        scanRoot: URL,
        state: QoderCursorState? = nil,
        now: Date = Date(),
        maxBytesPerPoll: Int = 4 << 20,
        maxLineBytes: Int = 32 << 20
    ) {
        self.scanRoot = scanRoot
        self.scanner = QoderTranscriptScanner(root: scanRoot)
        self.maxBytesPerPoll = maxBytesPerPoll
        self.maxLineBytes = maxLineBytes
        self.state = state ?? QoderCursorState(initializedAt: now)
    }

    public var cursorState: QoderCursorState { state }

    public func poll(sink: Sink) -> QoderPollReport {
        var report = QoderPollReport()
        let files = scanner.scan()
        report.scannedFiles = files.count
        var livePaths: Set<String> = []

        for file in files {
            livePaths.insert(file.path)
            var events: [QoderCollectionEvent] = []
            var nextCursor: QoderFileCursor
            var changed = false

            if var existing = state.cursors[file.path] {
                if existing.inode != file.inode {
                    guard
                        let reset = baseline(
                            file, reason: .identityReset, events: &events,
                            report: &report)
                    else { continue }
                    nextCursor = reset
                    changed = true
                } else if file.size < existing.offset {
                    guard
                        let reset = baseline(
                            file, reason: .truncatedReset, events: &events,
                            report: &report)
                    else { continue }
                    nextCursor = reset
                    changed = true
                } else {
                    guard
                        let current = trailingFingerprint(
                            path: file.path, offset: existing.offset)
                    else {
                        report.errors.append("cannot fingerprint \(file.path)")
                        continue
                    }
                    if current != existing.fingerprint {
                        guard
                            let reset = baseline(
                                file, reason: .fingerprintReset, events: &events,
                                report: &report)
                        else { continue }
                        nextCursor = reset
                        changed = true
                    } else if file.size > existing.offset
                        || (accumulators[file.path] == nil && canReplay(existing))
                    {
                        // A cold tailer with an open turn rewinds to the
                        // anchor even when no new bytes arrived, so recovery
                        // happens at start rather than at the next append.
                        let consumed = readAvailable(
                            file, cursor: &existing, events: &events, report: &report)
                        nextCursor = existing
                        changed = consumed
                    } else {
                        nextCursor = existing
                    }
                }
            } else {
                let created = file.creationDate ?? file.modificationDate ?? .distantPast
                if created > state.initializedAt {
                    events.append(
                        .baseline(
                            QoderBaselineEvent(
                                path: file.path, projectID: file.projectID,
                                sessionID: file.sessionID, isSubagent: file.isSubagent,
                                offset: 0, reason: .newFileFromStart)))
                    report.newFilesFromStart += 1
                    var cursor = makeCursor(
                        file, offset: 0, segmentLines: 0,
                        fingerprint: QoderDigest.sha256Hex(Data()))
                    _ = readAvailable(
                        file, cursor: &cursor, events: &events, report: &report)
                    nextCursor = cursor
                    changed = true
                } else {
                    guard
                        let reset = baseline(
                            file, reason: .existingFileAtEnd, events: &events,
                            report: &report)
                    else { continue }
                    nextCursor = reset
                    changed = true
                }
            }

            guard deliver(file, events: events, sink: sink, report: &report) else {
                continue
            }
            state.cursors[file.path] = nextCursor
            if changed {
                report.stateChanged = true
            }
        }

        let stale = state.cursors.keys.filter { !livePaths.contains($0) }
        if !stale.isEmpty {
            for path in stale {
                state.cursors.removeValue(forKey: path)
                accumulators.removeValue(forKey: path)
            }
            report.stateChanged = true
        }
        return report
    }

    private func baseline(
        _ file: QoderTranscriptFile, reason: QoderBaselineEvent.Reason,
        events: inout [QoderCollectionEvent], report: inout QoderPollReport
    ) -> QoderFileCursor? {
        guard
            let fingerprint = trailingFingerprint(path: file.path, offset: file.size)
        else {
            report.errors.append("cannot fingerprint \(file.path)")
            return nil
        }
        accumulators.removeValue(forKey: file.path)
        switch reason {
        case .existingFileAtEnd:
            report.baselinedFiles += 1
        case .newFileFromStart:
            report.newFilesFromStart += 1
        case .truncatedReset, .identityReset, .fingerprintReset:
            report.resetFiles += 1
        }
        events.append(
            .baseline(
                QoderBaselineEvent(
                    path: file.path, projectID: file.projectID,
                    sessionID: file.sessionID, isSubagent: file.isSubagent,
                    offset: file.size, reason: reason)))
        return makeCursor(
            file, offset: file.size, segmentLines: 0, fingerprint: fingerprint)
    }

    private func makeCursor(
        _ file: QoderTranscriptFile, offset: Int64, segmentLines: Int64,
        fingerprint: String
    ) -> QoderFileCursor {
        QoderFileCursor(
            path: file.path, projectID: file.projectID, sessionID: file.sessionID,
            isSubagent: file.isSubagent, inode: file.inode, offset: offset,
            segmentLines: segmentLines, resumeOffset: offset,
            resumeSegmentLines: segmentLines, fingerprint: fingerprint,
            updatedAt: Date())
    }

    /// The persisted resume point is usable only when it lies behind the
    /// committed offset at a counted line boundary. Anything else (corrupt or
    /// pre-upgrade state) means "resume at offset, no replay".
    private func canReplay(_ cursor: QoderFileCursor) -> Bool {
        guard cursor.resumeOffset >= 0,
            cursor.resumeOffset < cursor.offset,
            cursor.resumeSegmentLines >= 0,
            cursor.resumeSegmentLines <= cursor.segmentLines
        else { return false }
        return isLineBoundary(path: cursor.path, offset: cursor.resumeOffset)
    }

    /// The resume offset is the start of the anchor line, so the byte before
    /// it must be a newline (or the file start). A cursor whose resume point
    /// landed mid-line would replay from the middle of a record.
    private func isLineBoundary(path: String, offset: Int64) -> Bool {
        guard offset > 0 else { return true }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        else { return false }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset - 1))
            guard let byte = try handle.read(upToCount: 1) else { return false }
            return byte == Data([0x0A])
        } catch {
            return false
        }
    }

    private func accumulator(for file: QoderTranscriptFile) -> QoderTurnAccumulator {
        if let existing = accumulators[file.path] { return existing }
        let accumulator = QoderTurnAccumulator(
            context: QoderTurnAccumulator.Context(
                projectID: file.projectID, sessionID: file.sessionID,
                path: file.path, isSubagent: file.isSubagent))
        accumulators[file.path] = accumulator
        return accumulator
    }

    /// Reads complete lines only, at most `maxBytesPerPoll`. Returns true when
    /// the cursor moved.
    ///
    /// When no in-memory accumulator exists and the cursor still points at an
    /// open turn's anchor, reading starts there instead of at `offset`, so a
    /// restart rebuilds the unfinished turn from the transcript. A sink failure
    /// drops the accumulator, which routes the next poll through the same
    /// replay path and keeps an open turn from being orphaned mid-answer.
    private func readAvailable(
        _ file: QoderTranscriptFile, cursor: inout QoderFileCursor,
        events: inout [QoderCollectionEvent], report: inout QoderPollReport
    ) -> Bool {
        let committedOffset = cursor.offset
        let replaying = accumulators[file.path] == nil && canReplay(cursor)
        var working = cursor
        if replaying {
            working.offset = cursor.resumeOffset
            working.segmentLines = cursor.resumeSegmentLines
        }
        let available = file.size - working.offset
        guard available > 0 else { return false }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
        else {
            report.errors.append("cannot open \(file.path)")
            return false
        }
        defer { try? handle.close() }

        let data: Data
        do {
            try handle.seek(toOffset: UInt64(working.offset))
            guard let read = try handle.read(
                upToCount: Int(min(available, Int64(maxBytesPerPoll)))),
                !read.isEmpty
            else { return false }
            data = read
        } catch {
            report.errors.append("read failed for \(file.path): \(error)")
            return false
        }

        if replaying {
            report.replayedBytes += min(
                Int64(data.count), committedOffset - working.offset)
        }

        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            let moved = skipOversizedLine(
                file, cursor: &working, available: available, partialBytes: data.count,
                events: &events, report: &report)
            cursor = working
            return moved
        }

        let content = data[data.startIndex..<lastNewline]
        let consumed = data.distance(from: data.startIndex, to: lastNewline) + 1
        let windowStart = working.offset

        var lineCount: Int64 = 0
        var start = content.startIndex
        while true {
            let end = content[start...].firstIndex(of: 0x0A) ?? content.endIndex
            lineCount += 1
            let segmentLine = working.segmentLines + lineCount
            let lineStart = windowStart + Int64(
                content.distance(from: content.startIndex, to: start))
            let lineEnd = lineStart + Int64(content.distance(from: start, to: end)) + 1
            var line = content[start..<end]
            if line.last == 0x0D {
                line = line.dropLast()
            }
            if !line.isEmpty {
                if line.count > maxLineBytes {
                    report.parseFailures += 1
                    events.append(
                        .parseFailure(
                            QoderParseFailure(
                                path: file.path, sessionID: file.sessionID,
                                segmentLine: segmentLine,
                                detail: "line exceeds \(maxLineBytes) bytes")))
                } else {
                    do {
                        let entry = try QoderTranscriptLineParser.parse(Data(line))
                        events.append(
                            contentsOf: accumulator(for: file).ingest(
                                entry, segmentLine: segmentLine))
                    } catch {
                        report.parseFailures += 1
                        events.append(
                            .parseFailure(
                                QoderParseFailure(
                                    path: file.path, sessionID: file.sessionID,
                                    segmentLine: segmentLine,
                                    detail: String(describing: error))))
                    }
                }
            }
            advanceResume(
                &working, file: file, segmentLine: segmentLine,
                lineStart: lineStart, lineEnd: lineEnd)
            if end == content.endIndex { break }
            start = content.index(after: end)
        }

        let newOffset = windowStart + Int64(consumed)
        guard let fingerprint = trailingFingerprint(path: file.path, offset: newOffset)
        else {
            report.errors.append("cannot fingerprint \(file.path) after read")
            return false
        }
        working.offset = newOffset
        working.segmentLines += lineCount
        working.fingerprint = fingerprint
        working.updatedAt = Date()
        cursor = working
        report.readFiles += 1
        report.readBytes += Int64(consumed)
        return true
    }

    /// A single line longer than one poll window would otherwise stall the
    /// file forever. Search for its newline up to `maxLineBytes`; past that,
    /// drop one window and record a parse failure so the stream can progress.
    private func skipOversizedLine(
        _ file: QoderTranscriptFile, cursor: inout QoderFileCursor, available: Int64,
        partialBytes: Int, events: inout [QoderCollectionEvent],
        report: inout QoderPollReport
    ) -> Bool {
        let lineStart = cursor.offset
        if let afterNewline = findNewline(
            path: file.path, from: lineStart, limit: Int64(maxLineBytes))
        {
            let consumed = afterNewline - lineStart
            guard
                let fingerprint = trailingFingerprint(
                    path: file.path, offset: afterNewline)
            else {
                report.errors.append("cannot fingerprint \(file.path) after skip")
                return false
            }
            cursor.offset = afterNewline
            cursor.segmentLines += 1
            cursor.fingerprint = fingerprint
            cursor.updatedAt = Date()
            advanceResume(
                &cursor, file: file, segmentLine: cursor.segmentLines,
                lineStart: lineStart, lineEnd: afterNewline)
            report.parseFailures += 1
            report.readFiles += 1
            report.readBytes += consumed
            events.append(
                .parseFailure(
                    QoderParseFailure(
                        path: file.path, sessionID: file.sessionID,
                        segmentLine: cursor.segmentLines,
                        detail: "line exceeds poll window")))
            return true
        }
        if available > Int64(maxLineBytes) {
            let advance = Int64(partialBytes)
            guard
                let fingerprint = trailingFingerprint(
                    path: file.path, offset: lineStart + advance)
            else {
                report.errors.append("cannot fingerprint \(file.path) after skip")
                return false
            }
            cursor.offset = lineStart + advance
            cursor.segmentLines += 1
            cursor.fingerprint = fingerprint
            cursor.updatedAt = Date()
            // The drop lands mid-line, so the resume point (always a line
            // boundary) is left where it was; a cold start re-reads the line.
            report.parseFailures += 1
            report.readFiles += 1
            report.readBytes += advance
            events.append(
                .parseFailure(
                    QoderParseFailure(
                        path: file.path, sessionID: file.sessionID,
                        segmentLine: cursor.segmentLines,
                        detail: "line exceeds \(maxLineBytes) bytes; window dropped")))
            return true
        }
        return false
    }

    /// Moves the replay floor: a newly opened anchor pins it to that line's
    /// start; outside any turn it advances past the consumed line.
    private func advanceResume(
        _ cursor: inout QoderFileCursor, file: QoderTranscriptFile,
        segmentLine: Int64, lineStart: Int64, lineEnd: Int64
    ) {
        guard let anchorLine = accumulators[file.path]?.openAnchorSegmentLine else {
            cursor.resumeOffset = lineEnd
            cursor.resumeSegmentLines = segmentLine
            return
        }
        if anchorLine == segmentLine {
            cursor.resumeOffset = lineStart
            cursor.resumeSegmentLines = segmentLine - 1
        }
    }

    private func findNewline(path: String, from offset: Int64, limit: Int64) -> Int64? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            var scanned: Int64 = 0
            while scanned < limit {
                guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty
                else { return nil }
                if let newline = chunk.firstIndex(of: 0x0A) {
                    return offset + scanned
                        + Int64(chunk.distance(from: chunk.startIndex, to: newline)) + 1
                }
                scanned += Int64(chunk.count)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func trailingFingerprint(path: String, offset: Int64) -> String? {
        guard offset >= 0 else { return nil }
        if offset == 0 { return QoderDigest.sha256Hex(Data()) }
        let window: Int64 = 256
        let start = max(0, offset - window)
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(start))
            guard let data = try handle.read(upToCount: Int(offset - start)),
                data.count == Int(offset - start)
            else { return nil }
            return QoderDigest.sha256Hex(data)
        } catch {
            return nil
        }
    }

    private func deliver(
        _ file: QoderTranscriptFile, events: [QoderCollectionEvent], sink: Sink,
        report: inout QoderPollReport
    ) -> Bool {
        guard !events.isEmpty else { return true }
        do {
            try sink(events)
            report.deliveredEvents += events.count
            return true
        } catch {
            report.errors.append("sink failed for \(file.path): \(error)")
            accumulators.removeValue(forKey: file.path)
            return false
        }
    }
}
