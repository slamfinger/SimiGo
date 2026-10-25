import Foundation
import SimiGoRuntimeContract

private func encodedJSON(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
}

/// Minimal persistence adapter for a Codable opaque payload. The backend owns
/// the payload schema; this codec only provides a stable envelope identity.
public struct TypedExecutionRepresentationPayloadPersistence<
    Payload: ExecutionRepresentationPayload & Codable
>: ExecutionRepresentationPayloadPersisting {
    public let backendIdentity: String

    public init(backendIdentity: String) {
        self.backendIdentity = backendIdentity
    }

    public func encode(_ payload: any ExecutionRepresentationPayload) throws -> Data {
        guard let payload = payload as? Payload else {
            throw DurableExecutionStateStore.StoreError.malformedState(
                "payload does not match \(backendIdentity)")
        }
        return try encodedJSON(payload)
    }

    public func decode(_ data: Data) throws -> any ExecutionRepresentationPayload {
        try JSONDecoder().decode(Payload.self, from: data)
    }
}

public typealias MLXPrefixPayloadPersistence = TypedExecutionRepresentationPayloadPersistence<MLXPrefixPayload>
public typealias OversizedPrefixPayloadPersistence = TypedExecutionRepresentationPayloadPersistence<OversizedPrefixPayload>
