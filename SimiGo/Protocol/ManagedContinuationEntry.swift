import Foundation
import SimiGoRuntimeContract

// MARK: - Managed continuation entry (C)
//
// C-scope request fields on the Responses object. They are inert unless
// `recompute_policy` is present, and their presence never changes the ordinary
// continuation path:
//
//   "previous_es_state_id": "es-...",          // the managed anchor
//   "recompute_policy": "never" | "allow_safe_recompute",
//   "idempotency_key": "...",                  // optional opaque caller key
//   "consumer_es_state_id": "es-...",          // optional caller-chosen child
//   "root_ids": ["work"]                       // optional declared root set
//
// Absence of `recompute_policy` leaves the pre-C dispatch byte-identical. A
// present-but-unusable field is refused; it never degrades into an ordinary
// generation that silently ignores an explicitly requested policy.

struct ManagedContinuationFields: @unchecked Sendable {
    static let maxIdempotencyKeyBytes = 256

    /// Whether the key was present at all. Presence with a non-string value is a
    /// shape error, never a defaulted `never`.
    let policyPresent: Bool
    let policyRaw: Any?
    let idempotencyKey: String?
    let consumerESStateID: String?
    let rootIDs: [String]
    /// First unusable field, if any. Every C-scope field is validated even when
    /// the policy is absent so a typo cannot hide behind an inert request.
    let shapeError: String?

    var hasCScopeFields: Bool {
        idempotencyKey != nil || consumerESStateID != nil || !rootIDs.isEmpty
    }

    /// No C-scope field arrived: the dispatch must take the ordinary path.
    var isInert: Bool {
        !policyPresent && !hasCScopeFields && shapeError == nil
    }

    static func parse(_ json: [String: Any]) -> ManagedContinuationFields {
        var shapeError: String?

        var key: String?
        if let raw = json["idempotency_key"] {
            if let text = raw as? String, !text.isEmpty,
                text.utf8.count <= maxIdempotencyKeyBytes {
                key = text
            } else {
                shapeError = shapeError
                    ?? "idempotency_key (must be a non-empty string of at most \(maxIdempotencyKeyBytes) UTF-8 bytes)"
            }
        }

        var consumer: String?
        if let raw = json["consumer_es_state_id"] {
            if let text = raw as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                consumer = text
            } else {
                shapeError = shapeError
                    ?? "consumer_es_state_id (must be a non-empty string)"
            }
        }

        var roots: [String] = []
        if let raw = json["root_ids"] {
            if let list = raw as? [Any] {
                for element in list {
                    guard let root = element as? String,
                        !root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else {
                        shapeError = shapeError
                            ?? "root_ids (must be an array of non-empty strings)"
                        break
                    }
                    roots.append(root)
                }
            } else {
                shapeError = shapeError
                    ?? "root_ids (must be an array of non-empty strings)"
            }
        }

        return ManagedContinuationFields(
            policyPresent: json.keys.contains(RecomputePolicy.requestKey),
            policyRaw: json[RecomputePolicy.requestKey],
            idempotencyKey: key,
            consumerESStateID: consumer,
            rootIDs: roots,
            shapeError: shapeError)
    }
}

/// Everything the runtime needs to run P1 → S → G → P2 for one request. The
/// handler owns the DB + model; the HTTP layer only parses and reports.
public struct ManagedContinuationRequest: Sendable {
    public let requestId: String
    public let agentId: String?
    public let sessionId: String
    public let logicalBranchId: String
    public let anchorESStateID: String
    public let policy: RecomputePolicy
    public let idempotencyKey: String?
    public let consumerESStateID: String?
    public let rootIDs: [String]
    public let messages: [JSONValue]
    public let tools: [JSONValue]?
    public let config: ModelConfig

    public init(
        requestId: String,
        agentId: String?,
        sessionId: String,
        logicalBranchId: String,
        anchorESStateID: String,
        policy: RecomputePolicy,
        idempotencyKey: String?,
        consumerESStateID: String?,
        rootIDs: [String],
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig
    ) {
        self.requestId = requestId
        self.agentId = agentId
        self.sessionId = sessionId
        self.logicalBranchId = logicalBranchId
        self.anchorESStateID = anchorESStateID
        self.policy = policy
        self.idempotencyKey = idempotencyKey
        self.consumerESStateID = consumerESStateID
        self.rootIDs = rootIDs
        self.messages = messages
        self.tools = tools
        self.config = config
    }
}

/// Committed (or replayed) result. `replayable` is the evidence-backed
/// conjunction computed by the snapshot contract; nil means the replay found no
/// final snapshot to attest, never "assume replayable".
public struct ManagedContinuationResult: Sendable, Equatable {
    public let content: String
    public let toolCalls: [ParsedToolCall]
    public let usage: GenerationUsageReport?
    public let executionID: String
    public let childESStateID: String
    public let settlementID: String
    public let declaredSnapshotID: String
    public let finalSnapshotID: String
    public let fingerprint: String
    public let modelCalls: Int
    public let settlementsWritten: Int
    public let replayable: Bool?
    public let recomputed: Bool
    public let reusedExecution: Bool

    public init(
        content: String,
        toolCalls: [ParsedToolCall],
        usage: GenerationUsageReport?,
        executionID: String,
        childESStateID: String,
        settlementID: String,
        declaredSnapshotID: String,
        finalSnapshotID: String,
        fingerprint: String,
        modelCalls: Int,
        settlementsWritten: Int,
        replayable: Bool?,
        recomputed: Bool,
        reusedExecution: Bool
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
        self.executionID = executionID
        self.childESStateID = childESStateID
        self.settlementID = settlementID
        self.declaredSnapshotID = declaredSnapshotID
        self.finalSnapshotID = finalSnapshotID
        self.fingerprint = fingerprint
        self.modelCalls = modelCalls
        self.settlementsWritten = settlementsWritten
        self.replayable = replayable
        self.recomputed = recomputed
        self.reusedExecution = reusedExecution
    }
}

/// Typed, fail-closed failures of the managed-continuation entry.
public enum ManagedContinuationFailure: Error, Sendable, Equatable {
    /// No managed-continuation authority is wired for this runtime.
    case unavailable
    /// The managed pipeline is not available on the streaming path in v1.
    case unsupportedOnStream
    /// A C-scope request field is unusable. The detail names the field only.
    case invalidRequest(String)
    /// The core refused. The internal cause/evidence stay internal; only the
    /// public allowlist can reach the response body.
    case refused(ManagedRefusal.Refusal)
    /// Infrastructure or unclassified fault (never a business refusal).
    case engine(String)
}

extension ManagedContinuationFailure {
    var terminal: ContinuationTerminal {
        switch self {
        case .unavailable:
            return .admissionAuthorityUnavailable
        case .unsupportedOnStream:
            return ContinuationTerminal(
                status: 422,
                message: "Managed continuation is not supported on the streaming Responses path",
                errorKind: ManagedRefusal.Entry.managedContinuation.rawValue,
                reasonCode: nil)
        case .invalidRequest(let field):
            return ContinuationTerminal(
                status: 422,
                message: "Managed continuation refused: unusable \(field)",
                errorKind: ManagedRefusal.Entry.managedContinuation.rawValue,
                reasonCode: nil)
        case .refused(let refusal):
            let external = ManagedRefusal.external(
                refusal, entry: .managedContinuation)
            // O1: the body may carry only an allowlisted code. The internal cause,
            // stage and evidence never leave the process.
            let code = ManagedRefusal.sanitizedReasonCode(external.reasonCode)
            return ContinuationTerminal(
                status: external.status,
                message: code.map { "Managed continuation refused: \($0)" }
                    ?? "Managed continuation refused",
                errorKind: external.errorKind,
                reasonCode: code)
        case .engine:
            return .admissionEngineError
        }
    }
}

/// Pure classification: typed failures keep their terminal; anything else is the
/// entry's existing 500 bucket, never a 422 business refusal.
func managedContinuationTerminal(for error: Error) -> ContinuationTerminal {
    if let failure = error as? ManagedContinuationFailure {
        return failure.terminal
    }
    if let refusal = error as? ManagedRefusal.Refusal {
        return ManagedContinuationFailure.refused(refusal).terminal
    }
    return ManagedContinuationFailure.engine(
        "authoritative managed continuation unavailable").terminal
}

/// Injected managed-continuation authority. It MUST drive the product's single
/// managed pipeline (P1 → S → G → P2) and never a second validation path.
public typealias ManagedContinuationHandler =
    @Sendable (_ request: ManagedContinuationRequest) async throws
        -> ManagedContinuationResult

// MARK: - Production adapter (NativeMLX wiring)

/// The one model call the managed pipeline needs. It receives the messages AFTER
/// the declared sources were injected, so the `used` evidence describes exactly
/// what the model saw.
typealias ManagedContinuationGenerate =
    @Sendable (
        _ request: ManagedContinuationRequest,
        _ messages: [JSONValue]
    ) async throws -> GenerationResult

func makeNativeMLXManagedContinuationHandler(
    modelPath: String,
    generate: @escaping ManagedContinuationGenerate
) -> ManagedContinuationHandler {
    { request in
        try await runNativeManagedContinuation(
            request: request, modelPath: modelPath, generate: generate)
    }
}

enum ManagedSourceCaptureError: Error {
    case unknownRoot(String)
    case unreadableRoot(String)
    case unsafeEntry(String)
    case enumerationFailed(String)
    case resourceLimit(String)
}

/// Reads the declared sources with the same scan policy the IS scanner applies to
/// a work root. Root identity, descendant type, enumeration completeness and
/// aggregate memory use are all checked before the snapshot can reach generation.
enum ManagedSourceCapture {
    struct Limits {
        let maxRoots: Int
        let maxDepth: Int
        let maxVisitedEntries: Int
        let maxFiles: Int
        let fileByteCap: Int
        let maxTotalBytesRead: Int

        init(
            maxRoots: Int = 16,
            maxDepth: Int = 4,
            maxVisitedEntries: Int = 16_384,
            maxFiles: Int = 4_096,
            fileByteCap: Int = 1 << 20,
            maxTotalBytesRead: Int = 64 << 20
        ) {
            self.maxRoots = maxRoots
            self.maxDepth = maxDepth
            self.maxVisitedEntries = maxVisitedEntries
            self.maxFiles = maxFiles
            self.fileByteCap = fileByteCap
            self.maxTotalBytesRead = maxTotalBytesRead
        }

        static let production = Limits()
    }

    static let fileByteCap = 1 << 20
    static let maxDepth = 4
    /// Per-turn prompt budget for injected sources. Declared entries that do not
    /// fit stay declared-only; they are never truncated into `used` evidence.
    static let injectionByteBudget = 64 * 1024

    static func capture(
        _ request: SnapshotContract.Request,
        database: ESISDatabase,
        limits: Limits = .production
    ) throws -> ManagedContinuation.Captured {
        guard limits.maxRoots >= 0, limits.maxDepth >= 0,
              limits.maxVisitedEntries >= 0, limits.maxFiles >= 0,
              limits.fileByteCap >= 0, limits.maxTotalBytesRead >= 0 else {
            throw ManagedSourceCaptureError.resourceLimit("negative capture limit")
        }
        guard request.rootIDs.count <= limits.maxRoots,
              Set(request.rootIDs).count == request.rootIDs.count else {
            throw ManagedSourceCaptureError.resourceLimit("root count or duplicate root ID")
        }

        let fm = FileManager.default
        var entries: [SnapshotContract.DeclaredEntry] = []
        var totalVisited = 0
        var totalFiles = 0
        var totalBytesRead = 0

        for rootID in request.rootIDs.sorted() {
            // Reject a symlink at the registered root itself before the locator
            // helper canonicalizes it. Otherwise moving the original directory
            // elsewhere and replacing its old path with a symlink back to that
            // inode would silently turn the registered root into an alias.
            let registeredPath: String
            do {
                guard let row = try database.listRoots().first(where: { $0.rootID == rootID }),
                      row.locatorType == "path",
                      let path = row.displayName, !path.isEmpty else {
                    throw ManagedSourceCaptureError.unknownRoot(rootID)
                }
                registeredPath = path
            } catch let error as ManagedSourceCaptureError {
                throw error
            } catch {
                throw ManagedSourceCaptureError.unreadableRoot(rootID)
            }
            var registeredInfo = stat()
            let registeredPathResult = registeredPath.withCString {
                Darwin.lstat($0, &registeredInfo)
            }
            guard registeredPathResult == 0,
                  (registeredInfo.st_mode & S_IFMT) == S_IFDIR else {
                throw ManagedSourceCaptureError.unsafeEntry(registeredPath)
            }

            let identity: ESISDatabase.RootLocatorSnapshot
            do {
                identity = try database.rootLocatorSnapshot(rootID: rootID)
            } catch {
                throw ManagedSourceCaptureError.unreadableRoot(rootID)
            }
            let root = URL(fileURLWithPath: identity.path, isDirectory: true)
            var enumerationFailure: String?
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    enumerationFailure = "\(url.path): \(error.localizedDescription)"
                    return false
                }) else {
                throw ManagedSourceCaptureError.unreadableRoot(rootID)
            }

            let filesBeforeRoot = totalFiles
            var relativePaths: [String] = []
            while let object = enumerator.nextObject() {
                guard let url = object as? URL else {
                    throw ManagedSourceCaptureError.enumerationFailed(rootID)
                }
                totalVisited += 1
                guard totalVisited <= limits.maxVisitedEntries else {
                    throw ManagedSourceCaptureError.resourceLimit("visited entry limit exceeded")
                }

                var info = stat()
                let result = url.path.withCString { Darwin.lstat($0, &info) }
                guard result == 0 else {
                    throw ManagedSourceCaptureError.enumerationFailed(url.path)
                }
                let kind = info.st_mode & S_IFMT
                if kind == S_IFLNK {
                    enumerator.skipDescendants()
                    throw ManagedSourceCaptureError.unsafeEntry(url.path)
                }
                if kind == S_IFDIR { continue }
                guard kind == S_IFREG else {
                    throw ManagedSourceCaptureError.unsafeEntry(url.path)
                }

                let relative = relativePath(of: url, under: root)
                guard !relative.isEmpty else {
                    throw ManagedSourceCaptureError.unsafeEntry(url.path)
                }
                guard relative.split(separator: "/").count <= limits.maxDepth else {
                    continue
                }
                relativePaths.append(relative)
                totalFiles += 1
                guard totalFiles <= limits.maxFiles else {
                    throw ManagedSourceCaptureError.resourceLimit("file count limit exceeded")
                }
            }
            if let enumerationFailure {
                throw ManagedSourceCaptureError.enumerationFailed(enumerationFailure)
            }

            let captured: [ESISDatabase.RootFileSnapshot]
            do {
                captured = try database.captureRootFiles(
                    rootID: rootID, expected: identity, relativePaths: relativePaths,
                    maximumFiles: limits.maxFiles - filesBeforeRoot,
                    maximumBytesPerFile: limits.fileByteCap,
                    maximumTotalBytesRead: limits.maxTotalBytesRead - totalBytesRead)
            } catch {
                throw ManagedSourceCaptureError.unreadableRoot(rootID)
            }
            for file in captured {
                totalBytesRead += file.data.count
                guard totalBytesRead <= limits.maxTotalBytesRead else {
                    throw ManagedSourceCaptureError.resourceLimit("aggregate byte limit exceeded")
                }
                guard String(data: file.data, encoding: .utf8) != nil else { continue }
                entries.append(
                    try SnapshotContract.DeclaredEntry(
                        fileRootID: rootID,
                        relativePath: file.relativePath,
                        sha256: SnapshotContract.sha256Hex(file.data),
                        byteSource: .embedded(file.data),
                        size: file.data.count,
                        statIdentity: file.statIdentity))
            }
        }
        return .init(entries: entries)
    }

    /// Injects the captured versions and reports exactly the ones that went in.
    /// The block is appended to the trailing user turn: the leading prefix stays
    /// byte-stable so a managed run cannot destroy cross-ES KV bindings.
    static func inject(
        declared: SnapshotContract.Declared,
        messages: [JSONValue]
    ) -> (messages: [JSONValue], used: [SnapshotContract.UsedItem]) {
        var used: [SnapshotContract.UsedItem] = []
        var blocks: [String] = []
        var spent = 0
        let ordered = declared.entries.sorted {
            $0.identity.identifier < $1.identity.identifier
        }
        for entry in ordered {
            guard case .embedded(let data) = entry.byteSource,
                let text = String(data: data, encoding: .utf8)
            else { continue }
            let block = """
                <source root_id="\(entry.rootID ?? "")" path="\(entry.relativePath ?? "")" sha256="\(entry.digest)">
                \(text)
                </source>
                """
            guard spent + block.utf8.count <= injectionByteBudget else { continue }
            spent += block.utf8.count
            blocks.append(block)
            used.append(
                .from(declared: entry, injectedAs: "context[\(used.count)]"))
        }
        guard !blocks.isEmpty else { return (messages, []) }

        let context = blocks.joined(separator: "\n\n")
        var augmented = messages
        if let lastUser = augmented.lastIndex(where: {
            $0.object?["role"]?.string == "user"
        }), var object = augmented[lastUser].object,
            let content = object["content"]
        {
            object["content"] = .string(content.messageText + "\n\n" + context)
            augmented[lastUser] = .object(object)
        } else {
            augmented.append(
                .object(["role": .string("user"), "content": .string(context)]))
        }
        return (augmented, used)
    }

    static func relativePath(of url: URL, under root: URL) -> String {
        let rootParts = Array(root.standardizedFileURL.pathComponents.dropFirst())
        let fileParts = Array(url.standardizedFileURL.pathComponents.dropFirst())
        guard fileParts.count >= rootParts.count,
              Array(fileParts.prefix(rootParts.count)) == rootParts else { return "" }
        return fileParts.dropFirst(rootParts.count).joined(separator: "/")
    }
}

/// Carries the model output from G back to the caller. `run` returns only the
/// committed receipt, so the produced text is handed over through this box
/// instead of being re-read from storage (a replay has no fresh output).
final class ManagedProduced: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (text: String, usage: GenerationUsageReport?)?

    var value: (text: String, usage: GenerationUsageReport?)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}

/// The product's single managed pipeline: P1 → S → G → P2 through the core, with
/// the runtime's real source capture, model call and settlement gate.
func runNativeManagedContinuation(
    request: ManagedContinuationRequest,
    modelPath: String,
    generate: @escaping ManagedContinuationGenerate
) async throws -> ManagedContinuationResult {
    let db = try ESISDatabase(
        url: ManagedPaths.databaseURL, createIfNeeded: true)
    try db.runMigrations()
    let producer = ProducerIdentity.identity(fromPath: modelPath)
    // One contract for the declared snapshot and the settlement gate, so the
    // fingerprint's `contract` dimension and the settled payload cannot drift.
    let contract = InformationLoop.chatResultContractJSON

    let snapshotRequest = SnapshotContract.Request(
        kind: "managed_continuation",
        rootIDs: request.rootIDs,
        contractJSON: contract,
        recomputePolicy: request.policy.rawValue,
        idempotencyKey: request.idempotencyKey)

    let childStateID =
        request.consumerESStateID ?? "es-\(UUID().uuidString.lowercased())"
    guard let anchorPosition = try db.executionStatePosition(request.anchorESStateID) else {
        throw ManagedRefusal.Refusal(
            cause: .invalidAnchor, origin: .admission, phase: .p1,
            evidence: ["state_id": request.anchorESStateID, "reason": "unknown_state"])
    }

    let config = ManagedContinuation.Config(
        executionID: "mc-\(UUID().uuidString.lowercased())",
        anchorStateID: request.anchorESStateID,
        policy: request.policy,
        snapshotRequest: snapshotRequest,
        childStateID: childStateID,
        childModelIdentity: producer.model,
        childPosition: (anchorPosition ?? 0) + 1,
        identity: producer,
        idempotencyKey: request.idempotencyKey)

    let produced = ManagedProduced()

    let outcome: ManagedContinuation.Outcome
    do {
        outcome = try await ManagedContinuation.run(
            db: db,
            config: config,
            capture: { try ManagedSourceCapture.capture($0, database: db) },
            generate: { declared in
                let injection = ManagedSourceCapture.inject(
                    declared: declared, messages: request.messages)
                let result = try await generate(request, injection.messages)
                // T-1: an output the generator cannot attest as complete is not a
                // settled record. Throwing here is the only safe place — G runs
                // before P2, so nothing has been written and nothing can be reused.
                guard result.completion.isSettleable else {
                    throw ManagedRefusal.Refusal(
                        cause: .generationIncomplete, origin: .admission, phase: .g,
                        evidence: ["completion": result.completion.wireName])
                }
                produced.value = (result.text, result.usage)
                let settled = try SettlementAuthority.authorize(
                    generatedText: result.text, contractJSON: contract,
                    verifiedBindings: [:])
                return ManagedContinuation.Generated(
                    used: injection.used, settled: settled, nextInput: result.text)
            })
    } catch let refusal as ManagedRefusal.Refusal {
        // A refusal raised inside G reaches the entry as its own typed failure;
        // the core only returns refusals it decided itself.
        throw ManagedContinuationFailure.refused(refusal)
    }

    switch outcome {
    case .refused(let refusal, _):
        throw ManagedContinuationFailure.refused(refusal)
    case .committed(let committed):
        let fresh = produced.value
        let content: String
        if committed.reusedExecution {
            content = replayContent(db: db, settlementID: committed.settlementID) ?? ""
        } else {
            content = fresh?.text ?? ""
        }
        return ManagedContinuationResult(
            content: content,
            toolCalls: [],
            usage: committed.reusedExecution ? nil : fresh?.usage,
            executionID: committed.executionID,
            childESStateID: committed.childStateID,
            settlementID: committed.settlementID,
            declaredSnapshotID: committed.declaredSnapshotID,
            finalSnapshotID: committed.finalSnapshotID,
            fingerprint: committed.fingerprint,
            modelCalls: committed.modelCalls,
            settlementsWritten: committed.settlementsWritten,
            replayable: committed.replayable,
            recomputed: committed.recomputed,
            reusedExecution: committed.reusedExecution)
    }
}

/// A replay serves the value the prior attempt settled, never a regenerated one.
/// The chat result contract seals the whole message under `content`.
func replayContent(db: ESISDatabase, settlementID: String) -> String? {
    guard let receipt = try? db.settlementReceipt(settlementID),
        let object = try? JSONSerialization.jsonObject(with: receipt.payload)
            as? [String: Any],
        let content = object["content"] as? String, !content.isEmpty
    else { return nil }
    return content
}
