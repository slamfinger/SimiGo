import MLX

/// Evaluated MLX values cross these boundaries one-at-a-time; callers must
/// keep ownership serialized. Box them only at the narrow API boundary where
/// MLX has not adopted Sendable.
struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
