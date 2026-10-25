// SimiGoRuntimeMemory — the runtime-layer memory boundary consumer
// (Formal Integration Gate, decisions 1(b)/2(a)/3).
//
// Binds the frozen InformationStore boundary DIRECTLY (decision 2(a)):
// no facade, no reinterpretation — the ruled S1–S6 semantics pass
// through unchanged. This target knows nothing about SQLite, WAL,
// Physical Filing, palace, taxonomy or activation (decision 3).
//
// SimiGoRuntimeContract stays a pure zero-dependency contract layer —
// untouched by this target (decision 1(b)).

import Foundation
import InformationCore

/// The runtime-layer memory boundary: a minimal consumer of the frozen
/// `InformationStore` contract (S1–S6).
public struct RuntimeMemory {
    private let store: any InformationStore

    /// Injects any InformationStore implementation; the runtime layer
    /// never knows which Physical Filing backend serves it.
    public init(store: any InformationStore) {
        self.store = store
    }

    /// S1/S2/S3: persists a formed Information. Idempotent by identity —
    /// first-write-wins; an existing fact is never modified.
    public func persist(_ information: Information) throws {
        try store.store(information)
    }

    /// S4/S5: present → Information; absent → nil (never an error).
    public func retrieve(_ identity: InformationID) throws -> Information? {
        try store.fetch(by: identity)
    }
}
