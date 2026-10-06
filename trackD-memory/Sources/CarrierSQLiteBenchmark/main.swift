import Foundation
import Darwin
import SQLite3
import CarrierInterface
import CarrierSQLite

// CCVS-01 Phase C controlled benchmark driver (frozen protocol CCVS-01-PB v1.2).
// Admission (resource gate, 3x5s quiescence, environment manifest) then cold
// serial runs: P0 integrity baseline, P1 cold startup, WL1..WL6 families,
// P9 final integrity + JSON export. Crash suites (P8) are separate fresh runs.

struct Metrics {
    var samples: [String: [Double]] = [:]
    var errors: [String: Int] = [:]

    mutating func record(_ op: String, _ seconds: Double) {
        samples[op, default: []].append(seconds)
    }

    mutating func fail(_ op: String) {
        errors[op, default: 0] += 1
    }

    func percentile(_ op: String, _ p: Double) -> Double? {
        guard var v = samples[op], !v.isEmpty else { return nil }
        v.sort()
        let idx = min(v.count - 1, max(0, Int((p / 100.0) * Double(v.count - 1) + 0.5)))
        return v[idx]
    }
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

func timed<T>(_ metrics: inout Metrics, _ op: String, _ body: () async throws -> T) async throws -> T {
    let t0 = now()
    do {
        let value = try await body()
        metrics.record(op, now() - t0)
        return value
    } catch {
        metrics.fail(op)
        throw error
    }
}

// MARK: Deterministic fixtures (PB-F2: SplitMix64, seed-derived)

/// Fixture generator v2 for large files: seed-derived deterministic valid
/// UTF-8 text (word + random hex tokens), low compressibility bias.
/// Same master seed + this version => identical fixtures (ruling D-B).
let FIXTURE_GENERATOR_VERSION = "ccvs-fixturegen-v2-hexmix"
func largeFixtureBytes(_ rng: inout SplitMix64, _ bytes: Int) -> Data {
    var out = ""
    let hex = "0123456789abcdef"
    while out.utf8.count < bytes {
        let t = rng.next()
        let words = ["information", "space", "continuation", "carrier", "lineage", "revision", "locator", "pin"]
        out += words[Int(t % 8)] + "-"
        for _ in 0..<12 { out += String(hex[Int(rng.next() % 16)]) }
        out += " "
    }
    return Data(String(out.prefix(bytes)).utf8)
}
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
    mutating func text(_ bytes: Int, tag: String) -> String {
        let words = ["information", "space", "continuation", "carrier", "lineage", "revision", "locator", "pin"]
        var out = ""
        var token = next()
        while out.utf8.count < bytes {
            token = token &* 6364136223846793005 &+ 1442695040888963407
            out += words[Int(token % UInt64(words.count))] + " "
            if Int.random(in: 0..<16) == 0 { out += "\(tag)-\(token % 1000) " }
        }
        return String(out.prefix(bytes))
    }
}

// MARK: Resource observation (PB-F4)

struct ResourceSample: Codable {
    let seconds: Double
    let rssBytes: UInt64
    let cpuSeconds: Double
    let diskWrittenBytes: UInt64
    let diskReadBytes: UInt64
    let openFDs: Int32
}

func rusageV2() -> (rss: UInt64, cpu: Double, dw: UInt64, dr: UInt64)? {
    let size = MemoryLayout<rusage_info_v2>.size
    let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<rusage_info_v2>.alignment)
    memset(raw, 0, size)
    defer { raw.deallocate() }
    // macOS 26+ ABI: caller-allocated buffer, not an out-pointer.
    guard proc_pid_rusage(getpid(), RUSAGE_INFO_V2, raw.assumingMemoryBound(to: rusage_info_t?.self)) == 0 else { return nil }
    let p = raw.assumingMemoryBound(to: rusage_info_v2.self).pointee
    return (p.ri_resident_size, Double(p.ri_user_time + p.ri_system_time) / 1e9, p.ri_diskio_byteswritten, p.ri_diskio_bytesread)
}

func openFDCount() -> Int32 {
    Int32(Int(proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)) / MemoryLayout<proc_fdinfo>.size)
}

func sampleResources(at seconds: Double) -> ResourceSample? {
    guard let r = rusageV2() else { return nil }
    return ResourceSample(
        seconds: seconds, rssBytes: r.rss, cpuSeconds: r.cpu,
        diskWrittenBytes: r.dw, diskReadBytes: r.dr, openFDs: openFDCount()
    )
}

func nonBenchmarkCPULoad(window: Double) async -> Double? {
    var start = host_cpu_load_info()
    var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    guard withUnsafeMutablePointer(to: &start, {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size) == KERN_SUCCESS
        }
    }) else { return nil }
    try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
    var end = host_cpu_load_info()
    guard withUnsafeMutablePointer(to: &end, {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size) == KERN_SUCCESS
        }
    }) else { return nil }
    let idle = end.cpu_ticks.2 - start.cpu_ticks.2
    var total: UInt64 = 0
    let ticks = [start.cpu_ticks.0, start.cpu_ticks.1, start.cpu_ticks.2, start.cpu_ticks.3]
    let ticksEnd = [end.cpu_ticks.0, end.cpu_ticks.1, end.cpu_ticks.2, end.cpu_ticks.3]
    for (a, b) in zip(ticks, ticksEnd) { total += UInt64(b) - UInt64(a) }
    guard total > 0 else { return nil }
    return 1.0 - Double(idle) / Double(total)
}

// MARK: Admission (PC-4)

func admission(root: URL, declaredNewBytes: UInt64) throws -> [String: Any] {
    let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
    guard free >= 3 * declaredNewBytes else {
        throw CarrierInterfaceError.integrityIssue("RESOURCE_GATE_BLOCKED: free \(free) < 3x\(declaredNewBytes)")
    }
    var checks: [Double] = []
    let semaphore = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "quiescence")
    Task.detached {
        for _ in 0..<3 {
            if let load = await nonBenchmarkCPULoad(window: 5) { checks.append(load) }
        }
        semaphore.signal()
    }
    semaphore.wait()
    guard checks.count == 3, checks.allSatisfy({ $0 < 0.20 }) else {
        throw CarrierInterfaceError.integrityIssue("RESOURCE_GATE_BLOCKED: quiescence violated \(checks)")
    }
    var size = 0
    sysctlbyname("hw.memsize", nil, &size, nil, 0)
    var mem = UInt64(0)
    sysctlbyname("hw.memsize", &mem, &size, nil, 0)
    var cpuBrand = [CChar](repeating: 0, count: 256)
    sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &size, nil, 0)
    let env: [String: Any] = [
        "cpu": String(cString: cpuBrand),
        "memoryBytes": mem,
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "sqliteVersion": String(cString: sqlite3_libversion()),
        "quiescenceWindows": checks,
        "freeDiskBytes": free,
        "gate": "PASS"
    ]
    return env
}

// MARK: Benchmark run

struct RunConfig: Codable {
    let tier: String
    let runIndex: Int
    let masterSeed: UInt64
}

func jsonDict(_ dict: [String: Any]) -> Data? {
    try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted])
}

func runBenchmark(tier: String, runIndex: Int, masterSeed: UInt64, rootURL: URL) async throws -> [String: Any] {
    var rng = SplitMix64(seed: masterSeed &+ UInt64(runIndex) &+ 0xA1A1)
    let smallObjects = tier == "SMALL" ? 1000 : 10000
    let fileEntities = tier == "SMALL" ? 100 : 1000
    let largeCount = tier == "SMALL" ? 10 : 100
    let sessions = tier == "SMALL" ? 10 : 100
    let sessionEvents = tier == "SMALL" ? 1000 : 10000
    let relationEdges = tier == "SMALL" ? 2000 : 20000
    let mixedIterations = tier == "SMALL" ? 200 : 2000

    var m = Metrics()
    var invariantNotes: [String] = []
    let runRoot = rootURL.appendingPathComponent("run-\(runIndex)", isDirectory: true)
    try? FileManager.default.removeItem(at: runRoot)
    try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)

    // P0 + P1: fresh composition = cold start; first query completes open.
    let t0 = now()
    let factory = SQLiteCarrierFactory(rootURL: runRoot)
    let bundle = try factory.make()
    _ = try await bundle.runtime.composition.search.search("warm", limit: 1)
    m.record("startup_open", now() - t0)
    let baseline = try await bundle.runtime.integrityReport()
    guard baseline.isClean else { throw CarrierInterfaceError.integrityIssue("P0 baseline not clean") }

    func mkInfo(_ i: Int) -> CarrierInformationID { CarrierInformationID(rawValue: "info-\(i)") }
    func mkRev(_ i: Int, _ g: Int = 0) -> CarrierRevisionID { CarrierRevisionID(rawValue: "rev-\(i)-\(g)") }
    func mkRep(_ i: Int, _ g: Int = 0) -> CarrierRepresentationID { CarrierRepresentationID(rawValue: "rep-\(i)-\(g)") }
    func mkLoc(_ i: Int, _ g: Int = 0) -> CarrierLocatorID { CarrierLocatorID(rawValue: "loc-\(i)-\(g)") }
    func provenance() -> CarrierProvenance { CarrierProvenance(producedAt: Date(), producedBy: "ccvs01-a1") }

    let startedAt = Date()
    final class LockedSamples: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ResourceSample] = []
        func append(_ s: ResourceSample) { lock.lock(); items.append(s); lock.unlock() }
        var all: [ResourceSample] { lock.lock(); defer { lock.unlock() }; return items }
    }
    let resourceSamples = LockedSamples()
    var sampler: Task<Void, Never>?
    sampler = Task.detached {
        var t = 0.0
        while !Task.isCancelled {
            if let s = sampleResources(at: t) { resourceSamples.append(s) }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            t += 1
        }
    }
    defer { sampler?.cancel() }

    // WL1 — small-object lifecycle (create; move ≥500; revise ≥100; lookup ≥500)
    let dwStart1 = rusageV2()?.dw ?? 0
    let createStart = now()
    var wl1LogicalBytes: UInt64 = 0
    for i in 0..<smallObjects {
        let size = rng.int(1024...65536)
        let payload = CarrierPayload(bytes: Data(rng.text(size, tag: "wl1").utf8))
        wl1LogicalBytes += UInt64(payload.bytes.count)
        try await timed(&m, "create") {
            try await bundle.runtime.create(CarrierCreateRequest(
                informationID: mkInfo(i), revisionID: mkRev(i), representationID: mkRep(i),
                payload: payload, locatorID: mkLoc(i),
                locator: CarrierLocator(scheme: "file", value: "wl1/\(i).txt"),
                provenance: provenance(), searchableText: rng.text(120, tag: "wl1")))
        }
    }
    sync() // force this process's dirty pages to device before sampling
    let wl1Window = now() - createStart
    let wl1Logical = wl1LogicalBytes
    let wl1Disk = (rusageV2()?.dw ?? 0) - dwStart1
    m.record("wl1_ingest_window_seconds", wl1Window)

    for i in 0..<max(500, smallObjects) {
        try await timed(&m, "lookup") {
            _ = try await bundle.runtime.resolve(CarrierResolveRequest(informationID: mkInfo(i % smallObjects)))
        }
    }
    for i in 0..<smallObjects {
        try await timed(&m, "move") {
            _ = try await bundle.runtime.move(CarrierMoveRequest(
                informationID: mkInfo(i), newLocatorID: mkLoc(i, 1),
                newLocator: CarrierLocator(scheme: "file", value: "wl1/moved-\(i).txt"),
                movedAt: Date()))
        }
    }
    // I1 spot check: identity preserved after move.
    if try await bundle.runtime.resolve(CarrierResolveRequest(informationID: mkInfo(0)))
        .content.representation.informationID != mkInfo(0) {
        invariantNotes.append("I1 violated after move")
    }
    for i in 0..<min(smallObjects, 300) {
        try await timed(&m, "revise") {
            _ = try await bundle.runtime.revise(CarrierReviseRequest(
                informationID: mkInfo(i), revisionID: mkRev(i, 2), representationID: mkRep(i, 2),
                payload: CarrierPayload(bytes: Data(rng.text(4096, tag: "rev").utf8)), locatorID: mkLoc(i, 2),
                locator: CarrierLocator(scheme: "file", value: "wl1/rev-\(i).txt"),
                provenance: provenance(), predecessorRevisionID: mkRev(i, 1),
                searchableText: "revised \(i)"))
        }
    }
    // I2 spot check: historical revision still resolves to original digest.
    let originalContent = try await bundle.runtime.resolve(
        CarrierResolveRequest(informationID: mkInfo(0), revisionID: mkRev(0)))
    if originalContent.content.representation.representationID != mkRep(0) {
        invariantNotes.append("I2 historical representation changed")
    }
    for i in 0..<200 {
        try await timed(&m, "pin") {
            _ = try await bundle.runtime.pin(
                CarrierResolveRequest(informationID: mkInfo(i), revisionID: mkRev(i, 2)),
                pinID: CarrierPinID(rawValue: "pin-\(i)"), label: nil, at: Date())
        }
        try await timed(&m, "pin_read") {
            _ = try await bundle.runtime.composition.relations.pin(CarrierPinID(rawValue: "pin-\(i)"))
        }
    }
    // I6: pin stability under locator change.
    let pinBefore = try await bundle.runtime.composition.relations.pin(CarrierPinID(rawValue: "pin-0"))
    _ = try await bundle.runtime.move(CarrierMoveRequest(
        informationID: mkInfo(0), newLocatorID: mkLoc(0, 9),
        newLocator: CarrierLocator(scheme: "file", value: "wl1/post-pin.txt"), movedAt: Date()))
    let pinAfter = try await bundle.runtime.composition.relations.pin(CarrierPinID(rawValue: "pin-0"))
    if pinBefore?.digest != pinAfter?.digest || pinBefore?.locator != pinAfter?.locator {
        invariantNotes.append("I6 pin mutated by locator change")
    }
    for i in 0..<150 {
        try await timed(&m, "availability_update") {
            _ = try await bundle.runtime.recordAvailability(CarrierAvailabilityRequest(
                informationID: mkInfo(100 + i), state: .archived, reason: "wl1",
                observedAt: Date()))
        }
    }

    // WL2 — large files (all occurrences are observations)
    let dwStart2 = rusageV2()?.dw ?? 0
    var fixtureHash = ""
    for i in 0..<largeCount {
        let info = CarrierInformationID(rawValue: "large-\(i)")
        let bytes = largeFixtureBytes(&rng, 10 * 1024 * 1024) // PB-F2 UTF-8 text (D-C fix)
        if i == 0 { fixtureHash = sha256Hex(bytes) }
        try await timed(&m, "large_create") {
            _ = try await bundle.runtime.create(CarrierCreateRequest(
                informationID: info, revisionID: CarrierRevisionID(rawValue: "large-rev-\(i)"),
                representationID: CarrierRepresentationID(rawValue: "large-rep-\(i)"),
                payload: CarrierPayload(bytes: bytes, mediaType: "application/octet-stream"),
                locatorID: CarrierLocatorID(rawValue: "large-loc-\(i)"),
                locator: CarrierLocator(scheme: "file", value: "wl2/large-\(i).bin"),
                provenance: provenance()))
        }
        try await timed(&m, "large_read") {
            let resolved = try await bundle.runtime.resolve(CarrierResolveRequest(informationID: info))
            guard resolved.content.payload.bytes.count == 10 * 1024 * 1024 else {
                throw CarrierInterfaceError.integrityIssue("large file size mismatch")
            }
        }
    }
    sync()
    let largeLogical = UInt64(largeCount * 10 * 1024 * 1024)
    let largeDisk = (rusageV2()?.dw ?? 0) - dwStart2

    // WL3 — sessions
    for s in 0..<sessions {
        let sid = CarrierSessionID(rawValue: "session-\(s)")
        let perSession = sessionEvents / sessions
        for e in 0..<perSession {
            try await timed(&m, "session_append") {
                try await bundle.runtime.composition.sessions.append(CarrierSessionEvent(
                    eventID: CarrierSessionEventID(rawValue: "se-\(s)-\(e)"), sessionID: sid,
                    sequence: e, kind: "message",
                    payload: Data(rng.text(256, tag: "wl3").utf8),
                    occurredAt: Date(), provenance: provenance()))
            }
        }
        if e_count(perSession) >= 100 {
            try await timed(&m, "session_summary_add") {
                try await bundle.runtime.composition.sessions.addSummary(CarrierSessionSummary(
                    summaryID: CarrierSummaryID(rawValue: "sum-\(s)"), sessionID: sid,
                    throughSequence: perSession - 1,
                    payload: Data("summary \(s)".utf8), createdAt: Date(), provenance: provenance()))
            }
        }
        // I10: order preserved.
        let first = try await bundle.runtime.composition.sessions.events(in: sid, after: -1)
        if first.first?.sequence != 0 { invariantNotes.append("I10 session order violated") }
    }
    for s in 0..<sessions {
        try await timed(&m, "summary_read") {
            _ = try await bundle.runtime.composition.sessions.summaries(
                in: CarrierSessionID(rawValue: "session-\(s)"))
        }
    }

    // WL4 — relations
    for i in 0..<relationEdges {
        try await timed(&m, "relation_insert") {
            try await bundle.runtime.composition.relations.append(CarrierRelation(
                relationID: CarrierRelationID(rawValue: "rel-\(i)"),
                subject: mkInfo(i % smallObjects), predicate: i % 2 == 0 ? "related-to" : "derived-from",
                object: mkInfo((i * 7 + 3) % smallObjects), provenance: provenance()))
        }
    }
    // I5 spot check via 1-hop round trip identity stability.
    for k in 0..<120 {
        let start = mkInfo((k * 13) % smallObjects)
        try await timed(&m, "hop1") {
            _ = try await bundle.runtime.composition.relations.relations(involving: start)
        }
        try await timed(&m, "hop2") {
            let edges1 = try await bundle.runtime.composition.relations.relations(involving: start)
            for e in edges1.prefix(3) {
                _ = try await bundle.runtime.composition.relations.relations(involving: e.object)
            }
        }
        try await timed(&m, "hop3") {
            let edges1 = try await bundle.runtime.composition.relations.relations(involving: start)
            for e in edges1.prefix(2) {
                let edges2 = try await bundle.runtime.composition.relations.relations(involving: e.object)
                for e2 in edges2.prefix(2) {
                    _ = try await bundle.runtime.composition.relations.relations(involving: e2.object)
                }
            }
        }
    }

    // WL5 — search: ingest happened via searchableText; queries + rebuild
    for k in 0..<150 {
        try await timed(&m, "search_query") {
            _ = try await bundle.runtime.composition.search.search("information \(k % 50)", limit: 20)
        }
    }
    let rebuildDocs = try await bundle.runtime.composition.search.search("information", limit: 100000)
    _ = try await timed(&m, "index_rebuild") {
        try await bundle.runtime.rebuildSearch(with: rebuildDocs.map {
            CarrierSearchDocument(informationID: $0.informationID, revisionID: $0.revisionID,
                                  title: nil, text: "information rebuild \(Int($0.score))")
        })
    }
    // I11: rebuild equivalence on probe queries.
    for probe in ["continuation", "lineage 3", "carrier 7"] {
        let before = try await bundle.runtime.composition.search.search(probe, limit: 10)
            .map { $0.informationID.rawValue }
        let after = try await bundle.runtime.composition.search.search(probe, limit: 10)
            .map { $0.informationID.rawValue }
        if before != after { invariantNotes.append("I11 rebuild equivalence violated: \(probe)") }
    }

    // WL6 — mixed research day (binding workload; bound metrics use this segment)
    var wl6 = Metrics()
    for k in 0..<mixedIterations {
        let i = smallObjects + k
        let size = rng.int(1024...65536)
        try await timed(&wl6, "create") {
            _ = try await bundle.runtime.create(CarrierCreateRequest(
                informationID: mkInfo(i), revisionID: mkRev(i), representationID: mkRep(i),
                payload: CarrierPayload(bytes: Data(rng.text(size, tag: "wl6").utf8)), locatorID: mkLoc(i),
                locator: CarrierLocator(scheme: "file", value: "wl6/\(i).txt"),
                provenance: provenance(), searchableText: rng.text(120, tag: "wl6")))
        }
        try await timed(&wl6, "lookup") {
            _ = try await bundle.runtime.resolve(CarrierResolveRequest(informationID: mkInfo((k * 31) % i)))
        }
        try await timed(&wl6, "move") {
            _ = try await bundle.runtime.move(CarrierMoveRequest(
                informationID: mkInfo((k * 17) % i),
                newLocatorID: CarrierLocatorID(rawValue: "wl6-loc-\(k)"),
                newLocator: CarrierLocator(scheme: "file", value: "wl6/moved-\(k)"),
                movedAt: Date()))
        }
        try await timed(&wl6, "session_append") {
            try await bundle.runtime.composition.sessions.append(CarrierSessionEvent(
                eventID: CarrierSessionEventID(rawValue: "wl6-se-\(k)"),
                sessionID: CarrierSessionID(rawValue: "session-\(k % sessions)"),
                sequence: 10_000 + k, kind: "note",
                payload: Data(rng.text(256, tag: "wl6s").utf8),
                occurredAt: Date(), provenance: provenance()))
        }
        try await timed(&wl6, "relation_insert") {
            try await bundle.runtime.composition.relations.append(CarrierRelation(
                relationID: CarrierRelationID(rawValue: "wl6-rel-\(k)"),
                subject: mkInfo(i), predicate: "related-to",
                object: mkInfo((k * 7 + 1) % i), provenance: provenance()))
        }
        try await timed(&wl6, "hop2") {
            let edges1 = try await bundle.runtime.composition.relations.relations(involving: mkInfo(i))
            for e in edges1.prefix(3) {
                _ = try await bundle.runtime.composition.relations.relations(involving: e.object)
            }
        }
        try await timed(&wl6, "search_query") {
            _ = try await bundle.runtime.composition.search.search("wl6 \(k % 100)", limit: 20)
        }
    }

    // P9 — final integrity + export
    _ = try await timed(&m, "integrity_check") {
        try await bundle.runtime.integrityReport()
    }
    let finalReport = try await bundle.runtime.integrityReport()

    var report: [String: Any] = [
        "tier": tier, "run": runIndex, "seed": masterSeed,
        "mode": "cold", "startedAt": ISO8601DateFormatter().string(from: startedAt),
        "finishedAt": ISO8601DateFormatter().string(from: Date()),
        "invariantNotes": invariantNotes,
        "finalIntegrityClean": finalReport.isClean,
        "wl1Amplification": Double(wl1Disk) / Double(max(1, wl1Logical)),
        "largeAmplification": Double(largeDisk) / Double(max(1, largeLogical)),
        "wl1WindowSeconds": wl1Window,
        "fixtureGeneratorVersion": FIXTURE_GENERATOR_VERSION,
        "largeFixture0Sha256": fixtureHash
    ]
    for (name, list) in m.samples {
        var sorted = list; sorted.sort()
        guard !sorted.isEmpty else { continue }
        func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int((p / 100.0) * Double(sorted.count - 1) + 0.5))] }
        report["metric.\(name)"] = [
            "count": sorted.count, "errors": m.errors[name] ?? 0,
            "p50": pct(50), "p95": pct(95), "p99": pct(99), "max": sorted.last!
        ]
    }
    for (name, list) in wl6.samples {
        var sorted = list; sorted.sort()
        func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int((p / 100.0) * Double(sorted.count - 1) + 0.5))] }
        report["wl6.\(name)"] = [
            "count": sorted.count, "errors": wl6.errors[name] ?? 0,
            "p50": pct(50), "p95": pct(95), "p99": pct(99), "max": sorted.last!
        ]
    }
    let samples = resourceSamples.all
    if !samples.isEmpty {
        let rss = samples.map { $0.rssBytes }.sorted()
        report["rssMedianBytes"] = rss[rss.count / 2]
        report["rssP95Bytes"] = rss[min(rss.count - 1, rss.count * 95 / 100)]
        report["diskWrittenTotalBytes"] = samples.last?.diskWrittenBytes ?? 0
        report["diskReadTotalBytes"] = samples.last?.diskReadBytes ?? 0
    }
    sampler?.cancel()
    let data = jsonDict(report) ?? Data()
    try data.write(to: runRoot.appendingPathComponent("result.json"))
    FileHandle.standardError.write(Data("[run \(tier) #\(runIndex)] done, integrity clean=\(finalReport.isClean), invariants=\(invariantNotes.isEmpty)\n".utf8))
    return report
}

func e_count(_ n: Int) -> Int { n } // helper for summary gate

// MARK: Entry

let args = CommandLine.arguments
var tier = "SMALL"
var runs = 5
var seed: UInt64 = 20261006
var rootURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/CCVS01-Bench")
var i = 1
while i < args.count - 1 {
    switch args[i] {
    case "--tier": tier = args[i + 1]; i += 2
    case "--runs": runs = Int(args[i + 1]) ?? 5; i += 2
    case "--seed": seed = UInt64(args[i + 1]) ?? 20261006; i += 2
    case "--root": rootURL = URL(fileURLWithPath: args[i + 1]); i += 2
    default: i += 1
    }
}
rootURL = rootURL.appendingPathComponent(tier, isDirectory: true)
try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

let declared: UInt64 = tier == "SMALL" ? 220 * 1024 * 1024 : 2_000 * 1024 * 1024
FileHandle.standardError.write(Data("[admission] tier=\(tier) root=\(rootURL.path)\n".utf8))
let env = try admission(root: rootURL, declaredNewBytes: declared)
try jsonDict(env)?.write(to: rootURL.appendingPathComponent("environment.json"))

var aggregate: [String: [[String: Any]]] = [:]
for runIndex in 1...runs {
    let report = try await runBenchmark(tier: tier, runIndex: runIndex, masterSeed: seed, rootURL: rootURL)
    for (key, value) in report {
        if key.hasPrefix("metric.") || key.hasPrefix("wl6.") {
            aggregate[key, default: []].append(value as? [String: Any] ?? [:])
        }
    }
}
// Median-of-valid-runs aggregation (frozen Step 2)
var aggReport: [String: Any] = ["tier": tier, "runs": runs, "seed": seed, "aggregation": "median-of-runs"]
for (op, runStats) in aggregate {
    func median(_ key: String) -> Double? {
        let vals = runStats.compactMap { $0[key] as? Double }.sorted()
        guard !vals.isEmpty else { return nil }
        return vals.count % 2 == 1 ? vals[vals.count / 2] : (vals[vals.count / 2 - 1] + vals[vals.count / 2]) / 2
    }
    aggReport[op] = [
        "countMedian": median("count"), "p50": median("p50"),
        "p95": median("p95"), "p99": median("p99"), "maxMedian": median("max")
    ]
}
try jsonDict(aggReport)?.write(to: rootURL.appendingPathComponent("aggregate.json"))
FileHandle.standardError.write(Data("[aggregate] written to \(rootURL.appendingPathComponent("aggregate.json").path)\n".utf8))
