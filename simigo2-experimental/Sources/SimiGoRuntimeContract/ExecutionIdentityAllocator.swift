import Foundation

/// Runtime-side seam for durable `ExecutionID` acquisition. A host may inject
/// an in-memory implementation for stateless tests; production injects the
/// durable allocator below.
public protocol ExecutionIdentityReserving: Sendable {
    /// Returns the reservation already stored for `token`, otherwise durably
    /// reserves `requestedID` (or allocates a new ID). The operation is
    /// idempotent for the same token so a crash after ledger commit can retry.
    func reserve(token: String, requestedID: ExecutionID?) throws -> ExecutionID

    func hasReserved(_ id: ExecutionID) -> Bool
}

public enum ExecutionIdentityAllocatorError: Error, Equatable {
    case emptyToken
    case ledgerCorrupt(path: String, line: Int)
    case executionIDReserved(token: String, requestedID: ExecutionID, existingToken: String)
}

/// JSON-lines allocator with one idempotent reservation per operation token.
/// Each committed line is fsynced before the in-memory reservation becomes
/// visible; a torn tail fails closed on the next open instead of being skipped.
///
/// ponytail: exclusive `flock` supports process-crash recovery, not a
/// multi-host allocator; add a real coordination service if that becomes a need.
public final class DurableExecutionIdentityAllocator: ExecutionIdentityReserving, @unchecked Sendable {
    struct Reservation: Codable, Equatable {
        let token: String
        let executionID: String
        let createdAt: Date
    }

    enum AllocatorError: Error {
        case lockFailed(errno: Int32)
    }

    private let ledgerURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var reservationsByToken: [String: Reservation] = [:]
    private var reservationsByID: [String: Reservation] = [:]
    private var ledgerHandle: FileHandle?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.ledgerURL = directory.appendingPathComponent("execution-ids.jsonl")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.encoder = encoder
        self.decoder = decoder
        try loadLocked()
    }

    deinit {
        try? ledgerHandle?.close()
    }

    @discardableResult
    public func reserve(token: String, requestedID: ExecutionID?) throws -> ExecutionID {
        guard !token.isEmpty else {
            throw ExecutionIdentityAllocatorError.emptyToken
        }

        lock.lock()
        defer { lock.unlock() }
        if let existing = reservationsByToken[token] {
            let id = ExecutionID(existing.executionID)
            if let requestedID, id != requestedID {
                throw ExecutionIdentityAllocatorError.executionIDReserved(
                    token: token, requestedID: requestedID, existingToken: token)
            }
            return id
        }

        if let requestedID,
            let existing = reservationsByID[requestedID.rawValue] {
            throw ExecutionIdentityAllocatorError.executionIDReserved(
                token: token, requestedID: requestedID, existingToken: existing.token)
        }

        let id = requestedID ?? ExecutionID(UUID().uuidString)
        let reservation = Reservation(
            token: token, executionID: id.rawValue, createdAt: Date())
        try appendLocked(reservation)
        reservationsByToken[token] = reservation
        reservationsByID[id.rawValue] = reservation
        return id
    }

    public func hasReserved(_ id: ExecutionID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return reservationsByID[id.rawValue] != nil
    }

    public func reservation(forToken token: String) -> ExecutionID? {
        lock.lock()
        defer { lock.unlock() }
        return reservationsByToken[token].map { ExecutionID($0.executionID) }
    }

    private func loadLocked() throws {
        guard fileManager.fileExists(atPath: ledgerURL.path) else { return }
        let data = try Data(contentsOf: ledgerURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExecutionIdentityAllocatorError.ledgerCorrupt(
                path: ledgerURL.path, line: 1)
        }
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: true)
            .enumerated() {
            let reservation: Reservation
            do {
                reservation = try decoder.decode(
                    Reservation.self, from: Data(line.utf8))
            } catch {
                throw ExecutionIdentityAllocatorError.ledgerCorrupt(
                    path: ledgerURL.path, line: offset + 1)
            }
            guard reservationsByToken[reservation.token] == nil,
                reservationsByID[reservation.executionID] == nil
            else {
                throw ExecutionIdentityAllocatorError.ledgerCorrupt(
                    path: ledgerURL.path, line: offset + 1)
            }
            reservationsByToken[reservation.token] = reservation
            reservationsByID[reservation.executionID] = reservation
        }
        ledgerHandle = try FileHandle(forWritingTo: ledgerURL)
    }

    private func appendLocked(_ reservation: Reservation) throws {
        let handle: FileHandle
        if let ledgerHandle {
            handle = ledgerHandle
        } else {
            fileManager.createFile(atPath: ledgerURL.path, contents: nil)
            handle = try FileHandle(forWritingTo: ledgerURL)
            ledgerHandle = handle
        }

        try acquireExclusiveLock(handle)
        defer { flock(handle.fileDescriptor, LOCK_UN) }
        let record = try encoder.encode(reservation) + Data("\n".utf8)
        let startOffset = try handle.seekToEnd()
        do {
            try handle.write(contentsOf: record)
            try handle.synchronize()
        } catch {
            // A short/torn append must never turn into a permanent corrupt
            // ledger just because a later retry appends another line.
            try? handle.truncate(atOffset: startOffset)
            try? handle.synchronize()
            throw error
        }
    }

    private func acquireExclusiveLock(_ handle: FileHandle) throws {
        let result = flock(handle.fileDescriptor, LOCK_EX)
        guard result == 0 else {
            throw AllocatorError.lockFailed(errno: errno)
        }
    }
}
