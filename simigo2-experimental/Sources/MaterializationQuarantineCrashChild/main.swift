// MaterializationQuarantineCrashChild — SIGKILL harness for durable rollback
// quarantine. Spawned by MaterializationCoordinatorTests; NOT user-facing.

import Foundation
import SimiGo2Experimental

final class PublicationFault: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func enable() {
        lock.lock()
        enabled = true
        lock.unlock()
    }
}

final class RollbackFault: Error {}

var arguments = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String {
    guard let index = arguments.firstIndex(of: flag),
        index + 1 < arguments.count
    else {
        fputs("missing \(flag)\n", stderr)
        exit(2)
    }
    return arguments[index + 1]
}

let stage = value("--stage")
let root = URL(fileURLWithPath: value("--root"), isDirectory: true)
let reportURL: URL? = {
    guard let index = arguments.firstIndex(of: "--report"),
        index + 1 < arguments.count
    else { return nil }
    return URL(fileURLWithPath: arguments[index + 1])
}()

func killSelf() -> Never {
    kill(getpid(), SIGKILL)
    exit(9)
}

#if DEBUG
func runStage() async -> Never {
    switch stage {
    case "rollback-failure":
        let fault = PublicationFault()
        let store = PrefixSnapshotStore(
            root: root,
            pool: ExecutionStatePrefixPool(tokenBudget: 10_000),
            willPublishSidecar: { metadataURL in
                guard fault.isEnabled else { return }
                // Failure occurs AFTER the new snapshot has moved into place,
                // so a successful rollback must restore the old snapshot pair.
                try FileManager.default.createDirectory(
                    at: metadataURL, withIntermediateDirectories: true)
                try Data("blocked".utf8).write(
                    to: metadataURL.appendingPathComponent("blocked"))
            },
            willRollback: { throw RollbackFault() }
        )
        let namespace = PrefixPoolNamespace(modelID: "crash-child", kvFingerprint: "rollback")
        let tokens = Array(0..<256)

        do {
            _ = try await store.export(namespace: namespace, tokens: tokens) { url in
                try "old".write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            fputs("harness old export failed: \(error)\n", stderr)
            exit(3)
        }

        fault.enable()
        do {
            _ = try await store.export(namespace: namespace, tokens: tokens) { url in
                try "new".write(to: url, atomically: true, encoding: .utf8)
            }
            fputs("harness rollback-failure stage expected export to fail\n", stderr)
            exit(3)
        } catch let error as PhysicalUseRegistry.PublicationQuarantinedError {
            // The wrapped rollback fault is opaque across the public boundary;
            // the quarantine commit is the crash-relevant state.
            _ = error
        } catch {
            fputs("harness unexpected export failure: \(error)\n", stderr)
            exit(3)
        }

        try? Data("{\"stage\":\"rollback-failure\"}".utf8).write(to: reportURL!)
        killSelf()

    case "verify":
        struct Verdict: Codable {
            let quarantineCount: Int
            let rescanCount: Int
            let admissionBlocked: Bool
        }

        let store = PrefixSnapshotStore(
            root: root, pool: ExecutionStatePrefixPool(tokenBudget: 10_000))
        do {
            let quarantined = try store.quarantinedArtifacts()
            let rescanCount = try store.rescan()
            let key = try XCTUnwrapPath(quarantined.first?.artifactPath)
            let lease = store.physicalUse.acquire(key)
            if let lease {
                store.physicalUse.release(lease)
            }
            let verdict = Verdict(
                quarantineCount: quarantined.count,
                rescanCount: rescanCount,
                admissionBlocked: lease == nil)
            let data = try JSONEncoder().encode(verdict)
            FileHandle.standardOutput.write(data)
            exit(quarantined.count == 1 && rescanCount == 0 && lease == nil ? 0 : 4)
        } catch {
            fputs("harness verify failed: \(error)\n", stderr)
            exit(3)
        }

    default:
        fputs("unknown stage \(stage)\n", stderr)
        exit(2)
    }
}

func XCTUnwrapPath(_ path: String?) throws -> String {
    guard let path else { throw HarnessError.missingQuarantinePath }
    return path
}

enum HarnessError: Error {
    case missingQuarantinePath
}

await runStage()
#else
fputs("crash harness requires a DEBUG build\n", stderr)
exit(2)
#endif
