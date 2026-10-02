import Foundation
import InformationCore
import RelationCore
import Testing
import ExecutionCore

private final class MemoryInformationStore: InformationStore {
    private var storage: [String: Information] = [:]

    public func store(_ information: Information) throws {
        storage[information.identity.rawValue, default: information] = information
    }

    public func fetch(by identity: InformationID) throws -> Information? {
        storage[identity.rawValue]
    }
}

private final class MemoryRelationStore: RelationStore {
    private var storage: [String: Relation] = [:]

    public func store(_ relation: Relation) throws {
        storage[relation.identity.rawValue, default: relation] = relation
    }

    public func fetch(by identity: RelationID) throws -> Relation? {
        storage[identity.rawValue]
    }
}

@Suite
struct ExecutionCoreTests {
    private let date = Date(timeIntervalSinceReferenceDate: 0)

    @Test
    func observeAndFormUseStoreBoundaries() throws {
        let informationStore = MemoryInformationStore()
        let relationStore = MemoryRelationStore()
        let scope = ExecutionScope(informationStore: informationStore, relationStore: relationStore)
        let information = Information(
            identity: InformationID(rawValue: "i1"),
            content: "S0",
            provenance: Provenance(producedAt: date, producedBy: "observer")
        )

        try scope.form(information)
        let relation = Relation(
            identity: RelationID(rawValue: "r1"),
            subject: information.identity,
            predicate: RelationPredicate(value: "observed-change-of"),
            object: information.identity,
            provenance: information.provenance
        )
        try scope.form(relation)

        #expect(try scope.observe(information.identity) == information)
        #expect(try scope.observe(relation.identity) == relation)
    }

    @Test
    func existingBaselineFormsAfterAndRelationWithoutRewritingIt() throws {
        let scope = ExecutionScope(
            informationStore: MemoryInformationStore(),
            relationStore: MemoryRelationStore()
        )
        let baseline = Information(
            identity: InformationID(rawValue: "before"),
            content: "S0",
            provenance: Provenance(producedAt: date, producedBy: "observer", source: "/tmp/E")
        )
        try scope.form(baseline)

        let formed = try scope.formObservedChange(
            entitySource: "/tmp/E",
            before: .reference(baseline.identity),
            afterRepresentation: "S1",
            observer: "observer",
            observedAt: date
        )

        #expect(formed.before == baseline)
        #expect(formed.after.content == "S1")
        #expect(formed.after.provenance.extractionMode == "observation")
        #expect(formed.relation.subject == formed.after.identity)
        #expect(formed.relation.predicate.value == "observed-change-of")
        #expect(formed.relation.object == baseline.identity)
        #expect(try scope.observe(formed.after.identity) == formed.after)
        #expect(try scope.observe(formed.relation.identity) == formed.relation)
    }

    @Test
    func missingBaselineCapabilityFormsBothStates() throws {
        // Unit-level capability check only: this is not an R-B1 run and
        // does not substitute for the R-B1 genuine before baseline.
        let scope = ExecutionScope(
            informationStore: MemoryInformationStore(),
            relationStore: MemoryRelationStore()
        )

        let formed = try scope.formObservedChange(
            entitySource: "/tmp/E",
            before: .representation("S0"),
            afterRepresentation: "S1",
            observer: "observer",
            observedAt: date
        )

        #expect(formed.before.content == "S0")
        #expect(formed.after.content == "S1")
        #expect(try scope.observe(formed.before.identity) == formed.before)
    }

    @Test
    func missingReferenceBaselineIsBlocked() {
        let scope = ExecutionScope(
            informationStore: MemoryInformationStore(),
            relationStore: MemoryRelationStore()
        )

        #expect(throws: ExecutionScopeError.baselineNotFound(InformationID(rawValue: "missing"))) {
            try scope.formObservedChange(
                entitySource: "/tmp/E",
                before: .reference(InformationID(rawValue: "missing")),
                afterRepresentation: "S1",
                observer: "observer",
                observedAt: date
            )
        }
    }
}
