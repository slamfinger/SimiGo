import CryptoKit
import Foundation
import LOCALBCore
import Network
import XCTest

@testable import SimiGo

/// Shared LOCALB fixtures: a fully paired ACTIVE client, a real TLS
/// listener, real challenge/proof construction, and raw HTTP bytes.
/// Nothing here is a mock; subclasses add their own server construction.
class LOCALBTestCase: XCTestCase {

    // MARK: - Fixture

    /// Indirection so tests can move the registry head (permission grants,
    /// revocations) and have the server's trusted-checkpoint closure follow
    /// the new head instead of a snapshot pinned at pairing time.
    final class LOCALBTrustedCheckpointBox {
        var value: LOCALBRegistryCheckpoint
        init(value: LOCALBRegistryCheckpoint) { self.value = value }
    }

    struct Host {
        let port: UInt16
        let plaintextCompatPort: UInt16
        let spkiHex: String
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
        /// Present when the host was built through makeAuthorizedHost;
        /// bootstrap-path fixtures wire their own registry instead.
        let store: LOCALBRegistryStore?
        let coordinator: LOCALBPairingCoordinator?
        let trustedCheckpoint: LOCALBTrustedCheckpointBox?

        init(
            port: UInt16,
            plaintextCompatPort: UInt16,
            spkiHex: String,
            clientKey: Curve25519.Signing.PrivateKey,
            clientKeyID: String,
            store: LOCALBRegistryStore? = nil,
            coordinator: LOCALBPairingCoordinator? = nil,
            trustedCheckpoint: LOCALBTrustedCheckpointBox? = nil
        ) {
            self.port = port
            self.plaintextCompatPort = plaintextCompatPort
            self.spkiHex = spkiHex
            self.clientKey = clientKey
            self.clientKeyID = clientKeyID
            self.store = store
            self.coordinator = coordinator
            self.trustedCheckpoint = trustedCheckpoint
        }
    }

    func randomPort() -> UInt16 {
        UInt16.random(in: 42000...58000)
    }

    // MARK: - Branch lifecycle fixture (S3-A)

    /// Stateful stand-in for the runtime's branch registry: the deletion
    /// contract (existence check, generation guard, remaining listing) is
    /// exercised end-to-end at the HTTP layer against real state.
    private final class BranchFixture {
        var live: [String: Set<String>] = [:]
        var generations: [String: UInt64] = [:]
        private let lock = NSLock()

        func seed(sessionId: String, branchId: String) {
            lock.lock(); defer { lock.unlock() }
            live[sessionId, default: []].insert(branchId)
            generations["\(sessionId)/\(branchId)", default: 0] += 1
        }

        func delete(
            sessionId: String, branchId: String, expectedGeneration: UInt64?
        ) throws -> BranchDeletionOutcome {
            lock.lock(); defer { lock.unlock() }
            guard let branches = live[sessionId], branches.contains(branchId) else {
                throw BranchLifecycleError.branchUnknown(
                    sessionId: sessionId, branchId: branchId)
            }
            // expected_generation is RESERVED for the llama.cpp ES
            // integration; the fixture does not fabricate a generation
            // source, so no mismatch refusal is raised here.
            let key = "\(sessionId)/\(branchId)"
            let generation = generations[key] ?? 1
            var remaining = branches
            remaining.remove(branchId)
            live[sessionId] = remaining
            generations[key] = nil
            return BranchDeletionOutcome(
                deletedBranch: branchId,
                hadLiveSession: true,
                hadCheckpointFile: false,
                generation: generation,
                remainingLiveBranches: remaining.sorted(),
                remainingCheckpointBranches: []
            )
        }

        func listBranches(sessionId: String) -> [String] {
            lock.lock(); defer { lock.unlock() }
            return (live[sessionId] ?? []).sorted()
        }
    }

    private let branchFixture = BranchFixture()

    /// Seeds a live branch into the deletion fixture before the request.
    func seedBranch(sessionId: String, branchId: String) {
        branchFixture.seed(sessionId: sessionId, branchId: branchId)
    }

    func makeServer(port: UInt16) -> HTTPServer {
        HTTPServer(
            port: Int(port),
            modelId: "localb-b3-wiring-test",
            generateHandler: { _, _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "localb-b3-wiring-test",
                    savedAt: Date(),
                    history: []
                )
            },
            deleteBranchHandler: { [weak self] _, sessionId, branchId, expectedGeneration in
                guard let self else { throw BranchLifecycleError.branchUnknown(
                    sessionId: sessionId, branchId: branchId) }
                return try self.branchFixture.delete(
                    sessionId: sessionId, branchId: branchId,
                    expectedGeneration: expectedGeneration
                )
            },
            listBranchesHandler: { [weak self] _, sessionId in
                (live: self?.branchFixture.listBranches(sessionId: sessionId) ?? [],
                 checkpoints: [])
            },
            checkHealthHandler: { true }
        )
    }

    static func hexSha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }
            .joined()
    }

    /// Builds the full authorized host: registry lineage, host signing key,
    /// one paired ACTIVE client (default {P-INFERENCE, P-INFO-READ}), a TLS
    /// listener with an explicit loopback plaintext-compatibility port, and
    /// the B3 request-authorization wiring.
    func makeAuthorizedHost(
        configureAuthorization: Bool = true
    ) throws -> Host {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-b3-wiring-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let store = LOCALBRegistryStore(rootURL: root)
        var checkpoint = try store.initializeNewLineage()
        let hostSigningKey = Curve25519.Signing.PrivateKey()
        let hostPublicKey = Array(hostSigningKey.publicKey.rawRepresentation)
        checkpoint = try store.appendKeyRegistration(
            publicKeyRaw: hostPublicKey,
            generation: 1,
            checkpoint: checkpoint
        )
        let srsKeyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: hostPublicKey)
        let coordinator = LOCALBPairingCoordinator(registryStore: store)

        // Full interactive pairing: issue → PoP submission → operator
        // approval → single commit event (consume + register).
        let presentation = try coordinator.issueCredential(
            scopeLabel: "B3 wiring test client",
            tlsSPKIHash: Self.hexSha256("localb-b3-test-tls-spki"),
            srsKeyID: srsKeyID,
            checkpoint: checkpoint
        )
        let secret = try LOCALBPairingSubmission.decodeSecretBase64URL(
            presentation.takeSecretBase64URLOnce()
        )
        let clientKey = Curve25519.Signing.PrivateKey()
        let pop = try LOCALBPairingProofV1.sign(
            credentialID: presentation.credentialID,
            sessionNonce: try XCTUnwrap(
                HTTPServer.decodeLowerHex(presentation.sessionNonceHex)
            ),
            hostInstanceID: presentation.hostInstanceID,
            tlsSPKIHash: presentation.tlsSPKIHash,
            srsKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion,
            with: clientKey
        )
        let submission = LOCALBPairingSubmission(
            credentialID: presentation.credentialID,
            secretRaw: secret,
            clientPublicKeyRaw: Array(clientKey.publicKey.rawRepresentation),
            proofSignatureRaw: pop,
            actualTLSSPKIHash: presentation.tlsSPKIHash,
            presentedSRSKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion
        )
        let pending = try coordinator.preparePairing(
            submission,
            checkpoint: presentation.registryCheckpoint
        )
        let committed = try coordinator.approveAndRegister(
            pending,
            operatorApproved: true,
            operatorAuthorizationReference: "B3-WIRING-TEST",
            checkpoint: presentation.registryCheckpoint
        )
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        let transportKeychainDirectory =
            LOCALBTestIsolation.makeKeychainDirectory("b3-wiring")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: transportKeychainDirectory)
        }
        let transportKeychainPath = transportKeychainDirectory
            .appendingPathComponent("transport-identity.keychain-db").path
        let transportStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-b3.\(UUID().uuidString)",
            account: "tls",
            keychainPath: transportKeychainPath
        )
        addTeardownBlock { transportStore.deleteAll() }
        let identity = try transportStore.loadOrCreate()
        LOCALBTestIsolation.assertKeychainLanded(
            transportStore.keychainPath, expected: transportKeychainPath)

        let port = randomPort()
        let plaintextCompatPort = randomPort()
        let server = makeServer(port: port)
        server.configureLOCALBTransport(
            identity: identity,
            plaintextCompatibilityPort: Int(plaintextCompatPort)
        )
        let trustedCheckpointBox = LOCALBTrustedCheckpointBox(value: committed)
        if configureAuthorization {
            server.configureLOCALBRequestAuthorization(
                coordinator: coordinator,
                trustedCheckpoint: { trustedCheckpointBox.value }
            )
        }
        try server.start()
        addTeardownBlock { server.stop() }

        return Host(
            port: port,
            plaintextCompatPort: plaintextCompatPort,
            spkiHex: identity.spkiSHA256Hex,
            clientKey: clientKey,
            clientKeyID: clientKeyID,
            store: store,
            coordinator: coordinator,
            trustedCheckpoint: trustedCheckpointBox
        )
    }

    // MARK: - Raw HTTP helpers

    func sendRequest(
        port: UInt16,
        spkiHex: String?,
        request: String,
        timeout: TimeInterval = 10
    ) -> Data? {
        let parameters: NWParameters
        if let spkiHex {
            let options = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(
                options.securityProtocolOptions,
                { _, secTrust, complete in
                    guard
                        let trust = sec_trust_copy_ref(secTrust)
                            .takeRetainedValue() as SecTrust?,
                        let certificate = SecTrustGetCertificateAtIndex(trust, 0),
                        let hex = try? LOCALBTransportIdentityStore
                            .spkiSHA256Hex(of: certificate)
                    else {
                        complete(false)
                        return
                    }
                    complete(hex == spkiHex)
                },
                DispatchQueue.global()
            )
            parameters = NWParameters(tls: options)
        } else {
            parameters = .tcp
        }
        let client = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: parameters
        )
        let done = expectation(description: "raw http done")
        var response: Data?
        var fulfilled = false
        let fulfilledLock = NSLock()
        func finish() {
            fulfilledLock.lock()
            let already = fulfilled
            fulfilled = true
            fulfilledLock.unlock()
            if !already { done.fulfill() }
        }
        client.stateUpdateHandler = { state in
            switch state {
            case .ready:
                client.send(
                    content: Data(request.utf8),
                    completion: .contentProcessed { _ in }
                )
                client.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: 256 * 1024
                ) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        response = data
                        finish()
                    } else if isComplete || error != nil {
                        finish()
                    }
                }
            case .failed, .cancelled, .waiting:
                finish()
            default:
                break
            }
        }
        client.start(queue: DispatchQueue.global())
        wait(for: [done], timeout: timeout)
        client.cancel()
        return response
    }

    func statusLine(of response: Data?) -> String? {
        response.flatMap { String(data: $0, encoding: .utf8) }?
            .components(separatedBy: "\r\n").first
    }

    func jsonBody(of response: Data?) -> [String: Any]? {
        guard let text = response.flatMap({ String(data: $0, encoding: .utf8) }),
              let range = text.range(of: "\r\n\r\n")
        else { return nil }
        let body = String(text[range.upperBound...])
        return try? JSONSerialization.jsonObject(with: Data(body.utf8))
            as? [String: Any]
    }

    /// Fetches a one-time challenge over pinned TLS for the intended
    /// (method, target); the server derives the permission.
    func fetchChallenge(
        _ host: Host,
        method: String,
        target: String
    ) throws -> (challenge: [UInt8], permission: String) {
        let body = "{\"method\":\"\(method)\",\"requestTarget\":\"\(target)\"}"
        let request = "POST /localb/auth/challenge HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        let response = sendRequest(
            port: host.port,
            spkiHex: host.spkiHex,
            request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "challenge: \(status)")
        let json = try XCTUnwrap(jsonBody(of: response))
        let challengeHex = try XCTUnwrap(json["challenge"] as? String)
        let permission = try XCTUnwrap(json["permission"] as? String)
        let challenge = try XCTUnwrap(HTTPServer.decodeLowerHex(challengeHex))
        XCTAssertEqual(challenge.count, 32)
        return (challenge, permission)
    }

    /// Builds a signed protected request for the exact target/body and
    /// returns the raw HTTP request bytes. `extraHeaders` are sent on the
    /// wire but are NOT part of the signed material — the fixture for
    /// unsigned-header boundary tests.
    func protectedRequest(
        _ host: Host,
        method: String,
        target: String,
        contentType: String?,
        body: String,
        challenge: [UInt8],
        permission: LOCALBPermission,
        sendTarget: String? = nil,
        sendBody: String? = nil,
        extraHeaders: [(name: String, value: String)] = []
    ) throws -> String {
        let authority = "127.0.0.1:\(host.port)"
        let signed = try LOCALBHTTPRequestV1(
            method: method,
            authority: authority,
            requestTarget: target,
            contentType: contentType,
            bodyRaw: Array(body.utf8)
        )
        let proof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: host.clientKeyID,
            permission: permission,
            request: signed,
            challenge: challenge,
            with: host.clientKey
        )
        let wireTarget = sendTarget ?? target
        let wireBody = sendBody ?? body
        var request = "\(method) \(wireTarget) HTTP/1.1\r\n"
            + "Host: \(authority)\r\n"
        if let contentType {
            request += "Content-Type: \(contentType)\r\n"
        }
        for (name, value) in extraHeaders {
            request += "\(name): \(value)\r\n"
        }
        request += "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "X-SimiGo-LocalB-Challenge: "
            + HTTPServer.encodeLowerHex(challenge) + "\r\n"
            + "X-SimiGo-LocalB-Proof-V2: "
            + Data(proof).base64EncodedString() + "\r\n"
            + "Content-Length: \(wireBody.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + wireBody
        return request
    }

    // MARK: - Activated host fixture

    struct BootstrapHostEnvironment {
        let hostDirectory: URL
        let keychain: LOCALBKeychainSignerStore
        let transport: LOCALBTransportIdentityStore
        let spkiHex: String
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
    }

    /// An activated host (trusted checkpoint persisted outside the registry)
    /// with one paired ACTIVE client. No server is started here; callers
    /// exercise their own construction site through LOCALBHostRuntime.
    func makeBootstrapHostEnvironment() throws
        -> BootstrapHostEnvironment {
        let hostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-b3-boothost-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: hostDirectory)
        }

        let keychainRoot = hostDirectory
            .appendingPathComponent("keychains", isDirectory: true)
        let signerKeychainPath = keychainRoot
            .appendingPathComponent("production-signer.keychain-db").path
        let transportKeychainPath = keychainRoot
            .appendingPathComponent("transport-identity.keychain-db").path
        let keychain = LOCALBKeychainSignerStore(
            service: "com.simigo.tests.localb-boot.\(UUID().uuidString)",
            account: "signing-key-v1",
            keychainPath: signerKeychainPath)
        let transport = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-boot.\(UUID().uuidString)",
            account: "tls",
            keychainPath: transportKeychainPath)
        addTeardownBlock { transport.deleteAll() }

        let registryRoot = LOCALBHostRuntime.registryRoot(in: hostDirectory)
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: registryRoot,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        _ = try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: registryRoot,
            operatorRecordedCheckpoint: pending.checkpoint,
            keychainStore: keychain,
            transportIdentityStore: transport
        )
        LOCALBTestIsolation.assertKeychainLanded(
            keychain.keychainPath, expected: signerKeychainPath)
        LOCALBTestIsolation.assertKeychainLanded(
            transport.keychainPath, expected: transportKeychainPath)
        // The activation ceremony records the trusted checkpoint OUTSIDE
        // the registry; ordinary startup consumes it read-only.
        try LOCALBHostRuntime.persistTrustedCheckpoint(
            pending.checkpoint, in: hostDirectory)

        guard case .operational(let context) =
            try LOCALBHostRuntime.resolveOperational(
                hostDirectory: hostDirectory,
                keychainStore: keychain,
                transportIdentityStore: transport
            )
        else {
            throw NSError(
                domain: "LOCALBRequestAuthWiringTests", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "expected an operational host after activation"
                ])
        }

        // Full interactive pairing of one ACTIVE client into the verified
        // registry, exactly like the explicit-injection fixture.
        let coordinator = context.pairingCoordinator()
        var checkpoint = try context.currentTrustedCheckpoint()
        let presentation = try coordinator.issueCredential(
            scopeLabel: "B3 default-path client",
            tlsSPKIHash: pending.transportSPKIHashHex,
            srsKeyID: context.signerKeyID,
            checkpoint: checkpoint
        )
        let secret = try LOCALBPairingSubmission.decodeSecretBase64URL(
            presentation.takeSecretBase64URLOnce()
        )
        let clientKey = Curve25519.Signing.PrivateKey()
        let pop = try LOCALBPairingProofV1.sign(
            credentialID: presentation.credentialID,
            sessionNonce: try XCTUnwrap(
                HTTPServer.decodeLowerHex(presentation.sessionNonceHex)
            ),
            hostInstanceID: presentation.hostInstanceID,
            tlsSPKIHash: presentation.tlsSPKIHash,
            srsKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion,
            with: clientKey
        )
        let submission = LOCALBPairingSubmission(
            credentialID: presentation.credentialID,
            secretRaw: secret,
            clientPublicKeyRaw: Array(clientKey.publicKey.rawRepresentation),
            proofSignatureRaw: pop,
            actualTLSSPKIHash: presentation.tlsSPKIHash,
            presentedSRSKeyID: presentation.srsKeyID,
            protocolVersion: presentation.protocolVersion
        )
        let pendingPairing = try coordinator.preparePairing(
            submission, checkpoint: checkpoint
        )
        checkpoint = try coordinator.approveAndRegister(
            pendingPairing,
            operatorApproved: true,
            operatorAuthorizationReference: "B3-DEFAULT-PATH",
            checkpoint: checkpoint
        )
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        return BootstrapHostEnvironment(
            hostDirectory: hostDirectory,
            keychain: keychain,
            transport: transport,
            spkiHex: pending.transportSPKIHashHex,
            clientKey: clientKey,
            clientKeyID: clientKeyID
        )
    }

    func host(for environment: BootstrapHostEnvironment, port: UInt16) -> Host {
        Host(
            port: port,
            plaintextCompatPort: 0,
            spkiHex: environment.spkiHex,
            clientKey: environment.clientKey,
            clientKeyID: environment.clientKeyID
        )
    }
}
