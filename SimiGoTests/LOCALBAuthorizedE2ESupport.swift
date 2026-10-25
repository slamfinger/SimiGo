import CryptoKit
import Foundation
import LOCALBCore
import XCTest

@testable import SimiGo

/// TEST-ONLY LOCALB-authorized E2E fixture (owner ruling 2026-10-16,
/// option (a)): a real transport identity, a real LOCALB registry with a
/// fully paired ACTIVE client, a pinned-TLS URLSession, and one V2 proof
/// per protected request. This support never alters production defaults —
/// it exists so product E2E suites can run through the SAME fail-closed
/// transport and authorization gates a real paired client must pass.
enum LOCALBAuthorizedE2E {

    /// URLSession delegate that accepts ONLY the pinned listener SPKI.
    private final class PinnedDelegate: NSObject, URLSessionDelegate {
        let spkiHex: String
        init(spkiHex: String) {
            self.spkiHex = spkiHex
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (
                URLSession.AuthChallengeDisposition, URLCredential?
            ) -> Void
        ) {
            guard let trust = challenge.protectionSpace.serverTrust,
                  let certificate = SecTrustGetCertificateAtIndex(trust, 0),
                  let hex = try? LOCALBTransportIdentityStore
                      .spkiSHA256Hex(of: certificate),
                  hex == spkiHex
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    final class Host {
        let identity: LOCALBTransportIdentityHandle
        let spkiHex: String
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
        let coordinator: LOCALBPairingCoordinator
        let checkpointProvider: () throws -> LOCALBRegistryCheckpoint
        let session: URLSession

        private let registryRoot: URL
        private let transportStore: LOCALBTransportIdentityStore

        init(
            identity: LOCALBTransportIdentityHandle,
            spkiHex: String,
            clientKey: Curve25519.Signing.PrivateKey,
            clientKeyID: String,
            coordinator: LOCALBPairingCoordinator,
            checkpointProvider: @escaping () throws -> LOCALBRegistryCheckpoint,
            registryRoot: URL,
            transportStore: LOCALBTransportIdentityStore
        ) {
            self.identity = identity
            self.spkiHex = spkiHex
            self.clientKey = clientKey
            self.clientKeyID = clientKeyID
            self.coordinator = coordinator
            self.checkpointProvider = checkpointProvider
            self.registryRoot = registryRoot
            self.transportStore = transportStore
            self.session = URLSession(
                configuration: .ephemeral,
                delegate: PinnedDelegate(spkiHex: spkiHex),
                delegateQueue: nil
            )
        }

        deinit {
            transportStore.deleteAll()
            try? FileManager.default.removeItem(at: registryRoot)
        }
    }

    /// Builds the full authorized host: registry lineage + host signing key
    /// + one paired ACTIVE client (interactive pairing through the real
    /// issue → PoP → operator-approval → single-commit flow) + a real
    /// Keychain-backed transport identity.
    static func makeHost() throws -> Host {
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-e2e-host-\(UUID().uuidString)", isDirectory: true)

        let store = LOCALBRegistryStore(rootURL: registryRoot)
        var checkpoint = try store.initializeNewLineage()
        let hostSigningKey = Curve25519.Signing.PrivateKey()
        let hostPublicKey = Array(hostSigningKey.publicKey.rawRepresentation)
        checkpoint = try store.appendKeyRegistration(
            publicKeyRaw: hostPublicKey, generation: 1, checkpoint: checkpoint)
        let srsKeyID = try LOCALBSigningInputV1.keyID(publicKeyRaw: hostPublicKey)
        let coordinator = LOCALBPairingCoordinator(registryStore: store)

        let presentation = try coordinator.issueCredential(
            scopeLabel: "product E2E client",
            tlsSPKIHash: hexSha256("localb-e2e-tls-spki"),
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
            submission, checkpoint: presentation.registryCheckpoint
        )
        let committed = try coordinator.approveAndRegister(
            pending,
            operatorApproved: true,
            operatorAuthorizationReference: "PRODUCT-E2E-FIXTURE",
            checkpoint: presentation.registryCheckpoint
        )
        let clientKeyID = try LOCALBSigningInputV1.keyID(
            publicKeyRaw: Array(clientKey.publicKey.rawRepresentation)
        )

        let transportStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-e2e.\(UUID().uuidString)",
            account: "tls"
        )
        let identity = try transportStore.loadOrCreate()

        var trustedCheckpoint = committed
        return Host(
            identity: identity,
            spkiHex: identity.spkiSHA256Hex,
            clientKey: clientKey,
            clientKeyID: clientKeyID,
            coordinator: coordinator,
            checkpointProvider: { trustedCheckpoint },
            registryRoot: registryRoot,
            transportStore: transportStore
        )
    }

    private static func hexSha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Fetches a one-time challenge (over the same pinned TLS session) for
    /// the intended (method, target), signs the EXACT request — method,
    /// authority, full target including query, content type, content
    /// encoding, raw body bytes — and returns the proof headers.
    static func proofHeaders(
        host: Host,
        port: Int,
        method: String,
        target: String,
        contentType: String?,
        body: Data
    ) async throws -> [String: String] {
        let authority = "127.0.0.1:\(port)"

        let challengeBody = try JSONSerialization.data(
            withJSONObject: ["method": method, "requestTarget": target]
        )
        var challengeRequest = URLRequest(
            url: URL(
                string: "https://127.0.0.1:\(port)/localb/auth/challenge"
            )!,
            timeoutInterval: 60
        )
        challengeRequest.httpMethod = "POST"
        challengeRequest.setValue(
            "application/json", forHTTPHeaderField: "Content-Type")
        challengeRequest.setValue(
            host.clientKeyID,
            forHTTPHeaderField: "X-SimiGo-LocalB-Client-Key-ID")
        challengeRequest.httpBody = challengeBody

        let (challengeData, challengeResponse) = try await host.session
            .data(for: challengeRequest)
        let challengeHTTP = try XCTUnwrap(
            challengeResponse as? HTTPURLResponse
        )
        guard challengeHTTP.statusCode == 200 else {
            throw NSError(
                domain: "LOCALBAuthorizedE2E", code: challengeHTTP.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "challenge request failed: \(challengeHTTP.statusCode) "
                        + String(decoding: challengeData, as: UTF8.self)
                ])
        }
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: challengeData)
                as? [String: Any]
        )
        let challengeHex = try XCTUnwrap(json["challenge"] as? String)
        let permissionRaw = try XCTUnwrap(json["permission"] as? String)
        let permission = try XCTUnwrap(
            LOCALBPermission(rawValue: permissionRaw)
        )
        let challenge = try XCTUnwrap(HTTPServer.decodeLowerHex(challengeHex))

        let signed = try LOCALBHTTPRequestV1(
            method: method,
            authority: authority,
            requestTarget: target,
            contentType: contentType,
            bodyRaw: Array(body)
        )
        let proof = try LOCALBClientRequestProofV2.sign(
            clientKeyID: host.clientKeyID,
            permission: permission,
            request: signed,
            challenge: challenge,
            with: host.clientKey
        )
        return [
            "X-SimiGo-LocalB-Client-Key-ID": host.clientKeyID,
            "X-SimiGo-LocalB-Challenge":
                HTTPServer.encodeLowerHex(challenge),
            "X-SimiGo-LocalB-Proof-V2": Data(proof).base64EncodedString()
        ]
    }

    /// Sends one protected request with a fresh V2 proof over the pinned
    /// TLS session. The proof is computed over the exact bytes transmitted:
    /// same method, same target, same content type, same body.
    static func send(
        host: Host,
        port: Int,
        method: String,
        path: String,
        contentType: String? = nil,
        body: Data = Data()
    ) async throws -> (Data, HTTPURLResponse) {
        let headers = try await proofHeaders(
            host: host,
            port: port,
            method: method,
            target: path,
            contentType: contentType,
            body: body
        )
        var request = URLRequest(
            url: URL(string: "https://127.0.0.1:\(port)\(path)")!,
            timeoutInterval: 900
        )
        request.httpMethod = method
        if let contentType {
            request.setValue(
                contentType, forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        let (data, response) = try await host.session.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }
}
