import Foundation

/// What a recorded conversation round keeps, and what it says about itself.
///
/// A round is stored as text and nothing else: whatever the caller leaves out
/// is lost, because no later reader can recover the answer from a summary. The
/// one thing that must never be left to the caller's memory is the boundary —
/// what the round does not establish. It travels under a fixed heading, and a
/// round that states none is reported as such rather than read as unlimited.
public enum ChatRoundText {
    public static let boundaryHeading = "边界（入库时）："

    /// The reply as given, plus the boundary under its own heading.
    public static func compose(assistant: String, boundary: String?) -> String {
        guard let boundary = trimmed(boundary), !boundary.isEmpty else {
            return assistant
        }
        return assistant + "\n\n" + boundaryHeading + "\n" + boundary
    }

    /// True when the round states a boundary at all — passed as its own
    /// argument, or written into the reply under either word.
    public static func statesBoundary(assistant: String, boundary: String?) -> Bool {
        if let boundary = trimmed(boundary), !boundary.isEmpty { return true }
        return assistant.contains("边界") || assistant.contains("Boundary")
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
