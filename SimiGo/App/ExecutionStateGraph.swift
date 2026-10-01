import CryptoKit
import Combine
import SwiftUI

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

struct ExecutionGraphDocument: Codable, Hashable {
    var contractVersion = ESContract.version
    var representationID = ESContract.representationID
    var states: [ExecutionStateRecord] = []
    var checkpoints: [ExecutionCheckpoint] = []
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
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    var states: [ExecutionStateRecord] { document.states }
    var checkpoints: [ExecutionCheckpoint] { document.checkpoints }

    init(storeURL: URL = ExecutionStateGraphStore.defaultStoreURL()) {
        self.storeURL = storeURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            document = try decoder.decode(ExecutionGraphDocument.self, from: Data(contentsOf: storeURL))
            guard document.contractVersion == ESContract.version else {
                throw ExecutionGraphError.invalidCheckpoint("contract version mismatch")
            }
        } catch {
            // Fail closed: never overwrite an unreadable durable graph.
            loadError = "无法加载持久图：\(error.localizedDescription)"
            document = ExecutionGraphDocument()
        }
    }

    nonisolated static func defaultStoreURL() -> URL {
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
        do {
            let directory = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(document).write(to: storeURL, options: [.atomic])
        } catch {
            throw ExecutionGraphError.storeUnavailable(error.localizedDescription)
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
    @State private var selectedID: String?
    @State private var continuationInput = ""
    @State private var selectedCheckpointID: UUID?

    var body: some View {
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
                .frame(minWidth: 380, idealWidth: 480, maxHeight: .infinity)
        }
        .navigationTitle("Execution State")
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if selectedID == nil {
                selectedID = store.states.first?.id
            }
            if store.states.isEmpty, store.loadError == nil {
                try? store.create()
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
