// Information Core — the `InformationStore` semantic boundary (B1–B3).
//
// A store persists and retrieves already-formed Information. It does
// not decide who an Information is (that happened at formation, A2′),
// does not rewrite anything it has stored (A1/C3), and does not answer
// questions the frozen surface never asked: no search, ranking,
// listing, deletion or query language lives here.

/// The minimal persistence lifecycle of Information.
///
/// - `store` persists a formed Information. Idempotent by identity (B2):
///   storing an identity that already exists is a *successful no-op* —
///   a confirmation of an existing fact, not an update.
/// - `fetch` returns nil for absence (B3). Absence is a normal answer,
///   distinct from storage failure, which is expressed by throwing.
public protocol InformationStore {
    /// Persists an Information. Idempotent by identity (B2): storing an
    /// identity that already exists succeeds as a no-op and the stored
    /// Information remains unchanged.
    ///
    /// Throws only on storage failure.
    func store(_ information: Information) throws

    /// Returns the Information for `identity`, or nil for absence (B3).
    /// Absence is not an error; storage failure is.
    func fetch(by identity: InformationID) throws -> Information?
}
