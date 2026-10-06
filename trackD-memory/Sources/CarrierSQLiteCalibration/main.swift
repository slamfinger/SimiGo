import Foundation
import Darwin
import CarrierInterface
import CryptoKit
import CarrierSQLite

// CCVS-01 Amplification Measurement Calibration Study (ruling-mandated, narrow).
// Separates three physical quantities on Baseline A (A1):
//   steady-state footprint = allocated blocks of durable artifacts at rest
//   (entity files + registry DB + WAL + SHM + temp leftovers), measured after
//   sync; write traffic = process device-writeback delta (diagnostic only);
//   logical payload = exact submitted payload bytes.

func diskWritten() -> UInt64 {
    let size = MemoryLayout<rusage_info_v2>.size
    let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<rusage_info_v2>.alignment)
    memset(raw, 0, size)
    let rc = proc_pid_rusage(getpid(), RUSAGE_INFO_V2, raw.assumingMemoryBound(to: rusage_info_t?.self))
    precondition(rc == 0)
    let p = raw.assumingMemoryBound(to: rusage_info_v2.self).pointee
    let dw = p.ri_diskio_byteswritten
    raw.deallocate()
    return dw
}

func footprint(_ dir: URL) -> (logical: UInt64, allocated: UInt64, files: Int) {
    var logical: UInt64 = 0, allocated: UInt64 = 0, files = 0
    let fm = FileManager.default
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
    guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys)) else { return (0, 0, 0) }
    for case let url as URL in en {
        guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
        files += 1
        logical += UInt64(v.totalFileAllocatedSize ?? 0) // placeholder; replaced below
        // allocated size:
        if let alloc = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
            allocated += UInt64(alloc)
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            // track true logical size separately by subtracting: use second pass
        }
    }
    return (logical, allocated, files)
}

func footprintDetailed(_ dir: URL) -> (logicalBytes: UInt64, allocatedBytes: UInt64, files: Int) {
    var logical: UInt64 = 0, allocated: UInt64 = 0, files = 0
    let fm = FileManager.default
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
    guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys)) else { return (0, 0, 0) }
    for case let url as URL in en {
        guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
        files += 1
        logical += UInt64(v.fileSize ?? 0)
        allocated += UInt64(v.totalFileAllocatedSize ?? 0)
    }
    return (logical, allocated, files)
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
struct SplitMix64 { var s: UInt64; init(_ seed: UInt64) { s = seed }
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
    mutating func text(_ bytes: Int) -> String { String(repeating: "calibration ", count: bytes / 12 + 1).prefix(bytes).description } }

let root = FileManager.default.temporaryDirectory.appendingPathComponent("ccvs01-cal-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let factory = SQLiteCarrierFactory(rootURL: root)
var rng = SplitMix64(20261006)

// --- WL1-shaped ingest: 1000 small objects, exact logical accounting
var logicalSmall: UInt64 = 0
var dwTraffic1: UInt64 = 0
let dbURL = root.appendingPathComponent("registry.sqlite")
let wal = URL(fileURLWithPath: dbURL.path + "-wal")
let shm = URL(fileURLWithPath: dbURL.path + "-shm")
func fileSize(_ u: URL) -> UInt64 {
    (try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize).map(UInt64.init) ?? 0
}
do {
let bundle = try factory.make()
let dwStart = diskWritten()
for i in 0..<1000 {
    let size = rng.int(1024...65536)
    let bytes = Data(rng.text(size).utf8)
    logicalSmall += UInt64(bytes.count)
    _ = try await bundle.runtime.create(CarrierCreateRequest(
        informationID: CarrierInformationID(rawValue: "cal-\(i)"),
        revisionID: CarrierRevisionID(rawValue: "cal-rev-\(i)"),
        representationID: CarrierRepresentationID(rawValue: "cal-rep-\(i)"),
        payload: CarrierPayload(bytes: bytes),
        locatorID: CarrierLocatorID(rawValue: "cal-loc-\(i)"),
        locator: CarrierLocator(scheme: "file", value: "cal/\(i).txt"),
        provenance: CarrierProvenance(producedAt: Date(), producedBy: "calibration"),
        searchableText: rng.text(120)))
}
sync()
dwTraffic1 = diskWritten() - dwStart
let ent = footprintDetailed(root.appendingPathComponent("entities"))
var openWAL: UInt64 = 0
if let v = try? wal.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize { openWAL = UInt64(v) }
let dbAlloc = fileSize(dbURL)
let footprintOpen = ent.allocatedBytes + dbAlloc + openWAL + fileSize(shm)
print("SMALL-SHAPE INGEST")
print("logical_payload_bytes=\(logicalSmall)")
print("entity_files=\(ent.files) entity_allocated=\(ent.allocatedBytes) entity_logical=\(ent.logicalBytes)")
print("db_allocated=\(dbAlloc) wal_allocated_open=\(openWAL) shm_allocated=\(fileSize(shm))")
print("footprint_steady_open=\(footprintOpen) amp_footprint=\(Double(footprintOpen)/Double(logicalSmall))")
print("amp_entity_only=\(Double(ent.allocatedBytes)/Double(logicalSmall))")
print("write_traffic_diagnostic=\(dwTraffic1) amp_write_traffic=\(Double(dwTraffic1)/Double(logicalSmall))")
} // bundle scope ends → clean close/checkpoint
Thread.sleep(forTimeInterval: 0.3)
let closedWal = fileSize(URL(fileURLWithPath: wal.path))
let footprintClosed = footprintDetailed(root.appendingPathComponent("entities")).allocatedBytes + fileSize(dbURL) + closedWal + fileSize(shm)
print("footprint_steady_closed=\(footprintClosed) amp_closed=\(Double(footprintClosed)/Double(logicalSmall)) db_after_close=\(fileSize(dbURL)) wal_after_close=\(closedWal)")

// --- Large-file ingest: 10 x 10MiB via the same adapter
let bundle2 = try factory.make()
var logicalLarge: UInt64 = 0
let dw1 = diskWritten()
let hex = "0123456789abcdef"
var fixtureHash = ""
for i in 0..<10 {
    var out = ""
    while out.utf8.count < 10 * 1024 * 1024 {
        let t = rng.next()
        let words = ["information", "space", "continuation", "carrier", "lineage", "revision", "locator", "pin"]
        out += words[Int(t % 8)] + "-"
        for _ in 0..<12 { out += String(hex[hex.index(hex.startIndex, offsetBy: Int(rng.next() % 16))]) }
        out += " "
    }
    let bytes = Data(String(out.prefix(10 * 1024 * 1024)).utf8)
    if i == 0 { fixtureHash = sha256Hex(bytes) }
    logicalLarge += UInt64(bytes.count)
    _ = try await bundle2.runtime.create(CarrierCreateRequest(
        informationID: CarrierInformationID(rawValue: "large-\(i)"),
        revisionID: CarrierRevisionID(rawValue: "large-rev-\(i)"),
        representationID: CarrierRepresentationID(rawValue: "large-rep-\(i)"),
        payload: CarrierPayload(bytes: bytes, mediaType: "application/octet-stream"),
        locatorID: CarrierLocatorID(rawValue: "large-loc-\(i)"),
        locator: CarrierLocator(scheme: "file", value: "large/\(i).bin"),
        provenance: CarrierProvenance(producedAt: Date(), producedBy: "calibration")))
}
sync()
let dwTraffic2 = diskWritten() - dw1
let entL = footprintDetailed(root.appendingPathComponent("entities"))
var walL: UInt64 = 0
if let v = try? wal.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize { walL = UInt64(v) }
let footprintLargeOpen = entL.allocatedBytes + fileSize(dbURL) + walL + fileSize(shm)
print("LARGE INGEST (delta window)")
print("logical_payload_bytes=\(logicalLarge)")
print("entity_allocated_total=\(entL.allocatedBytes) wal_allocated=\(walL)")
print("footprint_steady_delta_approx=\(footprintLargeOpen - footprintClosed) amp_delta=\(Double(footprintLargeOpen - footprintClosed)/Double(logicalLarge))")
print("write_traffic_diagnostic=\(dwTraffic2) amp_write_traffic=\(Double(dwTraffic2)/Double(logicalLarge))")
print("fixture_generator=ccvs-fixturegen-v2-hexmix largeFixture0Sha256=\(fixtureHash)")
try? FileManager.default.removeItem(at: root)
