// Information Core — the `Information` semantic boundary.
//
// This file implements semantics already ruled and frozen
// (SIMIGO_LAB_PHASE1_API_RULING_20261002.md,
//  SIMIGO_LAB_PHASE1_API_GATE_CLOSED_20261002.md). It is not an
// exploration of what Information is.
//
// Ruled facts implemented here:
// - A1  `Information` is an immutable value. No mutation, no update;
//       storing the same identity again is a confirmation of an
//       existing fact, never a modification.
// - A2  `InformationID` is an opaque semantic identity. The identity
//       *belongs to* the Information; the *algorithm that computes it*
//       (hash, recipe, normalization, encoding) does not, and appears
//       nowhere in this file.
// - A3  Provenance optionality follows observed facts, not commonality:
//       producedAt / producedBy required; source, sourceTime, position
//       and extractionMode optional.
// - A4  Temporal meaning is a *paired* value: a content date together
//       with the source that recorded it. The pair is optional as a
//       whole; a date without a recorded source is not representable.
//       `unknown` is a recorded-source marker, never a claim of
//       inference. No retroactive inference.
// - A5  Negative space: no wing/room/hall, entities, relation,
//       activation, diary, retrieval, taxonomy or execution-state
//       surface exists here — no fields, no protocols, no placeholders.

import Foundation

/// The opaque semantic identity of an `Information`.
///
/// `InformationID` is a fact about an Information, not an algorithm.
/// Values are produced by a mechanism-side minter co-located with the
/// persistence layer (A2′: identity is formed with the Information; how
/// it is computed belongs to the mechanism). This type deliberately
/// exposes no hashing, recipe, version or encoding surface.
public struct InformationID: Hashable, Sendable {
    /// The persistent raw form of this identity. A plain value: the raw
    /// form is not the algorithm that produced it.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Where a content date was recorded from.
///
/// `unknown` is the service behavior's default marker for a recorded
/// date whose source was not captured; it never means "inferred".
public enum ContentDateSource: Hashable, Sendable {
    case filename
    case frontmatter
    case body
    case mtime
    case unknown
}

/// A content date and the source that recorded it — inseparable (A4).
public struct ContentDate: Hashable, Sendable {
    /// The date as recorded (ISO-8601 form). Stored verbatim; the Core
    /// performs no normalization or inference on it.
    public let iso8601: String
    /// The recorded source of the date.
    public let source: ContentDateSource

    public init(iso8601: String, source: ContentDateSource) {
        self.iso8601 = iso8601
        self.source = source
    }
}

/// Where in a structured source an Information came from.
///
/// `chunkIndex` was present on every observed structured path;
/// line numbers exist only on format-extraction paths, hence optional.
public struct SourcePosition: Hashable, Sendable {
    public let chunkIndex: Int
    public let lineStart: Int?
    public let lineEnd: Int?

    public init(chunkIndex: Int, lineStart: Int? = nil, lineEnd: Int? = nil) {
        self.chunkIndex = chunkIndex
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }
}

/// Who produced an Information, when, from where, and how (A3).
///
/// Required facts: producedAt, producedBy. Optional facts — optional
/// because the service tree actually omits them on some paths, not
/// because they are rare: `source` (origin path), `sourceTime` (origin
/// mtime), `position` (structured-extraction location),
/// `extractionMode` (structured-extraction provenance).
public struct Provenance: Hashable, Sendable {
    public let producedAt: Date
    public let producedBy: String
    public let source: String?
    public let sourceTime: Date?
    public let position: SourcePosition?
    public let extractionMode: String?

    public init(
        producedAt: Date,
        producedBy: String,
        source: String? = nil,
        sourceTime: Date? = nil,
        position: SourcePosition? = nil,
        extractionMode: String? = nil
    ) {
        self.producedAt = producedAt
        self.producedBy = producedBy
        self.source = source
        self.sourceTime = sourceTime
        self.position = position
        self.extractionMode = extractionMode
    }
}

/// An immutable, already-formed Information value (A1).
///
/// Formation chain (A2′): facts + formation context → mechanism-side
/// minter → `InformationID` → `Information` → store. By the time an
/// `Information` exists it is complete; there is no draft state and no
/// mutation.
///
/// `content` is verbatim by definition. Nothing in this type is
/// normalized, indexed, ranked, filed or activated — those are other
/// layers, and none of them appear here.
public struct Information: Hashable, Sendable {
    /// The semantic identity of this Information (A2).
    public let identity: InformationID
    /// The verbatim content.
    public let content: String
    /// Origin and production facts (A3).
    public let provenance: Provenance
    /// Recorded content date + source, as a pair (A4).
    public let temporal: ContentDate?

    public init(
        identity: InformationID,
        content: String,
        provenance: Provenance,
        temporal: ContentDate? = nil
    ) {
        self.identity = identity
        self.content = content
        self.provenance = provenance
        self.temporal = temporal
    }
}
