import Foundation

/// Post-settlement distillation. A settlement already seals its payload and
/// digest; this adds the reusable projection a later execution state can cite
/// without re-reading the sources the settlement was derived from.
///
/// The distillation is deterministic and model-free: it is a bounded, canonical
/// projection of the sealed payload, so the same settlement always yields byte
/// identical summary text and the same content address. Anything requiring a
/// new generation would be a settlement of its own, not a summary.
public enum SettlementSummaryPolicy {

    public static let schema = "simigo.settlement-summary/v1"
    public static let maxCharacters = 320

    public struct Summary: Codable, Equatable, Sendable {
        public let schema: String
        public let settlementID: String
        public let sessionID: String?
        public let query: String
        public let text: String
        public let sourcePayloadDigest: String
        /// Non-nil only for a derived settlement. A downstream reader must not
        /// cite a derived summary as independent model generation; the source
        /// settlement is the generation evidence.
        public let derivationType: String?
        public let sourceSettlementID: String?

        public init(settlementID: String, sessionID: String?, query: String,
                    text: String, sourcePayloadDigest: String,
                    derivationType: String? = nil,
                    sourceSettlementID: String? = nil) {
            self.schema = SettlementSummaryPolicy.schema
            self.settlementID = settlementID
            self.sessionID = sessionID
            self.query = query
            self.text = text
            self.sourcePayloadDigest = sourcePayloadDigest
            self.derivationType = derivationType
            self.sourceSettlementID = sourceSettlementID
        }
    }

    /// Text a settlement contributes to later retrieval: the produced content
    /// when the payload has one, otherwise a canonical projection of its scalar
    /// fields (`key=value`, keys sorted) so structured results distill too.
    public static func text(fromPayload payload: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: payload),
            let fields = object as? [String: Any]
        else {
            return String(data: payload, encoding: .utf8) ?? ""
        }
        if let content = fields["content"] as? String { return content }
        return fields.keys.sorted().compactMap { key -> String? in
            guard let value = fields[key] else { return nil }
            guard !(value is [String: Any]), !(value is [Any]) else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: "；")
    }

    /// Bounded distillation of produced text. Blank lines are dropped, the cut
    /// falls on a sentence boundary when one is available in range, and the
    /// result is stable for identical input.
    public static func distill(_ text: String, limit: Int = maxCharacters) -> String {
        let normalized = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard limit > 0, !normalized.isEmpty else { return "" }
        if normalized.count <= limit { return normalized }

        let head = String(normalized.prefix(limit))
        if let end = head.lastIndex(where: { "。！？；.!?;".contains($0) }) {
            let sentence = String(head[...end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count >= min(60, limit) { return sentence }
        }
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
