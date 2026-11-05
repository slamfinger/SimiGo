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
    static func activity(
        port: Int,
        session: URLSession = .shared
    ) async -> SlotActivity {
        guard let url = URL(string: "http://127.0.0.1:\(port)/slots") else {
            return .unknown
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        // /slots is a live process-safety signal. Never let URLCache return a
        // previous idle/busy snapshot to the health-check decision.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unknown
            }
            return SlotActivityParser.activity(
                from: data, statusCode: http.statusCode)
        } catch {
            return .unknown
        }
    }
}

extension ManagedGGUFRuntime: SlotActivityProviding {
    func slotActivity() async -> SlotActivity {
        guard let port = enginePort else { return .unknown }
        return await GGUFSlotActivityProbe.activity(port: port)
    }
}
