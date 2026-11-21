import CryptoKit
import Foundation
import SimiGoRuntimeContract

/// Append-only engine identity ledger.
///
/// Spec: `ES-IS-research/docs/research/ENGINE_IDENTITY_LEDGER_SPEC_V0.1_20261116.md`
/// (closes anomaly A-13 — the commit → build → digest chain had no file-level
/// link, so "which engine produced this reading" was unanswerable).
///
/// The ledger RECORDS and never JUDGES. It does not gate a launch, does not
/// validate a self-report, and does not decide whether a binary is the pinned
/// one. Every field is either a recomputable quantity (size / sha256 / mtime)
/// or a verbatim self-report. Judgement belongs to the reader.
///
/// Digests cover the resolved entry file AND every regular `*.dylib` beside it,
/// because the installed `llama-server` is a ~50 KB thin shell whose work lives
/// in `libllama-server-impl.dylib` and friends (`EnvManager.swift:82-86`,
/// `:427-433`). Digesting the shell alone identifies the wrong artifact — which
/// is exactly how earlier readings recorded a launcher digest as "the engine".
enum EngineIdentityLedger {

    enum Reason {
        static let launch = "launch"
        static let installVerify = "install-verify"
        static let probe = "probe"
    }

    struct FileDigest: Codable, Equatable {
        let name: String
        let size: Int
        let sha256: String
        /// Present on the entry row only; see `fileDigest(at:withMtime:)`.
        let mtime: String?
    }

    /// Who already ran `--version`. The install path probes the binary to decide
    /// whether it starts (`EnvManager.probeLlamaServerVersion`), so it hands that
    /// output over instead of making the ledger spawn a second probe (spec §3.1).
    enum SelfReport {
        /// The ledger runs `--version` itself (launch path, tests, diagnostics).
        case notProbed
        /// The caller already ran it. `nil` means it ran and said nothing.
        case probed(String?)
    }

    /// Parsed from the engine's own `--version`. Any field may be absent: the
    /// format is not stable across builds, and a fabricated triple is worse
    /// than an empty one (spec §7.3).
    struct VersionTriple: Codable, Equatable {
        let version: String?
        let build: String?
        let commit: String?
    }

    struct Row: Codable {
        let ts: String
        let reason: String
        let resolver: String?
        let path: String
        let realpath: String
        let entry: FileDigest?
        let libs: [FileDigest]
        let versionRaw: String?
        let version: VersionTriple?
        let pinnedRef: String?
        let launchArgsSha256: String?

        enum CodingKeys: String, CodingKey {
            case ts, reason, resolver, path, realpath, entry, libs
            case versionRaw = "version_raw"
            case version
            case pinnedRef = "pinned_ref"
            case launchArgsSha256 = "launch_args_sha256"
        }
    }

    /// `<managed root>/engine-ledger.jsonl`. Derived through `ManagedPaths` so an
    /// injected `SIMIGO_HOME` redirects it: a ledger that only ever lands in the
    /// real home is both untestable and a real-user-state write.
    static var ledgerURL: URL {
        ManagedPaths.managedRoot().appendingPathComponent("engine-ledger.jsonl")
    }

    // MARK: - Recording

    /// Measure one engine artifact set and append a row.
    ///
    /// Never throws and never propagates a failure: an audit trail that could
    /// fail a launch would be a new failure mode rather than evidence. A row
    /// that cannot be measured is still written, with the missing fields absent.
    static func record(
        reason: String,
        executablePath: String,
        resolver: String? = nil,
        pinnedRef: String? = nil,
        launchArgs: [String]? = nil,
        selfReport: SelfReport = .notProbed
    ) {
        guard !executablePath.isEmpty else { return }
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let raw: String?
        switch selfReport {
        case .notProbed: raw = probeVersion(resolved.path)
        case .probed(let text): raw = text
        }
        append(
            Row(
                ts: timestamp(Date()),
                reason: reason,
                resolver: resolver,
                path: executablePath,
                realpath: resolved.path,
                entry: fileDigest(at: resolved, withMtime: true),
                libs: libraryDigests(in: resolved.deletingLastPathComponent()),
                versionRaw: raw,
                version: raw.flatMap(parseVersion),
                pinnedRef: pinnedRef,
                launchArgsSha256: launchArgs.map(argsDigest)))
    }

    /// The most recent row, for the existing `/v1/simigo/env` payload. Reading,
    /// not judging: `nil` only means no engine event has been recorded yet.
    ///
    /// A torn trailing line (crash mid-append, external truncation) must not
    /// present recorded history as "never recorded": scan back to the newest
    /// line that still parses.
    static func latestRow() -> [String: Any]? {
        guard let text = try? String(contentsOf: ledgerURL, encoding: .utf8) else {
            return nil
        }
        for line in text.split(separator: "\n").reversed() where !line.isEmpty {
            if let object =
                (try? JSONSerialization.jsonObject(with: Data(line.utf8)))
                as? [String: Any]
            {
                return object
            }
        }
        return nil
    }

    // MARK: - Measurement

    /// Run `<binary> --version` and return its combined output verbatim. `nil`
    /// means it did not answer — recorded as an absent self-report, never as a
    /// guess. `--version` is the cheapest probe that still loads every
    /// dependency (measured 0.077 s on the pinned build, `EnvManager.swift:1133-1136`).
    static func probeVersion(_ path: String, timeout: TimeInterval = 10) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let finished = DispatchSemaphore(value: 0)
        // Handler before run(): a process that exits instantly can otherwise
        // signal before the handler exists, and the wait would burn the timeout.
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Waited BEFORE draining, deliberately. Draining first blocks this thread
        // until EOF, so a binary that hangs instead of answering would hang the
        // launch path and the timeout below would never get to run. `--version`
        // prints a few hundred bytes, far under the pipe buffer, so the child
        // cannot block on a full pipe; if some build ever did, the timeout fires
        // and the missing self-report is recorded as missing — never as a guess.
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        // The child has exited, so every writer end is closed and this returns at once.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Parse `version: 0.7.0-dev (build 1, commit 0878f7c)` shaped output.
    /// Missing fields stay missing; nothing is inferred from a path or a name.
    static func parseVersion(_ raw: String) -> VersionTriple? {
        let line = String(
            raw.split(whereSeparator: \.isNewline).first { $0.contains("version") }
                ?? Substring(raw))

        func token(after key: String, allow: (Character) -> Bool) -> String? {
            guard let range = line.range(of: key) else { return nil }
            let value = line[range.upperBound...]
                .drop(while: { $0.isWhitespace })
                .prefix(while: allow)
            return value.isEmpty ? nil : String(value)
        }

        let version = token(after: "version:") { !$0.isWhitespace && $0 != "(" }
        let build = token(after: "build", allow: \.isNumber)
        let commit = token(after: "commit") { $0.isLetter || $0.isNumber }
        guard version != nil || build != nil || commit != nil else { return nil }
        return VersionTriple(version: version, build: build, commit: commit)
    }

    /// - Parameter withMtime: the ENTRY records when the artifact landed (spec §2:
    ///   `entry` = `{size, sha256, mtime}`). Library rows do not, so they stay
    ///   exactly the `{name, size, sha256}` shape the spec names — synthesized
    ///   `Codable` omits a nil optional rather than writing `"mtime": null`.
    static func fileDigest(at url: URL, withMtime: Bool = false) -> FileDigest? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? Int,
            let sha = try? NativeMLX.sha256HexOfFile(at: url)
        else { return nil }
        let modified = withMtime
            ? (attrs[.modificationDate] as? Date).map { timestamp($0) } : nil
        return FileDigest(
            name: url.lastPathComponent, size: size, sha256: sha, mtime: modified)
    }

    /// Regular `*.dylib` files beside the binary, by name. Symlinks are skipped:
    /// `installSharedLibraries` (`EnvManager.swift:1165-1178`) copies the real
    /// libraries and the `libX.dylib -> libX.0.dylib` aliases both land there, so
    /// hashing aliases too would only duplicate a digest already recorded.
    static func libraryDigests(in directory: URL) -> [FileDigest] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names.sorted()
            .filter { $0.hasSuffix(".dylib") }
            .compactMap { name in
                let url = directory.appendingPathComponent(name)
                let isSymlink =
                    ((try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType)
                        == .typeSymbolicLink
                guard !isSymlink else { return nil }
                return fileDigest(at: url)
            }
    }

    static func argsDigest(_ args: [String]) -> String {
        SHA256.hash(data: Data(args.joined(separator: "\u{0}").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Append

    static func append(_ row: Row) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(row),
            var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"
        let url = ledgerURL
        let fm = FileManager.default
        try? fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // O_APPEND makes the kernel place every write at the current end, so a
        // concurrent writer or a crash mid-call can never rewrite rows already
        // on disk (the previous seekToEnd+write path fell back to an
        // overwriting write whenever the file handle failed to open). fsync
        // commits the accepted row before the caller moves on.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let bytes = Array(line.utf8)
        let written = bytes.withUnsafeBytes { buffer in
            write(fd, buffer.baseAddress, buffer.count)
        }
        guard written == bytes.count else { return }
        _ = fsync(fd)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
