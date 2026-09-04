import Foundation

public struct ProcessRunner: Sendable {
    nonisolated public static func run(_ dir: URL, _ args: [String]) throws {
        let process = createProcess(dir: dir, args: args)
        try executeProcess(process)
    }
    
    nonisolated public static func runAsync(_ dir: URL, _ args: [String]) async throws {
        try await Task.detached(priority: .userInitiated) { try run(dir, args) }.value
    }

    nonisolated public static func runAsyncWithOutput(
        _ dir: URL, _ args: [String], onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = createProcess(dir: dir, args: args)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    onOutput(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            process.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: NSError(domain: "ProcessRunner", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err.trimmingCharacters(in: .whitespacesAndNewlines)]))
                }
            }

            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
    
    nonisolated public static func env() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let simigoBin = "\(NSHomeDirectory())/.simigo/bin"
        var paths = (env["PATH"] ?? "").components(separatedBy: ":")
        if !paths.contains(simigoBin) { paths.insert(simigoBin, at: 0) }
        env["PATH"] = paths.joined(separator: ":")
        if env["HF_ENDPOINT"] == nil { env["HF_ENDPOINT"] = "https://hf-mirror.com" }
        return env
    }
    
    nonisolated public static func cleanup() async {
        for name in ["llama-server", "llama-cli"] {
            await cleanupProcess(name: name)
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    nonisolated private static func createProcess(dir: URL, args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.currentDirectoryURL = dir
        p.environment = env()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = Pipe()
        return p
    }
    
    nonisolated private static func executeProcess(_ process: Process) throws {
        guard let errPipe = process.standardError as? Pipe else {
            try process.run()
            process.waitUntilExit()
            return
        }
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
            throw NSError(domain: "ProcessRunner", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    nonisolated private static func cleanupProcess(name: String) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", name]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let pids = String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .compactMap { pid_t($0) } ?? []
        for pid in pids { kill(pid, SIGTERM) }
    }
}
