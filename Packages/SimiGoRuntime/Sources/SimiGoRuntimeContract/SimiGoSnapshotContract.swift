import Foundation

/// C-stage as-of snapshot primitives: immutable `declared` / `final` encoding,
/// capacity limits, the `used ⊆ declared` contract, and the `replayable`
/// conjunction.
///
/// This type is pure: it performs no I/O, owns no database, and never writes.
/// The S and P2 phases call it to produce bytes; object storage (write-once
/// `is_objects`, content-addressed by SHA-256) remains the only persistence.
///
/// Contract boundaries (owner rulings O1–O3):
///   * a public error code is not an internal refusal reason — the codes emitted
///     here are internal and are mapped to the entry's existing failure class;
///   * replayability is not "a digest was saved" — it is the conjunction below;
///   * a zero reference count is not deletion authorization — nothing here deletes.
public enum SimiGoSnapshotContract {

    public static let schemaVersion = "c-snapshot-v1"
    public static let canonicalVersion = "c-snapshot-v1"
    public static let digestAlgorithm = "sha256"

    /// All raw input bytes that must be embedded in one declared snapshot.
    /// Engineering limit for v1; both limits are fail-closed, never truncated.
    public static let embeddedRawByteLimit = 32 * 1024 * 1024
    /// One serialized snapshot object, inclusive of base64 and metadata. Applies
    /// to both `declared` (phase S) and `final` (phase P2).
    public static let serializedObjectByteLimit = 48 * 1024 * 1024

    // MARK: - Errors

    /// Internal diagnostics only. `code` must never be projected verbatim into
    /// an HTTP response (ruling O1); callers map it onto the entry's own class.
    public struct SnapshotError: Error, Sendable, Equatable, LocalizedError {
        public let code: String
        public let phase: String
        public let detail: String

        public init(code: String, phase: String, detail: String) {
            self.code = code
            self.phase = phase
            self.detail = detail
        }

        public var errorDescription: String? { "\(code) [\(phase)] \(detail)" }

        static func unrepresentable(phase: String, detail: String) -> SnapshotError {
            SnapshotError(code: "snapshot_unrepresentable", phase: phase, detail: detail)
        }
        static func fieldInvalid(phase: String, _ detail: String) -> SnapshotError {
            SnapshotError(code: "snapshot_field_invalid", phase: phase, detail: detail)
        }
        static func schemaUnknown(_ version: String, phase: String) -> SnapshotError {
            SnapshotError(code: "snapshot_schema_unknown", phase: phase, detail: "unknown version \(version)")
        }
        static func partUnknown(_ part: String, phase: String) -> SnapshotError {
            SnapshotError(code: "snapshot_part_unknown", phase: phase, detail: "unknown part \(part)")
        }
        static func digestMismatch(_ field: String, phase: String) -> SnapshotError {
            SnapshotError(code: "snapshot_digest_mismatch", phase: phase, detail: "\(field) does not match its content")
        }
        static func usedUndeclared(_ identifiers: [String], phase: String) -> SnapshotError {
            SnapshotError(code: "snapshot_used_undeclared", phase: phase,
                          detail: "used inputs outside the declared set: \(identifiers.sorted().joined(separator: ","))")
        }
        static func usedMismatch(_ identifiers: [String], phase: String) -> SnapshotError {
            SnapshotError(code: "snapshot_used_mismatch", phase: phase,
                          detail: "used digest differs from declared version: \(identifiers.sorted().joined(separator: ","))")
        }
        static func replayableMismatch(phase: String, detail: String) -> SnapshotError {
            SnapshotError(code: "snapshot_replayable_mismatch", phase: phase, detail: detail)
        }
    }

    // MARK: - Digests and canonical encoding

    public static func sha256Hex(_ data: Data) -> String {
        NativeSHA256.hexDigest(data)
    }

    static func isValidDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    static func canonicalJSON(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw SnapshotError.fieldInvalid(phase: "encode", "object is not representable JSON")
        }
        do {
            return try JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw SnapshotError.fieldInvalid(phase: "encode", "canonical serialization failed")
        }
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func parseTimestamp(_ value: String, phase: String) throws -> Date {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        throw SnapshotError.fieldInvalid(phase: phase, "unparseable timestamp \(value)")
    }

    // MARK: - Identity

    /// `(kind, 标识)` is the only join key allowed between `declared` and `used`.
    /// A file is identified by its root plus its normalized relative path, never
    /// by path alone — two roots may expose the same relative path.
    public struct SourceIdentity: Hashable, Sendable, CustomStringConvertible {
        public enum Kind: String, Sendable {
            case file
            case settlement
        }

        public let kind: Kind
        public let identifier: String

        public init(kind: Kind, identifier: String) {
            self.kind = kind
            self.identifier = identifier
        }

        public static func file(rootID: String, relativePath: String) -> SourceIdentity {
            SourceIdentity(kind: .file, identifier: "file:" + rootID + "/" + relativePath)
        }

        public static func settlement(_ settlementID: String) -> SourceIdentity {
            SourceIdentity(kind: .settlement, identifier: "settlement:" + settlementID)
        }

        public var description: String { identifier }
    }

    // MARK: - Byte provenance

    /// Where a declared entry's exact bytes are stored, and therefore whether the
    /// item can be rebuilt later. Callers cannot pass a boolean; the flag is
    /// derived from this evidence (ruling O2: overall value computed, not filled).
    public enum ByteSource: Sendable, Equatable {
        /// An immutable object store entry already verified by `readObject` to
        /// hash to the recorded digest. Only valid after that verification.
        case objectReference(objectID: String)
        /// Raw bytes preserved inside the snapshot object; hashed here.
        case embedded(Data)
        /// Bytes were read for this execution but not preserved; forensic only.
        case unretainedDiskRead

        public var isReplayable: Bool {
            switch self {
            case .objectReference, .embedded: return true
            case .unretainedDiskRead: return false
            }
        }

        var wireName: String {
            switch self {
            case .objectReference: return "object_store"
            case .embedded: return "embedded"
            case .unretainedDiskRead: return "disk"
            }
        }

        var objectID: String? {
            if case .objectReference(let objectID) = self { return objectID }
            return nil
        }

        var embeddedBytes: Data? {
            if case .embedded(let data) = self { return data }
            return nil
        }

        var embeddedByteCount: Int { embeddedBytes?.count ?? 0 }
    }

    public struct StatIdentity: Sendable, Equatable {
        public let device: String
        public let inode: String
        public let modificationNanoseconds: String

        public init(device: String, inode: String, modificationNanoseconds: String) {
            self.device = device
            self.inode = inode
            self.modificationNanoseconds = modificationNanoseconds
        }

        func jsonObject() -> [String: Any] {
            ["dev": device, "ino": inode, "mtime_ns": modificationNanoseconds]
        }

        static func decode(_ value: Any, phase: String) throws -> StatIdentity {
            guard let object = value as? [String: Any],
                  let dev = object["dev"] as? String,
                  let ino = object["ino"] as? String,
                  let mtime = object["mtime_ns"] as? String else {
                throw SnapshotError.fieldInvalid(phase: phase, "stat_identity must carry dev/ino/mtime_ns strings")
            }
            return StatIdentity(device: dev, inode: ino, modificationNanoseconds: mtime)
        }
    }

    // MARK: - Declared entries

    public struct DeclaredEntry: Sendable, Equatable {
        public let kind: SourceIdentity.Kind
        public let rootID: String?
        public let relativePath: String?
        public let settlementID: String?
        public let digest: String
        public let byteSource: ByteSource
        public let size: Int?
        public let modified: String?
        public let statIdentity: StatIdentity?
        public let validityAtCapture: String?

        public var identity: SourceIdentity {
            switch kind {
            case .file:
                return .file(rootID: rootID ?? "", relativePath: relativePath ?? "")
            case .settlement:
                return .settlement(settlementID ?? "")
            }
        }

        public var replayable: Bool { byteSource.isReplayable }

        public init(
            fileRootID: String,
            relativePath: String,
            sha256: String,
            byteSource: ByteSource,
            size: Int? = nil,
            modified: String? = nil,
            statIdentity: StatIdentity? = nil
        ) throws {
            try Self.validateCommon(digest: sha256, byteSource: byteSource, phase: "S")
            self.kind = .file
            self.rootID = fileRootID
            self.relativePath = relativePath
            self.settlementID = nil
            self.digest = sha256
            self.byteSource = byteSource
            self.size = size
            self.modified = modified
            self.statIdentity = statIdentity
            self.validityAtCapture = nil
        }

        public init(
            settlementID: String,
            payloadDigest: String,
            byteSource: ByteSource,
            validityAtCapture: String
        ) throws {
            try Self.validateCommon(digest: payloadDigest, byteSource: byteSource, phase: "S")
            self.kind = .settlement
            self.rootID = nil
            self.relativePath = nil
            self.settlementID = settlementID
            self.digest = payloadDigest
            self.byteSource = byteSource
            self.size = nil
            self.modified = nil
            self.statIdentity = nil
            self.validityAtCapture = validityAtCapture
        }

        static func validateCommon(digest: String, byteSource: ByteSource, phase: String) throws {
            guard isValidDigest(digest) else {
                throw SnapshotError.fieldInvalid(phase: phase, "digest must be 64 lowercase hex characters")
            }
            switch byteSource {
            case .objectReference(let objectID):
                guard isValidDigest(objectID) else {
                    throw SnapshotError.fieldInvalid(phase: phase, "object_id must be 64 lowercase hex characters")
                }
            case .embedded(let data):
                // Preserved bytes must already be the declared version; a snapshot
                // never embeds bytes it did not hash.
                guard sha256Hex(data) == digest else {
                    throw SnapshotError.fieldInvalid(phase: phase, "embedded bytes do not hash to the declared digest")
                }
            case .unretainedDiskRead:
                break
            }
        }

        func jsonObject() throws -> [String: Any] {
            var object: [String: Any] = [
                "kind": kind.rawValue,
                "byte_source": byteSource.wireName,
                "object_id": byteSource.objectID ?? NSNull(),
                "bytes_in_snapshot": byteSource.embeddedBytes != nil,
                "bytes_base64": byteSource.embeddedBytes?.base64EncodedString() ?? NSNull(),
                "replayable": replayable
            ]
            switch kind {
            case .file:
                object["root_id"] = rootID ?? ""
                object["relative_path"] = relativePath ?? ""
                object["sha256"] = digest
                object["size"] = size ?? NSNull()
                object["modified"] = modified ?? NSNull()
                object["stat_identity"] = statIdentity?.jsonObject() ?? NSNull()
            case .settlement:
                object["settlement_id"] = settlementID ?? ""
                object["payload_digest"] = digest
                object["validity_at_capture"] = validityAtCapture ?? NSNull()
            }
            return object
        }

        static func decode(_ value: Any, phase: String) throws -> DeclaredEntry {
            guard let object = value as? [String: Any],
                  let kindText = object["kind"] as? String,
                  let kind = SourceIdentity.Kind(rawValue: kindText) else {
                throw SnapshotError.fieldInvalid(phase: phase, "source entry must carry a known kind")
            }
            let byteSource = try decodeByteSource(object, phase: phase)
            switch kind {
            case .file:
                guard let rootID = object["root_id"] as? String,
                      let relativePath = object["relative_path"] as? String,
                      let digest = object["sha256"] as? String else {
                    throw SnapshotError.fieldInvalid(phase: phase, "file entry requires root_id/relative_path/sha256")
                }
                let statIdentity: StatIdentity?
                if let value = object["stat_identity"], !(value is NSNull) {
                    statIdentity = try StatIdentity.decode(value, phase: phase)
                } else {
                    statIdentity = nil
                }
                let entry = try DeclaredEntry(
                    fileRootID: rootID, relativePath: relativePath, sha256: digest,
                    byteSource: byteSource,
                    size: object["size"] as? Int,
                    modified: object["modified"] as? String,
                    statIdentity: statIdentity)
                try verifyRecordedReplayable(object, expected: entry.replayable, phase: phase)
                return entry
            case .settlement:
                guard let settlementID = object["settlement_id"] as? String,
                      let digest = object["payload_digest"] as? String,
                      let validity = object["validity_at_capture"] as? String else {
                    throw SnapshotError.fieldInvalid(phase: phase,
                                                     "settlement entry requires settlement_id/payload_digest/validity_at_capture")
                }
                let entry = try DeclaredEntry(
                    settlementID: settlementID, payloadDigest: digest,
                    byteSource: byteSource, validityAtCapture: validity)
                try verifyRecordedReplayable(object, expected: entry.replayable, phase: phase)
                return entry
            }
        }

        static func decodeByteSource(_ object: [String: Any], phase: String) throws -> ByteSource {
            guard let wire = object["byte_source"] as? String else {
                throw SnapshotError.fieldInvalid(phase: phase, "entry requires byte_source")
            }
            let objectID = object["object_id"] as? String
            let base64 = object["bytes_base64"] as? String
            switch wire {
            case "object_store":
                guard let objectID else {
                    throw SnapshotError.fieldInvalid(phase: phase, "object_store entry requires object_id")
                }
                guard base64 == nil else {
                    throw SnapshotError.fieldInvalid(phase: phase, "object_store entry must not embed bytes")
                }
                return .objectReference(objectID: objectID)
            case "embedded":
                guard let base64, let data = Data(base64Encoded: base64) else {
                    throw SnapshotError.fieldInvalid(phase: phase, "embedded entry requires bytes_base64")
                }
                guard objectID == nil else {
                    throw SnapshotError.fieldInvalid(phase: phase, "embedded entry must not name an object_id")
                }
                return .embedded(data)
            case "disk":
                guard objectID == nil, base64 == nil else {
                    throw SnapshotError.fieldInvalid(phase: phase, "disk entry must carry neither bytes nor object_id")
                }
                return .unretainedDiskRead
            default:
                throw SnapshotError.fieldInvalid(phase: phase, "unknown byte_source \(wire)")
            }
        }

        static func verifyRecordedReplayable(_ object: [String: Any], expected: Bool, phase: String) throws {
            guard let recorded = object["replayable"] as? Bool else {
                throw SnapshotError.fieldInvalid(phase: phase, "entry requires replayable")
            }
            guard recorded == expected else {
                throw SnapshotError.replayableMismatch(phase: phase,
                                                       detail: "per-item replayable does not follow from its byte source")
            }
        }
    }

    // MARK: - Request and anchor

    public struct Request: Sendable, Equatable {
        public let kind: String
        public let demandJSON: Data?
        public let rootIDs: [String]
        public let contractJSON: Data
        public let recomputePolicy: String?
        public let idempotencyKey: String?

        public init(
            kind: String,
            demandJSON: Data? = nil,
            rootIDs: [String],
            contractJSON: Data,
            recomputePolicy: String? = nil,
            idempotencyKey: String? = nil
        ) {
            self.kind = kind
            self.demandJSON = Self.canonicalized(demandJSON)
            self.rootIDs = rootIDs
            self.contractJSON = Self.canonicalized(contractJSON) ?? contractJSON
            self.recomputePolicy = recomputePolicy
            self.idempotencyKey = idempotencyKey
        }

        /// Normalizes key order so a decoded snapshot re-encodes to the same bytes.
        static func canonicalized(_ data: Data?) -> Data? {
            guard let data,
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return data
            }
            return try? JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        }

        func contractValue(phase: String) throws -> Any {
            try Self.jsonValue(contractJSON, field: "contract", phase: phase)
        }

        static func jsonValue(_ data: Data, field: String, phase: String) throws -> Any {
            guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                throw SnapshotError.fieldInvalid(phase: phase, "\(field) is not valid JSON")
            }
            return value
        }

        func jsonObject(phase: String) throws -> [String: Any] {
            [
                "kind": kind,
                "demand": try demandJSON.map { try Self.jsonValue($0, field: "demand", phase: phase) } ?? NSNull(),
                "root_ids": rootIDs,
                "contract": try contractValue(phase: phase),
                "recompute_policy": recomputePolicy ?? NSNull(),
                "idempotency_key": idempotencyKey ?? NSNull()
            ]
        }

        static func decode(_ value: Any, phase: String) throws -> Request {
            guard let object = value as? [String: Any],
                  let kind = object["kind"] as? String,
                  let rootIDs = object["root_ids"] as? [String] else {
                throw SnapshotError.fieldInvalid(phase: phase, "request requires kind/root_ids")
            }
            guard let contract = object["contract"], !(contract is NSNull) else {
                throw SnapshotError.fieldInvalid(phase: phase, "request requires contract")
            }
            let contractJSON = try JSONSerialization.data(
                withJSONObject: contract, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            var demandJSON: Data?
            if let demand = object["demand"], !(demand is NSNull) {
                demandJSON = try JSONSerialization.data(
                    withJSONObject: demand, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            }
            return Request(
                kind: kind,
                demandJSON: demandJSON,
                rootIDs: rootIDs,
                contractJSON: contractJSON,
                recomputePolicy: object["recompute_policy"] as? String,
                idempotencyKey: object["idempotency_key"] as? String)
        }
    }

    public struct Anchor: Sendable, Equatable {
        public let stateID: String
        public let settlementID: String
        public let payloadDigest: String

        public init(stateID: String, settlementID: String, payloadDigest: String) {
            self.stateID = stateID
            self.settlementID = settlementID
            self.payloadDigest = payloadDigest
        }

        func jsonObject() -> [String: Any] {
            ["state_id": stateID, "settlement_id": settlementID, "payload_digest": payloadDigest]
        }

        static func decode(_ value: Any, phase: String) throws -> Anchor {
            guard let object = value as? [String: Any],
                  let stateID = object["state_id"] as? String,
                  let settlementID = object["settlement_id"] as? String,
                  let payloadDigest = object["payload_digest"] as? String else {
                throw SnapshotError.fieldInvalid(phase: phase, "anchor requires state_id/settlement_id/payload_digest")
            }
            guard isValidDigest(payloadDigest) else {
                throw SnapshotError.fieldInvalid(phase: phase, "anchor payload_digest must be 64 lowercase hex characters")
            }
            return Anchor(stateID: stateID, settlementID: settlementID, payloadDigest: payloadDigest)
        }
    }

    // MARK: - Declared snapshot (phase S)

    public struct Declared: Sendable, Equatable {
        public let capturedAt: Date
        public let request: Request
        public let anchor: Anchor
        public let entries: [DeclaredEntry]

        public init(capturedAt: Date, request: Request, anchor: Anchor, entries: [DeclaredEntry]) {
            self.capturedAt = capturedAt
            self.request = request
            self.anchor = anchor
            self.entries = entries
        }

        /// True only when every necessary input has an exact, verifiable byte
        /// source. An entry observed on disk alone is forensic, not replayable.
        public var replayable: Bool { entries.allSatisfy(\.replayable) }

        public var embeddedRawByteCount: Int {
            entries.reduce(0) { $0 + $1.byteSource.embeddedByteCount }
        }

        /// Idempotency fingerprint projection: canonical version, digest
        /// algorithm, root set, contract, and per-source `(kind, 标识, sha256)`.
        /// Forensic fields (`captured_at`, `idempotency_key`, `recompute_policy`,
        /// execution ids) are deliberately excluded so a replayed attempt keeps
        /// the same fingerprint.
        public func computeDeclaredInputDigest(phase: String = "P1") throws -> String {
            let sources: [[String: Any]] = sortedEntries.map { entry in
                ["kind": entry.kind.rawValue, "identifier": entry.identity.identifier, "sha256": entry.digest]
            }
            let projection: [String: Any] = [
                "canonical_version": canonicalVersion,
                "digest_algorithm": digestAlgorithm,
                "root_ids": request.rootIDs.sorted(),
                "contract": try request.contractValue(phase: phase),
                "sources": sources
            ]
            return sha256Hex(try canonicalJSON(projection))
        }

        var sortedEntries: [DeclaredEntry] {
            entries.sorted { $0.identity.identifier < $1.identity.identifier }
        }

        /// Serialize as the single immutable `declared` object. Byte limits are
        /// enforced here, before anything is written; `objectByteLimit` exists so
        /// near-limit and over-limit behavior is testable at small sizes.
        public func encoded(objectByteLimit: Int = SimiGoSnapshotContract.serializedObjectByteLimit) throws -> Data {
            if embeddedRawByteCount > embeddedRawByteLimit {
                throw SnapshotError.unrepresentable(
                    phase: "S",
                    detail: "embedded raw bytes \(embeddedRawByteCount) exceed \(embeddedRawByteLimit)")
            }
            var object: [String: Any] = [
                "canonical_version": canonicalVersion,
                "part": "declared",
                "digest_algorithm": digestAlgorithm,
                "captured_at": timestamp(capturedAt),
                "request": try request.jsonObject(phase: "S"),
                "anchor": anchor.jsonObject(),
                "sources": try sortedEntries.map { try $0.jsonObject() },
                "declared_input_digest": try computeDeclaredInputDigest(phase: "S"),
                "replayable": replayable
            ]
            let withoutOverall = try canonicalJSON(object)
            object["overall_digest"] = sha256Hex(withoutOverall)
            let data = try canonicalJSON(object)
            if data.count > objectByteLimit {
                throw SnapshotError.unrepresentable(
                    phase: "S",
                    detail: "declared object \(data.count) bytes exceed \(objectByteLimit)")
            }
            return data
        }

        public static func decode(_ data: Data) throws -> Declared {
            let object = try parseObject(data, expectedPart: "declared")
            guard let capturedText = object["captured_at"] as? String,
                  let requestValue = object["request"],
                  let anchorValue = object["anchor"],
                  let sources = object["sources"] as? [Any],
                  let recordedInputDigest = object["declared_input_digest"] as? String,
                  let recordedOverall = object["overall_digest"] as? String,
                  let recordedReplayable = object["replayable"] as? Bool else {
                throw SnapshotError.fieldInvalid(phase: "decode", "declared object is missing required fields")
            }
            let declared = Declared(
                capturedAt: try parseTimestamp(capturedText, phase: "decode"),
                request: try Request.decode(requestValue, phase: "decode"),
                anchor: try Anchor.decode(anchorValue, phase: "decode"),
                entries: try sources.map { try DeclaredEntry.decode($0, phase: "decode") })

            var withoutOverall = object
            withoutOverall.removeValue(forKey: "overall_digest")
            guard sha256Hex(try canonicalJSON(withoutOverall)) == recordedOverall else {
                throw SnapshotError.digestMismatch("overall_digest", phase: "decode")
            }
            guard try declared.computeDeclaredInputDigest(phase: "decode") == recordedInputDigest else {
                throw SnapshotError.digestMismatch("declared_input_digest", phase: "decode")
            }
            guard recordedReplayable == declared.replayable else {
                throw SnapshotError.replayableMismatch(phase: "decode",
                                                       detail: "declared replayable is not what its entries support")
            }
            return declared
        }
    }

    // MARK: - Used inputs (phase G) and the `used ⊆ declared` contract

    public struct UsedItem: Sendable, Equatable {
        /// Where the consumed version came from. `disk` means the bytes were
        /// observed but not preserved, so this item cannot be rebuilt.
        public enum Provenance: String, Sendable {
            case objectStore = "object_store"
            case embedded
            case disk
        }

        public let identity: SourceIdentity
        public let digest: String
        public let provenance: Provenance
        public let injectedAs: String

        public init(identity: SourceIdentity, digest: String, provenance: Provenance, injectedAs: String) {
            self.identity = identity
            self.digest = digest
            self.provenance = provenance
            self.injectedAs = injectedAs
        }

        /// The sanctioned construction: digest and provenance come from the
        /// declared entry, so a hit cannot silently claim a different version.
        public static func from(declared entry: DeclaredEntry, injectedAs: String) -> UsedItem {
            let provenance: Provenance
            switch entry.byteSource {
            case .objectReference: provenance = .objectStore
            case .embedded: provenance = .embedded
            case .unretainedDiskRead: provenance = .disk
            }
            return UsedItem(identity: entry.identity, digest: entry.digest,
                            provenance: provenance, injectedAs: injectedAs)
        }

        public var replayable: Bool { provenance != .disk }

        func jsonObject() -> [String: Any] {
            [
                "kind": identity.kind.rawValue,
                "identifier": identity.identifier,
                "sha256": digest,
                "byte_source": provenance.rawValue,
                "replayable": replayable,
                "injected_as": injectedAs
            ]
        }

        static func decode(_ value: Any, phase: String) throws -> UsedItem {
            guard let object = value as? [String: Any],
                  let kindText = object["kind"] as? String,
                  let kind = SourceIdentity.Kind(rawValue: kindText),
                  let identifier = object["identifier"] as? String,
                  let digest = object["sha256"] as? String,
                  let injectedAs = object["injected_as"] as? String,
                  let wire = object["byte_source"] as? String,
                  let provenance = Provenance(rawValue: wire) else {
                throw SnapshotError.fieldInvalid(phase: phase,
                                                 "used item requires kind/identifier/sha256/byte_source/injected_as")
            }
            guard isValidDigest(digest) else {
                throw SnapshotError.fieldInvalid(phase: phase, "used sha256 must be 64 lowercase hex characters")
            }
            let item = UsedItem(identity: SourceIdentity(kind: kind, identifier: identifier),
                                digest: digest, provenance: provenance, injectedAs: injectedAs)
            if let recorded = object["replayable"] as? Bool, recorded != item.replayable {
                throw SnapshotError.replayableMismatch(phase: phase,
                                                       detail: "used replayable does not follow from its byte source")
            }
            return item
        }
    }

    public struct SubsetViolation: Sendable, Equatable, CustomStringConvertible {
        public enum Kind: String, Sendable {
            case undeclared
            case digestMismatch
        }
        public let kind: Kind
        public let identity: SourceIdentity
        public var description: String { "\(kind.rawValue):\(identity.identifier)" }
    }

    public struct Replayability: Sendable, Equatable {
        public let declaredReplayable: Bool
        public let usedPresent: Bool
        public let usedReplayable: Bool
        public let subsetViolations: [SubsetViolation]

        public var value: Bool {
            declaredReplayable && usedPresent && usedReplayable && subsetViolations.isEmpty
        }
    }

    /// `declared ∧ used ∧ (used ⊆ declared with per-item digest equality)`.
    /// `used` is optional so a crash during G (items lost) can never evaluate to
    /// replayable; an empty array means "the model consumed no IS input".
    public static func evaluateReplayable(declared: Declared, used: [UsedItem]?) -> Replayability {
        guard let used else {
            return Replayability(declaredReplayable: declared.replayable, usedPresent: false,
                                 usedReplayable: false, subsetViolations: [])
        }
        return Replayability(
            declaredReplayable: declared.replayable,
            usedPresent: true,
            usedReplayable: used.allSatisfy(\.replayable),
            subsetViolations: subsetViolations(declared: declared, used: used))
    }

    /// Compares per item, never by an aggregate digest: membership must match on
    /// `(kind, 标识)` and the recorded version must equal the declared sha256.
    public static func subsetViolations(declared: Declared, used: [UsedItem]) -> [SubsetViolation] {
        let declaredByIdentity = Dictionary(declared.entries.map { ($0.identity, $0) },
                                            uniquingKeysWith: { first, _ in first })
        var violations: [SubsetViolation] = []
        for item in used {
            guard let declaredEntry = declaredByIdentity[item.identity] else {
                violations.append(.init(kind: .undeclared, identity: item.identity))
                continue
            }
            if declaredEntry.digest != item.digest {
                violations.append(.init(kind: .digestMismatch, identity: item.identity))
            }
        }
        return violations.sorted { $0.identity.identifier < $1.identity.identifier }
    }

    // MARK: - Final snapshot (phase P2)

    public struct Final: Sendable, Equatable {
        public let declaredSnapshotID: String
        public let declaredInputDigest: String
        public let capturedAt: Date
        public let verifiedAsOf: Date
        public let used: [UsedItem]
        public let recheck: [String: String]
        /// Computed by `make` from per-item evidence (ruling O2). No caller can
        /// pass it; `decode` re-checks it against the used items and `verify`
        /// re-checks it against the declared object.
        public let replayable: Bool

        private init(
            declaredSnapshotID: String,
            declaredInputDigest: String,
            capturedAt: Date,
            verifiedAsOf: Date,
            used: [UsedItem],
            recheck: [String: String],
            replayable: Bool
        ) {
            self.declaredSnapshotID = declaredSnapshotID
            self.declaredInputDigest = declaredInputDigest
            self.capturedAt = capturedAt
            self.verifiedAsOf = verifiedAsOf
            self.used = used
            self.recheck = recheck
            self.replayable = replayable
        }

        public static func make(
            declared: Declared,
            declaredSnapshotID: String,
            used: [UsedItem],
            verifiedAsOf: Date,
            recheck: [String: String],
            capturedAt: Date = Date()
        ) throws -> Final {
            guard isValidDigest(declaredSnapshotID) else {
                throw SnapshotError.fieldInvalid(phase: "P2", "declared_snapshot_id must be 64 lowercase hex characters")
            }
            let evaluation = evaluateReplayable(declared: declared, used: used)
            let undeclared = evaluation.subsetViolations.filter { $0.kind == .undeclared }.map(\.identity.identifier)
            if !undeclared.isEmpty {
                throw SnapshotError.usedUndeclared(undeclared, phase: "P2")
            }
            let mismatched = evaluation.subsetViolations.filter { $0.kind == .digestMismatch }.map(\.identity.identifier)
            if !mismatched.isEmpty {
                throw SnapshotError.usedMismatch(mismatched, phase: "P2")
            }
            return Final(
                declaredSnapshotID: declaredSnapshotID,
                declaredInputDigest: try declared.computeDeclaredInputDigest(phase: "P2"),
                capturedAt: capturedAt,
                verifiedAsOf: verifiedAsOf,
                used: used.sorted { $0.identity.identifier < $1.identity.identifier },
                recheck: recheck,
                replayable: evaluation.value)
        }

        /// Recompute the conjunction against the declared object and require the
        /// recorded value to be exactly what the evidence supports.
        public func verify(against declared: Declared) throws {
            let evaluation = evaluateReplayable(declared: declared, used: used)
            guard evaluation.subsetViolations.isEmpty else {
                let undeclared = evaluation.subsetViolations.filter { $0.kind == .undeclared }.map(\.identity.identifier)
                if !undeclared.isEmpty { throw SnapshotError.usedUndeclared(undeclared, phase: "P2") }
                throw SnapshotError.usedMismatch(
                    evaluation.subsetViolations.map(\.identity.identifier), phase: "P2")
            }
            guard try declared.computeDeclaredInputDigest(phase: "P2") == declaredInputDigest else {
                throw SnapshotError.digestMismatch("declared_input_digest", phase: "P2")
            }
            guard evaluation.value == replayable else {
                throw SnapshotError.replayableMismatch(
                    phase: "P2", detail: "recorded replayable is not what declared+used support")
            }
        }

        public func encoded(objectByteLimit: Int = SimiGoSnapshotContract.serializedObjectByteLimit) throws -> Data {
            let object: [String: Any] = [
                "schema_version": schemaVersion,
                "canonical_version": canonicalVersion,
                "part": "final",
                "declared_snapshot_id": declaredSnapshotID,
                "declared_input_digest": declaredInputDigest,
                "captured_at": timestamp(capturedAt),
                "verified_as_of": timestamp(verifiedAsOf),
                "used": used.map { $0.jsonObject() },
                "replayable": replayable,
                "recheck": recheck
            ]
            let data = try canonicalJSON(object)
            if data.count > objectByteLimit {
                throw SnapshotError.unrepresentable(
                    phase: "P2", detail: "final object \(data.count) bytes exceed \(objectByteLimit)")
            }
            return data
        }

        public static func decode(_ data: Data) throws -> Final {
            let object = try parseObject(data, expectedPart: "final")
            guard let declaredSnapshotID = object["declared_snapshot_id"] as? String,
                  let declaredInputDigest = object["declared_input_digest"] as? String,
                  let capturedText = object["captured_at"] as? String,
                  let verifiedText = object["verified_as_of"] as? String,
                  let usedValues = object["used"] as? [Any],
                  let recordedReplayable = object["replayable"] as? Bool else {
                throw SnapshotError.fieldInvalid(phase: "decode", "final object is missing required fields")
            }
            guard isValidDigest(declaredSnapshotID) else {
                throw SnapshotError.fieldInvalid(phase: "decode", "declared_snapshot_id must be 64 lowercase hex characters")
            }
            let used = try usedValues.map { try UsedItem.decode($0, phase: "decode") }
            let recheck = (object["recheck"] as? [String: String]) ?? [:]
            guard recordedReplayable == used.allSatisfy(\.replayable) else {
                throw SnapshotError.replayableMismatch(
                    phase: "decode", detail: "final replayable is not what its used items support")
            }
            let final = Final(
                declaredSnapshotID: declaredSnapshotID,
                declaredInputDigest: declaredInputDigest,
                capturedAt: try parseTimestamp(capturedText, phase: "decode"),
                verifiedAsOf: try parseTimestamp(verifiedText, phase: "decode"),
                used: used,
                recheck: recheck,
                replayable: recordedReplayable)
            return final
        }
    }

    static func parseObject(_ data: Data, expectedPart: String) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SnapshotError.fieldInvalid(phase: "decode", "snapshot is not a JSON object")
        }
        guard let version = object["canonical_version"] as? String else {
            throw SnapshotError.fieldInvalid(phase: "decode", "snapshot requires canonical_version")
        }
        guard version == canonicalVersion else {
            throw SnapshotError.schemaUnknown(version, phase: "decode")
        }
        if let schema = object["schema_version"] as? String, schema != schemaVersion {
            throw SnapshotError.schemaUnknown(schema, phase: "decode")
        }
        guard let part = object["part"] as? String else {
            throw SnapshotError.fieldInvalid(phase: "decode", "snapshot requires part")
        }
        guard part == expectedPart else {
            throw SnapshotError.partUnknown(part, phase: "decode")
        }
        return object
    }
}
