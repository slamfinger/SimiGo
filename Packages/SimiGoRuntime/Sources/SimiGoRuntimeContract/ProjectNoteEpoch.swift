import Foundation

/// `project_notes.recorded_at` 的纪元归一。
///
/// The column contract is `ESISDatabase.stamp(_:)`: Apple reference seconds
/// (2001-01-01), written with 17 significant digits so a `Date` round-trips
/// bit-identically. Nine rows recorded on 2026-11-27 by a session that
/// hand-rolled its own `INSERT` carry Unix seconds (1970-01-01) instead
/// (defects FDC884A7 / BFC75162). The ledger is append-only and those rows are
/// the evidence, so they are never rewritten: every read normalizes them, at
/// the single row decoder and in the SQL that compares the column.
///
/// The discriminator is the clock, not a constant: a note cannot legitimately
/// be recorded far in the future, so a value that outruns `now` by more than a
/// day is not a reference stamp and gets shifted back. A fixed cutoff would be
/// simpler and wrong — reference seconds pass 1e9 in 2032-09, from which day
/// every well-formed row would be silently shifted 31 years into the past.
/// Reading the rule off the clock keeps it true for rows written after that
/// date too, and leaves the residual ambiguity where it belongs: 31 years from
/// now, when the two epochs finally overlap, only these nine legacy rows are
/// affected, and by then they are history rather than the live head.
/// Non-numeric values (legacy ISO-8601 rows, which `parseISO8601` still
/// accepts) are left untouched.
enum ProjectNoteEpoch {
    /// Seconds between 1970-01-01 and 2001-01-01.
    static let unixToReferenceOffset = 978_307_200.0

    /// How far ahead of the clock a stamp may sit and still be believed.
    static let futureTolerance: TimeInterval = 86_400

    /// Reference seconds past which a numeric `recorded_at` cannot be a
    /// well-formed stamp of something already recorded.
    static func threshold(_ now: Date = Date()) -> Double {
        now.timeIntervalSinceReferenceDate + futureTolerance
    }

    /// The stored value as Apple reference seconds, or `nil` when it is not
    /// numeric at all.
    static func referenceSeconds(
        _ stored: String, threshold: Double = ProjectNoteEpoch.threshold()
    ) -> Double? {
        guard let value = Double(stored) else { return nil }
        return value > threshold ? value - unixToReferenceOffset : value
    }

    /// The stored text with a Unix-seconds value rewritten in `stamp(_:)` form;
    /// anything else comes back byte-identical. Normalizing is therefore a
    /// no-op for every well-formed row and idempotent for an already normalized
    /// one. The subtraction stays in `Double` instead of going through
    /// `Date(timeIntervalSince1970:)` on purpose: `stamp(_:)` documents that the
    /// epoch offset is not bit-exact for ~1.7e9 values.
    static func normalizedStamp(
        _ stored: String, threshold: Double = ProjectNoteEpoch.threshold()
    ) -> String {
        guard let value = Double(stored), value > threshold else { return stored }
        return String(format: "%.17g", value - unixToReferenceOffset)
    }

    /// `CAST(recorded_at AS REAL)` with the same rule applied by the database,
    /// so a `WHERE` or `ORDER BY` over the column agrees with what Swift reads
    /// back through `normalizedStamp(_:)`. The threshold is interpolated as a
    /// formatted `Double` this type computed itself — never caller text — so
    /// the statement keeps its existing bind positions.
    static func recordedAtSQL(
        threshold: Double = ProjectNoteEpoch.threshold()
    ) -> String {
        """
        CASE WHEN CAST(recorded_at AS REAL) > \(String(format: "%.17g", threshold))
        THEN CAST(recorded_at AS REAL) - \(String(format: "%.1f", unixToReferenceOffset))
        ELSE CAST(recorded_at AS REAL) END
        """
    }
}
