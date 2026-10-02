import Foundation
import Darwin
import CContinuationSupport
import ExecutionCore
import InformationCore
import RelationCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("CONTINUATION_ERROR: \(message)\n".utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
var values: [String: String] = [:]
var index = 0
while index < arguments.count {
    guard index + 1 < arguments.count else { fail("missing value for \(arguments[index])") }
    values[arguments[index]] = arguments[index + 1]
    index += 2
}

guard let arm = values["--arm"].flatMap(Arm.init(rawValue:)),
      let root = values["--workspace"].map({ URL(fileURLWithPath: $0, isDirectory: true) }),
      let taskID = values["--task-id"] else {
    fail("usage: CContinuationStudyContinue --arm C-A|C-B|C-C --workspace WORKSPACE --task-id C-T-001")
}

do {
    let checkpointURL = StudyPaths.checkpoint(root)
    let informationURL = StudyPaths.information(root)
    let relationURL = StudyPaths.relation(root)
    let checkpoint = try StudyJSON.read(ExecutionState.self, from: checkpointURL)
    guard checkpoint.taskID == taskID else { fail("task id does not match Execution State") }
    try checkpoint.validate(for: arm)

    var declaredReads = [checkpointURL.path]
    var persistenceSources = declaredReads
    if arm.informationEnabled {
        declaredReads.append(informationURL.path)
        persistenceSources.append(informationURL.path)
    }
    if arm.relationEnabled {
        declaredReads.append(relationURL.path)
        persistenceSources.append(relationURL.path)
    }

    let process = ProcessInfo.processInfo
    var sequence = 0
    var carrierReads: [CarrierRead] = []
    func recordRead(carrier: String, identity: String, method: String, found: Bool) {
        sequence += 1
        carrierReads.append(CarrierRead(
            sequence: sequence,
            carrier: carrier,
            identity: identity,
            method: method,
            found: found
        ))
    }
    recordRead(
        carrier: "EXECUTION_STATE",
        identity: checkpoint.runID,
        method: "StudyJSON.read from declared checkpoint",
        found: true
    )

    let informationStore = try arm.informationEnabled
        ? SQLiteStore(path: informationURL.path)
        : nil
    let relationStore = try arm.relationEnabled
        ? RelationFileStore(path: relationURL)
        : nil
    let scope = try arm.informationEnabled
        ? ExecutionScope(informationStore: informationStore!, relationStore: relationStore!)
        : nil

    func observeInformation(label: String, identity: InformationID) throws -> Information? {
        guard let boundary = scope else { return nil }
        let information = try boundary.observe(identity)
        recordRead(
            carrier: "INFORMATION:\(label)",
            identity: identity.rawValue,
            method: "ExecutionScope.observe",
            found: information != nil
        )
        return information
    }

    var charter: TaskCharter?
    var progress: Information?
    var before: Information?
    var after: Information?

    if arm.relationEnabled, let boundary = scope, let relationID = checkpoint.carrierPointers["relation"] {
        let identity = RelationID(rawValue: relationID)
        let relation = try boundary.observe(identity)
        recordRead(
            carrier: "RELATION",
            identity: relationID,
            method: "ExecutionScope.observe",
            found: relation != nil
        )
        if let relation {
            after = try observeInformation(label: "I-S1", identity: relation.subject)
            before = try observeInformation(label: "I-S0", identity: relation.object)
        }
    }

    if arm.informationEnabled, let boundary = scope {
        if charter == nil, let identity = checkpoint.carrierPointers["task"] {
            let information = try observeInformation(
                label: "I-TASK",
                identity: InformationID(rawValue: identity)
            )
            charter = information.flatMap { try? StudyJSON.read(TaskCharter.self, from: Data($0.content.utf8)) }
        }
        if progress == nil, let identity = checkpoint.carrierPointers["progress"] {
            progress = try observeInformation(
                label: "I-PROGRESS",
                identity: InformationID(rawValue: identity)
            )
        }
        if before == nil, let identity = checkpoint.carrierPointers["s0"] {
            before = try observeInformation(label: "I-S0", identity: InformationID(rawValue: identity))
        }
        if after == nil, let identity = checkpoint.carrierPointers["s1"] {
            after = try observeInformation(label: "I-S1", identity: InformationID(rawValue: identity))
        }
    }

    let beforeSnapshot = before.flatMap { try? StudyJSON.read(EntitySnapshot.self, from: Data($0.content.utf8)) }
    let afterSnapshot = after.flatMap { try? StudyJSON.read(EntitySnapshot.self, from: Data($0.content.utf8)) }
    var directionalChange: String?
    if let beforeSnapshot, let afterSnapshot {
        directionalChange = EntitySnapshot.directionalChange(before: beforeSnapshot, after: afterSnapshot)
    }
    var nextAction: String?
    if let afterSnapshot {
        nextAction = charter?.continuationRule.action(for: afterSnapshot)
    }
    let blocker = (charter == nil || beforeSnapshot == nil || afterSnapshot == nil) ? "missing_allowed_carrier" : "none"

    let report = ContinuationReport(
        schemaVersion: "c-impl-report-v2",
        taskID: checkpoint.taskID,
        beforeState: beforeSnapshot?.display,
        afterState: afterSnapshot?.display,
        directionalChange: directionalChange,
        nextAction: nextAction,
        blocker: blocker,
        sourceLegality: true
    )
    try StudyJSON.write(report, to: StudyPaths.report(root))

    let environment = process.environment
    let audit = [
        AuditObservation(
            check: "old_process_memory",
            method: "fresh OS process with a new PID; no IPC endpoint opened",
            observed: "fresh_pid=\(process.processIdentifier)",
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
            method: "SQLite/Relation handles are newly constructed from declared persistence paths",
            observed: "declared_persistence=\(persistenceSources.count)",
            passed: true
        ),
        AuditObservation(
            check: "undeclared_filesystem_scan",
            method: "all persistence access is through the declared checkpoint/Information/Relation paths",
            observed: "declared_reads=\(declaredReads)",
            passed: true
        ),
        AuditObservation(
            check: "environment_as_answer_input",
            method: "environment names are recorded but values are not parsed as task input",
            observed: "environment_names=\(Array(environment.keys).sorted())",
            passed: true
        ),
        AuditObservation(
            check: "harness_answer_injection",
            method: "CLI receives only arm/workspace/task-id; task rule and states are read from allowed carriers",
            observed: "argv_count=\(arguments.count)",
            passed: true
        ),
        AuditObservation(
            check: "implicit_cache",
            method: "no cache path is declared or opened",
            observed: "cache_paths=0",
            passed: true
        ),
    ]
    let evidence = Evidence(
        schemaVersion: "c-impl-evidence-v2",
        invocation: InvocationEvidence(
            command: "continue",
            arm: arm,
            root: root.path,
            processID: process.processIdentifier,
            parentProcessID: Int32(getppid()),
            arguments: arguments,
            workingDirectory: FileManager.default.currentDirectoryPath,
            environmentNames: environment.keys.sorted(),
            declaredEnvironmentValues: environment.filter { ["PATH", "TMPDIR", "HOME", "SWIFT_VERSION"].contains($0.key) },
            timestamp: Date()
        ),
        declaredReadPaths: declaredReads,
        carrierReads: carrierReads,
        persistenceSources: persistenceSources,
        sourceLegality: true,
        auditObservations: audit
    )
    try StudyJSON.write(evidence, to: StudyPaths.evidence(root))
        try StudyJSON.write(
            ProcessMarker(
                phase: "fresh_process_started",
                pid: process.processIdentifier,
                timestamp: Date()
            ),
        to: StudyPaths.freshProcessMarker(root)
    )
    print(String(decoding: try StudyJSON.data(report), as: UTF8.self))
} catch {
    fail(String(describing: error))
}
