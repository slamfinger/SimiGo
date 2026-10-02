// Relation Core — mechanism-side identity minting (D2).
//
// The minter IS the recipe: deterministic, collision-safe
// (length-prefixed delimiter join), namespace-separated from the
// Information recipe. No timestamp salt — the service tree's
// datetime-salted triple IDs (non-deterministic, non-idempotent) are
// recorded negative evidence and are deliberately not replicated.

import CryptoKit
import Foundation
import InformationCore

/// Mechanism-side minter for `RelationID` values.
///
/// Public because formation happens outside this module, exactly like
/// the Information formation chain; the *recipe* stays invisible —
/// callers receive identities, never algorithms.
public enum RelationMinter {
    /// Mints the identity for a Relation being formed.
    public static func makeRelationID(
        subject: InformationID,
        predicate: RelationPredicate,
        object: InformationID
    ) -> RelationID {
        let parts = [
            "relation", // backend/recipe namespace, distinct from Information
            subject.rawValue,
            predicate.value,
            object.rawValue,
        ]
        let key = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return RelationID(rawValue: String(hex.prefix(24)))
    }
}
