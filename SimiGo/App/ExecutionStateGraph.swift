import CryptoKit
import Combine
import SwiftUI
import SimiGoRuntimeContract

/// SimiGo v2.1 Reference App.
///
/// This is the first product-shaped mapping of the frozen ES Contract
/// v1.0-amended. It deliberately avoids model inference and KV/cache fields:
/// the user operates an Execution State graph; Representation is opaque and
/// only its declared, versioned surface is displayed in diagnostics.

enum ESContract {
    static let version = "v1.0-amended"
    static let representationID = "R_Reference_v1"

    static let declaration = """
    Σ_R: ReferenceCheckpointV1
    C_R: canonical token-prefix array
    Inv_R: anchorHash = H(prefix); integrity checksum; model identity
    Rules_R: ρ_R1 anchor integrity · ρ_R2 prefix extension · \
    ρ_R3 record integrity
    INV-I ← ρ_R3 + model identity
    INV-P ← explicit position + ρ_R2
    INV-A ← ρ_R1
    INV-C ← continuation binding + ρ_R2
    """
}

enum ExecutionLifecycle: String, Codable {
    case active
    case saved
    case restored
    case discarded
}

struct ExecutionStateRecord: Identifiable, Codable, Hashable {
    let id: String
    let parentID: String?
    let modelIdentity: String
    let createdAt: Date

    var position: Int
    var continuationID: String
    var nextInput: String
    var anchor: String
    var prefix: [String]
    var lifecycle: ExecutionLifecycle
    var checkpointIDs: [UUID]
}

struct ExecutionCheckpoint: Identifiable, Codable, Hashable {
    let id: UUID
    let stateID: String
    let modelIdentity: String
    let position: Int
    let continuationID: String
    let nextInput: String
    let anchor: String
    let prefix: [String]
    let createdAt: Date
    let checksum: String
}

/// A native-authorized, settled Information-Space result committed to the durable
/// graph. It stores the canonical validated payload and its digest only — never
/// the raw model text — and can only be produced through the settlement authority.
struct SettlementReceipt: Identifiable, Codable, Hashable {
    let id: UUID
    let stateID: String
    let schemaVersion: String
    let payload: Data
    let payloadDigest: String
    let settledAt: Date
}

struct ExecutionGraphDocument: Codable, Hashable {
    var contractVersion = ESContract.version
    var representationID = ESContract.representationID
    var states: [ExecutionStateRecord] = []
    var checkpoints: [ExecutionCheckpoint] = []
    /// Optional for backward compatibility with pre-settlement graphs.
    var settlements: [SettlementReceipt]? = nil
}

enum ExecutionGraphError: Error, Equatable {
    case storeUnavailable(String)
    case invalidTransition(String)
    case invalidCheckpoint(String)
}

@MainActor
final class ExecutionStateGraphStore: ObservableObject {
    @Published private(set) var document = ExecutionGraphDocument()
    @Published private(set) var loadError: String?
    @Published var operationError: String?

    private let storeURL: URL
    private let dbURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - SQLite ES/IS authoritative store
    //
    // SQLite is the authoritative physical home for execution states, native
    // authorized settlements, and external file / agent-session indexes. Opening
    // is lazy and NON-FATAL: a corrupt or unwritable database is recorded in
    // `persistError` and NEVER silently overwritten (fail closed). The native
    // settlement gate has already refused unsafe values upstream, so this layer
    // only commits results that cleared that gate.
    private(set) var esis: SimiGoESISDatabase?
    private var esisOpenAttempted = false
    private var didImportLegacy = false
    @Published private(set) var persistError: String?
    private var legacyJSONData: Data?

    var states: [ExecutionStateRecord] { document.states }
    var checkpoints: [ExecutionCheckpoint] { document.checkpoints }

    init(storeURL: URL = ExecutionStateGraphStore.defaultStoreURL(),
         dbURL: URL = SimiGoPaths.databaseURL) {
        self.storeURL = storeURL
        self.dbURL = dbURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        // Legacy JSON is now ONLY a migration source: its bytes are captured, but
        // the file is never deleted or overwritten in place until a validated
        // hand-off to the authoritative store has provably covered it.
        if FileManager.default.fileExists(atPath: storeURL.path) {
            legacyJSONData = try? Data(contentsOf: storeURL)
        }

        // SQLite is the authoritative read store. Open it (importing any legacy
        // graph transactionally + validated) and rebuild the live graph FROM
        // SQLite — never from JSON — so the two can never drift apart.
        if let db = ensureESIS() {
            do {
                let g = try db.readGraph()
                let receipts = try db.readSettlementReceipts()
                document = Self.graphDocument(states: g.states, checkpoints: g.checkpoints,
                                              receipts: receipts)
                retireLegacyJSONIfNeeded(authoritativeIDs: g.states.map { $0.id })
            } catch {
                loadError = "无法从 SQLite 权威库加载执行图：\(error.localizedDescription)"
                document = ExecutionGraphDocument()
            }
        } else {
            // Fail-closed fallback: the authority is corrupt/unwritable. Serve the
            // read-only legacy JSON so the app still opens; never retire it here.
            loadLegacyJSONFallback()
        }
    }

    nonisolated static func defaultStoreURL() -> URL {
        // This store lives OUTSIDE the managed .simigo root (Application Support), so
        // SIMIGO_HOME does not move it. Without an explicit hook, a test run rewrites the
        // operator's real reference graph - the second non-isolatable sink found in the
        // RC1 audit. The override is opt-in; the default location is unchanged.
        if let override = ProcessInfo.processInfo.environment["SIMIGO_STATE_GRAPH_STORE"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).standardizingPath)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("SimiGo", isDirectory: true)
            .appendingPathComponent("StateGraph", isDirectory: true)
            .appendingPathComponent("reference-graph-v1.json")
    }

    func state(_ id: String?) -> ExecutionStateRecord? {
        states.first(where: { $0.id == id })
    }

    func children(of id: String) -> [ExecutionStateRecord] {
        states.filter { $0.parentID == id }
    }

    func checkpoints(for stateID: String) -> [ExecutionCheckpoint] {
        checkpoints.filter { $0.stateID == stateID }.sorted(by: { $0.createdAt > $1.createdAt })
    }

    func create() throws -> ExecutionStateRecord {
        try mutate { document in
            let id = Self.nextStateID(in: document.states)
            let state = ExecutionStateRecord(
                id: id,
                parentID: nil,
                modelIdentity: "reference-model",
                createdAt: Date(),
                position: 0,
                continuationID: UUID().uuidString,
                nextInput: "",
                anchor: Self.anchor([]),
                prefix: [],
                lifecycle: .active,
                checkpointIDs: []
            )
            document.states.append(state)
            return state
        }
    }

    @discardableResult
    func continueState(_ state: ExecutionStateRecord, input: String) throws -> ExecutionStateRecord {
        try mutate { document in
            guard let index = document.states.firstIndex(where: { $0.id == state.id }) else {
                throw ExecutionGraphError.invalidTransition("state not found")
            }
            guard document.states[index].lifecycle != .discarded else {
                throw ExecutionGraphError.invalidTransition("discarded state cannot continue")
            }
            guard !input.isEmpty else {
                throw ExecutionGraphError.invalidTransition("continuation input is empty")
            }

            var next = document.states[index]
            next.prefix.append(input)
            next.position += 1
            next.nextInput = input
            next.continuationID = UUID().uuidString
            next.anchor = Self.anchor(next.prefix)
            next.lifecycle = .active
            document.states[index] = next
            return next
        }
    }

    @discardableResult
    func save(_ state: ExecutionStateRecord) throws -> ExecutionCheckpoint {
        try mutate { document in
            guard let index = document.states.firstIndex(where: { $0.id == state.id }) else {
                throw ExecutionGraphError.invalidTransition("state not found")
            }
            guard document.states[index].lifecycle != .discarded else {
                throw ExecutionGraphError.invalidTransition("discarded state cannot save")
            }

            // save/checkpoint fixes the current closure into durable
            // representation; it does not create a new semantic state.
            let current = document.states[index]
            let checkpoint = ExecutionCheckpoint(
                id: UUID(),
                stateID: current.id,
                modelIdentity: current.modelIdentity,
                position: current.position,
                continuationID: current.continuationID,
                nextInput: current.nextInput,
                anchor: current.anchor,
                prefix: current.prefix,
                createdAt: Date(),
                checksum: Self.checksum(
                    stateID: current.id,
                    modelIdentity: current.modelIdentity,
                    position: current.position,
                    continuationID: current.continuationID,
                    nextInput: current.nextInput,
                    anchor: current.anchor,
                    prefix: current.prefix
                )
            )
            document.checkpoints.append(checkpoint)
            document.states[index].checkpointIDs.append(checkpoint.id)
            document.states[index].lifecycle = .saved
            return checkpoint
        }
    }

    @discardableResult
    func fork(_ parent: ExecutionStateRecord) throws -> ExecutionStateRecord {
        try mutate { document in
            guard document.states.contains(where: { $0.id == parent.id }) else {
                throw ExecutionGraphError.invalidTransition("parent not found")
            }
            guard parent.lifecycle != .discarded else {
                throw ExecutionGraphError.invalidTransition("discarded state cannot fork")
            }

            // A fork keeps the parent closure untouched and materializes the
            // child at the same position, anchor, and continuation closure.
            let child = ExecutionStateRecord(
                id: Self.nextStateID(in: document.states),
                parentID: parent.id,
                modelIdentity: parent.modelIdentity,
                createdAt: Date(),
                position: parent.position,
                continuationID: parent.continuationID,
                nextInput: parent.nextInput,
                anchor: parent.anchor,
                prefix: parent.prefix,
                lifecycle: .active,
                checkpointIDs: []
            )
            document.states.append(child)
            return child
        }
    }

    @discardableResult
    func restore(_ state: ExecutionStateRecord, checkpoint: ExecutionCheckpoint) throws -> ExecutionStateRecord {
        try Self.validate(checkpoint, for: state)

        return try mutate { document in
            guard let index = document.states.firstIndex(where: { $0.id == state.id }) else {
                throw ExecutionGraphError.invalidTransition("state not found")
            }
            guard document.states[index].lifecycle != .discarded else {
                throw ExecutionGraphError.invalidTransition("discarded state cannot restore")
            }
            guard document.checkpoints.contains(where: { $0.id == checkpoint.id }) else {
                throw ExecutionGraphError.invalidCheckpoint("checkpoint is not bound to this graph")
            }

            var restored = document.states[index]
            restored.position = checkpoint.position
            restored.continuationID = checkpoint.continuationID
            restored.nextInput = checkpoint.nextInput
            restored.anchor = checkpoint.anchor
            restored.prefix = checkpoint.prefix
            restored.lifecycle = .restored
            document.states[index] = restored
            return restored
        }
    }

    func discard(_ state: ExecutionStateRecord) throws {
        try mutate { document in
            guard let index = document.states.firstIndex(where: { $0.id == state.id }) else {
                throw ExecutionGraphError.invalidTransition("state not found")
            }
            guard document.states[index].lifecycle != .discarded else {
                throw ExecutionGraphError.invalidTransition("state is already discarded")
            }

            // Logical discard and durable release commit as one atomic graph
            // transition, preventing a discarded state with ghost checkpoints.
            let removed = Set(document.states[index].checkpointIDs)
            document.checkpoints.removeAll { removed.contains($0.id) }
            document.states[index].checkpointIDs = []
            document.states[index].lifecycle = .discarded
        }
    }

    func release(_ state: ExecutionStateRecord) throws {
        try mutate { document in
            guard let index = document.states.firstIndex(where: { $0.id == state.id }) else {
                throw ExecutionGraphError.invalidTransition("state not found")
            }

            // Release clears durable bindings only; it does not abolish the
            // logical state or invent a contract-external lifecycle.
            let removed = Set(document.states[index].checkpointIDs)
            document.checkpoints.removeAll { removed.contains($0.id) }
            document.states[index].checkpointIDs = []
            if document.states[index].lifecycle == .saved {
                document.states[index].lifecycle = .active
            }
        }
    }

    // MARK: - Native-authorized settlement (pre-settlement authority)

    /// Settle a producer's semantic result as a durable Information-Space record.
    ///
    /// `SimiGoSettlementAuthority` (native, MLX-free) is the single gate: it runs
    /// BEFORE any `mutate`/`persist`, so a contract rejection — unknown constraint,
    /// missing binding, canonicalization failure, or digest/derivation mismatch —
    /// throws here and NOTHING is written. There is no Python fallback and no
    /// partially settled record. Only the canonical validated payload is committed.
    @discardableResult
    func settleValidatedResult(
        generatedText: String,
        contractJSON: Data,
        verifiedBindings: [String: NativeContractValue],
        boundToState state: ExecutionStateRecord
    ) throws -> SimiGoSettlementAuthority.SettledResult {
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: generatedText,
            contractJSON: contractJSON,
            verifiedBindings: verifiedBindings
        )
        try mutate { document in
            guard document.states.contains(where: { $0.id == state.id }) else {
                throw ExecutionGraphError.invalidTransition("state not found")
            }
            let receipt = SettlementReceipt(
                id: UUID(),
                stateID: state.id,
                schemaVersion: settled.schemaVersion,
                payload: settled.validatedPayload,
                payloadDigest: settled.payloadDigest,
                settledAt: settled.settledAt
            )
            document.settlements = (document.settlements ?? []) + [receipt]
        }
        commitSettlementToAuthoritativeStore(settled, state: state)
        return settled
    }

    /// The declared result-contract for reference-state settlement.
    ///
    /// A single required `content` field is extracted from a `RESULT=` line and is
    /// constrained with `equals_binding` to commit to an Information-Space value
    /// (`next_input`) that is already persisted with the graph. It exercises the
    /// production-native constraint family only, so the gate never falls back to a
    /// Python validator, and an unknown/mismatched value refuses fail-closed.
    static let referenceResultContractJSON: Data = Data("{\"schema_version\":\"simigo.result-contract/v1\",\"fields\":{\"content\":{\"pattern\":\"^RESULT=(.+)$\",\"capture_group\":1,\"type\":\"string\",\"normalize\":\"trim\",\"nonempty\":true}},\"constraints\":[{\"kind\":\"equals_binding\",\"field\":\"content\",\"binding\":\"next_input\"}]}".utf8)

    /// Production settlement entry for a reference state.
    ///
    /// This is the real production caller of `settleValidatedResult` (and therefore
    /// of `SimiGoSettlementAuthority` / `NativeProducerResultContractGate` / the
    /// authoritative SQLite commit). The producer's generated text is bound to the
    /// state's already-settled `nextInput` — an IS value persisted with the graph.
    /// If the generated content does not commit to that value, the native gate
    /// throws BEFORE `settleValidatedResult` mutates or writes anything, so the
    /// action is fail-closed end to end and produces no partially settled record.
    @discardableResult
    func settleProducerResult(
        generatedText: String,
        boundToState state: ExecutionStateRecord
    ) throws -> SimiGoSettlementAuthority.SettledResult {
        let bindings: [String: NativeContractValue] = ["next_input": .string(state.nextInput)]
        return try settleValidatedResult(
            generatedText: generatedText,
            contractJSON: Self.referenceResultContractJSON,
            verifiedBindings: bindings,
            boundToState: state
        )
    }

    // MARK: - Authoritative SQLite commit + legacy migration

    /// Lazily open the authoritative SQLite store, run schema migrations, and on
    /// first open transactionally migrate any pre-existing JSON reference graph
    /// (validated row-by-row inside `importLegacyGraph`, rolled back on mismatch).
    private func ensureESIS() -> SimiGoESISDatabase? {
        if esisOpenAttempted { return esis }
        esisOpenAttempted = true
        do {
            let db = try SimiGoESISDatabase(url: dbURL)
            try db.runMigrations()
            if (try db.count("execution_states")) == 0,
               let legacy = legacyJSONData,
               !(try JSONDecoder().decode(ExecutionGraphDocument.self, from: legacy)).states.isEmpty {
                _ = try db.importLegacyGraph(jsonData: legacy, sourceLabel: storeURL.lastPathComponent)
                didImportLegacy = true
            }
            esis = db
            persistError = nil
        } catch {
            // Fail closed: never overwrite an unreadable / unwritable authority.
            esis = nil
            persistError = "SQLite ES/IS 不可用：\(error.localizedDescription)"
        }
        return esis
    }

    /// Mirror a gate-cleared settlement into the authoritative SQLite store.
    /// Non-fatal to the UI graph: a write failure is surfaced via `persistError`
    /// but never rolls back the already-authorized native settlement.
    private func commitSettlementToAuthoritativeStore(
        _ settled: SimiGoSettlementAuthority.SettledResult,
        state: ExecutionStateRecord
    ) {
        guard let db = ensureESIS() else { return }
        do {
            try db.recordExecutionState(
                id: state.id,
                parentID: state.parentID,
                modelIdentity: state.modelIdentity,
                position: state.position,
                continuationID: state.continuationID,
                anchor: state.anchor,
                lifecycle: state.lifecycle.rawValue,
                createdAt: state.createdAt
            )
            _ = try db.recordNativeSettlement(settled, stateID: state.id)
            persistError = nil
        } catch {
            persistError = "结算未能写入 SQLite ES/IS：\(error.localizedDescription)"
        }
    }

    // MARK: - Atomic transition helper

    private func mutate<T>(_ change: (inout ExecutionGraphDocument) throws -> T) throws -> T {
        if let loadError {
            throw ExecutionGraphError.storeUnavailable(loadError)
        }

        var next = document
        let result = try change(&next)
        try persist(next)
        document = next
        operationError = nil
        return result
    }

    private func persist(_ document: ExecutionGraphDocument) throws {
        // Write authority: the live execution graph (ES) is committed to SQLite.
        // Settlements (IS) are owned by the native gate and written separately, so
        // they are intentionally NOT part of this graph write.
        if let db = ensureESIS() {
            do {
                let states = document.states.map {
                    SimiGoESISDatabase.GraphState(
                        id: $0.id, parentID: $0.parentID, modelIdentity: $0.modelIdentity,
                        createdAt: $0.createdAt, position: $0.position,
                        continuationID: $0.continuationID, nextInput: $0.nextInput,
                        anchor: $0.anchor, prefix: $0.prefix, lifecycle: $0.lifecycle.rawValue,
                        checkpointIDs: $0.checkpointIDs)
                }
                let cps = document.checkpoints.map {
                    SimiGoESISDatabase.GraphCheckpoint(
                        id: $0.id, stateID: $0.stateID, modelIdentity: $0.modelIdentity,
                        position: $0.position, continuationID: $0.continuationID,
                        nextInput: $0.nextInput, anchor: $0.anchor, prefix: $0.prefix,
                        createdAt: $0.createdAt, checksum: $0.checksum)
                }
                try db.writeGraph(states: states, checkpoints: cps)
                persistError = nil
                retireLegacyJSONIfNeeded(authoritativeIDs: document.states.map { $0.id })
                return
            } catch {
                persistError = "执行图未能写入 SQLite 权威库：\(error.localizedDescription)"
                // Fall through to the JSON safety net so no durable state is lost.
            }
        }
        do {
            let directory = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(document).write(to: storeURL, options: [.atomic])
        } catch {
            throw ExecutionGraphError.storeUnavailable(error.localizedDescription)
        }
    }

    // MARK: - SQLite <-> document mapping and safe JSON retirement

    /// Rebuild the app's working document from authoritative SQLite rows.
    private static func graphDocument(
        states: [SimiGoESISDatabase.GraphState],
        checkpoints: [SimiGoESISDatabase.GraphCheckpoint],
        receipts: [SimiGoESISDatabase.SettlementReceiptRow]
    ) -> ExecutionGraphDocument {
        var doc = ExecutionGraphDocument()
        doc.states = states.map {
            ExecutionStateRecord(
                id: $0.id, parentID: $0.parentID, modelIdentity: $0.modelIdentity,
                createdAt: $0.createdAt, position: $0.position,
                continuationID: $0.continuationID, nextInput: $0.nextInput,
                anchor: $0.anchor, prefix: $0.prefix,
                lifecycle: ExecutionLifecycle(rawValue: $0.lifecycle) ?? .active,
                checkpointIDs: $0.checkpointIDs)
        }
        doc.checkpoints = checkpoints.map {
            ExecutionCheckpoint(
                id: $0.id, stateID: $0.stateID, modelIdentity: $0.modelIdentity,
                position: $0.position, continuationID: $0.continuationID,
                nextInput: $0.nextInput, anchor: $0.anchor, prefix: $0.prefix,
                createdAt: $0.createdAt, checksum: $0.checksum)
        }
        doc.settlements = receipts.map {
            SettlementReceipt(
                id: $0.id, stateID: $0.stateID, schemaVersion: $0.schemaVersion,
                payload: $0.payload, payloadDigest: $0.payloadDigest, settledAt: $0.settledAt)
        }
        return doc
    }

    /// Retire the legacy JSON only when it is PROVABLY covered by the authority:
    /// it was just imported, it holds no live states, or every one of its state ids
    /// already exists in SQLite. Otherwise the file is preserved untouched (SQLite
    /// still wins every read), so a validated hand-off can never lose data. The
    /// retirement itself is a rename that PRESERVES bytes — never a delete or an
    /// in-place overwrite.
    private func retireLegacyJSONIfNeeded(authoritativeIDs: [String]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path), let raw = legacyJSONData else { return }
        let legacyStates = (try? decoder.decode(ExecutionGraphDocument.self, from: raw))?.states ?? []
        let covered = legacyStates.isEmpty
            || didImportLegacy
            || Set(legacyStates.map { $0.id }).isSubset(of: Set(authoritativeIDs))
        guard covered else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let sidecar = storeURL.appendingPathExtension("migrated-\(stamp)")
        try? fm.moveItem(at: storeURL, to: sidecar)
        legacyJSONData = nil
    }

    /// Fail-closed read of the legacy JSON when the authority is unavailable.
    private func loadLegacyJSONFallback() {
        guard let raw = legacyJSONData else { return }
        do {
            let decoded = try decoder.decode(ExecutionGraphDocument.self, from: raw)
            guard decoded.contractVersion == ESContract.version else {
                throw ExecutionGraphError.invalidCheckpoint("contract version mismatch")
            }
            document = decoded
        } catch {
            loadError = "无法加载持久图：\(error.localizedDescription)"
            document = ExecutionGraphDocument()
        }
    }

    // MARK: - Representation rules

    static func anchor(_ prefix: [String]) -> String {
        hash(prefix.joined(separator: "\u{1F}"))
    }

    static func checksum(
        stateID: String,
        modelIdentity: String,
        position: Int,
        continuationID: String,
        nextInput: String,
        anchor: String,
        prefix: [String]
    ) -> String {
        let payload = [
            stateID,
            modelIdentity,
            String(position),
            continuationID,
            nextInput,
            anchor,
            prefix.joined(separator: "\u{1F}"),
        ].joined(separator: "\u{1E}")
        return "sha256-" + hash(payload)
    }

    static func validate(_ checkpoint: ExecutionCheckpoint, for state: ExecutionStateRecord) throws {
        guard checkpoint.stateID == state.id else {
            throw ExecutionGraphError.invalidCheckpoint("checkpoint belongs to another state")
        }
        guard checkpoint.modelIdentity == state.modelIdentity else {
            throw ExecutionGraphError.invalidCheckpoint("model identity mismatch")
        }
        guard checkpoint.anchor == anchor(checkpoint.prefix) else {
            throw ExecutionGraphError.invalidCheckpoint("anchor integrity failure")
        }
        let expected = checksum(
            stateID: checkpoint.stateID,
            modelIdentity: checkpoint.modelIdentity,
            position: checkpoint.position,
            continuationID: checkpoint.continuationID,
            nextInput: checkpoint.nextInput,
            anchor: checkpoint.anchor,
            prefix: checkpoint.prefix
        )
        guard checkpoint.checksum == expected else {
            throw ExecutionGraphError.invalidCheckpoint("record integrity failure")
        }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func nextStateID(in states: [ExecutionStateRecord]) -> String {
        let used = Set(states.map(\.id))
        var index = states.count + 1
        while true {
            let id = String(format: "S-%04d", index)
            if !used.contains(id) { return id }
            index += 1
        }
    }
}

struct ExecutionStateGraphView: View {
    @EnvironmentObject private var store: ExecutionStateGraphStore
    @State private var mode: Mode = .live
    @State private var selectedID: String?
    @State private var continuationInput = ""
    @State private var selectedCheckpointID: UUID?
    @State private var settleInput = ""

    /// 2026-10-16 收敛：窗口默认显示引擎真身（Live 只读投影）；
    /// 契约参考图（ES Contract v1.0-amended 的产品化演示）保留为切换页。
    private enum Mode: String, CaseIterable, Identifiable {
        case live = "实时引擎"
        case reference = "契约参考图"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("视图", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch mode {
            case .live:
                LiveExecutionStateView()
            case .reference:
                referenceBody
            }
        }
        .navigationTitle("Execution State")
        .frame(minWidth: 720, minHeight: 480)
    }

    private var referenceBody: some View {
        HSplitView {
            List {
                ForEach(store.states.filter { $0.parentID == nil }) { state in
                    StateNodeView(
                        state: state,
                        states: store.states,
                        selection: $selectedID
                    )
                }
            }
            .frame(minWidth: 260, idealWidth: 320)

            inspector
                .frame(minWidth: 380, idealWidth: 480)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.states.first?.id
            }
            if store.states.isEmpty, store.loadError == nil {
                do {
                    _ = try store.create()
                } catch {
                    store.operationError = String(describing: error)
                }
                selectedID = store.states.first?.id
            }
        }
    }

    private var selectedState: ExecutionStateRecord? {
        store.state(selectedID)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.loadError ?? store.operationError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            if let state = selectedState {
                detail(state)
            } else {
                Text("选择一个 State")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ state: ExecutionStateRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.id).font(.title2.weight(.semibold))
                Text("Representation: Reference")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            properties(state)

            continuationEditor
            lifecycleActions(state)
            settleSection(state)
            restoreSection(state)
            diagnostics

            Spacer()
        }
    }

    private func properties(_ state: ExecutionStateRecord) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Identity").foregroundStyle(.secondary)
                Text(state.id).font(.system(.body, design: .monospaced))
            }
            GridRow {
                Text("Parent").foregroundStyle(.secondary)
                Text(state.parentID ?? "root").font(.system(.body, design: .monospaced))
            }
            GridRow {
                Text("Position").foregroundStyle(.secondary)
                Text(String(state.position))
            }
            GridRow {
                Text("Anchor").foregroundStyle(.secondary)
                Text(String(state.anchor.prefix(16)))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            GridRow {
                Text("Continuation").foregroundStyle(.secondary)
                Text(state.continuationID).font(.system(.body, design: .monospaced))
            }
            GridRow {
                Text("Status").foregroundStyle(.secondary)
                Text(state.lifecycle.rawValue)
            }
            GridRow {
                Text("Durable").foregroundStyle(.secondary)
                Text(state.checkpointIDs.isEmpty ? "none" : "\(state.checkpointIDs.count) checkpoint(s)")
            }
        }
    }

    private var continuationEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Continue this State")
                .font(.headline)
            HStack {
                TextField("token", text: $continuationInput)
                    .textFieldStyle(.roundedBorder)
                Button("Continue") {
                    run { guard let state = selectedState else { return }
                        try store.continueState(state, input: continuationInput)
                        continuationInput = ""
                    }
                }
                .disabled(continuationInput.isEmpty || selectedState?.lifecycle == .discarded)
            }
        }
    }

    private func lifecycleActions(_ state: ExecutionStateRecord) -> some View {
        HStack {
            Button("Save") { run { try store.save(state) } }
                .disabled(state.lifecycle == .discarded)
            Button("Fork") { run { _ = try store.fork(state) } }
                .disabled(state.lifecycle == .discarded)
            Button("Release") { run { try store.release(state) } }
                .disabled(state.checkpointIDs.isEmpty)
            Button("Discard", role: .destructive) { run { try store.discard(state) } }
                .disabled(state.lifecycle == .discarded)
        }
    }

    /// Settlement action wired to the production native pre-settlement authority.
    ///
    /// The button calls `store.settleProducerResult`, which runs the native result-
    /// contract gate and only then commits to the authoritative SQLite store. On a
    /// contract refusal the error is surfaced in `store.operationError` and NOTHING
    /// is written (fail-closed), so this is a real, app-reachable production call
    /// chain rather than an orphaned API.
    private func settleSection(_ state: ExecutionStateRecord) -> some View {
        let receipts = (store.document.settlements ?? []).filter { $0.stateID == state.id }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Settle (Native Gate)").font(.headline)
            Text("Producer result must commit to this State's IS next-input: \"\(state.nextInput)\"")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                TextField("RESULT=<text>", text: $settleInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.lifecycle == .discarded)
                Button("Fill from IS") { settleInput = "RESULT=\(state.nextInput)" }
                    .disabled(state.nextInput.isEmpty)
            }
            HStack {
                Button("Settle via Native Gate") {
                    run { _ = try store.settleProducerResult(generatedText: settleInput, boundToState: state) }
                }
                .disabled(state.nextInput.isEmpty || settleInput.isEmpty || state.lifecycle == .discarded)
                Text(receipts.isEmpty ? "no settlement" : "\(receipts.count) settled")
                    .font(.footnote)
                    .foregroundStyle(receipts.isEmpty ? .secondary : .primary)
            }
        }
    }

    private func restoreSection(_ state: ExecutionStateRecord) -> some View {
        let points = store.checkpoints(for: state.id)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Restore").font(.headline)
            Picker("Checkpoint", selection: $selectedCheckpointID) {
                Text("none").tag(UUID?.none)
                ForEach(points) { checkpoint in
                    Text("\(checkpoint.position) · \(checkpoint.id.uuidString.prefix(8))")
                        .tag(UUID?.some(checkpoint.id))
                }
            }
            Button("Restore fail-closed") {
                run {
                    guard let checkpoint = points.first(where: { $0.id == selectedCheckpointID }) else {
                        throw ExecutionGraphError.invalidCheckpoint("select a checkpoint")
                    }
                    try store.restore(state, checkpoint: checkpoint)
                }
            }
            .disabled(selectedCheckpointID == nil || state.lifecycle == .discarded)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Representation Declaration") {
            Text(ESContract.declaration)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func run(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            store.operationError = String(describing: error)
        }
    }
}

private struct StateNodeView: View {
    let state: ExecutionStateRecord
    let states: [ExecutionStateRecord]
    @Binding var selection: String?

    private var children: [ExecutionStateRecord] {
        states.filter { $0.parentID == state.id }
    }

    var body: some View {
        if children.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: .constant(true)) {
                ForEach(children) { child in
                    StateNodeView(state: child, states: states, selection: $selection)
                }
            } label: {
                row
            }
        }
    }

    private var row: some View {
        Button {
            selection = state.id
        } label: {
            HStack {
                Image(systemName: state.lifecycle == .discarded ? "xmark.circle" : "circle.hexagongrid")
                    .foregroundStyle(state.lifecycle == .discarded ? Color.secondary : Color.accentColor)
                Text(state.id)
                    .font(.system(.body, design: .monospaced))
                Text(state.lifecycle.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(state.position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == state.id ? Color.accentColor.opacity(0.14) : Color.clear)
    }
}

/// 引擎真身视图（2026-10-16 收敛）：消费 Service 的只读投影，
/// 2s 轮询、task 随视图消失自动取消。无进程内运行时（外部进程 /
/// 云后端 / 已停止）显示占位说明——不伪造状态（遥测语义诚实红线）。
private struct LiveExecutionStateView: View {
    @EnvironmentObject private var svc: Service
    @State private var snapshot: EngineExecutionStateSnapshot?

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.slash")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("无进程内执行状态")
                    Text("外部进程 / 云后端运行中，或运行时已停止")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            while !Task.isCancelled {
                svc.refreshExecutionState()
                snapshot = svc.executionState
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func content(_ snapshot: EngineExecutionStateSnapshot) -> some View {
        List {
            Section("运行时") {
                LabeledContent("状态", value: snapshot.isRunning ? "运行中" : "已停止")
                LabeledContent("待入请求", value: "\(snapshot.pendingRequests)")
                LabeledContent("生成中", value: "\(snapshot.activeGenerations)")
                LabeledContent("活会话", value: "\(snapshot.sessions.count)")
            }

            Section("活会话（最近活跃在前）") {
                if snapshot.sessions.isEmpty {
                    Text("（无）").foregroundStyle(.secondary)
                }
                ForEach(snapshot.sessions, id: \.mapKey) { card in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.label)
                                .font(.system(.body, design: .monospaced))
                            Text("history \(card.historyCount) 条 · \(card.lastActivity.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            if card.requestScoped { badge("一次性", .secondary) }
                            if card.isRestoredSnapshot { badge("restore", .blue) }
                            if card.checkpointDirty { badge("dirty", .orange) }
                        }
                    }
                }
            }

            Section("分支血统（fork 溯源）") {
                if snapshot.forks.isEmpty {
                    Text("（无）").foregroundStyle(.secondary)
                }
                ForEach(Array(snapshot.forks.reversed().enumerated()), id: \.offset) { _, fork in
                    HStack {
                        // fork 溯源是完整 storageKey：紧凑标签可碰撞（同
                        // agent/尾段/branch），附完整键摘要保证可辨
                        // （2026-10-16 外审 F2 残余收口）。
                        Text("\(EngineExecutionStateSnapshot.forkProvenanceLabel(storageKey: fork.parent)) → \(EngineExecutionStateSnapshot.forkProvenanceLabel(storageKey: fork.child))")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(fork.at.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("执行血统（最近 \(min(snapshot.lineageRecords.count, 20)) 条）") {
                ForEach(Array(snapshot.lineageRecords.suffix(20).reversed()), id: \.executionId) { record in
                    HStack {
                        Text("exec \(record.executionId.prefix(6))")
                            .font(.system(.body, design: .monospaced))
                        statusLabel(record.status)
                        Spacer()
                        Text(duration(record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func statusLabel(_ status: ExecutionStatus) -> some View {
        let color: Color
        switch status {
        case .running: color = .blue
        case .completed: color = .green
        case .failed: color = .red
        case .cancelled: color = .orange
        }
        return Text(status.rawValue)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func duration(_ record: ExecutionRecord) -> String {
        guard let end = record.completedAt else { return "…" }
        return String(format: "%.1fs", end.timeIntervalSince(record.startedAt))
    }
}
