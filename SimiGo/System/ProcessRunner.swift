import Foundation

/// What the app hands to every child process it starts.
///
/// The `run`/`runAsync`/`runAsyncWithOutput`/`cleanup` family that used to live
/// here had zero callers and zero tests (every real child process is started by
/// `EnvManager` or `Service`); removed 2026-11-14. Only the environment survives,
/// because that is what the callers actually ask for.
public struct ProcessRunner: Sendable {
    /// Mainland mirror used when the ambient environment does not name an
    /// endpoint. An explicit non-empty `HF_ENDPOINT` is preserved: it is the
    /// operator's override, not something this app should silently replace.
    nonisolated public static let defaultHFEndpoint = "https://hf-mirror.com"

    nonisolated public static func hfEndpoint(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let configured = environment["HF_ENDPOINT"] ?? ""
        return configured.isEmpty ? defaultHFEndpoint : configured
    }

    nonisolated public static func env() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let simigoBin = "\(NSHomeDirectory())/.simigo/bin"
        var paths = (env["PATH"] ?? "").components(separatedBy: ":")
        if !paths.contains(simigoBin) { paths.insert(simigoBin, at: 0) }
        env["PATH"] = paths.joined(separator: ":")
        env["HF_ENDPOINT"] = hfEndpoint(environment: env)
        return env
    }
}
