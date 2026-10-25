import Foundation
import CryptoKit
import Darwin

// G7b / G8a IDENTITY SELF-CHECK — a running D1 worker proves that the executable
// image it is actually running is the one the supervisor bound, before any
// authorization is consumed or any model call is made.
//
// Why this is the honest mechanism (and not a claim of a bound delivery):
//   * The worker resolves its OWN on-disk executable path (_NSGetExecutablePath)
//     and hashes the real bytes with SHA-256. That is the process identity, not a
//     label the caller supplied.
//   * The supervisor computes the same digest from the binary it launches and
//     passes it via G3_EXPECT_EXEC_SHA256. A match means "the image that started
//     == the image the supervisor armed" — the running PID and the executable
//     file identity verify each other.
//   * If the environment variable is missing, or its value does not equal the
//     self-hash, the worker refuses BEFORE reading the authorization marker and
//     before the gated run. Fail-closed: an unbound worker never consumes a
//     one-shot marker, so an identity failure cannot burn an authorization slot.

public enum G3D1Identity {
    /// The environment variable that carries the expected executable digest.
    public static let expectedEnvKey = "G3_EXPECT_EXEC_SHA256"

    public enum Check: Equatable, Sendable {
        /// The self-hash matched the expected digest; `execSHA256` is the verified value.
        case verified(execSHA256: String, execPath: String)
        /// G3_EXPECT_EXEC_SHA256 was absent or blank — no binding was provided.
        case missingExpectation
        /// The expectation is present but does not equal the running image.
        case mismatch(expected: String, actual: String)
        /// The executable path could not be resolved or read.
        case unreadable(detail: String)
    }

    /// Resolve the real, symlink-followed path of the running executable.
    public static func currentExecutablePath(env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        var size = UInt32(buffer.count)
        if _NSGetExecutablePath(&buffer, &size) != 0 {
            var resized = [CChar](repeating: 0, count: Int(size))
            if _NSGetExecutablePath(&resized, &size) != 0 { return nil }
            buffer = resized
        }
        let raw = String(cString: buffer)
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(raw, &resolved) == nil { return raw }
        return String(cString: resolved)
    }

    /// SHA-256 of the executable's bytes at `path`, lower-case hex.
    public static func sha256OfFile(at path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Perform the identity self-check against G3_EXPECT_EXEC_SHA256.
    public static func check(env: [String: String] = ProcessInfo.processInfo.environment) -> Check {
        let expectedRaw = (env[expectedEnvKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedRaw.isEmpty else { return .missingExpectation }
        guard let path = currentExecutablePath(env: env) else {
            return .unreadable(detail: "cannot resolve executable path")
        }
        guard let actual = sha256OfFile(at: path) else {
            return .unreadable(detail: "cannot read executable at \(path)")
        }
        let expected = expectedRaw.lowercased()
        if expected == actual { return .verified(execSHA256: actual, execPath: path) }
        return .mismatch(expected: expected, actual: actual)
    }

    /// True only when the check is a verified match.
    public static func isVerified(_ check: Check) -> Bool {
        if case .verified = check { return true }
        return false
    }
}
