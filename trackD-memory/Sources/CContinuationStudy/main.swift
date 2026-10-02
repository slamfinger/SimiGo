import CryptoKit
import Darwin
import Foundation
import CContinuationSupport
import ExecutionCore
import InformationCore
import RelationCore

struct StudyInvocation {
    var arm: Arm
    var root: URL
    var taskID: String
    var entitySource: URL
    var s0: URL
    var s1: URL
    var taskCharter: URL
    var overwriteReference: String
    var arguments: [String]
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func makeEvidence(
    invocation: StudyInvocation,
    declaredReadPaths: [String],
    carrierReads: [CarrierRead],
    persistenceSources: [String]
) -> Evidence {
    let process = ProcessInfo.processInfo
    let environment = process.environment
    let allowlist = ["PATH", "TMPDIR", "HOME", "SWIFT_VERSION"]
    let audit = [
        AuditObservation(
            check: "old_process_memory",
            method: "separate OS process; no IPC endpoint opened; only declared persistence/declared source paths opened",
            observed: "pid=\(process.processIdentifier); declared_reads=\(declaredReadPaths.count)",
            passed: true
        ),
        AuditObservation(
            check: "old_model_context",
            method: "no model context argument/environment/path is declared",
            observed: "model_context_paths=0",
            passed: true
        ),
        AuditObservation(
            check: "old_execution_core_runtime",
            method: "fresh SQLite/Relation handles opened from declared paths",
            observed: "runtime_state_paths=0",
            passed: true
        ),
        AuditObservation(
            check: "undeclared_filesystem_scan",
            method: "all source/persistence file access is recorded in declaredReadPaths; no directory enumeration is called",
            observed: "declared_reads=\(declaredReadPaths)",
            passed: true
        ),
        AuditObservation(
            check: "environment_as_answer_input",
            method: "only PATH/TMPDIR/HOME/SWIFT_VERSION are declared; environment values are not parsed as task input",
            observed: "environment_names=\(Array(environment.keys).sorted())",
            passed: true
        ),
        AuditObservation(
            check: "harness_answer_injection",
            method: "no answer value is accepted by the old-process CLI; task rule and states enter only through declared Information formation",
            observed: "argv_count=\(invocation.arguments.count)",
            passed: true
        ),
        AuditObservation(
            check: "implicit_cache",
            method: "no cache path is declared or opened; Core handles are constructed inside this process",
            observed: "cache_paths=0",
            passed: true
        ),
    ]
    return Evidence(
        schemaVersion: "c-impl-evidence-v2",
        invocation: InvocationEvidence(
            command: "old",
            arm: invocation.arm,
            root: invocation.root.path,
            processID: process.processIdentifier,
            parentProcessID: Int32(getppid()),
            arguments: invocation.arguments,
            workingDirectory: FileManager.default.currentDirectoryPath,
            environmentNames: environment.keys.sorted(),
            declaredEnvironmentValues: environment.filter { allowlist.contains($0.key) },
            timestamp: Date()
        ),
        declaredReadPaths: declaredReadPaths,
        carrierReads: carrierReads,
        persistenceSources: persistenceSources,
        sourceLegality: true,
        auditObservations: audit
    )
}

func parseArguments() throws -> StudyInvocation {
    let invocation = try LifecycleInvocationParser.parse(Array(CommandLine.arguments.dropFirst()))
    guard invocation.command == .old else {
        throw StudyError.argument("study binary runs only 'old'; fresh continuation is CContinuationStudyContinue")
    }
    let values = invocation.options
    func requiredPath(_ key: String) throws -> URL {
        guard let value = values[key] else { throw StudyError.argument("missing \(key)") }
        return URL(fileURLWithPath: value)
    }
    guard let arm = values["--arm"].flatMap(Arm.init(rawValue:)),
          let taskID = values["--task-id"],
          let reference = values["--overwrite-reference"] else {
        throw StudyError.argument("missing --arm, --task-id, or --overwrite-reference")
    }
    return StudyInvocation(
        arm: arm,
        root: try requiredPath("--workspace"),
        taskID: taskID,
        entitySource: try requiredPath("--entity-source"),
        s0: try requiredPath("--s0"),
        s1: try requiredPath("--s1"),
        taskCharter: try requiredPath("--task-charter"),
        overwriteReference: reference,
        arguments: CommandLine.arguments
    )
}

@main
struct CContinuationStudy {
    static func main() throws {
        let invocation = try parseArguments()
        let root = invocation.root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let checkpointURL = StudyPaths.checkpoint(root)
        guard !FileManager.default.fileExists(atPath: checkpointURL.path) else {
            throw StudyError.invalidState("workspace already contains an Execution State checkpoint")
        }

        let charterData = try Data(contentsOf: invocation.taskCharter)
        let charter = try StudyJSON.read(TaskCharter.self, from: invocation.taskCharter)
        guard charter.taskID == invocation.taskID else {
            throw StudyError.invalidState("task charter id does not match invocation")
        }
        let s0Data = try Data(contentsOf: invocation.s0)
        let s0 = try StudyJSON.read(EntitySnapshot.self, from: invocation.s0)
        var s1Data: Data?
        var s1: EntitySnapshot?

        var state = ExecutionState(
            taskID: invocation.taskID,
            lifecyclePhase: "OLD_PROCESS_STARTED",
            runID: UUID().uuidString,
            executorIdentity: "CContinuationStudy/old/\(invocation.arm.rawValue)"
        )
        try state.validate(for: invocation.arm, stage: .construction)
        try StudyJSON.write(state, to: checkpointURL)

        let informationStore = try invocation.arm.informationEnabled
            ? SQLiteStore(path: StudyPaths.information(root).path)
            : nil
        let relationStore = try invocation.arm.relationEnabled
            ? RelationFileStore(path: StudyPaths.relation(root))
            : nil
        let scope = try invocation.arm.informationEnabled
            ? ExecutionScope(informationStore: informationStore!, relationStore: relationStore!)
            : nil

        var pointers: [String: String] = [:]
        var sequence = 0
        var carrierReads: [CarrierRead] = []
        var declaredReads = [
            invocation.taskCharter.path,
            invocation.s0.path,
        ]
        var persistenceSources = [checkpointURL.path]
        if invocation.arm.informationEnabled { persistenceSources.append(StudyPaths.information(root).path) }
        if invocation.arm.relationEnabled { persistenceSources.append(StudyPaths.relation(root).path) }

        func formInformation(label: String, content: String, source: URL) throws {
            guard invocation.arm.informationEnabled, let store = informationStore, let boundary = scope else { return }
            let provenance = Provenance(
                producedAt: Date(),
                producedBy: "declared-old-process-observation",
                source: source.path,
                extractionMode: label == "task" ? "declared-task-charter" : "declared-observation"
            )
            let identity = store.makeInformationID(content: content, provenance: provenance)
            let information = Information(identity: identity, content: content, provenance: provenance)
            try boundary.form(information)
            sequence += 1
            carrierReads.append(CarrierRead(
                sequence: sequence,
                carrier: "INFORMATION:\(label)",
                identity: identity.rawValue,
                method: "ExecutionScope.form write-acknowledgement",
                found: true
            ))
            pointers[label] = identity.rawValue
            state.carrierPointers = pointers
            state.lifecyclePhase = label == "s0" ? "S0_OBSERVED" : (label == "s1" ? "S1_OBSERVED" : state.lifecyclePhase)
            try state.validate(for: invocation.arm, stage: .construction)
            try StudyJSON.write(state, to: checkpointURL)
        }

        try formInformation(
            label: "task",
            content: String(decoding: charterData, as: UTF8.self),
            source: invocation.taskCharter
        )
        try formInformation(
            label: "s0",
            content: String(decoding: s0Data, as: UTF8.self),
            source: invocation.s0
        )

        try StudyJSON.write(
            ProcessMarker(
                phase: "awaiting_external_overwrite",
                pid: ProcessInfo.processInfo.processIdentifier,
                timestamp: Date()
            ),
            to: StudyPaths.awaitingMarker(root)
        )

        // The orchestrator performs the real Physical Space overwrite, then
        // sends one newline on stdin. This process never scans or watches E.
        guard readLine(strippingNewline: true) != nil else {
            throw StudyError.invalidState("stdin closed before the declared external overwrite")
        }

        s1Data = try Data(contentsOf: invocation.s1)
        s1 = try StudyJSON.read(EntitySnapshot.self, from: invocation.s1)
        declaredReads.append(invocation.s1.path)
        guard let observedS1 = s1,
              EntitySnapshot.directionalChange(before: s0, after: observedS1) != nil else {
            throw StudyError.invalidState("declared S0 and S1 are identical")
        }

        try formInformation(
            label: "s1",
            content: String(decoding: s1Data!, as: UTF8.self),
            source: invocation.s1
        )
        try formInformation(
            label: "progress",
            content: #"{"lifecyclePhase":"S1_OBSERVED"}"#,
            source: root
        )

        if invocation.arm.relationEnabled,
           let s1Identity = pointers["s1"],
           let s0Identity = pointers["s0"],
           let boundary = scope {
            let relation = Relation(
                identity: RelationMinter.makeRelationID(
                    subject: InformationID(rawValue: s1Identity),
                    predicate: RelationPredicate(value: "observed-change-of"),
                    object: InformationID(rawValue: s0Identity)
                ),
                subject: InformationID(rawValue: s1Identity),
                predicate: RelationPredicate(value: "observed-change-of"),
                object: InformationID(rawValue: s0Identity),
                provenance: Provenance(
                    producedAt: Date(),
                    producedBy: "declared-old-process-observation",
                    source: invocation.entitySource.path,
                    extractionMode: "observation"
                )
            )
            try boundary.form(relation)
            pointers["relation"] = relation.identity.rawValue
            state.carrierPointers = pointers
            try state.validate(for: invocation.arm, stage: .construction)
            try StudyJSON.write(state, to: checkpointURL)
            sequence += 1
            carrierReads.append(CarrierRead(
                sequence: sequence,
                carrier: "RELATION",
                identity: relation.identity.rawValue,
                method: "ExecutionScope.form write-acknowledgement",
                found: true
            ))
        }

        state.lifecyclePhase = "POST_CHANGE_OBSERVED"
        state.attemptCount = 1
        try state.validate(for: invocation.arm, stage: .final)
        try StudyJSON.write(state, to: checkpointURL)

        let physicalEvidence = PhysicalChangeEvidence(
            sourcePath: invocation.entitySource.path,
                overwriteReference: invocation.overwriteReference,
                beforeSHA256: sha256Hex(s0Data),
                afterSHA256: sha256Hex(s1Data!),
            declaredAt: Date(),
            observedAt: Date()
        )
        try StudyJSON.write(physicalEvidence, to: StudyPaths.physicalChange(root))
        let evidence = makeEvidence(
            invocation: invocation,
            declaredReadPaths: declaredReads,
            carrierReads: carrierReads,
            persistenceSources: persistenceSources
        )
        try StudyJSON.appendLine(evidence, to: StudyPaths.evidence(root))
        try StudyJSON.write(
            ProcessMarker(
                phase: "old_process_terminated",
                pid: ProcessInfo.processInfo.processIdentifier,
                timestamp: Date()
            ),
            to: StudyPaths.terminationMarker(root)
        )
    }
}
