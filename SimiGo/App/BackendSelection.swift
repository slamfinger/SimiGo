import Foundation

/// Local model backend the product can start. Remote providers are not a
/// selection: an external agent brings its own model and settles through MCP.
public enum BackendSelection: String, CaseIterable, Sendable {
    case mlx
    case llamaCpp

    public var displayName: String {
        switch self {
        case .mlx: return "MLX"
        case .llamaCpp: return "LLaMA.cpp"
        }
    }
}
