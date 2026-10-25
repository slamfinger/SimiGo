import Foundation
import Testing
import CContinuationSupport
import ExecutionCore
import InformationCore
import RelationCore

@Suite
struct CBIndependentPathTests {
    @Test
    func disabledRelationCarrierFailsClosed() {
        let store = DisabledRelationStore(reason: "C-B is Information-only")
        let relation = Relation(
            identity: RelationMinter.makeRelationID(
                subject: InformationID(rawValue: "after"),
                predicate: RelationPredicate(value: "observed-change-of"),
                object: InformationID(rawValue: "before")
            ),
            subject: InformationID(rawValue: "after"),
            predicate: RelationPredicate(value: "observed-change-of"),
            object: InformationID(rawValue: "before"),
            provenance: Provenance(producedAt: Date(), producedBy: "test")
        )

        #expect(throws: StudyError.self) { try store.store(relation) }
        #expect(throws: StudyError.self) { try store.fetch(by: relation.identity) }
    }

    @Test
    func cBInformationOnlyScopeFormsAndObservesWithoutRelationCarrierUse() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let informationStore = try SQLiteStore(path: root.appendingPathComponent("information.sqlite").path)
        let disabledRelationStore = DisabledRelationStore(reason: "C-B is Information-only")
        let scope = ExecutionScope(
            informationStore: informationStore,
            relationStore: disabledRelationStore
        )
        let information = Information(
            identity: informationStore.makeInformationID(
                content: #"{"lifecyclePhase":"S1_OBSERVED"}"#,
                provenance: Provenance(producedAt: Date(), producedBy: "test")
            ),
            content: #"{"lifecyclePhase":"S1_OBSERVED"}"#,
            provenance: Provenance(producedAt: Date(), producedBy: "test")
        )

        try scope.form(information)
        let observed = try scope.observe(information.identity)
        #expect(observed?.identity == information.identity)
        #expect(observed?.content == information.content)
    }
}
