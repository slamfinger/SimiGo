// Integration Boundary Gate — upper-layer consumer (SPEC I6/I8).
//
// This file is the structural proof of the stable boundary:
// it imports ONLY `InformationCore`, binds ONLY `any InformationStore`,
// and contains ZERO SQLite/WAL/transaction/filing symbols. Swapping the
// Physical Filing backend must not require touching this file.

import InformationCore

/// An upper-layer consumer of the Information Core.
///
/// It forms Information values (formation facts arrive from outside;
/// the identity comes from a mechanism-side minter at the composition
/// root), persists them through the `InformationStore` boundary, and
/// retrieves them by identity. It knows nothing about how persistence
/// works.
struct UpperLayer {
    /// The stable boundary (I8). Concrete backend injected at the
    /// composition root.
    private let store: any InformationStore

    init(store: any InformationStore) {
        self.store = store
    }

    /// Forms an Information in this layer from formation facts (I1) —
    /// by the time it exists it is complete and immutable (A1/A2′).
    func formInformation(identity: InformationID, content: String, provenance: Provenance, temporal: ContentDate?) -> Information {
        Information(identity: identity, content: content, provenance: provenance, temporal: temporal)
    }

    /// Real call chain, hop 1: upper layer → InformationStore (I1).
    func persist(_ information: Information) throws {
        try store.store(information)
    }

    /// Real call chain, hop 2: InformationID → InformationStore → back (I2/I3).
    func retrieve(_ identity: InformationID) throws -> Information? {
        try store.fetch(by: identity)
    }
}
