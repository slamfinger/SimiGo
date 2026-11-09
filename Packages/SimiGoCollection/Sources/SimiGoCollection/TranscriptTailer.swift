import Darwin
import Foundation

/// Descriptor-based access to Qoder transcript files. Candidate paths are
/// discovered by the scanner, but every metadata/content read re-opens the
/// path beneath the pinned scan root with O_NOFOLLOW on each component.
enum TranscriptPathAccess {
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
public struct FileCursor: Codable, Sendable, Equatable {
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

public struct CursorState: Codable, Sendable, Equatable {
    /// Files that already existed at this instant are opened at EOF, never
    /// backfilled. Files created afterwards are read from their first byte.
    public var initializedAt: Date
    public var cursors: [String: FileCursor]
    /// The baseline policy these cursors were built under. A cursor made by
    /// `skip_existing` sits at EOF, so switching to `read_existing` would keep
    /// skipping exactly the content the new policy promises to collect. When
    /// the stored policy differs, the cursors are retired and the files are
    /// re-read from their first byte; the candidate keys are stable, so the
    /// inbox absorbs the replay instead of duplicating it.
    public var policy: String?

    public init(
        initializedAt: Date, cursors: [String: FileCursor] = [:],
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
public final class FileCursorStore {
    public let fileURL: URL

    /// A bounded durable checkpoint: enough for the normal 4,096-file inventory,
    /// while refusing corrupted or attacker-grown state before unbounded reads.
    static let maximumCursorStateBytes = 8 * 1024 * 1024
    static let maximumCursorCount = 4_096

    public init(directoryURL: URL) {
        self.fileURL = directoryURL.appendingPathComponent("cursor.json")
    }

    public func load() throws -> CursorState? {
        // lstat + Data(contentsOf:) would leave a pathname race in which a
        // checked regular file could be replaced by a symlink before the read.
        // Open once without following the final component, then validate and
        // consume bytes through that same descriptor.
        let descriptor = fileURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw CollectionStateFailure.unreadableState(
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
            throw CollectionStateFailure.unreadableState(
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
                    throw CollectionStateFailure.unreadableState(
                        path: fileURL.path,
                        detail: "cursor state grew beyond the maximum cursor-state byte limit while reading")
                }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw CollectionStateFailure.unreadableState(
                    path: fileURL.path, detail: String(cString: strerror(errno)))
            }
        }

        do {
            return try JSONDecoder().decode(CursorState.self, from: data)
        } catch {
            throw CollectionStateFailure.corruptLegacyCursor(
                path: fileURL.path, detail: String(describing: error))
        }
    }

    public func save(_ state: CursorState) throws {
        guard state.cursors.count <= Self.maximumCursorCount else {
            throw CollectionStateFailure.unreadableState(
                path: fileURL.path,
                detail: "cursor state exceeds the maximum tracked cursor count (\(Self.maximumCursorCount))")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumCursorStateBytes else {
            throw CollectionStateFailure.unreadableState(
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
            throw CollectionStateFailure.unreadableState(
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
            throw CollectionStateFailure.unreadableState(
                path: fileURL.path, detail: "saved cursor is not a regular owned file with link count one")
        }
    }
}

public struct TranscriptFile: Sendable, Equatable {
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
public enum TranscriptScanResult: Sendable, Equatable {
    /// The whole tree was listed successfully.
    case complete([TranscriptFile])
    /// The scan root does not exist, so nothing can be proven stale.
    case absent
    /// At least one directory could not be listed; `files` is what was
    /// visible, and every stored cursor must survive this poll.
    case partial(files: [TranscriptFile], errors: [String])

    public var files: [TranscriptFile] {
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
public struct TranscriptScanner {
    public let root: URL
    /// A walk that stops at a budget is partial, never complete: a short list
    /// cannot prove that an unlisted file was deleted.
    public let maxScannedFiles: Int
    public let maxVisitedEntries: Int

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .fileSizeKey, .creationDateKey, .contentModificationDateKey,
    ]

    public init(root: URL, maxScannedFiles: Int = 4_096,
                maxVisitedEntries: Int = 16_384) {
        self.root = URL(
            fileURLWithPath: TranscriptPathAccess.canonicalPath(root.path),
            isDirectory: true)
        self.maxScannedFiles = max(0, maxScannedFiles)
        self.maxVisitedEntries = max(0, maxVisitedEntries)
    }

    /// A lazy directory iterator. `FileManager.contentsOfDirectory` reads
    /// the whole directory — entries and their attribute fetches — into an
    /// array before a single one can be charged to the scan budget, so the
    /// budgets only bounded the walk over an already-allocated array, not
    /// the read itself. readdir yields one entry at a time: when the budget
    /// stops the walk, the listing stops with it. Hidden entries (leading
    /// dot, including `.` and `..`) are never produced, matching the
    /// `.skipsHiddenFiles` behavior this replaces.
    ///
    /// Deliberately an `IteratorProtocol` and not a `Sequence`: an open
    /// directory handle is a one-shot stream. A exhausted iterator returns
    /// nil forever, so there is no "second iteration reads as a complete
    /// scan of an empty directory" shape to trip over.
    private final class DirectoryEntries: IteratorProtocol {
        /// Set when the directory could not be opened, or when a readdir
        /// failed mid-stream. Absence is `POSIXError(.ENOENT)`; each layer
        /// decides whether that is normal for it.
        private(set) var error: Error?

        private var dirp: UnsafeMutablePointer<DIR>?
        private let directory: URL

        init(_ directory: URL) {
            self.directory = directory
            guard let handle = opendir(directory.path) else {
                error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                return
            }
            dirp = handle
        }

        deinit {
            if let dirp { closedir(dirp) }
        }

        func next() -> URL? {
            guard let dirp, error == nil else { return nil }
            while true {
                errno = 0
                guard let entry = readdir(dirp) else {
                    if errno != 0 {
                        error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    return nil
                }
                var record = entry.pointee
                let name = withUnsafeBytes(of: &record.d_name) { buffer in
                    String(cString: buffer.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                guard !name.hasPrefix(".") else { continue }
                return directory.appendingPathComponent(name)
            }
        }
    }

    public func scan() -> TranscriptScanResult {
        let rootDirectoryFD: Int32
        do {
            rootDirectoryFD = try TranscriptPathAccess.openDirectoryPathNoFollow(root.path)
        } catch {
            if isNoSuchFileError(error) { return .absent }
            return .partial(
                files: [], errors: ["cannot safely open scan root \(root.path): \(error)"])
        }
        defer { Darwin.close(rootDirectoryFD) }

        let projectIterator = DirectoryEntries(root)
        if let openError = projectIterator.error {
            if isNoSuchFileError(openError) { return .absent }
            return .partial(
                files: [], errors: ["cannot list \(root.path): \(openError)"])
        }

        var errors: [String] = []
        var visitedEntries = 0
        var budgetError: String?
        func chargeEntry() -> Bool {
            visitedEntries += 1
            guard visitedEntries <= maxVisitedEntries else {
                budgetError = "scan entry budget exceeded (\(maxVisitedEntries)); "
                    + "remaining directories were not walked"
                return false
            }
            return true
        }

        var files: [TranscriptFile] = []
        projectLoop: while let project = projectIterator.next() {
            guard chargeEntry() else { break }
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
            let childIterator = DirectoryEntries(project)
            if let openError = childIterator.error {
                errors.append("cannot list \(project.path): \(openError)")
                continue
            }
            while let child = childIterator.next() {
                guard chargeEntry() else { break projectLoop }
                guard files.count < maxScannedFiles else {
                    budgetError = "scan file budget exceeded (\(maxScannedFiles)); "
                        + "remaining files were not walked"
                    break projectLoop
                }
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

                    let agentIterator: DirectoryEntries
                    do {
                        let subagentValues = try subagents.resourceValues(
                            forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        // The directory entry itself must be a real directory.
                        // A symlink is never opened even if its target is one.
                        guard subagentValues.isDirectory == true,
                              subagentValues.isSymbolicLink != true else {
                            continue
                        }
                        agentIterator = DirectoryEntries(subagents)
                    } catch {
                        if !isNoSuchFileError(error) {
                            errors.append("cannot list \(subagents.path): \(error)")
                        }
                        continue
                    }
                    if let openError = agentIterator.error {
                        if !isNoSuchFileError(openError) {
                            errors.append("cannot list \(subagents.path): \(openError)")
                        }
                        continue
                    }
                    // Main files and subagent files spend the same two
                    // budgets: every surfaced entry is charged and the file
                    // cap is rechecked, exactly like the session layer above.
                    while let agent = agentIterator.next() {
                        guard chargeEntry() else { break projectLoop }
                        guard files.count < maxScannedFiles else {
                            budgetError = "scan file budget exceeded (\(maxScannedFiles)); "
                                + "remaining files were not walked"
                            break projectLoop
                        }
                        guard agent.pathExtension == "jsonl" else { continue }
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
                    if let readError = agentIterator.error {
                        errors.append("cannot list \(subagents.path): \(readError)")
                    }
                }
            }
            if let readError = childIterator.error {
                errors.append("cannot list \(project.path): \(readError)")
            }
        }
        if let readError = projectIterator.error {
            errors.append("cannot list \(root.path): \(readError)")
        }

        if let budgetError { errors.append(budgetError) }
        let sorted = files.sorted { $0.path < $1.path }
        return errors.isEmpty ? .complete(sorted) : .partial(files: sorted, errors: errors)
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
    ) -> TranscriptFile? {
        do {
            let relative = try TranscriptPathAccess.relativePath(url.path, under: root)
            let opened = try TranscriptPathAccess.openFile(
                rootDirectoryFD: rootDirectoryFD, relativePath: relative)
            defer { Darwin.close(opened.descriptor) }
            return TranscriptFile(
                path: url.path, projectID: projectID, sessionID: sessionID,
                isSubagent: isSubagent, size: opened.size, inode: opened.inode,
                creationDate: opened.creationDate, modificationDate: opened.modificationDate)
        } catch {
            return nil
        }
    }
}

public struct PollReport: Sendable, Equatable {
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
    /// The poll stopped because its poll-wide byte or event budget ran out.
    /// The cursors that were not reached stay where they are; the next poll
    /// continues from them.
    public var budgetExhausted = false
    /// The walk saw the whole root. False when it stopped at a scan budget, and
    /// then no cursor may be retired as "deleted".
    public var scanComplete = true
    public var errors: [String] = []

    public init() {}
}

/// 首次见到一个文件时怎么处理。
///
/// `skipExisting` 是历史默认：启用前就存在的文件基线与 EOF，永不回溯——
/// 宁可漏采也不把用户既有对话偷偷读进来。
/// `readExisting` 是「采集桥」的语义：选了目录就把该目录已有的会话采进来。
/// 两者都只影响**没有游标**的文件；有游标的文件照旧增量 tail。
public enum BaselinePolicy: String, Sendable, Equatable, Codable {
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
public final class TranscriptTailer {
    public typealias Sink = ([CollectionEvent]) throws -> Void

    public let scanRoot: URL
    public let baselinePolicy: BaselinePolicy
    public let maxBytesPerPoll: Int
    public let maxLineBytes: Int
    /// Events handed to the sink in one poll. The runner stages them in memory
    /// before committing, so this is the bound on that staging buffer. The
    /// check applies per line inside a file's read too, so one file cannot
    /// flood the staging buffer between the file-boundary checks.
    public let maxEventsPerPoll: Int
    public let maxScannedFiles: Int
    public let maxVisitedEntries: Int

    private let scanner: TranscriptScanner
    private var state: CursorState
    private var accumulators: [String: TurnAccumulator] = [:]
    /// Fair rotation: files processed least recently go first, so a budget that
    /// only covers part of the tree still visits every file over a few polls.
    private var lastVisit: [String: UInt64] = [:]
    private var visitClock: UInt64 = 0
    /// Progress inside a single line too long to scan in one poll. The scan is
    /// not a read the cursor can carry, so it is remembered here and continued
    /// by the next poll; a restart simply re-scans from the line start.
    /// `window` is the first read window of that line, which is what a
    /// too-long line is dropped by.
    private var oversizedScan: [String: (scanned: Int64, window: Int)] = [:]

    /// Deterministic post-read fingerprint fault injection for package tests.
    /// Production callers leave this nil and use descriptor-backed reads.
    var trailingFingerprintOverride: ((String, Int64, UInt64) -> String?)?

    public init(
        scanRoot: URL,
        state: CursorState? = nil,
        now: Date = Date(),
        baselinePolicy: BaselinePolicy = .skipExisting,
        maxBytesPerPoll: Int = 4 << 20,
        maxLineBytes: Int = 32 << 20,
        maxEventsPerPoll: Int = 20_000,
        maxScannedFiles: Int = 4_096,
        maxVisitedEntries: Int = 16_384
    ) {
        let canonicalRoot = URL(
            fileURLWithPath: TranscriptPathAccess.canonicalPath(scanRoot.path),
            isDirectory: true)
        self.scanRoot = canonicalRoot
        self.baselinePolicy = baselinePolicy
        self.scanner = TranscriptScanner(
            root: canonicalRoot, maxScannedFiles: maxScannedFiles,
            maxVisitedEntries: maxVisitedEntries)
        self.maxBytesPerPoll = maxBytesPerPoll
        self.maxLineBytes = maxLineBytes
        self.maxEventsPerPoll = maxEventsPerPoll
        self.maxScannedFiles = maxScannedFiles
        self.maxVisitedEntries = maxVisitedEntries
        self.state = state ?? CursorState(initializedAt: now)
    }

    public var cursorState: CursorState { state }

    public func poll(sink: Sink) -> PollReport {
        var report = PollReport()
        // A cursor is only meaningful under the policy that produced it: after
        // `skip_existing` parks a file at EOF, `read_existing` must not inherit
        // that position, or "选目录即采集既有会话" would silently collect nothing.
        if state.policy != baselinePolicy.rawValue {
            state.cursors.removeAll()
            accumulators.removeAll()
            // A scan position belongs to the file identity that produced it, so
            // it cannot survive a policy change any more than a cursor can.
            oversizedScan.removeAll()
            state.policy = baselinePolicy.rawValue
            report.stateChanged = true
        }
        let scan = scanner.scan()
        // Least-recently-visited first, then path order: with a poll budget that
        // covers only part of the tree, the next poll starts where this one
        // stopped instead of re-reading the same head every time.
        let files = scan.files.sorted { lhs, rhs in
            let left = lastVisit[lhs.path] ?? 0
            let right = lastVisit[rhs.path] ?? 0
            if left != right { return left < right }
            return lhs.path < rhs.path
        }
        report.scannedFiles = files.count
        report.errors.append(contentsOf: scan.errors)
        report.scanComplete = scan.isComplete
        // Everything the walk saw is live, including files this poll's budget
        // did not reach: a file that exists but was not read has not been
        // deleted, and retiring its cursor would replay it from the start.
        let livePaths = Set(files.map(\.path))
        var budget = max(0, maxBytesPerPoll)

        for file in files {
            if budget <= 0 || report.deliveredEvents >= maxEventsPerPoll {
                report.budgetExhausted = true
                break
            }
            lastVisit[file.path] = visitClock
            visitClock &+= 1
            var events: [CollectionEvent] = []
            var nextCursor: FileCursor
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
                            oversizedScan.removeValue(forKey: file.path)
                            continue
                        }
                        if file.size > existing.offset
                            || (accumulators[file.path] == nil && disposition == .replay)
                        {
                            // A cold tailer with an open turn rewinds to the
                            // anchor even when no new bytes arrived, so recovery
                            // happens at start rather than at the next append.
                            let consumed = readAvailable(
                                file, cursor: &existing, events: &events,
                                budget: &budget, report: &report)
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
                            BaselineEvent(
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
                        fingerprint: SourceDigest.sha256Hex(Data()))
                    _ = readAvailable(
                        file, cursor: &cursor, events: &events,
                        budget: &budget, report: &report)
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
        _ file: TranscriptFile, reason: BaselineEvent.Reason,
        events: inout [CollectionEvent], report: inout PollReport
    ) -> FileCursor? {
        guard
            let fingerprint = trailingFingerprint(
            path: file.path, offset: file.size, expectedInode: file.inode)
        else {
            report.errors.append("cannot fingerprint \(file.path)")
            return nil
        }
        accumulators.removeValue(forKey: file.path)
        // The scan position describes a line of the file that was just
        // re-identified. Keeping it would let the next append resume mid-way
        // through content that no longer shares that prefix.
        oversizedScan.removeValue(forKey: file.path)
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
                BaselineEvent(
                    path: file.path, projectID: file.projectID,
                    sessionID: file.sessionID, isSubagent: file.isSubagent,
                    offset: file.size, reason: reason)))
        return makeCursor(
            file, offset: file.size, segmentLines: 0, fingerprint: fingerprint)
    }

    private func makeCursor(
        _ file: TranscriptFile, offset: Int64, segmentLines: Int64,
        fingerprint: String
    ) -> FileCursor {
        FileCursor(
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
    private func resumeDisposition(_ cursor: FileCursor) -> ResumeDisposition {
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
        guard let byte = try? TranscriptPathAccess.read(
            descriptor: opened.descriptor, offset: offset - 1, count: 1) else { return false }
        return byte == Data([0x0A])
    }

    private func accumulator(for file: TranscriptFile) -> TurnAccumulator {
        if let existing = accumulators[file.path] { return existing }
        let accumulator = TurnAccumulator(
            context: TurnAccumulator.Context(
                projectID: file.projectID, sessionID: file.sessionID,
                path: file.path, isSubagent: file.isSubagent))
        accumulators[file.path] = accumulator
        return accumulator
    }

    /// Reads complete lines only, at most the poll's remaining byte budget.
    /// Returns true when the cursor moved.
    ///
    /// When no in-memory accumulator exists and the cursor still points at an
    /// open turn's anchor, reading starts there instead of at `offset`, so a
    /// restart rebuilds the unfinished turn from the transcript. A sink failure
    /// drops the accumulator, which routes the next poll through the same
    /// replay path and keeps an open turn from being orphaned mid-answer.
    private func readAvailable(
        _ file: TranscriptFile, cursor: inout FileCursor,
        events: inout [CollectionEvent], budget: inout Int,
        report: inout PollReport
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
        guard budget > 0 else {
            report.budgetExhausted = true
            return false
        }
        if oversizedScan[file.path] != nil, working.offset == cursor.offset {
            // The same oversized line is still being scanned. Its already
            // scanned prefix is known to hold no newline, so this poll spends
            // its whole budget on the search instead of re-reading that prefix.
            let moved = skipOversizedLine(
                file, cursor: &working, available: available, partialBytes: 0,
                budget: &budget, events: &events, report: &report)
            cursor = working
            return moved
        }
        let opened: TranscriptPathAccess.OpenedFile
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
            data = try TranscriptPathAccess.read(
                descriptor: opened.descriptor, offset: working.offset,
                count: Int(min(available, Int64(budget))))
            guard !data.isEmpty else { return false }
        } catch {
            report.errors.append("read failed for \(file.path): \(error)")
            return false
        }
        budget -= data.count

        if replaying {
            report.replayedBytes += min(
                Int64(data.count), committedOffset - working.offset)
        }

        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            let moved = skipOversizedLine(
                file, cursor: &working, available: available, partialBytes: data.count,
                budget: &budget, events: &events, report: &report)
            cursor = working
            return moved
        }

        let content = data[data.startIndex..<lastNewline]
        let windowStart = working.offset
        // Preserve only events that predate this read (notably a first-seen
        // baseline). Read-derived candidates are provisional until the source
        // path still resolves to the pinned inode after parsing.
        let readDerivedEventStart = events.count

        var lineCount: Int64 = 0
        var parsedBytes = 0
        var start = content.startIndex
        while true {
            // The runner stages every event of a poll in memory before its
            // durable commit, so the event budget has to bind inside one
            // file's read as well: a file whose parse floods events stops
            // mid-window and the next poll resumes from the parsed position.
            // Crossing the cap by one line's events is the price of parsing
            // in whole lines.
            if report.deliveredEvents + events.count >= maxEventsPerPoll {
                report.budgetExhausted = true
                break
            }
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
                            ParseFailure(
                                path: file.path, sessionID: file.sessionID,
                                segmentLine: segmentLine,
                                detail: "line exceeds \(maxLineBytes) bytes")))
                } else {
                    do {
                        let entry = try TranscriptLineParser.parse(Data(line))
                        events.append(
                            contentsOf: accumulator(for: file).ingest(
                                entry, segmentLine: segmentLine))
                    } catch {
                        report.parseFailures += 1
                        events.append(
                            .parseFailure(
                                ParseFailure(
                                    path: file.path, sessionID: file.sessionID,
                                    segmentLine: segmentLine,
                                    detail: String(describing: error))))
                    }
                }
            }
            advanceResume(
                &working, file: file, segmentLine: segmentLine,
                lineStart: lineStart, lineEnd: lineEnd)
            parsedBytes = content.distance(from: content.startIndex, to: end) + 1
            if end == content.endIndex { break }
            start = content.index(after: end)
        }

        // A budget stop leaves the rest of the window unparsed: those bytes
        // stay behind the cursor and are re-read (and re-charged) by the next
        // poll, so `readBytes` counts what the cursor consumed, like the
        // complete-window case where it equals `consumed`.
        guard parsedBytes > 0 else { return false }
        let newOffset = windowStart + Int64(parsedBytes)
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
            oversizedScan.removeValue(forKey: file.path)
            return false
        }
        working.offset = newOffset
        working.segmentLines += lineCount
        working.fingerprint = fingerprint
        working.updatedAt = Date()
        cursor = working
        report.readFiles += 1
        report.readBytes += Int64(parsedBytes)
        return true
    }

    /// A single line longer than one poll window would otherwise stall the
    /// file forever. Search for its newline up to `maxLineBytes`, spending the
    /// poll's remaining byte budget on the scan as well: the search reads the
    /// same disk the tail reads. When the budget ends mid-line, the scan
    /// position is remembered for the next poll; past `maxLineBytes`, one
    /// window is dropped with a parse failure so the stream still progresses.
    private func skipOversizedLine(
        _ file: TranscriptFile, cursor: inout FileCursor, available: Int64,
        partialBytes: Int, budget: inout Int,
        events: inout [CollectionEvent],
        report: inout PollReport
    ) -> Bool {
        let lineStart = cursor.offset
        let pending = oversizedScan[file.path]
        // A line that stops at the end of the file is incomplete, not
        // oversized: more bytes may still arrive, and re-reading from the line
        // start is exactly what parses it once they do. Only a line that
        // continues past what this poll could read is handled as too long.
        guard pending != nil || available > Int64(partialBytes) else {
            return false
        }
        // The window just read was itself searched for a newline and had none,
        // so its bytes count as scanned; a resumed scan picks up where the
        // previous poll stopped instead of re-reading that prefix.
        let alreadyScanned = (pending?.scanned ?? 0) + Int64(partialBytes)
        let window = pending?.window ?? max(partialBytes, 1)
        let lineAllowance = max(0, Int64(maxLineBytes) - alreadyScanned)
        let scanLimit = min(lineAllowance, Int64(max(0, budget)))
        var scanned: Int64 = 0
        var charged: Int64 = 0
        var afterNewline: Int64?
        if scanLimit > 0 {
            let found = findNewline(
                path: file.path, from: lineStart + alreadyScanned,
                limit: scanLimit, expectedInode: file.inode)
            afterNewline = found.position
            scanned = found.scanned
            charged = found.charged
            budget -= Int(charged)
        }
        if let afterNewline {
            oversizedScan.removeValue(forKey: file.path)
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
            // Bytes actually read this poll: the window plus the scan.
            report.readBytes += Int64(partialBytes) + charged
            events.append(
                .parseFailure(
                    ParseFailure(
                        path: file.path, sessionID: file.sessionID,
                        segmentLine: cursor.segmentLines,
                        detail: "line exceeds poll window")))
            return true
        }
        if alreadyScanned + scanned >= Int64(maxLineBytes) {
            oversizedScan.removeValue(forKey: file.path)
            let advance = min(Int64(window), available)
            guard advance > 0 else { return false }
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
            report.readBytes += Int64(partialBytes) + charged
            events.append(
                .parseFailure(
                    ParseFailure(
                        path: file.path, sessionID: file.sessionID,
                        segmentLine: cursor.segmentLines,
                        detail: "line exceeds \(maxLineBytes) bytes; window dropped")))
            return true
        }
        oversizedScan[file.path] = (alreadyScanned + scanned, window)
        if budget <= 0 { report.budgetExhausted = true }
        return false
    }

    /// Moves the replay floor: a newly opened anchor pins it to that line's
    /// start; outside any turn it advances past the consumed line.
    private func advanceResume(
        _ cursor: inout FileCursor, file: TranscriptFile,
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
    ) throws -> TranscriptPathAccess.OpenedFile {
        let rootFD = try TranscriptPathAccess.openDirectoryPathNoFollow(scanRoot.path)
        defer { Darwin.close(rootFD) }
        let relative = try TranscriptPathAccess.relativePath(path, under: scanRoot)
        return try TranscriptPathAccess.openFile(
            rootDirectoryFD: rootFD, relativePath: relative, expectedInode: expectedInode)
    }

    private func findNewline(
        path: String, from offset: Int64, limit: Int64, expectedInode: UInt64
    ) -> (position: Int64?, scanned: Int64, charged: Int64) {
        guard offset >= 0, limit >= 0,
              let opened = try? openTranscriptFile(path: path, expectedInode: expectedInode)
        else { return (nil, 0, 0) }
        defer { Darwin.close(opened.descriptor) }
        var scanned: Int64 = 0
        // Bytes actually taken off disk. A chunk whose newline lands early is
        // still read in full, so this is what the poll budget must be charged:
        // charging `scanned` instead would leave the next file a budget larger
        // than the disk work that remains.
        var charged: Int64 = 0
        while scanned < limit {
            let count = Int(min(1 << 20, limit - scanned))
            guard let chunk = try? TranscriptPathAccess.read(
                descriptor: opened.descriptor, offset: offset + scanned, count: count),
                !chunk.isEmpty else { return (nil, scanned, charged) }
            charged += Int64(chunk.count)
            if let newline = chunk.firstIndex(of: 0x0A) {
                let found = Int64(chunk.distance(from: chunk.startIndex, to: newline)) + 1
                return (offset + scanned + found, scanned + found, charged)
            }
            scanned += Int64(chunk.count)
        }
        return (nil, scanned, charged)
    }

    private func trailingFingerprint(
        path: String, offset: Int64, expectedInode: UInt64
    ) -> String? {
        if let trailingFingerprintOverride {
            return trailingFingerprintOverride(path, offset, expectedInode)
        }
        guard offset >= 0 else { return nil }
        if offset == 0 { return SourceDigest.sha256Hex(Data()) }
        let window: Int64 = 256
        let start = max(0, offset - window)
        guard let opened = try? openTranscriptFile(path: path, expectedInode: expectedInode)
        else { return nil }
        defer { Darwin.close(opened.descriptor) }
        guard let data = try? TranscriptPathAccess.read(
            descriptor: opened.descriptor, offset: start, count: Int(offset - start)),
            data.count == Int(offset - start) else { return nil }
        return SourceDigest.sha256Hex(data)
    }

    private func deliver(
        _ file: TranscriptFile, events: [CollectionEvent], sink: Sink,
        report: inout PollReport
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
