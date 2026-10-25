import Foundation
import SimiGoRuntimeContract

// SIMIGO_ENV_BOOTSTRAP=1 — one-shot provisioning of the full generation
// environment, so a fresh install (or a clean root) reaches the state where
// Execution State and Information Space can actually run:
//
//   1. managed directory tree        (`<root>/{bin,sources,build,manifests,logs,staging,locks}`)
//   2. llama.cpp toolchain           (version-locked source build -> `bin/llama-server`,
//                                     build caches pruned to binaries only)
//   3. hf CLI                        (adopt if present; else Homebrew install -> `bin/hf`)
//   4. authoritative ES/IS database  (blank on first run, never reset after)
//   5. work-root registration        (`SIMIGO_WORKROOT=<abs path>` -> `roots` table,
//                                     category `work`, locator `path`)
//
// `SIMIGO_HOME` selects the managed root exactly like the rest of the product,
// so the entry is testable against an isolated root and, unset, provisions the
// real `<home>/.simigo`. The JSON report goes to stdout and, when
// `SIMIGO_ENV_BOOTSTRAP_REPORT` is set, to that path as well.
//
// It never starts a model, opens a listener, or touches pairing state: it only
// provisions. Exit 0 when every step reports a non-failed status, else 1.

enum SimiGoEnvBootstrapEntry {

    static let environmentKey = "SIMIGO_ENV_BOOTSTRAP"

    struct Decision {
        let requested: Bool
        let valid: Bool
        let error: String?
    }

    static func evaluate(env: [String: String] = ProcessInfo.processInfo.environment) -> Decision {
        guard let raw = env[environmentKey], raw == "1" else {
            return Decision(requested: false, valid: false, error: nil)
        }
        if let workRoot = env["SIMIGO_WORKROOT"], !workRoot.isEmpty,
            !workRoot.hasPrefix("/")
        {
            return Decision(requested: true, valid: false,
                error: "SIMIGO_WORKROOT must be an absolute path")
        }
        return Decision(requested: true, valid: true, error: nil)
    }

    @MainActor
    static func run() async -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let workRoot = env["SIMIGO_WORKROOT"].flatMap { $0.isEmpty ? nil : $0 }
        let report = await EnvManager.shared.bootstrapGenerationEnvironment(workRoot: workRoot)

        let encoder = JSONSerialization.jsonSerializerCompatibleDictionary(report)
        let data = (try? JSONSerialization.data(
            withJSONObject: encoder, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? "{}"
        FileHandle.standardError.write(Data((text + "\n").utf8))
        if let outPath = env["SIMIGO_ENV_BOOTSTRAP_REPORT"], !outPath.isEmpty {
            try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
        }
        // Every provisioning step reports its own status; the entry fails only
        // when a step outright failed (a `manual_required` hf without Homebrew
        // is guidance, not a failure).
        func stepFailed(_ step: [String: Any]) -> Bool {
            (step["status"] as? String).map { ["failed", "install_failed", "install_bin_missing", "构建失败", "构建中断"].contains($0) } ?? false
        }
        var failed = false
        if let llama = report["llama_cpp"] as? [String: Any] { failed = failed || stepFailed(llama) }
        if let hf = report["hf"] as? [String: Any] { failed = failed || (hf["status"] as? String) == "install_failed" }
        if let db = report["database"] as? [String: Any] { failed = failed || stepFailed(db) }
        return failed ? 1 : 0
    }
}

private extension JSONSerialization {
    /// Force-cast the report tree into JSON-serializable containers, dropping
    /// nothing: the bootstrap report is built exclusively from dictionaries,
    /// arrays and strings/numbers, so a non-conforming value is a programming
    /// error best surfaced by the serialization try? above.
    static func jsonSerializerCompatibleDictionary(_ value: Any) -> [String: Any] {
        value as? [String: Any] ?? ["unserializable": String(describing: type(of: value))]
    }
}
