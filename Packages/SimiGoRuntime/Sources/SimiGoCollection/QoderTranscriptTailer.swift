import Foundation

/// Durable read position for one transcript file.
///
/// `offset` is always a line boundary, so a restart never re-parses a partial
/// line twice. `fingerprint` is a digest of the bytes immediately before
/// `offset`; together with `inode` it detects a rewritten or replaced file that
/// merely kept its size, which a size-only cursor would silently trust.
public struct QoderFileCursor: Codable, Sendable, Equatable {
    public let path: String
    public let projectID: String
    public let sessionID: String
    public let isSubagent: Bool
    public let inode: UInt64
    public let offset: Int64
    public let segmentLines: Int64
    public let fingerprint: String
    public let updatedAt: Date

    public init(
        path: String, projectID: String, sessionID: String, isSubagent: Bool,
        inode: UInt64, offset: Int64, segmentLines: Int64, fingerprint: String,
        updatedAt: Date
    ) {
        self.path = path
        self.projectID = projectID
        self.sessionID = sessionID
        self.isSubagent = isSubagent
        self.inode = inode
        self.offset = offset
        self.segmentLines = segmentLines
        self.fingerprint = fingerprint
        self.updatedAt = updatedAt
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

public protocol QoderCursorStoring: AnyObject {
    func load() -> QoderCursorState?
    func save(_ state: QoderCursorState) throws
}

public final class QoderFileCursorStore: QoderCursorStoring {
    public let fileURL: URL

    public init(directoryURL: URL) {
        self.fileURL = directoryURL.appendingPathComponent("cursor.json")
    }

    public func load() -> QoderCursorState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(QoderCursorState.self, from: data)
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
    public var deliveredEvents = 0
    public var parseFailures = 0
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
                    } else if file.size > existing.offset {
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
            segmentLines: segmentLines, fingerprint: fingerprint, updatedAt: Date())
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
    private func readAvailable(
        _ file: QoderTranscriptFile, cursor: inout QoderFileCursor,
        events: inout [QoderCollectionEvent], report: inout QoderPollReport
    ) -> Bool {
        let available = file.size - cursor.offset
        guard available > 0 else { return false }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
        else {
            report.errors.append("cannot open \(file.path)")
            return false
        }
        defer { try? handle.close() }

        let data: Data
        do {
            try handle.seek(toOffset: UInt64(cursor.offset))
            guard let read = try handle.read(
                upToCount: Int(min(available, Int64(maxBytesPerPoll)))),
                !read.isEmpty
            else { return false }
            data = read
        } catch {
            report.errors.append("read failed for \(file.path): \(error)")
            return false
        }

        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            return skipOversizedLine(
                file, cursor: &cursor, available: available, partialBytes: data.count,
                events: &events, report: &report)
        }

        let content = data[data.startIndex..<lastNewline]
        let consumed = data.distance(from: data.startIndex, to: lastNewline) + 1

        var lineCount: Int64 = 0
        var start = content.startIndex
        while true {
            let end = content[start...].firstIndex(of: 0x0A) ?? content.endIndex
            lineCount += 1
            let segmentLine = cursor.segmentLines + lineCount
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
            if end == content.endIndex { break }
            start = content.index(after: end)
        }

        guard let fingerprint = trailingFingerprint(
            path: file.path, offset: cursor.offset + Int64(consumed))
        else {
            report.errors.append("cannot fingerprint \(file.path) after read")
            return false
        }
        cursor = QoderFileCursor(
            path: cursor.path, projectID: cursor.projectID, sessionID: cursor.sessionID,
            isSubagent: cursor.isSubagent, inode: cursor.inode,
            offset: cursor.offset + Int64(consumed),
            segmentLines: cursor.segmentLines + lineCount,
            fingerprint: fingerprint, updatedAt: Date())
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
        if let afterNewline = findNewline(
            path: file.path, from: cursor.offset, limit: Int64(maxLineBytes))
        {
            let consumed = afterNewline - cursor.offset
            guard
                let fingerprint = trailingFingerprint(
                    path: file.path, offset: afterNewline)
            else {
                report.errors.append("cannot fingerprint \(file.path) after skip")
                return false
            }
            cursor = QoderFileCursor(
                path: cursor.path, projectID: cursor.projectID,
                sessionID: cursor.sessionID, isSubagent: cursor.isSubagent,
                inode: cursor.inode, offset: afterNewline,
                segmentLines: cursor.segmentLines + 1, fingerprint: fingerprint,
                updatedAt: Date())
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
                    path: file.path, offset: cursor.offset + advance)
            else {
                report.errors.append("cannot fingerprint \(file.path) after skip")
                return false
            }
            cursor = QoderFileCursor(
                path: cursor.path, projectID: cursor.projectID,
                sessionID: cursor.sessionID, isSubagent: cursor.isSubagent,
                inode: cursor.inode, offset: cursor.offset + advance,
                segmentLines: cursor.segmentLines + 1, fingerprint: fingerprint,
                updatedAt: Date())
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
