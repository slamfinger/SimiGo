import Darwin
import Foundation

/// Descriptor-based access to Qoder transcript files. Candidate paths are
/// discovered by the scanner, but every metadata/content read re-opens the
/// path beneath the pinned scan root with O_NOFOLLOW on each component.
enum QoderTranscriptPathAccess {
    struct OpenedFile {
        let descriptor: Int32
        let size: Int64
        let inode: UInt64
        let creationDate: Date?
        let modificationDate: Date?
    }

    static func canonicalPath(_ path: String) -> String {
        guard let resolved = path.withCString({ Darwin.realpath($0, nil) }) else {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved)).standardizedFileURL.path
    }

    static func openDirectoryPathNoFollow(_ path: String) throws -> Int32 {
        let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        let canonical = canonicalPath(path)
        guard canonical == standardized else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ELOOP))
        }

        // macOS temporary roots may traverse APFS firmlink/alias components
        // that realpath canonicalizes but that cannot all be walked with a
        // component-wise O_NOFOLLOW sequence. Pin the resolved directory by
        // comparing the opened descriptor with the exact lstat leaf identity.
        var pathInfo = stat()
        let statResult = canonical.withCString { Darwin.lstat($0, &pathInfo) }
        guard statResult == 0, (pathInfo.st_mode & S_IFMT) == S_IFDIR else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let descriptor = canonical.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var openedInfo = stat()
        guard Darwin.fstat(descriptor, &openedInfo) == 0,
              (openedInfo.st_mode & S_IFMT) == S_IFDIR,
              openedInfo.st_dev == pathInfo.st_dev,
              openedInfo.st_ino == pathInfo.st_ino else {
            let code = errno
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return descriptor
    }

    static func relativePath(_ path: String, under root: URL) throws -> String {
        let rootParts = root.standardizedFileURL.pathComponents
        let pathParts = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard pathParts.count > rootParts.count,
              Array(pathParts.prefix(rootParts.count)) == rootParts else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        let relative = pathParts.dropFirst(rootParts.count).joined(separator: "/")
        guard !relative.isEmpty else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        return relative
    }

    static func openFile(
        rootDirectoryFD: Int32,
        relativePath: String,
        expectedInode: UInt64? = nil
    ) throws -> OpenedFile {
        let components = relativePath.split(
            separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        var parentFD = Darwin.dup(rootDirectoryFD)
        guard parentFD >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        for component in components.dropLast() {
            let next = String(component).withCString {
                Darwin.openat(
                    parentFD, $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard next >= 0 else {
                let code = errno
                Darwin.close(parentFD)
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            }
            Darwin.close(parentFD)
            parentFD = next
        }
        let leaf = String(components[components.count - 1])
        let descriptor = leaf.withCString {
            Darwin.openat(
                parentFD, $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        let openError = errno
        Darwin.close(parentFD)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(openError))
        }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              info.st_size >= 0,
              expectedInode == nil || UInt64(info.st_ino) == expectedInode else {
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        let creation = Date(
            timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec)
                + Double(info.st_birthtimespec.tv_nsec) / 1_000_000_000)
        let modification = Date(
            timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        return OpenedFile(
            descriptor: descriptor, size: Int64(info.st_size), inode: UInt64(info.st_ino),
            creationDate: creation, modificationDate: modification)
    }

    static func read(descriptor: Int32, offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, count >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, max(1, count)))
        while result.count < count {
            let requested = min(buffer.count, count - result.count)
            let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.pread(
                    descriptor, base, requested, off_t(offset + Int64(result.count)))
            }
            if amount < 0 && errno == EINTR { continue }
            guard amount >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            if amount == 0 { break }
            result.append(contentsOf: buffer.prefix(amount))
        }
        return result
    }
}


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
    /// The baseline policy these cursors were built under. A cursor made by
    /// `skip_existing` sits at EOF, so switching to `read_existing` would keep
    /// skipping exactly the content the new policy promises to collect. When
    /// the stored policy differs, the cursors are retired and the files are
    /// re-read from their first byte; the candidate keys are stable, so the
    /// inbox absorbs the replay instead of duplicating it.
    public var policy: String?

    public init(
        initializedAt: Date, cursors: [String: QoderFileCursor] = [:],
        policy: String? = nil
    ) {
        self.initializedAt = initializedAt
        self.cursors = cursors
        self.policy = policy
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

    /// A bounded durable checkpoint: enough for the normal 4,096-file inventory,
    /// while refusing corrupted or attacker-grown state before unbounded reads.
    static let maximumCursorStateBytes = 8 * 1024 * 1024
    static let maximumCursorCount = 4_096

    public init(directoryURL: URL) {
        self.fileURL = directoryURL.appendingPathComponent("cursor.json")
    }

    public func load() throws -> QoderCursorState? {
        // lstat + Data(contentsOf:) would leave a pathname race in which a
        // checked regular file could be replaced by a symlink before the read.
        // Open once without following the final component, then validate and
        // consume bytes through that same descriptor.
        let descriptor = fileURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path, detail: "cannot open cursor without following links: "
                    + String(cString: strerror(errno)))
        }
        defer { Darwin.close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= off_t(Self.maximumCursorStateBytes)
        else {
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path,
                detail: "cursor is not a regular owned file with link count one or exceeds the maximum cursor-state byte limit")
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(descriptor, raw.baseAddress, raw.count)
            }
            if count > 0 {
                guard count <= Self.maximumCursorStateBytes - data.count else {
                    throw QoderCollectionStateError.unreadableState(
                        path: fileURL.path,
                        detail: "cursor state grew beyond the maximum cursor-state byte limit while reading")
                }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw QoderCollectionStateError.unreadableState(
                    path: fileURL.path, detail: String(cString: strerror(errno)))
            }
        }

        do {
            return try JSONDecoder().decode(QoderCursorState.self, from: data)
        } catch {
            throw QoderCollectionStateError.corruptLegacyCursor(
                path: fileURL.path, detail: String(describing: error))
        }
    }

    public func save(_ state: QoderCursorState) throws {
        guard state.cursors.count <= Self.maximumCursorCount else {
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path,
                detail: "cursor state exceeds the maximum tracked cursor count (\(Self.maximumCursorCount))")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumCursorStateBytes else {
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path,
                detail: "cursor state exceeds the maximum cursor-state byte limit (\(Self.maximumCursorStateBytes))")
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Atomic replacement never opens an existing cursor target. Apply the
        // restrictive mode through a no-follow descriptor as well, so a late
        // symlink swap cannot redirect chmod to an external file.
        try data.write(to: fileURL, options: [.atomic])
        let descriptor = fileURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path, detail: "cannot open saved cursor without following links: "
                    + String(cString: strerror(errno)))
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              fchmod(descriptor, 0o600) == 0
        else {
            throw QoderCollectionStateError.unreadableState(
                path: fileURL.path, detail: "saved cursor is not a regular owned file with link count one")
        }
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

/// Outcome of one walk over the transcript tree.
///
/// An unreadable directory and an empty one both yield no files, but only a
/// walk that listed every directory proves a previously seen file was deleted
/// rather than merely inaccessible. Retiring cursors from a partial view would
/// erase read positions whose transcripts were never fully delivered.
public enum QoderTranscriptScanResult: Sendable, Equatable {
    /// The whole tree was listed successfully.
    case complete([QoderTranscriptFile])
    /// The scan root does not exist, so nothing can be proven stale.
    case absent
    /// At least one directory could not be listed; `files` is what was
    /// visible, and every stored cursor must survive this poll.
    case partial(files: [QoderTranscriptFile], errors: [String])

    public var files: [QoderTranscriptFile] {
        switch self {
        case .complete(let files):
            return files
        case .absent:
            return []
        case .partial(let files, _):
            return files
        }
    }

    public var errors: [String] {
        guard case .partial(_, let errors) = self else { return [] }
        return errors
    }

    /// Only a complete walk distinguishes "deleted" from "temporarily
    /// unreadable"; stale cursors may be retired from this outcome alone.
    public var isComplete: Bool {
        guard case .complete = self else { return false }
        return true
    }
}

/// Finds the transcript files Qoder itself writes:
///   <root>/<project>/<session>.jsonl
///   <root>/<project>/<session>/subagents/<agent>.jsonl
public struct QoderTranscriptScanner {
    public let root: URL

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .fileSizeKey, .creationDateKey, .contentModificationDateKey,
    ]

    public init(root: URL) {
        self.root = URL(
            fileURLWithPath: QoderTranscriptPathAccess.canonicalPath(root.path),
            isDirectory: true)
    }

    public func scan() -> QoderTranscriptScanResult {
        let rootDirectoryFD: Int32
        do {
            rootDirectoryFD = try QoderTranscriptPathAccess.openDirectoryPathNoFollow(root.path)
        } catch {
            if isNoSuchFileError(error) { return .absent }
            return .partial(
                files: [], errors: ["cannot safely open scan root \(root.path): \(error)"])
        }
        defer { Darwin.close(rootDirectoryFD) }

        let projects: [URL]
        do {
            projects = try listDirectory(root)
        } catch {
            if isNoSuchFileError(error) { return .absent }
            return .partial(
                files: [], errors: ["cannot list \(root.path): \(error)"])
        }

        var errors: [String] = []

        var files: [QoderTranscriptFile] = []
        for project in projects {
            guard
                let projectValues = try? project.resourceValues(
                    forKeys: Self.resourceKeys)
            else {
                errors.append("cannot read attributes for \(project.path)")
                continue
            }
            guard projectValues.isDirectory == true, projectValues.isSymbolicLink != true
            else { continue }
            let projectID = project.lastPathComponent
            guard let children = list(project, errors: &errors) else { continue }
            for child in children {
                guard
                    let values = try? child.resourceValues(forKeys: Self.resourceKeys)
                else {
                    errors.append("cannot read attributes for \(child.path)")
                    continue
                }
                guard values.isSymbolicLink != true else { continue }
                if values.isRegularFile == true, child.pathExtension == "jsonl" {
                    if let file = makeFile(
                        child, rootDirectoryFD: rootDirectoryFD, projectID: projectID,
                        sessionID: child.deletingPathExtension().lastPathComponent,
                        isSubagent: false)
                    {
                        files.append(file)
                    } else {
                        errors.append("cannot read attributes for \(child.path)")
                    }
                } else if values.isDirectory == true {
                    let subagents = child.appendingPathComponent(
                        "subagents", isDirectory: true)
                    // Most sessions have no subagents. Treat only a real
                    // no-such-file result as absence; permission and I/O
                    // failures make the scan partial and preserve cursors.
                    let subagentValues: URLResourceValues
                    do {
                        subagentValues = try subagents.resourceValues(
                            forKeys: Self.resourceKeys)
                    } catch {
                        if !isNoSuchFileError(error) {
                            errors.append(
                                "cannot inspect \(subagents.path): \(error)")
                        }
                        continue
                    }
                    // Missing is the normal case. A symlink or a non-directory
                    // is never traversed, even if its target is a real directory.
                    guard subagentValues.isSymbolicLink != true,
                          subagentValues.isDirectory == true
                    else { continue }

                    let agents: [URL]
                    do {
                        let subagentValues = try subagents.resourceValues(
                            forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        // The directory entry itself must be a real directory.
                        // contentsOfDirectory follows a symlink otherwise.
                        guard subagentValues.isDirectory == true,
                              subagentValues.isSymbolicLink != true else {
                            continue
                        }
                        agents = try listDirectory(subagents)
                    } catch {
                        if !isNoSuchFileError(error) {
                            errors.append("cannot list \(subagents.path): \(error)")
                        }
                        continue
                    }
                    for agent in agents where agent.pathExtension == "jsonl" {
                        guard
                            let agentValues = try? agent.resourceValues(
                                forKeys: Self.resourceKeys)
                        else {
                            errors.append("cannot read attributes for \(agent.path)")
                            continue
                        }
                        guard agentValues.isRegularFile == true,
                            agentValues.isSymbolicLink != true
                        else { continue }
                        if let file = makeFile(
                            agent, rootDirectoryFD: rootDirectoryFD, projectID: projectID,
                            sessionID: child.lastPathComponent, isSubagent: true)
                        {
                            files.append(file)
                        } else {
                            errors.append("cannot read attributes for \(agent.path)")
                        }
                    }
                }
            }
        }

        let sorted = files.sorted { $0.path < $1.path }
        return errors.isEmpty ? .complete(sorted) : .partial(files: sorted, errors: errors)
    }

    private func list(_ directory: URL, errors: inout [String]) -> [URL]? {
        do {
            return try listDirectory(directory)
        } catch {
            errors.append("cannot list \(directory.path): \(error)")
            return nil
        }
    }

    private func listDirectory(_ directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [.skipsHiddenFiles])
    }

    private func isNoSuchFileError(_ error: Error) -> Bool {
        let value = error as NSError
        if value.domain == NSPOSIXErrorDomain,
            value.code == POSIXErrorCode.ENOENT.rawValue
        {
            return true
        }
        if value.domain == NSCocoaErrorDomain,
            value.code == NSFileNoSuchFileError
                || value.code == NSFileReadNoSuchFileError
        {
            return true
        }
        return false
    }

    private func makeFile(
        _ url: URL, rootDirectoryFD: Int32, projectID: String, sessionID: String,
        isSubagent: Bool
    ) -> QoderTranscriptFile? {
        do {
            let relative = try QoderTranscriptPathAccess.relativePath(url.path, under: root)
            let opened = try QoderTranscriptPathAccess.openFile(
                rootDirectoryFD: rootDirectoryFD, relativePath: relative)
            defer { Darwin.close(opened.descriptor) }
            return QoderTranscriptFile(
                path: url.path, projectID: projectID, sessionID: sessionID,
                isSubagent: isSubagent, size: opened.size, inode: opened.inode,
                creationDate: opened.creationDate, modificationDate: opened.modificationDate)
        } catch {
            return nil
        }
    }
}

public struct QoderPollReport: Sendable, Equatable {
    public var scannedFiles = 0
    public var baselinedFiles = 0
    /// 既有文件按回填策略从头读的个数（`existingFileFromStart`）。
    public var backfilledFiles = 0
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

/// 首次见到一个文件时怎么处理。
///
/// `skipExisting` 是历史默认：启用前就存在的文件基线与 EOF，永不回溯——
/// 宁可漏采也不把用户既有对话偷偷读进来。
/// `readExisting` 是「采集桥」的语义：选了目录就把该目录已有的会话采进来。
/// 两者都只影响**没有游标**的文件；有游标的文件照旧增量 tail。
public enum QoderBaselinePolicy: String, Sendable, Equatable, Codable {
    case skipExisting = "skip_existing"
    case readExisting = "read_existing"
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
    public let baselinePolicy: QoderBaselinePolicy
    public let maxBytesPerPoll: Int
    public let maxLineBytes: Int

    private let scanner: QoderTranscriptScanner
    private var state: QoderCursorState
    private var accumulators: [String: QoderTurnAccumulator] = [:]

    /// Deterministic post-read fingerprint fault injection for package tests.
    /// Production callers leave this nil and use descriptor-backed reads.
    var trailingFingerprintOverride: ((String, Int64, UInt64) -> String?)?

    public init(
        scanRoot: URL,
        state: QoderCursorState? = nil,
        now: Date = Date(),
        baselinePolicy: QoderBaselinePolicy = .skipExisting,
        maxBytesPerPoll: Int = 4 << 20,
        maxLineBytes: Int = 32 << 20
    ) {
        let canonicalRoot = URL(
            fileURLWithPath: QoderTranscriptPathAccess.canonicalPath(scanRoot.path),
            isDirectory: true)
        self.scanRoot = canonicalRoot
        self.baselinePolicy = baselinePolicy
        self.scanner = QoderTranscriptScanner(root: canonicalRoot)
        self.maxBytesPerPoll = maxBytesPerPoll
        self.maxLineBytes = maxLineBytes
        self.state = state ?? QoderCursorState(initializedAt: now)
    }

    public var cursorState: QoderCursorState { state }

    public func poll(sink: Sink) -> QoderPollReport {
        var report = QoderPollReport()
        // A cursor is only meaningful under the policy that produced it: after
        // `skip_existing` parks a file at EOF, `read_existing` must not inherit
        // that position, or "选目录即采集既有会话" would silently collect nothing.
        if state.policy != baselinePolicy.rawValue {
            state.cursors.removeAll()
            accumulators.removeAll()
            state.policy = baselinePolicy.rawValue
            report.stateChanged = true
        }
        let scan = scanner.scan()
        let files = scan.files
        report.scannedFiles = files.count
        report.errors.append(contentsOf: scan.errors)
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
                            path: file.path, offset: existing.offset, expectedInode: file.inode)
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
                    } else {
                        let disposition = resumeDisposition(existing)
                        if case .invalid(let detail) = disposition {
                            // Reading on from the committed offset would build
                            // the answer without the prompt that opened it and
                            // hand out an orphan, so this path stops where it
                            // is until the state is repaired or quarantined.
                            report.errors.append(
                                "corrupt resume point for \(file.path): \(detail)")
                            accumulators.removeValue(forKey: file.path)
                            continue
                        }
                        if file.size > existing.offset
                            || (accumulators[file.path] == nil && disposition == .replay)
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
                }
            } else {
                let created = file.creationDate ?? file.modificationDate ?? .distantPast
                let backfill = baselinePolicy == .readExisting
                if backfill || created > state.initializedAt {
                    events.append(
                        .baseline(
                            QoderBaselineEvent(
                                path: file.path, projectID: file.projectID,
                                sessionID: file.sessionID, isSubagent: file.isSubagent,
                                offset: 0,
                                reason: backfill
                                    ? .existingFileFromStart : .newFileFromStart)))
                    if backfill {
                        report.backfilledFiles += 1
                    } else {
                        report.newFilesFromStart += 1
                    }
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

        // A cursor is retired only when the walk proved the file no longer
        // exists. An absent root or a partial listing cannot prove deletion,
        // and erasing a read position would re-baseline undelivered appends.
        if scan.isComplete {
            let stale = state.cursors.keys.filter { !livePaths.contains($0) }
            if !stale.isEmpty {
                for path in stale {
                    state.cursors.removeValue(forKey: path)
                    accumulators.removeValue(forKey: path)
                }
                report.stateChanged = true
            }
        }
        return report
    }

    private func baseline(
        _ file: QoderTranscriptFile, reason: QoderBaselineEvent.Reason,
        events: inout [QoderCollectionEvent], report: inout QoderPollReport
    ) -> QoderFileCursor? {
        guard
            let fingerprint = trailingFingerprint(
            path: file.path, offset: file.size, expectedInode: file.inode)
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
        case .existingFileFromStart:
            // 回填路径在 first-seen 分支自己发事件并计数（offset=0）；这里只
            // 为 switch 完整，正常不会走到。
            report.backfilledFiles += 1
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

    private enum ResumeDisposition: Equatable {
        /// No turn was open at the committed offset; nothing to replay.
        case none
        /// The cursor names an open turn whose anchor is a line boundary.
        case replay
        /// The cursor claims an open turn but cannot name its anchor, so
        /// reading forward from the committed offset would orphan the answer.
        case invalid(String)
    }

    /// Classifies the persisted resume point before any read.
    ///
    /// Cursors written before the resume point existed decode to a point equal
    /// to the committed offset, which is the legitimate "no replay" case. A
    /// cursor that *does* declare an open turn must name a boundary strictly
    /// behind the committed position; anything else is damage, not absence, and
    /// must not degrade into "resume at offset".
    private func resumeDisposition(_ cursor: QoderFileCursor) -> ResumeDisposition {
        let declaresOpenTurn =
            cursor.resumeOffset < cursor.offset
            || cursor.resumeSegmentLines < cursor.segmentLines
        guard declaresOpenTurn else {
            guard cursor.resumeOffset == cursor.offset,
                cursor.resumeSegmentLines == cursor.segmentLines
            else {
                return .invalid(
                    "resume point \(cursor.resumeOffset)/\(cursor.resumeSegmentLines) "
                        + "does not match the committed position "
                        + "\(cursor.offset)/\(cursor.segmentLines)")
            }
            return .none
        }
        guard cursor.resumeOffset >= 0,
            cursor.resumeOffset < cursor.offset,
            cursor.resumeSegmentLines >= 0,
            cursor.resumeSegmentLines < cursor.segmentLines
        else {
            return .invalid(
                "resume point \(cursor.resumeOffset)/\(cursor.resumeSegmentLines) "
                    + "is outside 0..<\(cursor.offset)/0..<\(cursor.segmentLines)")
        }
        guard isLineBoundary(
            path: cursor.path, offset: cursor.resumeOffset, expectedInode: cursor.inode) else {
            return .invalid("resume offset \(cursor.resumeOffset) is not a line boundary")
        }
        return .replay
    }

    /// The resume offset is the start of the anchor line, so the byte before
    /// it must be a newline (or the file start). A cursor whose resume point
    /// landed mid-line would replay from the middle of a record.
    private func isLineBoundary(path: String, offset: Int64, expectedInode: UInt64) -> Bool {
        guard offset > 0,
              let opened = try? openTranscriptFile(path: path, expectedInode: expectedInode)
        else { return offset == 0 }
        defer { Darwin.close(opened.descriptor) }
        guard let byte = try? QoderTranscriptPathAccess.read(
            descriptor: opened.descriptor, offset: offset - 1, count: 1) else { return false }
        return byte == Data([0x0A])
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
        let replaying =
            accumulators[file.path] == nil && resumeDisposition(cursor) == .replay
        var working = cursor
        if replaying {
            working.offset = cursor.resumeOffset
            working.segmentLines = cursor.resumeSegmentLines
        }
        let available = file.size - working.offset
        guard available > 0 else { return false }
        let opened: QoderTranscriptPathAccess.OpenedFile
        do {
            opened = try openTranscriptFile(path: file.path, expectedInode: file.inode)
        } catch {
            report.errors.append("cannot safely open \(file.path): \(error)")
            return false
        }
        defer { Darwin.close(opened.descriptor) }
        guard opened.size >= working.offset else {
            report.errors.append("transcript changed before read: \(file.path)")
            return false
        }

        let data: Data
        do {
            data = try QoderTranscriptPathAccess.read(
                descriptor: opened.descriptor, offset: working.offset,
                count: Int(min(available, Int64(maxBytesPerPoll))))
            guard !data.isEmpty else { return false }
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
        // Preserve only events that predate this read (notably a first-seen
        // baseline). Read-derived candidates are provisional until the source
        // path still resolves to the pinned inode after parsing.
        let readDerivedEventStart = events.count

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
        guard let fingerprint = trailingFingerprint(
            path: file.path, offset: newOffset, expectedInode: file.inode)
        else {
            report.errors.append("cannot fingerprint \(file.path) after read")
            if events.count > readDerivedEventStart {
                events.removeSubrange(readDerivedEventStart..<events.count)
            }
            // Parsing may have mutated the open-turn accumulator before the
            // final path/inode check. Discard it so the next poll rebuilds from
            // the durable replay offset instead of delivering or duplicating
            // candidates from an identity that no longer verifies.
            accumulators.removeValue(forKey: file.path)
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
            path: file.path, from: lineStart, limit: Int64(maxLineBytes),
            expectedInode: file.inode)
        {
            let consumed = afterNewline - lineStart
            guard
                let fingerprint = trailingFingerprint(
                    path: file.path, offset: afterNewline, expectedInode: file.inode)
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
                    path: file.path, offset: lineStart + advance, expectedInode: file.inode)
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

    private func openTranscriptFile(
        path: String, expectedInode: UInt64
    ) throws -> QoderTranscriptPathAccess.OpenedFile {
        let rootFD = try QoderTranscriptPathAccess.openDirectoryPathNoFollow(scanRoot.path)
        defer { Darwin.close(rootFD) }
        let relative = try QoderTranscriptPathAccess.relativePath(path, under: scanRoot)
        return try QoderTranscriptPathAccess.openFile(
            rootDirectoryFD: rootFD, relativePath: relative, expectedInode: expectedInode)
    }

    private func findNewline(
        path: String, from offset: Int64, limit: Int64, expectedInode: UInt64
    ) -> Int64? {
        guard offset >= 0, limit >= 0,
              let opened = try? openTranscriptFile(path: path, expectedInode: expectedInode)
        else { return nil }
        defer { Darwin.close(opened.descriptor) }
        var scanned: Int64 = 0
        while scanned < limit {
            let count = Int(min(1 << 20, limit - scanned))
            guard let chunk = try? QoderTranscriptPathAccess.read(
                descriptor: opened.descriptor, offset: offset + scanned, count: count),
                !chunk.isEmpty else { return nil }
            if let newline = chunk.firstIndex(of: 0x0A) {
                return offset + scanned
                    + Int64(chunk.distance(from: chunk.startIndex, to: newline)) + 1
            }
            scanned += Int64(chunk.count)
        }
        return nil
    }

    private func trailingFingerprint(
        path: String, offset: Int64, expectedInode: UInt64
    ) -> String? {
        if let trailingFingerprintOverride {
            return trailingFingerprintOverride(path, offset, expectedInode)
        }
        guard offset >= 0 else { return nil }
        if offset == 0 { return QoderDigest.sha256Hex(Data()) }
        let window: Int64 = 256
        let start = max(0, offset - window)
        guard let opened = try? openTranscriptFile(path: path, expectedInode: expectedInode)
        else { return nil }
        defer { Darwin.close(opened.descriptor) }
        guard let data = try? QoderTranscriptPathAccess.read(
            descriptor: opened.descriptor, offset: start, count: Int(offset - start)),
            data.count == Int(offset - start) else { return nil }
        return QoderDigest.sha256Hex(data)
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
