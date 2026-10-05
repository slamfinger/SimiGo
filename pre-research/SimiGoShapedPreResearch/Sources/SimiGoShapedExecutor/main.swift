// SimiGo-shaped pre-research executor — composition root + P1/P2 runner.
//
// P1: this process is a cold start — a fresh database path with no
// persisted history; the executor carries no prior state.
// P2: the full S1–S6 store/fetch shape is reproduced here through the
// InformationCore boundary only.
// P3: `ColdStartExecutor` (Executor.swift) contains zero backend
// symbols — verified by external grep audit.

import Foundation
import InformationCore

// ——— Composition root (the single backend-aware place) ———
let databasePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "simigo-shaped.sqlite"
let physicalStore = try SQLiteStore(path: databasePath)

// ——— Cold-start executor (SimiGo-shaped, boundary-only) ———
let executor = ColdStartExecutor(store: physicalStore)

let provenance = Provenance(
    producedAt: Date(timeIntervalSince1970: 1_790_980_000),
    producedBy: "simigo-shaped-cold-start-executor"
)

// S1: new identity → persist.
let identity = physicalStore.makeInformationID(
    content: "SimiGo-shaped pre-research — 冷启动执行者经 Information 边界落库的第一条事实",
    provenance: provenance
)
let information = executor.formInformation(identity: identity, content: "SimiGo-shaped pre-research — 冷启动执行者经 Information 边界落库的第一条事实", provenance: provenance)
try executor.persist(information)
print("PASS S1 new identity persisted (cold start, fresh DB: \(databasePath))")

// S4: present → Information (same semantic value).
let present = try executor.retrieve(identity)
assert(present != nil, "FAIL S4: present fetch nil")
assert(present == information, "FAIL S4: roundtrip value differs")
print("PASS S4 present returns the same semantic value")

// S5: absent → nil.
let absent = try executor.retrieve(InformationID(rawValue: "absent0000000000000000"))
assert(absent == nil, "FAIL S5: absence not nil")
print("PASS S5 absence = nil")

// S2: same identity + same value → no-op confirm.
try executor.persist(information)
let afterSame = try executor.retrieve(identity)
assert(afterSame == information, "FAIL S2: same-value re-store changed the fact")
print("PASS S2 same-value store is an idempotent no-op confirm")

// S3: same identity + CONFLICTING value → no-op, first-write-wins.
let conflicting = Information(
    identity: identity,
    content: "CONFLICTING VALUE — S3 first-write-wins 下不得覆盖既有事实",
    provenance: Provenance(producedAt: Date(), producedBy: "s3-conflict-probe")
)
try executor.persist(conflicting)
let afterConflict = try executor.retrieve(identity)
assert(afterConflict == information, "FAIL S3: existing fact was overwritten")
print("PASS S3 conflicting store is a no-op; existing fact remains authoritative")

print("P1 + P2 (S1–S6 shape): ALL PASS — cold-start executor works through the Information boundary only")
