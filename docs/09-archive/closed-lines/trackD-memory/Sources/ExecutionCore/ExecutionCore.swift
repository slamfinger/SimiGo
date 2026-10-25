// Execution Core — the first consumer layer over the frozen Cores.
//
// B-Impl scope (SIMIGO_LAB_B_DESIGN_20261003.md):
// - C1 binds the two frozen store boundaries and passes their S4/R4
//   surfaces straight through.
// - C2 forms before/after Information plus an observed-change Relation
//   using the existing immutable Core values only.
// - C3 deliberately has no hash-diffing, file scanning, watching or
//   trigger execution. Callers supply already-observed material.
//
// This is implementation-level support only. It neither runs nor
// records an R-B1 experiment result.

import Foundation
import InformationCore
import RelationCore

/// Where the before side of an observation comes from.
///
// ponytail: two allowed shapes only — the design needs exactly these;
// add sourceTime/position only when a real observation requires them.
public enum ObservationBaseline: Sendable {
    /// An already-addressable baseline. R-B1 must use this genuine form.
    case reference(InformationID)

    /// The design's form-if-missing capability. Not an R-B1 shortcut.
    case representation(String)
}

/// The three addressable values produced by one observed change.
public struct ObservedChangeFormation: Sendable {
    public let before: Information
    public let after: Information
    public let relation: Relation

    init(before: Information, after: Information, relation: Relation) {
        self.before = before
        self.after = after
        self.relation = relation
    }
}

public enum ExecutionScopeError: Error, Equatable, Sendable {
    case baselineNotFound(InformationID)
}

/// C1: a boundary consumer over any injected Core stores.
public struct ExecutionScope {
    private let informationStore: any InformationStore
    private let relationStore: any RelationStore

    public init(informationStore: any InformationStore, relationStore: any RelationStore) {
        self.informationStore = informationStore
        self.relationStore = relationStore
    }

    /// S4 fetch, unchanged.
    public func observe(_ identity: InformationID) throws -> Information? {
        try informationStore.fetch(by: identity)
    }

    /// R4 fetch, unchanged.
    public func observe(_ identity: RelationID) throws -> Relation? {
        try relationStore.fetch(by: identity)
    }

    /// Forms and persists an Information through the frozen S1/S2 chain.
    public func form(_ information: Information) throws {
        try informationStore.store(information)
    }

    /// Forms and persists a Relation through the frozen R1/R2 chain.
    public func form(_ relation: Relation) throws {
        try relationStore.store(relation)
    }

    /// C2: forms an observed after-state and its observed-change Relation.
    ///
    /// A `.representation` baseline is formed first, then the after-state,
    /// then the Relation. This is a Core-semantic composition, not an
    /// R-B1 run and not a substitute for a genuine R-B1 baseline.
    public func formObservedChange(
        entitySource: String,
        before: ObservationBaseline,
        afterRepresentation: String,
        observer: String,
        observedAt: Date
    ) throws -> ObservedChangeFormation {
        let provenance = Provenance(
            producedAt: observedAt,
            producedBy: observer,
            source: entitySource,
            extractionMode: "observation"
        )

        let baseline: Information
        switch before {
        case .reference(let identity):
            guard let existing = try informationStore.fetch(by: identity) else {
                throw ExecutionScopeError.baselineNotFound(identity)
            }
            baseline = existing
        case .representation(let content):
            baseline = Information(
                identity: Self.makeInformationID(content: content, provenance: provenance),
                content: content,
                provenance: provenance
            )
            try informationStore.store(baseline)
        }

        let after = Information(
            identity: Self.makeInformationID(content: afterRepresentation, provenance: provenance),
            content: afterRepresentation,
            provenance: provenance
        )
        try informationStore.store(after)

        let predicate = RelationPredicate(value: "observed-change-of")
        let relation = Relation(
            identity: RelationMinter.makeRelationID(
                subject: after.identity,
                predicate: predicate,
                object: baseline.identity
            ),
            subject: after.identity,
            predicate: predicate,
            object: baseline.identity,
            provenance: provenance
        )
        try relationStore.store(relation)

        return ObservedChangeFormation(
            before: baseline,
            after: after,
            relation: relation
        )
    }

    /// ExecutionCore's mechanism-side Information identity minting.
    /// The recipe stays private; callers see only opaque identities.
    private static func makeInformationID(content: String, provenance: Provenance) -> InformationID {
        InformationMinter.makeInformationID(
            namespace: "execution",
            content: content,
            source: provenance.source
        )
    }
}
