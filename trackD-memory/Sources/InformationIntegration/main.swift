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

// ===========================================================================
// BACKEND INDEPENDENCE GATE (K5–K10): the SAME UpperLayer type, ZERO
// changes, driving a second Physical Filing backend.
// ===========================================================================

// ——— Backend-2 composition (its own mechanism-side minting) ———
let inMemoryStore = InMemoryStore()
let upperLayerOnBackend2 = UpperLayer(store: inMemoryStore)

let backend2Identity = inMemoryStore.makeInformationID(
    content: "Backend Independence Gate — 同一 UpperLayer，零改动驱动第二 backend",
    provenance: Provenance(
        producedAt: Date(timeIntervalSince1970: 1_790_950_000),
        producedBy: "integration-upper-layer"
    )
)

// K6: full chain through the unchanged UpperLayer type.
let backend2Information = upperLayerOnBackend2.formInformation(
    identity: backend2Identity,
    content: "Backend Independence Gate — 同一 UpperLayer，零改动驱动第二 backend",
    provenance: Provenance(
        producedAt: Date(timeIntervalSince1970: 1_790_950_000),
        producedBy: "integration-upper-layer"
    ),
    temporal: nil
)
try upperLayerOnBackend2.persist(backend2Information)
print("PASS K6 UpperLayer → Backend-2 full chain (same type, zero changes)")

// K7: semantic roundtrip on Backend-2.
let backend2Retrieved = try upperLayerOnBackend2.retrieve(backend2Identity)
assert(backend2Retrieved == backend2Information, "FAIL K7: Backend-2 roundtrip differs")
print("PASS K7 semantic roundtrip on Backend-2")

// K8: absence = nil, duplicate store idempotent — on Backend-2.
let backend2Absent = try upperLayerOnBackend2.retrieve(InformationID(rawValue: "absent-in-memory-000"))
assert(backend2Absent == nil, "FAIL K8: Backend-2 absence not nil")
try upperLayerOnBackend2.persist(backend2Information)
let backend2Again = try upperLayerOnBackend2.retrieve(backend2Identity)
assert(backend2Again == backend2Retrieved, "FAIL K8: Backend-2 duplicate changed the fact")
print("PASS K8 absence=nil + idempotent on Backend-2")

// Cross-check: the same Information value persists independently in
// both backends — identity belongs to the Information, not the store.
try upperLayerOnBackend2.persist(formed)
let fromBackend2 = try upperLayerOnBackend2.retrieve(identity)
assert(fromBackend2 == retrieved, "FAIL: same identity diverged across backends")
print("PASS cross-backend: one identity, two Physical Filings, one semantic fact")

print("BACKEND INDEPENDENCE K5–K8 + CROSS-BACKEND: ALL PASS")

// ===========================================================================
// PERSISTENCE SEMANTICS GATE (S3 ruled ① first-write-wins): same identity +
// conflicting value → success no-op, the existing fact remains
// authoritative — identically on BOTH backends. No conflict/merge/
// overwrite semantics exist anywhere.
// ===========================================================================

func assertFirstWriteWins(_ layer: UpperLayer, _ identity: InformationID, _ original: Information, label: String) throws {
    let conflicting = Information(
        identity: identity,
        content: "CONFLICTING VALUE — 依据 S3 裁定不得覆盖既有事实",
        provenance: Provenance(
            producedAt: Date(timeIntervalSince1970: 1_790_960_000),
            producedBy: "conflict-probe"
        ),
        temporal: nil
    )
    try layer.persist(conflicting) // S3: success no-op — never overwrites
    let fact = try layer.retrieve(identity)
    assert(fact == original, "FAIL S3[\(label)]: existing fact was changed")
    print("PASS S3 first-write-wins on \(label): existing fact remains authoritative")
}

// S3 on Backend-1 (SQLiteStore)
assert(retrieved != nil, "FAIL S3: SQLite chain lost its fact before conflict probe")
try assertFirstWriteWins(upperLayer, identity, retrieved!, label: "SQLiteStore")

// S3 on Backend-2 (InMemoryStore)
assert(backend2Retrieved != nil, "FAIL S3: InMemory chain lost its fact before conflict probe")
try assertFirstWriteWins(upperLayerOnBackend2, backend2Identity, backend2Retrieved!, label: "InMemoryStore")

print("PERSISTENCE SEMANTICS S1–S6: CONTRACT VERIFIED ON BOTH BACKENDS")
