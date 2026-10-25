// Integration Boundary Gate — Backend-2 (K5).
//
// A second `InformationStore` implemented entirely OUTSIDE the accepted
// InformationCore module: it sees only the public protocol and public
// types. Zero SQLite symbols. Its identity minting is its own mechanism
// (recipes belong to mechanisms, C4/A2′); identities remain opaque to
// every consumer.

import CryptoKit
import Foundation
import InformationCore

/// Test/in-memory Physical Filing backend. The minimal counterexample
/// to "the architecture presupposes SQLite": same protocol, same
/// semantics, different mechanism.
public final class InMemoryStore: InformationStore {
    /// Keyed by identity raw value. B2 idempotency: an existing key is
    /// never overwritten — re-store confirms the existing fact.
    private var storage: [String: Information] = [:]

    public init() {}

    /// Mechanism-side identity minting for this backend's formation
    /// path. Recipe is deliberately distinct from the SQLite recipe:
    /// identities are opaque, and cross-recipe equivalence stays a
    /// mechanism-side concern.
    public func makeInformationID(content: String, provenance: Provenance) -> InformationID {
        let parts = [
            "in-memory", // backend namespace: distinct recipe, same discipline
            content,
            provenance.source ?? "",
            String(provenance.position?.chunkIndex ?? 0),
        ]
        let key = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return InformationID(rawValue: String(hex.prefix(24)))
    }

    /// Idempotent by identity (B2): storing an existing identity is a
    /// successful no-op; the stored fact remains unchanged (A1).
    public func store(_ information: Information) throws {
        let key = information.identity.rawValue
        if storage[key] == nil {
            storage[key] = information
        }
        // else: confirm existing fact — successful no-op.
    }

    /// Absence is nil (B3); this backend cannot fail storage itself,
    /// and never conflates absence with error.
    public func fetch(by identity: InformationID) throws -> Information? {
        storage[identity.rawValue]
    }
}
