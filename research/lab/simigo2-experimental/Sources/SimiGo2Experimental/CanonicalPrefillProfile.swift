import Foundation

/// F1 canonical prefill profile (adjudicated 2026-10-15: single, verifiable
/// canonical execution shape; strict output equality between the cold path
/// and the warm path UNDER THE SAME canonical shape; no relaxation to
/// semantic equivalence across arbitrary shapes).
///
/// Canonical shape: `PrefillParameters.Chunking.remainder` with a fixed
/// stride. The plan is PREFIX-STABLE by construction: chunk boundaries sit
/// at multiples of the stride, so the first k·stride tokens of ANY prompt
/// are computed by the identical sequence of forwards regardless of how
/// many tokens follow — the property that makes a cache boundary at a
/// multiple of the stride a stable equivalence point between a cold
/// session's prefill and a warm session's restored-prefix continuation.
///
/// Cache artifacts bind the profile version: the namespace fingerprint
/// carries it, so a protocol change moves every artifact into a new
/// namespace — old artifacts become unreachable (isolated, never silently
/// reused) without any deletion pass.
public struct CanonicalPrefillProfile: Codable, Hashable, Sendable {
    public let version: String
    public let stride: Int

    public init(version: String = "canonical-remainder-v1", stride: Int) {
        precondition(stride >= 1, "canonical stride must be positive")
        self.version = version
        self.stride = stride
    }

    /// A position is a legal cache boundary iff it is a positive multiple
    /// of the stride — the stable-equivalence points of the plan.
    public func isStableBoundary(_ position: Int) -> Bool {
        position > 0 && position % stride == 0
    }

    /// Largest stable boundary at or below `position`.
    public func stableBoundary(atOrBelow position: Int) -> Int {
        (max(position, 1) / stride) * stride
    }

    public var fingerprint: String {
        "\(version)-stride\(stride)"
    }
}
