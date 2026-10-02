// Integration Boundary Gate — composition root + invariant runner.
//
// The composition root is the ONLY place allowed to know the concrete
// backend (SPEC §3.4). Everything downstream of the injection runs
// against `any InformationStore`.

import Foundation
import InformationCore

let databasePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "integration.sqlite"

// ——— Composition root (the single SQLite-aware line of this Gate) ———
let physicalStore = try SQLiteStore(
    path: databasePath,
    filing: PhysicalFiling(wing: "integration", room: "boundary-gate")
)

// ——— Injection: upper layer sees ONLY the boundary (I6/I8) ———
let upperLayer = UpperLayer(store: physicalStore)

// ——— Formation context ———
let formationFacts = Provenance(
    producedAt: Date(timeIntervalSince1970: 1_790_940_000),
    producedBy: "integration-upper-layer",
    source: "upper-layer-formation-context.md",
    position: SourcePosition(chunkIndex: 1)
)
let identity = physicalStore.makeInformationID(
    content: "Integration Boundary Gate — 上层形成的 Information（verbatim ⺁）",
    provenance: formationFacts
)

// I1: upper layer forms and persists through the boundary.
let formed = upperLayer.formInformation(
    identity: identity,
    content: "Integration Boundary Gate — 上层形成的 Information（verbatim ⺁）",
    provenance: formationFacts,
    temporal: ContentDate(iso8601: "2026-10-02", source: .unknown)
)
try upperLayer.persist(formed)
print("PASS I1 upper-layer-formed Information persisted through the boundary")

// I2: same semantic value retrieved by identity.
let retrieved = try upperLayer.retrieve(identity)
assert(retrieved != nil, "FAIL I2: retrieval nil after persist")
assert(retrieved == formed, "FAIL I2: roundtrip value differs")
print("PASS I2 identity roundtrip returns the same semantic value")

// I3: absence is nil.
let absent = try upperLayer.retrieve(InformationID(rawValue: "absent0000000000000000"))
assert(absent == nil, "FAIL I3: absence is not nil")
print("PASS I3 absence = nil")

// I4: duplicate store is idempotent.
try upperLayer.persist(formed)
let afterDuplicate = try upperLayer.retrieve(identity)
assert(afterDuplicate == retrieved, "FAIL I4: duplicate store changed the fact")
print("PASS I4 duplicate store idempotent")

print("RUNTIME INVARIANTS I1–I4: ALL PASS")
print("DBPATH=\(databasePath)")
print("STRUCTURAL INVARIANTS I5–I8: verified by external audit (grep + sqlite3 CLI) — see gate record")
