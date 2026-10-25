// Relation Core — the `Relation` semantic boundary (Phase 2, D1–D3).
//
// Implements the ruled minimal model: Relation is an immutable directed
// connection BETWEEN two Information facts. It references Information
// by identity — it never redefines entities, never carries content of
// its own beyond the connection, and is a PARALLEL semantic object to
// Information, not a child of it.
//
// Ruled facts implemented here:
// - D1  Endpoints are `InformationID` references. InformationID is
//       never downgraded to a bare string; free-string endpoints are an
//       external/legacy capability and do not exist in this surface.
// - D2  `RelationID` is an opaque semantic identity, deterministically
//       minted by a mechanism-side minter. The recipe never appears in
//       the semantic API. (The service tree's datetime-salted,
//       non-idempotent triple IDs are recorded negative evidence.)
// - D3  Immutable. No validFrom/validTo/active/terminated/status fields
//       exist; temporal validity is NOT part of the Phase 2 minimal
//       surface, and a relation's end, if ever needed, will be a NEW
//       fact — never a back-write.
// - NS  No predicate vocabulary, registry, taxonomy or ontology: the
//       predicate is a semantic slot with a minimal value carrier only.

import Foundation
import InformationCore

/// The opaque semantic identity of a `Relation` (D2).
///
/// A fact about a Relation, produced by a mechanism-side minter. No
/// recipe, version, timestamp-salt or encoding surface exists here.
public struct RelationID: Hashable, Sendable {
    /// The persistent raw form of this identity.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The named connection kind of a `Relation` — a semantic SLOT only.
///
/// Minimal value carrier (registered implementation decision): no
/// vocabulary, no enum, no registry, no taxonomy. What a predicate
/// *means* is outside this Core.
public struct RelationPredicate: Hashable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

/// An immutable, already-formed directed relation between two
/// Information facts (D1/D3).
///
/// Formation mirrors A2′: facts + context → mechanism-side minter →
/// `RelationID` → immutable `Relation` → store. Endpoints reference
/// Information *by identity*; a Relation does not contain, interpret
/// or activate the Information it connects.
public struct Relation: Hashable, Sendable {
    /// The semantic identity of this Relation (D2).
    public let identity: RelationID
    /// The subject endpoint (an Information identity, D1).
    public let subject: InformationID
    /// The named connection kind (semantic slot, no vocabulary).
    public let predicate: RelationPredicate
    /// The object endpoint (an Information identity, D1).
    public let object: InformationID
    /// Origin and production facts (mirrors A3 fact-grouping).
    public let provenance: Provenance

    public init(
        identity: RelationID,
        subject: InformationID,
        predicate: RelationPredicate,
        object: InformationID,
        provenance: Provenance
    ) {
        self.identity = identity
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.provenance = provenance
    }
}
