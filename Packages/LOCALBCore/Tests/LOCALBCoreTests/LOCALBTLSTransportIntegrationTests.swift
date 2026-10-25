import Foundation
import Network
import XCTest

@testable import LOCALBCore

/// B1 stop-condition integration tests: the transport identity must work as a
/// REAL NWProtocolTLS local identity — real handshake, real Keychain identity,
/// client-side SPKI pinning. No mock identities are used anywhere here.
final class LOCALBTLSTransportIntegrationTests: XCTestCase {
    private lazy var scratchKeychainPath: String =
        NSTemporaryDirectory() + "/localb-tests-\(UUID().uuidString).keychain-db"

    private func makeStore() -> LOCALBTransportIdentityStore {
        LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-tls.\(UUID().uuidString)",
            account: "tls",
            keychainPath: scratchKeychainPath
        )
    }

    private func makeListener(
        identity: LOCALBTransportIdentityHandle
    ) throws -> NWListener {
        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity.secIdentity) else {
            throw LOCALBStatus.transportIdentityMismatch
        }
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions, secIdentity
        )
        let parameters = NWParameters(tls: tlsOptions)
        parameters.allowLocalEndpointReuse = true
        return try NWListener(using: parameters, on: .any)
    }

    /// Client TLS options whose verification block pins the given SPKI hex.
    /// The pin is computed from the certificate the server actually presented
    /// (via SecTrust) — never from any request content.
    private func makeClientOptions(pinnedSPKIHex: String) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, secTrust, complete in
                guard let trust = sec_trust_copy_ref(secTrust).takeRetainedValue() as SecTrust?,
                      let certificate = SecTrustGetCertificateAtIndex(trust, 0),
                      let hex = try? LOCALBTransportIdentityStore.spkiSHA256Hex(of: certificate) else {
                    complete(false)
                    return
                }
                complete(hex == pinnedSPKIHex)
            },
            DispatchQueue.global()
        )
        return options
    }

    func testRealTLSHandshakeWithPinnedSPKI() throws {
        let store = makeStore()
        defer { store.deleteAll() }
        let handle = try store.loadOrCreate()

        let listener = try makeListener(identity: handle)
        defer { listener.cancel() }

        let listenerReady = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { listenerReady.fulfill() }
            if case .failed = state { XCTFail("listener failed: \(state)") }
        }

        let echoReceived = expectation(description: "echo received over TLS")
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = { state in
                if case .failed = state { XCTFail("server connection failed: \(state)") }
            }
            connection.start(queue: .global())
            // Stream echo: receive the inbound bytes and send them back.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                data, _, _, error in
                guard error == nil, let data else {
                    XCTFail("server receive failed: \(String(describing: error))")
                    return
                }
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        listener.start(queue: .global())
        wait(for: [listenerReady], timeout: 15.0)
        let port = try XCTUnwrap(listener.port)

        let client = NWConnection(
            host: "127.0.0.1", port: port,
            using: NWParameters(tls: makeClientOptions(pinnedSPKIHex: handle.spkiSHA256Hex))
        )
        defer { client.cancel() }

        let clientReady = expectation(description: "client TLS ready")
        client.stateUpdateHandler = { state in
            if case .ready = state { clientReady.fulfill() }
            if case .failed = state { XCTFail("client TLS failed: \(state)") }
        }
        client.start(queue: .global())
        wait(for: [clientReady], timeout: 15.0)

        // The handshake proved the identity chain; now prove data flows over
        // the pinned session.
        let payload = Data("localb-tls-stop-condition".utf8)
        client.send(content: payload, completion: .contentProcessed { error in
            XCTAssertNil(error)
        })
        client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            data, _, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, payload)
            echoReceived.fulfill()
        }
        wait(for: [echoReceived], timeout: 15.0)
    }

    func testWrongPinRejectsHandshake() throws {
        let store = makeStore()
        defer { store.deleteAll() }
        let handle = try store.loadOrCreate()

        let listener = try makeListener(identity: handle)
        defer { listener.cancel() }

        let listenerReady = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { listenerReady.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
        }
        listener.start(queue: .global())
        wait(for: [listenerReady], timeout: 15.0)
        let port = try XCTUnwrap(listener.port)

        // The client pins a WRONG fingerprint (all zeros). Acceptance
        // criterion: no protected session is ever established — the client
        // must never reach .ready (a clean .failed or a handshake that never
        // completes both satisfy "rejected").
        let wrongPin = String(repeating: "0", count: 64)
        let client = NWConnection(
            host: "127.0.0.1", port: port,
            using: NWParameters(tls: makeClientOptions(pinnedSPKIHex: wrongPin))
        )
        let handshakeRejected = expectation(description: "handshake rejected by wrong pin")
        handshakeRejected.isInverted = true
        var becameReady = false
        client.stateUpdateHandler = { state in
            if case .ready = state { becameReady = true }
        }
        client.start(queue: .global())
        // A send attempt forces the handshake to resolve instead of idling.
        client.send(content: Data("probe".utf8), completion: .contentProcessed { _ in })
        // Inverted expectation: passing means the client never became ready.
        wait(for: [handshakeRejected], timeout: 10.0)
        client.cancel()
        XCTAssertFalse(becameReady, "client must never become ready with a wrong pin")
    }
}
