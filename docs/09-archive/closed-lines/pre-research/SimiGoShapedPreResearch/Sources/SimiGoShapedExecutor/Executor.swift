// SimiGo-shaped cold-start executor (3.1(c) pre-research).
//
// Structural proof of P3: this layer imports ONLY `InformationCore`
// and binds ONLY `any InformationStore`. It contains zero SQLite, WAL,
// Physical Filing or backend symbols — the concrete backend is injected
// at the composition root (main.swift), exactly as a future
// SimiGoRuntime integration would inject it.

import Foundation
import InformationCore

/// A cold-start executor shaped like a SimiGo runtime consumer:
/// fresh process, no persisted history, forms and retrieves Information
/// exclusively through the InformationStore boundary.
struct ColdStartExecutor {
    private let store: any InformationStore

    init(store: any InformationStore) {
        self.store = store
    }

    /// Forms an Information from formation facts (S1 entry).
    func formInformation(identity: InformationID, content: String, provenance: Provenance) -> Information {
        Information(identity: identity, content: content, provenance: provenance)
    }

    /// S1: new identity → persist. S2: same → no-op confirm.
    /// S3: conflicting → no-op, first-write-wins.
    func persist(_ information: Information) throws {
        try store.store(information)
    }

    /// S4: present → Information. S5: absent → nil.
    func retrieve(_ identity: InformationID) throws -> Information? {
        try store.fetch(by: identity)
    }
}
