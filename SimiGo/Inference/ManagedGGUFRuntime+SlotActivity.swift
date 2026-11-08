import CoreFoundation
import Foundation

/// What the engine's own `/slots` response lets us conclude about activity.
///
/// Three states, no fourth: `unknown` is a first-class answer for a missing
/// port, a timeout, a non-200 status or a payload that does not match the
/// locked llama.cpp schema. `unknown` is never treated as idle by callers.
nonisolated enum SlotActivity: Equatable, Sendable {
    case idle
    case busy
    case unknown
}

nonisolated enum SlotActivityParser {
    /// The locked llama.cpp (b11720) reports `is_processing` per slot. A
    /// missing or malformed field is unknown, never idle: the old `state`
    /// field is not part of this schema and its absence must not read as
    /// "all slots free".
    ///
    /// An empty list is also unknown — a server that exposes no slots cannot
    /// prove the engine is idle.
    static func activity(from data: Data, statusCode: Int) -> SlotActivity {
        guard statusCode == 200,
            let object = try? JSONSerialization.jsonObject(with: data),
            let slots = object as? [[String: Any]],
            !slots.isEmpty
        else { return .unknown }

        var sawMalformed = false
        for slot in slots {
            guard let value = slot["is_processing"] as? NSNumber,
                CFGetTypeID(value) == CFBooleanGetTypeID()
            else {
                sawMalformed = true
                continue
            }
            if value.boolValue { return .busy }
        }
        return sawMalformed ? .unknown : .idle
    }
}

/// Pure decisions used by the health loop. `unknown` is deliberately not
/// equivalent to idle: it permits the health check, but never protects a
/// failed engine from restart. Cancellation and runtime freshness override all
/// slot observations.
nonisolated enum GGUFHealthCheckPolicy {
    static func shouldSkipPreflight(
        isGGUF: Bool, isInProcess: Bool, injectedFailure: Bool,
        slotActivity: SlotActivity
    ) -> Bool {
        isGGUF && !isInProcess && !injectedFailure && slotActivity == .busy
    }

    static func shouldDeferRestart(
        isGGUF: Bool, slotActivity: SlotActivity
    ) -> Bool {
        isGGUF && slotActivity == .busy
    }

    static func shouldRestartAfterFailure(
        isCancelled: Bool, runtimeIsCurrent: Bool,
        isGGUF: Bool, slotActivity: SlotActivity
    ) -> Bool {
        !isCancelled && runtimeIsCurrent
            && !shouldDeferRestart(isGGUF: isGGUF, slotActivity: slotActivity)
    }
}

/// A runtime that can report its engine's slot activity without going through
/// the product listener.
protocol SlotActivityProviding: AnyObject {
    func slotActivity() async -> SlotActivity
}

nonisolated enum SlotActivityResolver {
    /// Non-GGUF runtimes, and the window where no runtime exists, answer
    /// `unknown` instead of guessing.
    static func activity(for runtime: Runtime?) async -> SlotActivity {
        guard let provider = runtime as? SlotActivityProviding else {
            return .unknown
        }
        return await provider.slotActivity()
    }

    static func activity(for provider: SlotActivityProviding?) async -> SlotActivity {
        guard let provider else { return .unknown }
        return await provider.slotActivity()
    }
}

nonisolated enum GGUFSlotActivityProbe {
    /// Reads the engine's own loopback `/slots`. The product listener is never
    /// used: there is no route, no auth surface and no LAN exposure added.
    static func makeRequest(port: Int) -> URLRequest? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/slots") else {
            return nil
        }
        return URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 1.0)
    }

    static func activity(
        port: Int,
        session: URLSession = .shared
    ) async -> SlotActivity {
        guard let raw = await rawSlots(port: port, session: session) else {
            return .unknown
        }
        return SlotActivityParser.activity(
            from: raw.data, statusCode: raw.status)
    }

    /// The raw /slots payload plus its status: one fetch serves both the
    /// health loop's lossy classification and the R2-B progress monitor, so
    /// monitoring adds no request and changes no busy-protection timing.
    static func rawSlots(
        port: Int,
        session: URLSession = .shared
    ) async -> (data: Data, status: Int)? {
        guard let request = makeRequest(port: port) else {
            return nil
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return nil
            }
            return (data, http.statusCode)
        } catch {
            return nil
        }
    }
}

extension ManagedGGUFRuntime: SlotActivityProviding {
    /// Stable per runtime instance: every internalStart creates a fresh
    /// runtime, so an engine restart necessarily changes the generation and
    /// the monitor re-baselines (owner ruling: identity is generation x slot
    /// x task).
    var engineGeneration: UInt64 {
        UInt64(bitPattern: Int64(ObjectIdentifier(self).hashValue))
    }

    func slotActivity() async -> SlotActivity {
        guard let port = enginePort else {
            // The engine port is temporarily unresolvable: no slot was
            // observed this tick, so tracked baselines must be blocked from
            // confirming a stall across the gap (review 2026-11-08).
            _ = progressMonitor.observeProbeFailure(
                engineGeneration: engineGeneration)
            return .unknown
        }
        guard let raw = await GGUFSlotActivityProbe.rawSlots(port: port) else {
            _ = progressMonitor.observeProbeFailure(
                engineGeneration: engineGeneration)
            return .unknown
        }
        let activity = SlotActivityParser.activity(
            from: raw.data, statusCode: raw.status)
        for v in SlotProgressIngest.ingest(
            data: raw.data, statusCode: raw.status,
            engineGeneration: engineGeneration, into: progressMonitor) {
            if v.state == .candidateStall {
                let taskLabel = v.idTask.map(String.init) ?? "unknown"
                RuntimeTraceLogger.shared.trace(
                    "[SLOT-PROGRESS] slot=\(v.slotID) task=\(taskLabel) "
                        + "state=\(v.state.rawValue) phase=\(v.phase.rawValue) "
                        + "noProgressMs=\(v.noProgressMS ?? 0) \(v.reason) "
                        + "— monitor only; no restart is authorised")
            }
        }
        return activity
    }
}
