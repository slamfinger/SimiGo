import Foundation
import SimiGoRuntimeContract

/// Producer identity a chat/Responses turn settles under. Injected by the
/// runtime that resolved the model snapshot; absent means the turn still
/// executes but its settlement carries only the protocol-level model id.
public struct InformationTurnProducer: Sendable {
    public let modelIdentity: String
    public let identity: SimiGoSettlementIdentityBinding.Identity

    public init(modelIdentity: String, identity: SimiGoSettlementIdentityBinding.Identity) {
        self.modelIdentity = modelIdentity
        self.identity = identity
    }
}

public typealias InformationTurnProducerProvider = @Sendable () -> InformationTurnProducer?
