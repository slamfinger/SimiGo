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
/// Cross-process arbitration: the in-memory maps only know what THIS process
/// appended, so they are advisory. The on-disk ledger under the exclusive
/// flock is authoritative — every append re-reads and re-checks it before
/// committing, so two processes that both raced past stale views still commit
/// at most one reservation per token or ID. Without the re-check, a requested
/// ID claimed concurrently by two processes would be double-committed and the
/// ledger would fail closed as corrupt on the next open.
///
/// ponytail: the append-time full ledger re-read is O(total) per reservation;
/// scan only the tail appended since this process's last known offset if
/// ledger volume ever makes that cost real.
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

    /// Number of durably committed reservations visible to this view. A clean
    /// open proves the ledger is duplicate-free, so this is also the number of
    /// unique reserved IDs.
    public var reservationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reservationsByID.count
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
        let committed = try appendLocked(reservation, requestedID: requestedID)
        reservationsByToken[committed.token] = committed
        reservationsByID[committed.executionID] = committed
        return ExecutionID(committed.executionID)
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
        let reservations = try decodeLedger(try Data(contentsOf: ledgerURL))
        for reservation in reservations {
            reservationsByToken[reservation.token] = reservation
            reservationsByID[reservation.executionID] = reservation
        }
        ledgerHandle = try FileHandle(forWritingTo: ledgerURL)
    }

    /// Decode the whole ledger; a malformed or duplicated line fails closed.
    private func decodeLedger(_ data: Data) throws -> [Reservation] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExecutionIdentityAllocatorError.ledgerCorrupt(path: ledgerURL.path, line: 1)
        }
        var byToken: [String: Reservation] = [:]
        var byID: [String: Reservation] = [:]
        var reservations: [Reservation] = []
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
            guard byToken[reservation.token] == nil,
                byID[reservation.executionID] == nil
            else {
                throw ExecutionIdentityAllocatorError.ledgerCorrupt(
                    path: ledgerURL.path, line: offset + 1)
            }
            byToken[reservation.token] = reservation
            byID[reservation.executionID] = reservation
            reservations.append(reservation)
        }
        return reservations
    }

    /// Append `reservation` under the exclusive flock and return the
    /// authoritative reservation: either the freshly appended one, or the
    /// already-committed reservation for the same token (another process won
    /// the race while this handle was open — the committed identity wins over
    /// a locally generated one, matching crash-retry idempotency, unless the
    /// caller explicitly demanded a different ID). A requested ID some other
    /// process already committed throws instead of double-committing: the
    /// ledger is re-read under the lock, so stale in-memory views cannot
    /// split identity.
    private func appendLocked(
        _ reservation: Reservation, requestedID: ExecutionID?
    ) throws -> Reservation {
        let handle: FileHandle
        if let ledgerHandle {
            handle = ledgerHandle
        } else {
            // createFile truncates an existing file, and another view or
            // process may have committed lines since this allocator opened:
            // only create the ledger when it is genuinely absent.
            if !fileManager.fileExists(atPath: ledgerURL.path) {
                fileManager.createFile(atPath: ledgerURL.path, contents: nil)
            }
            handle = try FileHandle(forWritingTo: ledgerURL)
            ledgerHandle = handle
        }

        try acquireExclusiveLock(handle)
        defer { flock(handle.fileDescriptor, LOCK_UN) }
        let committed = try decodeLedger(try Data(contentsOf: ledgerURL))
        for entry in committed {
            reservationsByToken[entry.token] = entry
            reservationsByID[entry.executionID] = entry
        }
        if let existing = committed.first(where: { $0.token == reservation.token }) {
            if let requestedID, ExecutionID(existing.executionID) != requestedID {
                throw ExecutionIdentityAllocatorError.executionIDReserved(
                    token: reservation.token,
                    requestedID: requestedID,
                    existingToken: existing.token)
            }
            return existing
        }
        if let existing = committed.first(where: { $0.executionID == reservation.executionID }) {
            throw ExecutionIdentityAllocatorError.executionIDReserved(
                token: reservation.token,
                requestedID: ExecutionID(reservation.executionID),
                existingToken: existing.token)
        }
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
        return reservation
    }

    private func acquireExclusiveLock(_ handle: FileHandle) throws {
        let result = flock(handle.fileDescriptor, LOCK_EX)
        guard result == 0 else {
            throw AllocatorError.lockFailed(errno: errno)
        }
    }
}
