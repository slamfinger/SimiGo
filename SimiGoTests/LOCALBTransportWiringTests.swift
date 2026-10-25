import Foundation
import LOCALBCore
import Network
import XCTest

@testable import SimiGo

/// LOCALB B1 transport wiring tests. These exercise the REAL transport path:
/// a real LOCALB transport identity from the Keychain, a real TLS listener
/// produced by HTTPServer.start(), real TLS clients with SPKI pinning, and
/// real HTTP responses. No mocks.
final class LOCALBTransportWiringTests: XCTestCase {
    private func randomPort() -> UInt16 {
        UInt16.random(in: 42000...58000)
    }

    private func makeServer(port: UInt16) -> HTTPServer {
        HTTPServer(
            port: Int(port),
            modelId: "localb-wiring-test",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "localb-wiring-test",
                    savedAt: Date(),
                    history: []
                )
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
    }

    private func makeTransportStore() -> LOCALBTransportIdentityStore {
        let store = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-wiring.\(UUID().uuidString)",
            account: "tls"
        )
        addTeardownBlock { store.deleteAll() }
        return store
    }

    /// Sends a raw "GET /health" over the given parameters and returns the
    /// full response bytes (nil on connection failure before any data).
    private func rawHTTPGet(
        port: UInt16,
        tlsOptions: NWProtocolTLS.Options?,
        timeout: TimeInterval
    ) -> Data? {
        let parameters: NWParameters
        if let tlsOptions {
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = NWParameters.tcp
        }
        let client = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: parameters
        )
        let done = expectation(description: "http get done")
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
        let queue = DispatchQueue.global()
        client.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let request = "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
                client.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                client.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                    data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        response = data
                        finish()
                    } else if isComplete || error != nil {
                        finish()
                    }
                }
            case .failed, .cancelled:
                finish()
            case .waiting:
                // A rejected TLS handshake surfaces as .waiting after the
                // verify block fails; the session is dead for our purposes.
                finish()
            default:
                break
            }
        }
        client.start(queue: queue)
        wait(for: [done], timeout: timeout)
        client.cancel()
        return response
    }

    /// Client TLS options pinning the given SPKI hex.
    private func pinnedClientOptions(spkiHex: String) -> NWProtocolTLS.Options {
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
                complete(hex == spkiHex)
            },
            DispatchQueue.global()
        )
        return options
    }

    func testTransportSecurityAttributesNeverGrantPlaintextPairingEligibility() {
        XCTAssertFalse(
            HTTPServer.ConnectionContext.TransportSecurity.plainHTTP
                .eligibleForLOCALBPairingBinding
        )
        XCTAssertFalse(
            HTTPServer.ConnectionContext.TransportSecurity.plaintextCompatibility()
                .eligibleForLOCALBPairingBinding
        )
        XCTAssertTrue(
            HTTPServer.ConnectionContext.TransportSecurity
                .tls(spkiSHA256Hex: String(repeating: "a", count: 64))
                .eligibleForLOCALBPairingBinding
        )
        XCTAssertEqual(
            HTTPServer.ConnectionContext.TransportSecurity.plainHTTP.protectionHeader,
            "unprotected-by-LOCALB"
        )
        XCTAssertEqual(
            HTTPServer.ConnectionContext.TransportSecurity
                .tls(spkiSHA256Hex: "").protectionHeader,
            "localb-tls"
        )
    }

    func testSecureModeWithoutIdentityFailsClosedInsteadOfPlaintext() throws {
        let port = randomPort()
        let server = makeServer(port: port)
        // NO identity configured and NO legacy opt-in: default secure mode
        // must REFUSE to start — plaintext is never a silent fallback.
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }
        // A second call must behave identically (no state left behind).
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }
    }

    func testLegacyPlaintextCompatModeServesMarkedResponses() throws {
        let port = randomPort()
        let server = makeServer(port: port)
        // EXPLICIT legacy opt-in: plaintext allowed, every response marked.
        server.configureLOCALBSecurityMode(.legacyPlaintextCompat)
        try server.start()
        defer { server.stop() }

        let response = rawHTTPGet(port: port, tlsOptions: nil, timeout: 15)
        let text = String(data: try XCTUnwrap(response), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("200"), "health must succeed, got: \(text.prefix(120))")
        XCTAssertTrue(
            text.contains("X-SimiGo-Protection: unprotected-by-LOCALB"),
            "legacy plaintext responses must be explicitly marked"
        )
    }

    func testTransportPolicyDecisionMatrix() throws {
        // Loopback DEFAULT is plaintext (owner ruling 2026-10-26: the local
        // 127.0.0.1:8000 API is the product's developer/tool surface).
        XCTAssertEqual(
            LOCALBTransportPolicy.decide(
                bindHost: "127.0.0.1", environment: [:]
            ).securityMode,
            .legacyPlaintextCompat
        )
        XCTAssertEqual(
            LOCALBTransportPolicy.decide(
                bindHost: "127.0.0.1",
                environment: ["SIMIGO_TRANSPORT": "legacy-http"]
            ).securityMode,
            .legacyPlaintextCompat
        )
        // LAN bind ignores the legacy opt-in entirely (secure mandatory).
        let lanDecision = LOCALBTransportPolicy.decide(
            bindHost: "0.0.0.0",
            environment: ["SIMIGO_TRANSPORT": "legacy-http"]
        )
        XCTAssertEqual(lanDecision.securityMode, .secure)
        // Loopback CAN force TLS explicitly.
        let secureLoopback = LOCALBTransportPolicy.decide(
            bindHost: "127.0.0.1", environment: ["SIMIGO_TRANSPORT": "secure"]
        )
        XCTAssertEqual(secureLoopback.securityMode, .secure)

        // SIMIGO_TRANSPORT=secure on loopback with a REAL verified identity → TLS.
        let store = makeTransportStore()
        let identity = try store.loadOrCreate()
        if case .tls(let loaded) = LOCALBTransportPolicy.decide(
            bindHost: "127.0.0.1",
            environment: ["SIMIGO_TRANSPORT": "secure"],
            identityStore: store
        ) {
            XCTAssertEqual(loaded.spkiSHA256Hex, identity.spkiSHA256Hex)
        } else {
            XCTFail("SIMIGO_TRANSPORT=secure with a valid identity must decide TLS")
        }
    }

    func testFailClosedPropagatesOriginalStatusThroughStart() throws {
        // Scenario 1: identity missing entirely → transportIdentityMissing.
        let emptyStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-wiring.\(UUID().uuidString)",
            account: "tls"
        )
        let missingServer = makeServer(port: randomPort())
        LOCALBTransportPolicy.apply(
            LOCALBTransportPolicy.decide(
                bindHost: "127.0.0.1", environment: [:], identityStore: emptyStore
            ),
            to: missingServer
        )
        XCTAssertThrowsError(try missingServer.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMissing)
        }

        // Scenario 2: index corrupt → transportIdentityCorrupt (NOT the
        // flattened .missing).
        let corruptStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-wiring.\(UUID().uuidString)",
            account: "tls"
        )
        _ = try corruptStore.loadOrCreate()
        let corruptIndex: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: corruptStore.service,
            kSecAttrAccount as String: corruptStore.account,
            kSecValueData as String: Data("not-a-valid-envelope".utf8)
        ]
        XCTAssertEqual(SecItemAdd(try corruptStore.scopedAdd(corruptIndex) as CFDictionary, nil),
                       errSecDuplicateItem)
        // Overwrite the existing index data with garbage.
        XCTAssertEqual(
            SecItemUpdate(
                try corruptStore.scopedQuery([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: corruptStore.service,
                    kSecAttrAccount as String: corruptStore.account
                ]) as CFDictionary,
                [kSecValueData as String: Data("garbage".utf8)] as CFDictionary
            ),
            errSecSuccess
        )
        let corruptServer = makeServer(port: randomPort())
        LOCALBTransportPolicy.apply(
            LOCALBTransportPolicy.decide(
                bindHost: "127.0.0.1", environment: [:], identityStore: corruptStore
            ),
            to: corruptServer
        )
        XCTAssertThrowsError(try corruptServer.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }
        corruptStore.deleteAll()

        // Scenario 3: identity mismatch (index points at a foreign key tag)
        // → transportIdentityMismatch.
        let mismatchStore = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-wiring.\(UUID().uuidString)",
            account: "tls"
        )
        _ = try mismatchStore.loadOrCreate()
        // Rewrite ONLY the envelope's key_tag to a squatter key's tag.
        let squatterTag = Data("squatter-\(UUID().uuidString)".utf8)
        let squatterAttrs: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: squatterTag,
            kSecAttrIsPermanent as String: true
        ]
        XCTAssertNotNil(SecKeyCreateRandomKey(
            try mismatchStore.scopedAdd(squatterAttrs) as CFDictionary, nil))
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: mismatchStore.service,
            kSecAttrAccount as String: mismatchStore.account,
            kSecReturnData as String: true
        ]
        var readResult: CFTypeRef?
        XCTAssertEqual(
            SecItemCopyMatching(try mismatchStore.scopedQuery(readQuery) as CFDictionary,
                                &readResult),
            errSecSuccess
        )
        let envelopeData = try XCTUnwrap(readResult as? Data)
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: envelopeData) as? [String: Any]
        )
        envelope["key_tag"] = squatterTag.base64EncodedString()
        let rewritten = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertEqual(
            SecItemUpdate(
                try mismatchStore.scopedQuery([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: mismatchStore.service,
                    kSecAttrAccount as String: mismatchStore.account
                ]) as CFDictionary,
                [kSecValueData as String: rewritten] as CFDictionary
            ),
            errSecSuccess
        )
        let mismatchServer = makeServer(port: randomPort())
        LOCALBTransportPolicy.apply(
            LOCALBTransportPolicy.decide(
                bindHost: "127.0.0.1", environment: [:], identityStore: mismatchStore
            ),
            to: mismatchServer
        )
        XCTAssertThrowsError(try mismatchServer.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityMismatch)
        }
        if let scopedSquatter = try? mismatchStore.scopedQuery([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: squatterTag
        ]) { SecItemDelete(scopedSquatter as CFDictionary) }
        mismatchStore.deleteAll()
    }

    func testLegacyModeRefusesLanBindAtListenerBoundary() throws {
        // Even a caller that BYPASSES LOCALBTransportPolicy and sets legacy
        // plaintext mode directly on a LAN bind is refused by start() itself
        // — the invariant lives at the actual listener boundary.
        let server = HTTPServer(
            port: Int(randomPort()),
            modelId: "localb-wiring-test",
            bindHost: "0.0.0.0",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "test/main",
                    modelId: "localb-wiring-test",
                    savedAt: Date(),
                    history: []
                )
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true }
        )
        server.configureLOCALBSecurityMode(.legacyPlaintextCompat)
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .plaintextNotAllowedOnLAN)
        }
        // Repeated attempts behave identically; nothing was started.
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .plaintextNotAllowedOnLAN)
        }
    }

    func testFailClosedDecisionNotBypassedByPreviouslyCachedIdentity() throws {
        // Regression (same-instance reuse): a server first configured with a
        // REAL verified identity, then re-applied a .failClosed decision
        // after the identity store became corrupt, must REFUSE to start with
        // the ORIGINAL corrupt status — the stale cached identity may never
        // satisfy the latest decision. Exercises the REAL start() path.
        let store = makeTransportStore()
        let identity = try store.loadOrCreate()

        // Corrupt the store AFTER the identity was verified.
        XCTAssertEqual(
            SecItemUpdate(
                try store.scopedQuery([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: store.service,
                    kSecAttrAccount as String: store.account
                ]) as CFDictionary,
                [kSecValueData as String: Data("corrupted".utf8)] as CFDictionary
            ),
            errSecSuccess
        )

        let server = makeServer(port: randomPort())
        // First round: valid identity configured (simulating earlier policy
        // application on this same instance).
        server.configureLOCALBTransport(identity: identity)
        // Second round: the policy now decides fail-closed on the SAME
        // server instance.
        LOCALBTransportPolicy.apply(
            .failClosed(.transportIdentityCorrupt),
            to: server
        )
        // start() must throw the ORIGINAL corrupt status — never start any
        // listener (neither TLS with the stale identity nor plaintext).
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? LOCALBStatus, .transportIdentityCorrupt)
        }

        // Recovery on the same instance: repairing the store and applying a
        // fresh valid decision clears the failure and starts TLS normally.
        store.deleteAll()
        let repaired = try store.loadOrCreate()
        LOCALBTransportPolicy.apply(
            LOCALBTransportPolicy.decide(
                bindHost: "127.0.0.1", environment: [:], identityStore: store
            ),
            to: server
        )
        XCTAssertNoThrow(try server.start())
        server.stop()
        _ = repaired
    }

    func testConfiguredTLSServerServesHealthWithPinnedSPKIAndProtectionHeader() throws {
        let store = makeTransportStore()
        let identity = try store.loadOrCreate()

        let port = randomPort()
        let server = makeServer(port: port)
        server.configureLOCALBTransport(identity: identity)
        try server.start()
        defer { server.stop() }

        let response = rawHTTPGet(
            port: port,
            tlsOptions: pinnedClientOptions(spkiHex: identity.spkiSHA256Hex),
            timeout: 15
        )
        let text = String(data: try XCTUnwrap(response), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("200"), "health over pinned TLS must succeed")
        XCTAssertTrue(
            text.contains("X-SimiGo-Protection: localb-tls"),
            "TLS responses must carry the localb-tls marking"
        )
    }

    func testWrongPinYieldsNoHTTPResponse() throws {
        let store = makeTransportStore()
        let identity = try store.loadOrCreate()

        let port = randomPort()
        let server = makeServer(port: port)
        server.configureLOCALBTransport(identity: identity)
        try server.start()
        defer { server.stop() }

        let wrongPin = String(repeating: "0", count: 64)
        let response = rawHTTPGet(
            port: port,
            tlsOptions: pinnedClientOptions(spkiHex: wrongPin),
            timeout: 10
        )
        XCTAssertNil(
            response,
            "a wrong pin must never yield any HTTP response bytes"
        )
    }

    func testExplicitPlaintextCompatibilityListenerServesMarkedResponses() throws {
        let store = makeTransportStore()
        let identity = try store.loadOrCreate()

        let port = randomPort()
        let compatPort = randomPort()
        let server = makeServer(port: port)
        server.configureLOCALBTransport(
            identity: identity,
            plaintextCompatibilityPort: Int(compatPort)
        )
        try server.start()
        defer { server.stop() }

        // Main port: TLS with localb-tls marking.
        let tlsResponse = rawHTTPGet(
            port: port,
            tlsOptions: pinnedClientOptions(spkiHex: identity.spkiSHA256Hex),
            timeout: 15
        )
        let tlsText = String(data: try XCTUnwrap(tlsResponse), encoding: .utf8) ?? ""
        XCTAssertTrue(tlsText.contains("X-SimiGo-Protection: localb-tls"))

        // Compatibility port: plaintext, explicitly marked unprotected.
        let plainResponse = rawHTTPGet(port: compatPort, tlsOptions: nil, timeout: 15)
        let plainText = String(data: try XCTUnwrap(plainResponse), encoding: .utf8) ?? ""
        XCTAssertTrue(plainText.contains("200"))
        XCTAssertTrue(
            plainText.contains("X-SimiGo-Protection: unprotected-by-LOCALB"),
            "compatibility plaintext must be explicitly marked"
        )
    }
}
