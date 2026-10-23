import CryptoKit
import Foundation
import LOCALBCore
import Network
import XCTest

@testable import SimiGo

/// 需求② 端到端（本地可核验层）：外部服务端“采用”产物配置后，推理确实
/// 经由与生产相同的 RemoteOpenAIRuntime 派发路径转发到 provider。
///
/// 链路：applyExternalAdoption 产出的 (baseURL, model) 形状（已由
/// ExternalServerAdoptionTests 验证写入 Service）→ 与生产
/// internalStartCloud 相同的 RemoteOpenAIRuntime.startWithLOCALB 启动
/// → 真实 LOCALB 激活主机 + 签名 inference 请求 → HTTPServer 转发
/// → 本地 OpenAI 兼容桩 provider（记录上游请求行/头/体）。
///
/// 诚实边界：桩 provider 证明的是产品侧派发、路径映射、模型覆盖与鉴权
/// 注入，不是真实 ollama/LM Studio 进程本身（其安装/运行属外部资源门控）。
final class ExternalAdoptionInferenceE2ETests: XCTestCase {

    // MARK: - Fixture（复刻 LOCALBRequestAuthWiringTests 已验证的激活主机夹具）

    private struct Host {
        let port: UInt16
        let spkiHex: String
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
    }

    private struct BootstrapHostEnvironment {
        let hostDirectory: URL
        let keychain: LOCALBKeychainSignerStore
        let transport: LOCALBTransportIdentityStore
        let spkiHex: String
        let clientKey: Curve25519.Signing.PrivateKey
        let clientKeyID: String
    }

    private func randomPort() -> UInt16 {
        UInt16.random(in: 42000...58000)
    }

    private func makeBootstrapHostEnvironment() throws
        -> BootstrapHostEnvironment {
        let hostDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-adoption-e2e-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: hostDirectory)
        }

        let keychain = LOCALBKeychainSignerStore(
            service: "com.simigo.tests.localb-adoption.\(UUID().uuidString)",
            account: "signing-key-v1")
        let transport = LOCALBTransportIdentityStore(
            service: "com.simigo.tests.localb-adoption.\(UUID().uuidString)",
            account: "tls")
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
                domain: "ExternalAdoptionInferenceE2ETests", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "expected an operational host after activation"
                ])
        }

        let coordinator = context.pairingCoordinator()
        var checkpoint = try context.currentTrustedCheckpoint()
        let presentation = try coordinator.issueCredential(
            scopeLabel: "adoption-e2e client",
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
            operatorAuthorizationReference: "ADOPTION-E2E",
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

    /// 记录完整请求（请求行/头部/体）、返回固定 chat completion JSON 的
    /// loopback 桩 provider。
    private final class StubOpenAIServer: @unchecked Sendable {
        let listener: NWListener
        private let lock = NSLock()
        private var _requestLines: [String] = []
        private var _headerBlocks: [String] = []
        private var _bodies: [String] = []
        private(set) var port: UInt16 = 0

        var requestLines: [String] { lock.lock(); defer { lock.unlock() }; return _requestLines }
        var headerBlocks: [String] { lock.lock(); defer { lock.unlock() }; return _headerBlocks }
        var bodies: [String] { lock.lock(); defer { lock.unlock() }; return _bodies }

        static func start() throws -> StubOpenAIServer {
            let listener = try NWListener(using: .tcp)
            let stub = StubOpenAIServer(listener: listener)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: DispatchQueue.global())
                // URLSession 可能把头部与请求体拆进不同 TCP 段——累积到
                // 头部完整且收满 Content-Length 后才解析记录。
                let bufferLock = NSLock()
                var buffer = Data()
                func receiveMore() {
                    connection.receive(
                        minimumIncompleteLength: 1, maximumLength: 65_536
                    ) { data, _, isComplete, _ in
                        if let data { buffer.append(data) }
                        bufferLock.lock()
                        let textSoFar = String(data: buffer, encoding: .utf8) ?? ""
                        bufferLock.unlock()
                        guard let headerEnd =
                            textSoFar.range(of: "\r\n\r\n")
                        else {
                            if isComplete { connection.cancel() }
                            else { receiveMore() }
                            return
                        }
                        var expectedBodyLength = -1
                        for line in textSoFar
                            .components(separatedBy: "\r\n")
                            .dropFirst()
                        {
                            let parts = line.split(
                                separator: ":", maxSplits: 1)
                            guard parts.count == 2,
                                  parts[0].lowercased() == "content-length"
                            else { continue }
                            expectedBodyLength = Int(
                                parts[1].trimmingCharacters(
                                    in: .whitespaces)) ?? -1
                            break
                        }
                        let bodySoFar =
                            textSoFar.suffix(from: headerEnd.upperBound)
                        if expectedBodyLength < 0
                            || bodySoFar.utf8.count >= expectedBodyLength
                            || isComplete {
                            stub.record(from: textSoFar)
                            let responseBody = StubOpenAIServer.responseBody
                            let response =
                                "HTTP/1.1 200 OK\r\n"
                                + "Content-Type: application/json\r\n"
                                + "Content-Length: \(responseBody.utf8.count)\r\n"
                                + "Connection: close\r\n\r\n" + responseBody
                            connection.send(
                                content: Data(response.utf8),
                                completion: .contentProcessed { _ in
                                    connection.cancel()
                                }
                            )
                        } else {
                            receiveMore()
                        }
                    }
                }
                receiveMore()
            }
            listener.start(queue: DispatchQueue(label: "stub-openai-provider"))
            _ = ready.wait(timeout: .now() + 5)
            stub.port = listener.port?.rawValue ?? 0
            guard stub.port != 0 else {
                throw NSError(
                    domain: "ExternalAdoptionInferenceE2ETests", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "stub provider failed to bind"
                    ])
            }
            return stub
        }

        static let responseBody =
            "{\"id\":\"stub-1\",\"object\":\"chat.completion\","
            + "\"model\":\"stub\",\"choices\":[{"
            + "\"index\":0,\"message\":{\"role\":\"assistant\","
            + "\"content\":\"EXTERNAL_ADOPTION_STUB_REPLY\"},"
            + "\"finish_reason\":\"stop\"}]}"

        func record(from text: String) {
            guard let headerEnd = text.range(of: "\r\n\r\n") else { return }
            let lines = text.components(separatedBy: "\r\n")
            let body = String(text.suffix(from: headerEnd.upperBound))
            lock.lock()
            _requestLines.append(lines.first ?? "")
            _headerBlocks.append(
                String(text[text.startIndex..<headerEnd.lowerBound]))
            _bodies.append(body)
            lock.unlock()
        }

        func stop() { listener.cancel() }

        private init(listener: NWListener) { self.listener = listener }
    }

    private func sendRequest(
        port: UInt16,
        spkiHex: String?,
        request: String,
        timeout: TimeInterval = 15
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

    private func statusLine(of response: Data?) -> String? {
        response.flatMap { String(data: $0, encoding: .utf8) }?
            .components(separatedBy: "\r\n").first
    }

    private func jsonBody(of response: Data?) -> [String: Any]? {
        guard let text = response.flatMap({ String(data: $0, encoding: .utf8) }),
              let range = text.range(of: "\r\n\r\n")
        else { return nil }
        let body = String(text[range.upperBound...])
        return try? JSONSerialization.jsonObject(with: Data(body.utf8))
            as? [String: Any]
    }

    private func fetchChallenge(
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

    private func protectedRequest(
        _ host: Host,
        method: String,
        target: String,
        contentType: String?,
        body: String,
        challenge: [UInt8],
        permission: LOCALBPermission
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
        var request = "\(method) \(target) HTTP/1.1\r\n"
            + "Host: \(authority)\r\n"
        if let contentType {
            request += "Content-Type: \(contentType)\r\n"
        }
        request += "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "X-SimiGo-LocalB-Challenge: "
            + HTTPServer.encodeLowerHex(challenge) + "\r\n"
            + "X-SimiGo-LocalB-Proof-V2: "
            + Data(proof).base64EncodedString() + "\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        return request
    }

    // MARK: - Test

    func testAdoptedEndpointConfigDispatchesInferenceThroughProductionRuntime()
        async throws {
        let stub = try StubOpenAIServer.start()
        addTeardownBlock { stub.stop() }

        // 采用产物形状：ollama 风格 http 端点 + 默认模型（adoptedEndpoint
        // 的输出直接落到这里）。
        let adoptedBaseURL = "http://127.0.0.1:\(stub.port)/v1"
        let adoptedModel = "qwen2.5-coder:7b"
        let configuration = CloudBackendConfiguration(
            baseURLString: adoptedBaseURL, model: adoptedModel
        )
        try configuration.validated(apiKey: "stub-key")

        let environment = try makeBootstrapHostEnvironment()
        let runtime = RemoteOpenAIRuntime(
            configuration: configuration,
            apiKey: "stub-key"
        )
        let port = randomPort()
        try await runtime.startWithLOCALB(
            ModelInfo(path: "cloud", kind: .cloudOpenAI),
            port: Int(port),
            localbHostDirectory: environment.hostDirectory,
            keychainStore: environment.keychain,
            transportIdentityStore: environment.transport
        )
        addTeardownBlock { await runtime.stop() }

        let host = Host(
            port: port,
            spkiHex: environment.spkiHex,
            clientKey: environment.clientKey,
            clientKeyID: environment.clientKeyID
        )

        // 真实签名 inference 请求：客户端体使用别名 model，必须由采用配置覆盖。
        let (challenge, permission) = try fetchChallenge(
            host, method: "POST", target: "/v1/chat/completions"
        )
        XCTAssertEqual(permission, "P-INFERENCE")
        let body =
            "{\"model\":\"client-alias\","
            + "\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}"
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/chat/completions",
            contentType: "application/json",
            body: body,
            challenge: challenge,
            permission: .inference
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        let status = try XCTUnwrap(statusLine(of: response))
        XCTAssertTrue(status.contains(" 200 "), "got: \(status)")

        // ① provider 生成的内容确实回传到客户端（派发发生）。
        let text = response.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(
            text.contains("EXTERNAL_ADOPTION_STUB_REPLY"),
            "provider content must reach the client, got: \(text.prefix(400))"
        )

        // ② 上游收到 OpenAI 兼容路径 + 采用鉴权 + 模型覆盖。
        let upstreamLine = try XCTUnwrap(stub.requestLines.first)
        XCTAssertTrue(
            upstreamLine.hasPrefix("POST /v1/chat/completions"),
            "adopted /v1 base must map chat/completions under /v1, got: \(upstreamLine)"
        )
        let headers = try XCTUnwrap(stub.headerBlocks.first).lowercased()
        XCTAssertTrue(
            headers.contains("authorization: bearer stub-key"),
            "upstream auth injected from adopted configuration, got: \(headers.prefix(400))"
        )
        let upstreamBody = try XCTUnwrap(stub.bodies.first)
        XCTAssertTrue(
            upstreamBody.contains(adoptedModel)
                && !upstreamBody.contains("client-alias"),
            "model must be overridden by adopted config, got: \(upstreamBody.prefix(300))"
        )
    }
}
