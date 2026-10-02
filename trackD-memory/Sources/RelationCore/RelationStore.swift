// Relation Core — the `RelationStore` semantic boundary (D4).
//
// Independent from `InformationStore` by ruling: the finalized S1–S6
// Information persistence contract is NOT extended, reused or nested.
// This boundary carries its own minimal surface, whose behavioral shape
// mirrors the ruled Information semantics (first-write-wins, absence =
// nil, failure = throw) — recorded as an implementation decision; a
// formal RelationStore contract gate becomes relevant only if multiple
// Relation backends ever exist.

/// The minimal persistence lifecycle of a Relation.
///
/// - `store` persists a formed Relation. Idempotent by identity: storing
///   an identity that already exists succeeds as a no-op and the stored
///   Relation remains unchanged (first-write-wins mirror).
/// - `fetch` returns nil for absence; absence is not an error, storage
///   failure is.
public protocol RelationStore {
    /// Persists a Relation. Idempotent by identity (first-write-wins).
    ///
    /// Throws only on storage failure.
    func store(_ relation: Relation) throws

    /// Returns the Relation for `identity`, or nil for absence.
    func fetch(by identity: RelationID) throws -> Relation?
}
