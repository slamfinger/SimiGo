import Foundation
import CryptoKit
import LOCALBCore
import SimiGoRuntimeContract
import Network

/// SimiGo 本机 / 局域网共享 OpenAI-compatible HTTP Server
///
/// 设计边界：
/// - 负责 HTTP/TCP、OpenAI JSON、SSE、连接生命周期、Responses 状态链与请求取消。
/// - 不负责 generation queue / KV cache / prefix cache / tool execution。
/// - NativeMLX.generate(...) 是唯一推理入口。
/// - 同一 Session 的并发一致性由 NativeMLX.SessionGenerationGate 负责。
///
/// Session / KV 分层原则：
///
/// 1. HTTPServer 只负责确定“这个请求属于哪个逻辑 Session”。
/// 2. HTTPServer 不根据 messages 猜测 Session。
/// 3. HTTPServer 不为了 KV reuse 主动压缩不同请求的 SessionId。
/// 4. Physical KV 是否复用，由 NativeMLX / KV Runtime 根据真实 token prefix、
///    tool fingerprint、runtime lineage 等条件决定。
///
/// OpenAI Chat / Completions：
///
///     explicit session
///             ↓
///     preserve client identity
///             ↓
///     no explicit session
///             ↓
///     request-scoped session
///
/// 不再存在：
///
///     messages
///        ↓
///     deriveStableSessionId()
///        ↓
///     强行合并 Session
///
/// Responses：
///
/// previous_response_id
///         ↓
/// StoredResponse
///         ↓
/// parent.agentId / parent.sessionId / parent.logicalBranchId
///         ↓
/// canonicalMessages
///         ↓
/// NativeMLX.generate(...)
///         ↓
/// StoredResponse(newResponseId)
///
/// StoredResponse 只保存协议层逻辑历史，不保存 Physical KV。
/// Physical KV 是否复用由 NativeMLX 自己依据真实 token prefix /
/// tool fingerprint / runtime lineage 决定。
public final class HTTPServer: @unchecked Sendable {

    // MARK: - Public Types

    public typealias GenerateHandler = @Sendable (
        _ requestId: String,
        _ agentId: String?,
        _ sessionId: String,
        _ logicalBranchId: String,
        _ messages: [JSONValue],
        _ tools: [JSONValue]?,
        _ config: ModelConfig,
        _ onChunk: @escaping @Sendable (String) -> Void,
        _ onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> GenerationResult

    public typealias CheckHealthHandler = @Sendable () async -> Bool

    public typealias CancelGenerationHandler = @Sendable (_ requestId: String) -> Void

    public typealias ForkBranchHandler = @Sendable (
        _ agentId: String?,
        _ sessionId: String,
        _ sourceBranch: String,
        _ targetBranch: String
    ) async throws -> SessionCacheMetadata

    public typealias DeleteBranchHandler = @Sendable (
        _ agentId: String?,
        _ sessionId: String,
        _ logicalBranchId: String
    ) async throws -> Void

    public typealias ListBranchesHandler = @Sendable (
        _ agentId: String?,
        _ sessionId: String
    ) -> (live: [String], checkpoints: [String])

    // MARK: - Limits

    private static let maxHeaderBytes = 64 * 1024
    private static let maxHeaderLineBytes = 8 * 1024
    private static let maxHeaderCount = 128
    private static let maxBodyBytes = 16 * 1024 * 1024
    private static let receiveChunkSize = 32 * 1024

    // MARK: - HTTP Errors

    enum HTTPServerError: Error {
        case badRequest(String)
        case payloadTooLarge
        case unsupportedTransferEncoding(String)
        case expectationFailed
        case clientDisconnected
        case localbTransportNotTrusted
        case localbAuthorizationUnavailable
        case localbRequestRejected(reason: String)
        case localbRouteDenied(reason: String)

        var statusCode: Int {
            switch self {
            case .badRequest, .clientDisconnected:
                return 400
            case .payloadTooLarge:
                return 413
            case .unsupportedTransferEncoding:
                return 501
            case .expectationFailed:
                return 417
            case .localbTransportNotTrusted:
                return 403
            case .localbAuthorizationUnavailable:
                return 503
            case .localbRequestRejected:
                return 401
            case .localbRouteDenied:
                return 403
            }
        }

        var message: String {
            switch self {
            case .badRequest(let message):
                return message
            case .payloadTooLarge:
                return "Request body too large"
            case .unsupportedTransferEncoding(let value):
                return "Unsupported Transfer-Encoding: \(value)"
            case .expectationFailed:
                return "Unsupported Expect header"
            case .clientDisconnected:
                return "Client disconnected before the request was complete"
            case .localbTransportNotTrusted:
                return "Protected requests require a LOCALB TLS connection"
            case .localbAuthorizationUnavailable:
                return "LOCALB request authorization is not configured"
            case .localbRequestRejected(let reason):
                return reason
            case .localbRouteDenied(let reason):
                return reason
            }
        }
    }

    // MARK: - Connection Context

    nonisolated final class ConnectionContext: @unchecked Sendable {
        let connection: NWConnection
        let key: ObjectIdentifier
        let requestId: String
        let sendQueue: DispatchQueue

        /// Server-side transport security attributes (LOCALB B1).
        /// Populated EXCLUSIVIVELY by accept() from the accepting listener's
        /// own trusted configuration state — never from request headers,
        /// JSON, or any client-supplied value. Plaintext connections can
        /// never masquerade as TLS and never qualify for LOCALB pairing
        /// binding.
        struct TransportSecurity: Sendable {
            let isTLS: Bool
            /// SPKI fingerprint of the TLS listener identity (nil on plaintext).
            let listenerSPKIHashHex: String?
            /// True only on the explicitly-enabled plaintext-compatibility
            /// listener (B1 condition 4); such connections are marked
            /// "unprotected-by-LOCALB" and never gain pairing eligibility.
            let isExplicitPlaintextCompatibility: Bool

            static let plainHTTP = TransportSecurity(
                isTLS: false,
                listenerSPKIHashHex: nil,
                isExplicitPlaintextCompatibility: false
            )

            static func tls(spkiSHA256Hex: String) -> TransportSecurity {
                TransportSecurity(
                    isTLS: true,
                    listenerSPKIHashHex: spkiSHA256Hex,
                    isExplicitPlaintextCompatibility: false
                )
            }

            static func plaintextCompatibility() -> TransportSecurity {
                TransportSecurity(
                    isTLS: false,
                    listenerSPKIHashHex: nil,
                    isExplicitPlaintextCompatibility: true
                )
            }

            /// Value of the X-SimiGo-Protection response header.
            var protectionHeader: String {
                isTLS ? "localb-tls" : "unprotected-by-LOCALB"
            }

            /// Whether this connection may participate in LOCALB TLS pairing
            /// binding. Plaintext NEVER qualifies, under any configuration.
            var eligibleForLOCALBPairingBinding: Bool { isTLS }
        }

        let transportSecurity: TransportSecurity

        private let stateLock = NSLock()

        private var _requestTask: Task<Void, Never>?
        private var _clientRequestId: String?
        private var _agentId: String?
        private var _sessionId: String?
        private var _logicalBranchId: String?

        private var _generationStarted = false
        private var _cancellationSignalled = false
        private var _closed = false
        private var _cancelledByRuntime = false

        /// Slice 8: this request's continuation admission result. Set by the
        /// pre-generation gate, read by the post-generation settlement of the
        /// SAME request — never looked up again from mutable ES state.
        private var _continuationBinding: ContinuationRequestBinding?

        /// 生成期对端关闭监听（2026-10-15 孤儿推理收口）。
        /// NWConnection 对客户端优雅关闭（FIN）不产生 state 变化，只在
        /// receive 侧以 EOF 浮出；此前检测全靠出站 send 错误（流式）或
        /// 心跳，非流式路径在整段生成期间零出站字节——客户端关掉后推理
        /// 会空转到自然结束。生成期挂一条 1 字节 receive：EOF/错误即
        /// terminate → cancelGeneration；由 accept() 注入回调。
        private var _peerCloseWatcherArmed = false
        var onPeerClosed: (@Sendable () -> Void)?

        /// 出站真实数据（headers / chunk / 事件）最后一次发送的时刻。
        /// SSE 心跳据此判断当前是否处于静默窗口。
        private let outboundActivity = Locked(Date())

        init(
            connection: NWConnection,
            transportSecurity: TransportSecurity = .plainHTTP
        ) {
            self.connection = connection
            self.key = ObjectIdentifier(connection)
            self.transportSecurity = transportSecurity
            // 短字节串 ID（8 hex）：仅作取消映射字典键 / X-Request-Id / trace
            // 展示，本机单用户量级下碰撞可忽略，紧凑 trace 不再拖全量 UUID。
            self.requestId =
                "req-\(UUID().uuidString.prefix(8).lowercased())"
            self.sendQueue = DispatchQueue(
                label: "com.simigo.httpserver.send.\(UUID().uuidString)",
                qos: .userInitiated
            )
        }

        var closed: Bool {
            stateLock.withLock {
                _closed
            }
        }

        var agentId: String? {
            stateLock.withLock {
                _agentId
            }
        }

        var sessionId: String? {
            stateLock.withLock {
                _sessionId
            }
        }

        var logicalBranchId: String? {
            stateLock.withLock {
                _logicalBranchId
            }
        }

        var clientRequestId: String? {
            stateLock.withLock {
                _clientRequestId
            }
        }

        func setIdentity(
            agentId: String?,
            sessionId: String?,
            logicalBranchId: String? = nil,
            clientRequestId: String? = nil
        ) {
            stateLock.withLock {
                _agentId = agentId
                _sessionId = sessionId
                _logicalBranchId = logicalBranchId
                _clientRequestId = clientRequestId
            }
        }

        var continuationBinding: ContinuationRequestBinding? {
            stateLock.withLock {
                _continuationBinding
            }
        }

        func setContinuationBinding(_ binding: ContinuationRequestBinding?) {
            stateLock.withLock {
                _continuationBinding = binding
            }
        }

        @discardableResult
        func markGenerationStarted() -> Bool {
            // started=原语义（closed 时 false，调用方据此放弃）；
            // armWatcher 独立——重复 start（容错路径）只挂一条监听。
            let outcome: (started: Bool, armWatcher: Bool) =
                stateLock.withLock {
                    guard !_closed else {
                        return (false, false)
                    }

                    _generationStarted = true

                    if _peerCloseWatcherArmed {
                        return (true, false)
                    }

                    _peerCloseWatcherArmed = true
                    return (true, true)
                }

            // receive 注册不能在 stateLock 内做（回调可能立即入队重入）。
            if outcome.armWatcher {
                armPeerCloseWatch()
            }

            return outcome.started
        }

        func markGenerationFinished() {
            stateLock.withLock {
                _generationStarted = false
                _peerCloseWatcherArmed = false
            }
        }

        /// 挂起 1 字节 receive 直到本连接生成结束。任何非空入站数据
        /// （客户端提前管道化）不视为断连，续听；EOF / 错误才触发回调。
        /// 自身 cancel（正常收尾）产生的 ECANCELED 由 active 判定拦下。
        private func armPeerCloseWatch() {
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: 1
            ) { [weak self] data, _, isComplete, error in

                guard let self else {
                    return
                }

                let clientGone =
                    error != nil
                    || (isComplete && (data?.isEmpty ?? true))

                let active: Bool = stateLock.withLock {
                    guard
                        self._generationStarted,
                        !self._closed,
                        self._peerCloseWatcherArmed
                    else {
                        return false
                    }

                    if clientGone {
                        self._peerCloseWatcherArmed = false
                    }

                    return true
                }

                guard active else {
                    return
                }

                if clientGone {
                    onPeerClosed?()
                } else {
                    armPeerCloseWatch()
                }
            }
        }

        func registerLifecycle() async {
            await RuntimeLifecycleCoordinator.shared.register(
                requestID: requestId,
                agentID: agentId,
                sessionID: sessionId
            )
        }

        func transitionToQueued() async throws {
            try await RuntimeLifecycleCoordinator.shared.transition(requestID: requestId, to: .queued)
        }

        /// 统一终止入口：defer 中无法 await，以独立 Task 汇入协调器（幂等）。
        /// 失败路径必须给出 P0-1 分类 reason；未显式分类时按连接状态回落。
        func finishLifecycle(success: Bool, failureReason: String? = nil) {
            Task {
                let reason = success
                    ? "completed"
                    : (failureReason ?? cancellationFailureReason())
                await RuntimeLifecycleCoordinator.shared.finish(
                    requestID: requestId,
                    success: success,
                    reason: reason
                )
            }
        }

        /// P0-1 失败分类：runtime shutdown > 客户端断连 > 引擎内部取消。
        func cancellationFailureReason() -> String {
            stateLock.withLock {
                if _cancelledByRuntime { return "cancelled_by_runtime" }
                if _closed { return "cancelled_by_client" }
                return "cancelled_internally"
            }
        }

        /// Runtime shutdown / 配置重载时标记：取消责任在 Runtime 而非客户端。
        func markCancelledByRuntime() {
            stateLock.withLock {
                _cancelledByRuntime = true
            }
        }

        @discardableResult
        func setRequestTask(_ task: Task<Void, Never>) -> Bool {
            stateLock.withLock {
                guard !_closed else {
                    return false
                }

                _requestTask = task
                return true
            }
        }

        func closeAndTakeRequestTask(
            cancelGeneration: Bool
        ) -> (
            shouldCancelGeneration: Bool,
            requestTask: Task<Void, Never>?
        ) {
            stateLock.withLock {
                let shouldCancel =
                    cancelGeneration &&
                    _generationStarted &&
                    !_cancellationSignalled

                if shouldCancel {
                    _cancellationSignalled = true
                }

                _closed = true
                _peerCloseWatcherArmed = false

                let task = _requestTask
                _requestTask = nil

                return (
                    shouldCancel,
                    task
                )
            }
        }

        @discardableResult
        func markClosed() -> Bool {
            stateLock.withLock {
                let wasOpen = !_closed

                _closed = true
                _peerCloseWatcherArmed = false
                _requestTask = nil

                return wasOpen
            }
        }

        func canSend() -> Bool {
            stateLock.withLock {
                !_closed
            }
        }

        func touchOutboundActivity() {
            outboundActivity.set(Date())
        }

        var secondsSinceOutboundActivity: TimeInterval {
            Date().timeIntervalSince(outboundActivity.value)
        }
    }

    // MARK: - HTTP Request

    /// Internal (not file-private) so handler extensions in this module can
    /// share the single parsed-request type without re-parsing targets.
    struct HTTPRequest {
        let method: String

        /// Route path derived exactly once at parse time from the validated
        /// request target (query removed). Routing and dispatch consume this
        /// single derivation; nothing re-splits the target later.
        let path: String

        /// Exact origin-form request target as received, including the query
        /// string. This verbatim view is what a LOCALB request proof signs;
        /// `path` is only a derived route view of it.
        let requestTarget: String

        /// Authority from the single accepted Host header (empty only for
        /// HTTP/1.0 requests without Host).
        let authority: String

        let headers: [String: String]
        let body: Data
    }

    // MARK: - Server State

    private let port: NWEndpoint.Port
    let modelId: String
    private let bindHost: String
    private let bonjourEnabled: Bool

    let generateHandler: GenerateHandler
    let forkBranchHandler: ForkBranchHandler
    let continuationAdmission: ContinuationAdmissionHandler?
    /// Post-generation settlement authority for the opt-in continuation
    /// contract. Absent (nil) means any request that explicitly asks to
    /// settle is refused fail-closed BEFORE generation.
    let continuationSettlement: ContinuationSettlementHandler?
    /// Zero-call settlement consumption authority for the typed
    /// `settlement_consumption` opt-in. Absent (nil) means such a request is
    /// refused fail-closed BEFORE any generation.
    let settlementConsumption: SettlementConsumptionHandler?
    /// Managed-continuation authority (`previous_es_state_id` +
    /// `recompute_policy`). Absent (nil) means such a request is refused
    /// fail-closed; the legacy continuation path is unaffected.
    let managedContinuation: ManagedContinuationHandler?
    /// Producer identity for information-turn settlements. Absent only when the
    /// runtime has no resolved model snapshot (headless/library callers).
    let informationTurnProducer: InformationTurnProducerProvider?
    private let deleteBranchHandler: DeleteBranchHandler
    private let listBranchesHandler: ListBranchesHandler
    private let checkHealthHandler: CheckHealthHandler
    private let cancelGenerationHandler: CancelGenerationHandler?
    private let capabilitiesProvider: (() -> ModelCapabilityContract?)?
    let remoteBackend: RemoteOpenAIBackend?
    /// UI 模型设置兜底：请求未显式指定的字段（采样/maxTokens/thinking/kvCache）
    /// 落到 UI 值而非 ModelConfig 硬编码默认——模型页参数此前对协议请求不生效。
    private let baseConfigProvider: () -> ModelConfig

    private let queue = DispatchQueue(
        label: "com.simigo.httpserver.connections",
        qos: .userInitiated
    )

    private var listener: NWListener?

    private var connections: [ObjectIdentifier: ConnectionContext] = [:]
    private let connectionLock = NSLock()

    let responsesStore = ResponsesStateStore()

    // MARK: - LOCALB transport security mode

    /// B1 security-mode matrix (authoritative behavior of start()):
    ///
    /// | mode                        | identity | behavior                          |
    /// |-----------------------------|----------|-----------------------------------|
    /// | secure (default)            | valid    | TLS listener on the main port     |
    /// | secure (default)            | missing  | start() THROWS — never plaintext  |
    /// | legacyPlaintextCompat       | any      | plaintext main port, every        |
    /// | (explicit operator opt-in)  |          | response marked                   |
    /// |                             |          | "unprotected-by-LOCALB"           |
    /// | secure + compat port config | valid    | TLS main port + separate explicit |
    /// |                             |          | plaintext compatibility port      |
    public enum LOCALBSecurityMode: Sendable {
        case secure
        case legacyPlaintextCompat
    }

    private var localbSecurityMode: LOCALBSecurityMode = .secure
    private var localbTransportIdentity: LOCALBTransportIdentityHandle?
    private var localbPlaintextCompatibilityPort: NWEndpoint.Port?
    private var plaintextCompatListener: NWListener?
    /// Original typed LOCALBStatus behind a fail-closed transport decision
    /// (identity corrupt / index corrupt / mismatch / …), recorded by the
    /// transport policy so start() propagates the ORIGINAL failure instead
    /// of flattening every cause into transportIdentityMissing. A recorded
    /// failure takes PRIORITY over any previously-configured identity: a
    /// re-applied policy decision on a reused server instance must never be
    /// bypassed by a stale cached identity. Operators must be able to
    /// distinguish "missing" from "corrupt" at startup.
    private var localbTransportDecisionFailure: LOCALBStatus?

    /// Called by LOCALBTransportPolicy.apply for .failClosed decisions.
    /// Recording a failure ALSO clears any previously-configured identity —
    /// the latest decision owns the server state.
    public func recordLOCALBTransportFailure(_ status: LOCALBStatus) {
        localbTransportDecisionFailure = status
        localbTransportIdentity = nil
        localbPlaintextCompatibilityPort = nil
    }

    /// Explicit operator opt-in for the legacy plaintext listener. Without
    /// this call the server is in .secure mode: a missing or unusable LOCALB
    /// transport identity makes start() fail closed — plaintext is NEVER a
    /// silent fallback.
    public func configureLOCALBSecurityMode(_ mode: LOCALBSecurityMode) {
        localbSecurityMode = mode
    }

    /// Explicit operator action: enable the LOCALB TLS listener with a fully
    /// verified transport identity (see LOCALBTransportIdentityStore —
    /// certificate/private-key/SecIdentity chain already validated). Call
    /// before start(). Optionally keep a legacy plaintext listener on a
    /// SEPARATE port (explicit compatibility).
    public func configureLOCALBTransport(
        identity: LOCALBTransportIdentityHandle,
        plaintextCompatibilityPort: Int? = nil
    ) {
        // Configuring a NEW verified identity clears any stale fail-closed
        // decision from a previous policy round on this instance — success
        // and failure states never coexist.
        localbTransportDecisionFailure = nil
        localbTransportIdentity = identity
        localbPlaintextCompatibilityPort =
            plaintextCompatibilityPort.flatMap {
                NWEndpoint.Port(rawValue: UInt16($0))
            }
    }

    /// LOCALB B3 request-content authorization state. The coordinator is
    /// backed by the LOCALB registry; the trusted-checkpoint provider is
    /// supplied by the host (management plane). When nil, every protected
    /// route fails closed with 503.
    private var localbRequestAuthorization:
        (coordinator: LOCALBPairingCoordinator,
         trustedCheckpoint: () throws -> LOCALBRegistryCheckpoint)?

    /// Explicit operator action: enable LOCALB V2 request-content
    /// authorization for protected routes. Permissions are ALWAYS derived
    /// server-side from the canonical method and route path through
    /// localbRoutePolicy(forMethod:routePath:) — the same table is used
    /// for challenge issuance and for request authorization.
    public func configureLOCALBRequestAuthorization(
        coordinator: LOCALBPairingCoordinator,
        trustedCheckpoint: @escaping () throws -> LOCALBRegistryCheckpoint
    ) {
        localbRequestAuthorization = (coordinator, trustedCheckpoint)
    }

    // MARK: - Init

    public init(
        port: Int,
        modelId: String,
        bindHost: String = "127.0.0.1",
        bonjourEnabled: Bool = true,
        generateHandler: @escaping GenerateHandler,
        forkBranchHandler: @escaping ForkBranchHandler,
        deleteBranchHandler: @escaping DeleteBranchHandler,
        listBranchesHandler: @escaping ListBranchesHandler,
        checkHealthHandler: @escaping CheckHealthHandler,
        cancelGenerationHandler: CancelGenerationHandler? = nil,
        capabilitiesProvider: (() -> ModelCapabilityContract?)? = nil,
        remoteBackend: RemoteOpenAIBackend? = nil,
        baseConfigProvider: @escaping () -> ModelConfig = { ModelConfig() },
        continuationAdmission: ContinuationAdmissionHandler? = nil,
        continuationSettlement: ContinuationSettlementHandler? = nil,
        settlementConsumption: SettlementConsumptionHandler? = nil,
        managedContinuation: ManagedContinuationHandler? = nil,
        informationTurnProducer: InformationTurnProducerProvider? = nil
    ) {
        guard let endpointPort = NWEndpoint.Port(
            rawValue: UInt16(port)
        ) else {
            fatalError("Invalid HTTP server port: \(port)")
        }

        self.port = endpointPort
        self.modelId = modelId

        let normalizedHost =
            bindHost.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        self.bindHost =
            normalizedHost.isEmpty
            ? "127.0.0.1"
            : normalizedHost

        self.bonjourEnabled = bonjourEnabled
        self.generateHandler = generateHandler
        self.forkBranchHandler = forkBranchHandler
        self.deleteBranchHandler = deleteBranchHandler
        self.listBranchesHandler = listBranchesHandler
        self.checkHealthHandler = checkHealthHandler
        self.cancelGenerationHandler = cancelGenerationHandler
        self.capabilitiesProvider = capabilitiesProvider
        self.remoteBackend = remoteBackend
        self.baseConfigProvider = baseConfigProvider
        self.continuationAdmission = continuationAdmission
        self.continuationSettlement = continuationSettlement
        self.settlementConsumption = settlementConsumption
        self.managedContinuation = managedContinuation
        self.informationTurnProducer = informationTurnProducer
    }

    // MARK: - Lifecycle

    public func start() throws {
        guard listener == nil else {
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true

        // B1 security-mode matrix (see LOCALBSecurityMode). In .secure mode
        // (the default) a missing or unusable transport identity makes
        // start() fail closed — plaintext is NEVER a silent fallback — and
        // the ORIGINAL typed failure (corrupt index, key mismatch, …)
        // recorded by the transport policy is propagated, not flattened.
        // Plaintext on the main port exists only under the explicit
        // .legacyPlaintextCompat opt-in, is REFUSED on non-loopback binds
        // at this listener boundary (not only in the policy helper), and
        // marks every response "unprotected-by-LOCALB".
        let normalizedHost =
            bindHost
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        let isLoopback =
            normalizedHost == "127.0.0.1" ||
            normalizedHost == "localhost" ||
            normalizedHost == "::1"

        var bonjourServiceType = "_http._tcp"
        let parameters: NWParameters
        let acceptSecurity: ConnectionContext.TransportSecurity
        switch localbSecurityMode {
        case .secure:
            // A recorded fail-closed decision takes PRIORITY over any
            // configured identity — even if an identity was configured on
            // this instance earlier, the latest policy decision owns the
            // state and start() must fail with the ORIGINAL typed status.
            if let failure = localbTransportDecisionFailure {
                throw failure
            }
            guard let identity = localbTransportIdentity else {
                throw LOCALBStatus.transportIdentityMissing
            }
            let tlsOptions = NWProtocolTLS.Options()
            guard let secIdentity = sec_identity_create(identity.secIdentity) else {
                throw LOCALBStatus.transportIdentityMismatch
            }
            sec_protocol_options_set_local_identity(
                tlsOptions.securityProtocolOptions,
                secIdentity
            )
            parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
            bonjourServiceType = "_simigo._tcp"
            acceptSecurity = .tls(spkiSHA256Hex: identity.spkiSHA256Hex)
        case .legacyPlaintextCompat:
            // Listener-boundary invariant: the legacy plaintext mode is
            // loopback-only. A direct caller that bypasses
            // LOCALBTransportPolicy and sets legacy mode on a LAN bind is
            // refused HERE, at the actual listener startup point.
            guard isLoopback else {
                throw LOCALBStatus.plaintextNotAllowedOnLAN
            }
            parameters = NWParameters(tls: nil, tcp: tcpOptions)
            acceptSecurity = .plainHTTP
        }

        parameters.allowLocalEndpointReuse = true

        if isLoopback {
            parameters.requiredInterfaceType = .loopback
        }

        let newListener = try NWListener(
            using: parameters,
            on: port
        )

        if !isLoopback && bonjourEnabled {
            newListener.service = NWListener.Service(
                name: "SimiGo",
                type: bonjourServiceType,
                domain: nil,
                txtRecord: nil
            )
        }

        newListener.newConnectionHandler = {
            [weak self] connection in
            self?.accept(connection, transportSecurity: acceptSecurity)
        }

        newListener.stateUpdateHandler = {
            [weak self] state in

            guard let self else {
                return
            }

            switch state {
            case .ready:
                print(
                    "✅ [HTTPServer] 监听 " +
                    "\(self.bindHost):\(self.port.rawValue) " +
                    "model=\(self.modelId)"
                )

            case .failed(let error):
                print(
                    "❌ [HTTPServer] listener failed: " +
                    "\(error.localizedDescription)"
                )

            case .cancelled:
                print("🛑 [HTTPServer] listener stopped")

            default:
                break
            }
        }

        newListener.start(queue: queue)
        listener = newListener

        // Explicitly-enabled legacy plaintext compatibility listener (B1
        // condition 4). It exists ONLY when the operator explicitly named a
        // separate port while in secure mode with a valid identity; every
        // response it serves carries the "unprotected-by-LOCALB" marking,
        // and its connections never gain LOCALB pairing eligibility. It can
        // never substitute for the TLS listener. Invariant: the compat
        // listener is loopback-ONLY regardless of the main bind — a LAN
        // main bind can never expose plaintext through this side port.
        if let compatPort = localbPlaintextCompatibilityPort,
           localbSecurityMode == .secure,
           localbTransportIdentity != nil {
            let compatTCP = NWProtocolTCP.Options()
            compatTCP.noDelay = true
            let compatParameters = NWParameters(tls: nil, tcp: compatTCP)
            compatParameters.allowLocalEndpointReuse = true
            compatParameters.requiredInterfaceType = .loopback
            if let compatListener = try? NWListener(
                using: compatParameters,
                on: compatPort
            ) {
                compatListener.newConnectionHandler = {
                    [weak self] connection in
                    self?.accept(
                        connection,
                        transportSecurity: .plaintextCompatibility()
                    )
                }
                compatListener.start(queue: queue)
                plaintextCompatListener = compatListener
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        plaintextCompatListener?.cancel()
        plaintextCompatListener = nil

        let contexts: [ConnectionContext] = connectionLock.withLock {
            let values = Array(connections.values)
            connections.removeAll()
            return values
        }

        for context in contexts {
            context.markCancelledByRuntime()
            terminate(
                context,
                cancelGeneration: true
            )
        }

        responsesStore.clear()
    }

    // MARK: - Connection Lifecycle

    private func accept(
        _ connection: NWConnection,
        transportSecurity: ConnectionContext.TransportSecurity = .plainHTTP
    ) {
        let context = ConnectionContext(
            connection: connection,
            transportSecurity: transportSecurity
        )

        connectionLock.withLock {
            connections[context.key] = context
        }

        connection.stateUpdateHandler = {
            [weak self, weak context] state in

            guard let self, let context else {
                return
            }

            switch state {
            case .failed, .cancelled:
                self.terminate(
                    context,
                    cancelGeneration: true
                )

            default:
                break
            }
        }

        // 生成期对端关闭监听回调（EOF 路径与 state 失败路径共用 terminate）。
        // r= 展示 6 位短 ID，与 [LC] 行可直连（2026-09-19 展示惯例）。
        // 回调自 receive completion（@Sendable、连接队列）进入：
        // terminate 是 MainActor 隔离，经 Task 跳演员执行，此时无锁持有。
        context.onPeerClosed = { [weak self, weak context] in
            guard let context else {
                return
            }

            RuntimeTraceLogger.shared.trace(
                "[PROTOCOL] peerClosed r=\(String(context.requestId.dropFirst(4).prefix(6)))"
            )

            Task { @MainActor [weak self, weak context] in
                guard let self, let context else {
                    return
                }

                self.terminate(
                    context,
                    cancelGeneration: true
                )
            }
        }

        // V1.6.1（事件 B 修复，2026-09-19）：每连接独立串行队列——
        // 原实现全部连接共享一条串行队列，单个连接回调卡死（os_state
        // dispatch_sync 等主事件，事件 B 3/3 复现）即冻结全部连接 I/O
        // 与监听回调 → 服务全局无响应。隔离后卡死仅影响该连接自身，
        // 其余连接与监听不受牵连。
        connection.start(queue: DispatchQueue(
            label: "com.simigo.httpserver.conn.\(context.key)"))

        let task = Task {
            [weak self, weak context] in

            guard let self, let context else {
                return
            }

            do {
                guard !context.closed else {
                    return
                }

                let request =
                    try await self.readRequest(
                        from: connection
                    )

                guard !context.closed else {
                    return
                }

                try await self.route(
                    request,
                    context: context
                )

            } catch is CancellationError {
                // terminate() owns cancellation.

            } catch {
                guard !context.closed else {
                    return
                }

                let serverError =
                    error as? HTTPServerError

                let status =
                    serverError?.statusCode ?? 400

                let message =
                    serverError?.message ??
                    error.localizedDescription

                self.sendError(
                    message,
                    status: status,
                    on: connection,
                    context: context
                )
            }
        }

        if !context.setRequestTask(task) {
            task.cancel()
        }
    }

    func finish(_ context: ConnectionContext) {
        context.markClosed()

        connectionLock.withLock {
            guard connections[context.key] === context else {
                return
            }

            connections.removeValue(
                forKey: context.key
            )
        }
    }

    // terminate 为模块默认 MainActor 隔离（勿显式标注：隐性隔离下既有
    // 连接队列调用点无警告，显式化会翻成硬警告）。本方法由连接队列
    // 回调进入时须跳主演员执行（见 onPeerClosed 注释）。
    func terminate(
        _ context: ConnectionContext,
        cancelGeneration: Bool
    ) {
        let result =
            context.closeAndTakeRequestTask(
                cancelGeneration: cancelGeneration
            )

        connectionLock.withLock {
            if connections[context.key] === context {
                connections.removeValue(
                    forKey: context.key
                )
            }
        }

        result.requestTask?.cancel()

        if result.shouldCancelGeneration {
            cancelGenerationHandler?(
                context.requestId
            )
        }

        context.connection.cancel()
    }

    // MARK: - SSE Heartbeat

    /// 长上下文静默窗口保活（2026-09-12）。
    ///
    /// 流式响应从 headers/首事件到第一个 token 之间没有出站字节
    /// （16k token 冷预填充可达 50s+），客户端流闲置看门狗会判死连接重连；
    /// 孤儿推理又因静默期没有 send 失败而无法被感知，占住全局 generation
    /// gate，重试请求全部排队——表现为「重新连接 N/10、后台推理进行中」。
    ///
    /// 心跳在静默窗口注入 SSE 注释行（": ..."，规范要求解析器忽略），
    /// 同时让死连接在下一个心跳浮出 send 错误 → terminate → 取消生成、
    /// 释放 gate。有真实数据出站时不注入。仅流式 handler 使用，
    /// handler 返回时必须 cancel 返回的 Task。
    func startSSEHeartbeat(
        for context: ConnectionContext,
        interval: TimeInterval = 5,
        makeEvent: (@Sendable () -> Data?)? = nil
    ) -> Task<Void, Never> {

        let quietThreshold = interval * 0.9

        return Task { [weak self, weak context] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(interval * 1_000_000_000)
                )

                guard !Task.isCancelled else { return }

                guard
                    let self,
                    let context,
                    !context.closed
                else {
                    return
                }

                guard
                    context.secondsSinceOutboundActivity
                        >= quietThreshold
                else {
                    continue
                }

                context.sendQueue.async {
                    [weak self, weak context] in

                    guard
                        let self,
                        let context,
                        context.canSend()
                    else {
                        return
                    }

                    // 心跳不 touchOutboundActivity：它不是数据，
                    // 下一个 interval 的静默判定不应被自己抹平。
                    // makeEvent 提供协议内真实事件时优先发事件——
                    // 前端看门狗按「事件静默」计数，注释行满足不了它
                    // （2026-09-13 dense/MoE 长预填双双 ~605-671s 被断实测）。
                    if let makeEvent, let event = makeEvent() {
                        context.connection.send(
                            content: event,
                            isComplete: false,
                            completion: .contentProcessed {
                                [weak self, weak context] error in

                                guard
                                    let self,
                                    let context
                                else {
                                    return
                                }

                                if error != nil {
                                    self.terminate(
                                        context,
                                        cancelGeneration: true
                                    )
                                }
                            }
                        )
                    } else {
                        context.connection.send(
                            content: Data(": keepalive\n\n".utf8),
                            isComplete: false,
                            completion: .contentProcessed {
                                [weak self, weak context] error in

                                guard
                                    let self,
                                    let context
                                else {
                                    return
                                }

                                if error != nil {
                                    self.terminate(
                                        context,
                                        cancelGeneration: true
                                    )
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Routing

    // MARK: - LOCALB Route Permissions & Request Authorization (B3)

    /// The single trusted route decision. The three states are strictly
    /// distinct — there is no nil case, so an explicitly denied route can
    /// never be mistaken for an open one, and an unknown route can never
    /// degrade to "no authorization required".
    enum LOCALBRoutePolicy: Equatable, Sendable {
        /// No proof required: OPTIONS preflight, health probes, and the
        /// challenge endpoint itself.
        case open
        /// Requires a verified V2 proof carrying exactly this permission.
        case protected(permission: LOCALBPermission)
        /// Explicitly refused under the LOCALB regime, with a machine-
        /// readable reason. Distinct from `open` at every enforcement
        /// point: challenge issuance, request authorization, and dispatch.
        case denied(reason: String)
    }

    /// The single trusted route→policy table. Challenge issuance and
    /// request authorization MUST both derive their decision through this
    /// function; a permission is never taken from a client header, query
    /// parameter, or JSON field.
    nonisolated static func localbRoutePolicy(
        forMethod method: String,
        routePath: String
    ) -> LOCALBRoutePolicy {
        switch (method, routePath) {
        case ("OPTIONS", _),
             ("GET", "/health"),
             ("HEAD", "/health"),
             ("GET", "/v1/simigo/env"),
             ("GET", "/v1/simigo/roots"),
             ("GET", "/v1/simigo/is/status"),
             ("GET", "/v1/simigo/search"),
             ("POST", "/v1/simigo/search"),
             ("PUT", "/v1/simigo/roots"),
             ("POST", "/v1/simigo/roots"),
             ("POST", "/localb/auth/challenge"):
            return .open
        case ("GET", "/v1/models"), ("GET", "/models"),
             ("GET", "/v1/simigo/is/settlement"),
             ("GET", "/v1/simigo/is/dependency"),
             ("GET", "/v1/simigo/is/file"),
             ("GET", "/v1/simigo/is/object"):
            return .protected(permission: .informationRead)
        case ("POST", "/v1/simigo/is/reconcile"):
            // Re-derives carried validity; it writes only derived IS state, so
            // it needs the SRS-write permission rather than inference or admin.
            return .protected(permission: .srsWrite)
        case ("POST", "/mcp"), ("GET", "/mcp"):
            // Agent-facing IS surface: the tools read the settled index and may
            // register roots / re-derive validity, so the whole endpoint needs
            // the SRS-write permission (never inference only).
            return .protected(permission: .srsWrite)
        case ("POST", "/v1/chat/completions"),
             ("POST", "/chat/completions"),
             ("POST", "/v1/completions"),
             ("POST", "/completions"),
             ("POST", "/v1/responses"):
            return .protected(permission: .inference)
        case ("POST", "/v1/branches/fork"),
             ("POST", "/v1/branches/delete"),
             ("POST", "/v1/branches/list"):
            // Least-privilege fail-closed (B3 security review 2026-10-16):
            // branch mutations are NOT part of P-INFERENCE, and no dedicated
            // branch permission exists yet, so protected access is refused
            // outright. This is an explicit denial, never a removal from the
            // table — a missing entry would fall back to the fail-closed
            // default below, and a nil-style "not listed" could be read as
            // "no authorization required".
            return .denied(
                reason: "LOCALB_BRANCH_OPERATIONS_NOT_AUTHORIZED"
            )
        default:
            if method == "GET", routePath.hasPrefix("/v1/models/") {
                return .protected(permission: .informationRead)
            }
            // Fail-closed default: anything not explicitly open or
            // protected is denied. The route switch can still answer 404,
            // but only after this explicit denial has been considered.
            return .denied(reason: "LOCALB_ROUTE_UNKNOWN")
        }
    }

    /// Identity-selection headers that the signed request contract does
    /// NOT cover (LOCALBHTTPRequestV1 signs method, authority, target,
    /// content type, content encoding, and body — never arbitrary
    /// headers). On protected routes a client may select execution
    /// identity ONLY through signed JSON fields such as `agent_id`,
    /// `session_id`, `branch_id`, or `thread_id`.
    nonisolated static func localbIdentitySelectionHeaders()
        -> Set<String> {
        [
            "x-simigo-agent",
            "x-agent-id",
            "x-simigo-session",
            "x-session-id",
            "thread-id",
            "x-thread-id",
            "x-codex-thread-id",
            "x-logical-branch-id",
            "x-branch-id",
            // Carries a thread_id JSON payload used for thread selection.
            "x-codex-turn-metadata",
        ]
    }

    /// Returns the first identity-selection header whose value would
    /// actually select an identity (non-empty after trimming), if any.
    /// Whitespace-only values select nothing and are not violations.
    /// Callers must REJECT the request — never strip the header and let
    /// it fall through to a default identity, which would change the
    /// execution semantics while appearing to succeed.
    nonisolated static func localbIdentitySelectionViolation(
        in headers: [String: String]
    ) -> String? {
        for name in localbIdentitySelectionHeaders().sorted() {
            if let value = headers[name],
               !value.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty {
                return name
            }
        }
        return nil
    }

    /// Reviewed dispatch-header allowlist for LOCALB-authorized requests
    /// (local inference handlers): the downstream request is rebuilt ONLY
    /// from the verified signed object, so the header map contains at most
    /// the signed content semantics. Nothing from the pre-authorization
    /// header map survives.
    nonisolated static func localbDispatchHeaders(
        contentType: String,
        contentEncoding: String
    ) -> [String: String] {
        var headers: [String: String] = [:]
        if !contentType.isEmpty {
            headers["content-type"] = contentType
        }
        headers["content-encoding"] = contentEncoding
        return headers
    }

    /// Reviewed upstream-forward allowlist for LOCALB-authorized remote
    /// dispatch, applied independently of the local dispatch allowlist:
    /// only signed content semantics may cross this boundary. Upstream
    /// Authorization is injected server-side from the configured backend
    /// and can never be selected by client headers; path and method come
    /// from the signed request. `accept` is deliberately not forwarded —
    /// streaming is decided by the signed body's `stream` flag.
    nonisolated static func localbRemoteForwardAllowlist() -> Set<String> {
        ["content-type", "content-encoding"]
    }

    nonisolated static func decodeLowerHex(_ value: String) -> [UInt8]? {
        let chars = Array(value.utf8)
        guard !chars.isEmpty, chars.count.isMultiple(of: 2) else { return nil }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                return c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                return c - UInt8(ascii: "a") + 10
            default:
                return nil
            }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let high = nibble(chars[index]),
                  let low = nibble(chars[index + 1])
            else {
                return nil
            }
            bytes.append((high << 4) | low)
        }
        return bytes
    }

    nonisolated static func encodeLowerHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies a protected request and returns the dispatch request built
    /// ONLY from the verified `authorized.request`: routePath for routing,
    /// bodyRaw for the body, signed content-type for content semantics.
    /// After this returns, the pre-authorization HTTPRequest is never routed.
    private func verifyLOCALBProtectedRequest(
        _ request: HTTPRequest,
        tablePermission: LOCALBPermission,
        context: ConnectionContext
    ) throws -> HTTPRequest {
        // B1 transport trust boundary: only the accepting listener's own TLS
        // configuration state qualifies. Client-supplied SPKI values are
        // never read.
        guard context.transportSecurity.eligibleForLOCALBPairingBinding else {
            throw HTTPServerError.localbTransportNotTrusted
        }

        guard let authorization = localbRequestAuthorization else {
            throw HTTPServerError.localbAuthorizationUnavailable
        }

        guard let clientKeyID = request.headers["x-simigo-localb-client-key-id"],
              let challengeHex = request.headers["x-simigo-localb-challenge"],
              let proofBase64 = request.headers["x-simigo-localb-proof-v2"],
              let challenge = Self.decodeLowerHex(challengeHex),
              challenge.count == 32,
              let proof = Data(base64Encoded: proofBase64),
              proof.count == 64
        else {
            throw HTTPServerError.localbRequestRejected(
                reason: "LOCALB_CLIENT_PROOF_MISSING"
            )
        }

        // Unsigned identity-selection header boundary: identity on a
        // protected route may only come from the signed JSON body. A
        // request carrying one of these headers is rejected outright —
        // never silently stripped, because stripping would let it run
        // under a different (default) identity while appearing to
        // succeed.
        if let offendingHeader = Self.localbIdentitySelectionViolation(
            in: request.headers
        ) {
            throw HTTPServerError.localbRequestRejected(
                reason: "LOCALB_UNSIGNED_IDENTITY_HEADER_\(offendingHeader.uppercased())"
            )
        }

        // Build the signed representation from the SAME finalized parser
        // result that produced this request: exact method token, exact
        // origin-form target, authority from the single Host, raw body bytes.
        let signedRequest = try LOCALBHTTPRequestV1(
            method: request.method,
            authority: request.authority.lowercased(),
            requestTarget: request.requestTarget,
            contentType: request.headers["content-type"],
            contentEncoding: request.headers["content-encoding"] ?? "identity",
            bodyRaw: Array(request.body)
        )

        // Re-derive the route policy from the CANONICAL signed target and
        // require the same protected-table entry that governs this route —
        // the challenge was issued under exactly this mapping. Denied and
        // open policies both fail here: a denied route cannot be served
        // through the authorization path even with an otherwise valid
        // proof.
        guard case .protected(let canonicalPermission) = Self.localbRoutePolicy(
            forMethod: signedRequest.method,
            routePath: signedRequest.routePath
        ), canonicalPermission == tablePermission else {
            throw HTTPServerError.localbRequestRejected(
                reason: "LOCALB_INVALID_PROTECTED_REQUEST"
            )
        }

        let authorized: LOCALBAuthorizedRequest
        do {
            authorized = try authorization.coordinator.authorizeProtectedRequest(
                clientKeyID: clientKeyID,
                permission: canonicalPermission,
                request: signedRequest,
                challenge: challenge,
                proofSignatureRaw: Array(proof),
                checkpoint: try authorization.trustedCheckpoint()
            )
        } catch let status as LOCALBStatus {
            throw HTTPServerError.localbRequestRejected(reason: status.rawValue)
        }

        // Dispatch consumes ONLY the verified request object: method,
        // route path, query, authority and body come from
        // `authorized.request`, and headers are rebuilt through the
        // reviewed allowlist — the pre-authorization header map never
        // reaches the switch below.
        return HTTPRequest(
            method: authorized.request.method,
            path: authorized.request.routePath,
            requestTarget: authorized.request.requestTarget,
            authority: authorized.request.authority,
            headers: Self.localbDispatchHeaders(
                contentType: authorized.request.contentType,
                contentEncoding: authorized.request.contentEncoding
            ),
            body: Data(authorized.request.bodyRaw)
        )
    }

    /// LOCALB B3 challenge issuance. Requires a trusted LOCALB TLS
    /// connection — the same transport boundary as protected requests. The
    /// permission is derived server-side from the intended canonical method
    /// and route path; the issued challenge is single-use and bound to
    /// (clientKeyID, permission).
    // MARK: - SimiGo local management endpoints (database interface)

    /// GET/POST /v1/simigo/search?q=... — demand 驱动的信息检索：
    /// 已结算结果直接复用（reused=true），输入变化才重算并落新结算。
    private func handleSimigoSearchRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        var query: String?
        var rootID: String?
        if !request.body.isEmpty,
            let obj = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        {
            query = obj["q"] as? String ?? obj["query"] as? String
            rootID = obj["root_id"] as? String
        }
        if query == nil,
            let target = URL(string: "http://x" + request.requestTarget),
            let comps = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems
        {
            query = comps.first(where: { $0.name == "q" })?.value
            rootID = rootID ?? comps.first(where: { $0.name == "root_id" })?.value
        }
        guard let q = query, !q.isEmpty else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected q=<关键词>"],
                status: 400, on: context.connection, context: context)
            return
        }
        do {
            let db = try SimiGoESISDatabase(url: SimiGoPaths.databaseURL, createIfNeeded: true)
            try db.runMigrations()
            var includeChat = true
            var sessionID: String?
            if !request.body.isEmpty,
                let obj = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
            {
                if let flag = obj["include_chat"] as? Bool { includeChat = flag }
                sessionID = obj["session_id"] as? String
            }
            if let target = URL(string: "http://x" + request.requestTarget),
                let comps = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems
            {
                if let flag = comps.first(where: { $0.name == "include_chat" })?.value {
                    includeChat = (flag as NSString).boolValue
                }
                sessionID = sessionID
                    ?? comps.first(where: { $0.name == "session_id" })?.value
            }
            let loop = SimiGoInformationLoop(database: db)
            let resolution = try loop.resolve(.init(
                sessionID: sessionID, query: q,
                rootIDs: rootID.map { [$0] } ?? [],
                includeChat: includeChat,
                chatSessionIDs: sessionID.map { [$0] } ?? []))
            sendJSON(
                [
                    "demand_id": resolution.demandID,
                    "reused": resolution.reused,
                    "status": resolution.reused ? "reused" : "settled",
                    "result_sha256": resolution.resultSHA256,
                    "retrieval_settlement_id": resolution.retrievalSettlementID,
                    "stale_items": resolution.staleItemIDs,
                    "items": resolution.hits.map { [
                        "item_id": $0.itemID,
                        "kind": $0.kind,
                        "locator": $0.locator,
                        "line": $0.lineNo,
                        "text": $0.lineText,
                        "source_sha256": $0.sourceSHA256,
                    ] },
                    "hits": resolution.hits.filter { $0.kind == "file" }.map { [
                        "root_id": $0.rootID ?? "",
                        "path": $0.relativePath ?? "",
                        "line": $0.lineNo,
                        "text": $0.lineText,
                    ] },
                ],
                status: 200,
                on: context.connection,
                context: context
            )
        } catch {
            sendJSON(
                ["error": "SEARCH_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/env — generation-environment status: managed root,
    /// llama-server, hf, database, registered roots, LOCALB resolution.
    /// Read-only; every field is derived from the managed root at call time.
    private func handleSimigoEnvRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        let fm = FileManager.default
        let root = SimiGoPaths.managedRoot()
        let llama = EnvManager.findTool("llama-server")
            ?? (fm.isExecutableFile(atPath: SimiGoPaths.bin.appendingPathComponent("llama-server").path)
                ? SimiGoPaths.bin.appendingPathComponent("llama-server").path : nil)
        let hf = EnvManager.findTool("hf")
            ?? (fm.isExecutableFile(atPath: SimiGoPaths.bin.appendingPathComponent("hf").path)
                ? SimiGoPaths.bin.appendingPathComponent("hf").path : nil)
        var db: [String: Any] = ["path": SimiGoPaths.databaseURL.path]
        if let opened = try? SimiGoESISDatabase(url: SimiGoPaths.databaseURL, createIfNeeded: false),
            let version = try? opened.schemaVersion()
        {
            db["exists"] = fm.fileExists(atPath: SimiGoPaths.databaseURL.path)
            db["schema_version"] = version
            db["roots"] = (try? opened.listRoots().map(\ .rootID)) ?? []
        } else {
            db["exists"] = false
        }
        let localb: String
        switch try? LOCALBHostRuntime.resolveOperational(
            hostDirectory: LOCALBHostRuntime.defaultHostDirectory()
        ) {
        case .operational: localb = "operational"
        case .notInitialized: localb = "not_initialized"
        default: localb = "unresolvable"
        }
        sendJSON(
            [
                "managed_root": root.path,
                "llama_server": llama ?? NSNull(),
                "hf": hf ?? NSNull(),
                "database": db,
                "localb": localb,
            ],
            status: 200,
            on: context.connection,
            context: context
        )
    }

    /// GET /v1/simigo/roots — list registered external roots.
    private func handleSimigoRootsRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let db = try? SimiGoESISDatabase(url: SimiGoPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(["error": "database unavailable"], status: 503, on: context.connection, context: context)
            return
        }
        let rows = (try? db.listRoots()) ?? []
        sendJSON(
            ["roots": rows.map { [
                "root_id": $0.rootID,
                "category": $0.category,
                "display_name": $0.displayName,
                "locator_type": $0.locatorType,
                "status": $0.status,
            ] }],
            status: 200,
            on: context.connection,
            context: context
        )
    }

    /// GET /v1/simigo/is/status[?deep=1] — physical Information-Space carrier
    /// health: object store size, append-only index/dependency history, rows not
    /// yet addressed to an object, dangling references, and (with `deep=1`)
    /// per-object hash verification. Read-only and fail-closed: a database that
    /// cannot be read returns 503 instead of a healthy-looking empty report.
    private func handleSimigoCarrierStatusRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        let deep = URLComponents(string: "http://x" + request.requestTarget)?
            .queryItems?.contains(where: {
                $0.name == "deep" && ["1", "true", "yes"].contains($0.value ?? "")
            }) ?? false
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            let report = try db.carrierReport(deepVerify: deep)
            sendJSON(
                [
                    "schema_version": report.schemaVersion,
                    "object_count": report.objectCount,
                    "object_bytes": report.objectBytes,
                    "index_entries": report.indexEntries,
                    "dependency_entries": report.dependencyEntries,
                    "unaddressed_file_contents": report.unaddressedFileContents,
                    "unaddressed_chat_messages": report.unaddressedChatMessages,
                    "unaddressed_retrieval_results": report.unaddressedRetrievalResults,
                    "unaddressed_settlements": report.unaddressedSettlements,
                    "settlement_summaries": report.settlementSummaries,
                    "dangling_references": report.danglingReferences,
                    "corrupt_objects": report.corruptObjects,
                    "inline_legacy_payloads": report.inlineLegacyPayloads,
                    "deep_verified": report.deepVerified,
                ],
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "CARRIER_UNREADABLE", "detail": "\(error)"],
                status: 503, on: context.connection, context: context)
        }
    }

    private func simigoQueryItem(_ request: HTTPRequest, _ name: String) -> String? {
        guard let url = URL(string: "http://x" + request.requestTarget),
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems
        else { return nil }
        return items.first(where: { $0.name == name })?.value
    }

    private func simigoOptionalJSON(_ value: String?) -> Any {
        value ?? NSNull()
    }

    /// Text when the bytes are UTF-8, base64 otherwise — never lossy.
    private func simigoPayloadFields(_ data: Data) -> [String: Any] {
        let size = data.count
        if let text = String(data: data, encoding: .utf8) {
            return ["encoding": "utf8", "payload": text, "payload_size": size]
        }
        return [
            "encoding": "base64", "payload": data.base64EncodedString(),
            "payload_size": size,
        ]
    }

    private func simigoDependencyJSON(
        _ entry: SimiGoESISDatabase.DependencyEntry
    ) -> [String: Any] {
        [
            "dependency_id": entry.dependencyID,
            "content_address": entry.contentAddress,
            "revision": entry.revision,
            "reason": entry.reason,
            "recorded_at": entry.recordedAt,
            "append_order": entry.appendOrder,
        ]
    }

    /// GET /v1/simigo/is/settlement?id=... — read a settled result back with its
    /// verified payload, producer bindings, validity, and dependency revisions.
    private func handleSimigoSettlementRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let id = simigoQueryItem(request, "id"), !id.isEmpty else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected id=<settlement_id>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            guard let receipt = try db.settlementReceipt(id) else {
                sendJSON(
                    ["error": "SETTLEMENT_NOT_FOUND", "detail": id],
                    status: 404, on: context.connection, context: context)
                return
            }
            var body: [String: Any] = [
                "settlement_id": receipt.settlementID,
                "state_id": simigoOptionalJSON(receipt.stateID),
                "payload_object_id": simigoOptionalJSON(receipt.payloadObjectID),
                "payload_sha256": receipt.payloadSHA256,
                "schema_version": simigoOptionalJSON(receipt.schemaVersion),
                "contract_version": simigoOptionalJSON(receipt.contractVersion),
                "settled_at": simigoOptionalJSON(receipt.settledAt),
                "validation_status": simigoOptionalJSON(receipt.validationStatus),
                "validity": receipt.validity,
                "invalidated_at": simigoOptionalJSON(receipt.invalidatedAt),
                "bindings": receipt.bindings,
                "dependencies": receipt.dependencies.map(simigoDependencyJSON),
            ]
            body.merge(simigoPayloadFields(receipt.payload)) { _, new in new }
            sendJSON(body, status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "SETTLEMENT_PAYLOAD_UNVERIFIED", "detail": "\(error)"],
                status: 409, on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/is/dependency?id=... — current revision plus full history.
    private func handleSimigoDependencyRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let id = simigoQueryItem(request, "id"), !id.isEmpty else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected id=<dependency_id>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            let history = try db.dependencyHistory(id)
            guard let current = history.last else {
                sendJSON(
                    ["error": "DEPENDENCY_NOT_FOUND", "detail": id],
                    status: 404, on: context.connection, context: context)
                return
            }
            sendJSON(
                [
                    "dependency_id": id,
                    "current": simigoDependencyJSON(current),
                    "history": history.map(simigoDependencyJSON),
                ],
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "DEPENDENCY_READ_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/is/file?root_id=...&path=... — settled file content,
    /// read back through its content address.
    private func handleSimigoFileRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let rootID = simigoQueryItem(request, "root_id"), !rootID.isEmpty,
            let path = simigoQueryItem(request, "path"), !path.isEmpty
        else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected root_id=<id>&path=<relative>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            guard let content = try db.carriedFileContent(
                rootID: rootID, relativePath: path)
            else {
                sendJSON(
                    ["error": "FILE_NOT_SETTLED", "detail": "\(rootID)/\(path)"],
                    status: 404, on: context.connection, context: context)
                return
            }
            var body: [String: Any] = [
                "root_id": content.rootID,
                "path": content.relativePath,
                "content_sha256": content.contentSHA256,
                "object_id": simigoOptionalJSON(content.objectID),
                "settled_at": content.settledAt,
                "status": simigoOptionalJSON(content.status),
            ]
            body.merge(simigoPayloadFields(content.content)) { _, new in new }
            sendJSON(body, status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "FILE_CONTENT_UNVERIFIED", "detail": "\(error)"],
                status: 409, on: context.connection, context: context)
        }
    }

    /// GET /v1/simigo/is/object?id=... — verify and return one stored object.
    private func handleSimigoObjectRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        guard let id = simigoQueryItem(request, "id"), !id.isEmpty else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected id=<sha256>"],
                status: 400, on: context.connection, context: context)
            return
        }
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            guard let row = try db.objectRow(id) else {
                sendJSON(
                    ["error": "OBJECT_NOT_FOUND", "detail": id],
                    status: 404, on: context.connection, context: context)
                return
            }
            guard db.verifyObject(id) else {
                sendJSON(
                    ["error": "OBJECT_CORRUPT", "detail": id],
                    status: 409, on: context.connection, context: context)
                return
            }
            var body: [String: Any] = [
                "object_id": row.objectID,
                "created_order": row.createdOrder,
                "verified": true,
            ]
            body.merge(simigoPayloadFields(row.content)) { _, new in new }
            sendJSON(body, status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "OBJECT_READ_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    /// POST /v1/simigo/is/reconcile — re-derive validity for registered roots.
    /// Body is optional: {"category": "work", "max_age_seconds": 0}.
    private func handleSimigoReconcileRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        var category = "work"
        var maxAge: Double = 0
        if !request.body.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: request.body)
                as? [String: Any]
        {
            if let value = object["category"] as? String, !value.isEmpty {
                category = value
            }
            if let value = object["max_age_seconds"] as? Double, value > 0 {
                maxAge = value
            }
        }
        guard let db = try? SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: false)
        else {
            sendJSON(
                ["error": "DATABASE_UNAVAILABLE"],
                status: 503, on: context.connection, context: context)
            return
        }
        do {
            let result = try db.reconcileRegisteredRoots(
                category: category, minAgeSeconds: maxAge)
            sendJSON(
                [
                    "category": category,
                    "root_count": result.rootCount,
                    "settled_roots": result.settledRoots,
                    "fresh_roots": result.freshRoots,
                    "missing_roots": result.missingRoots,
                    "unlocatable_roots": result.unlocatableRoots,
                    "failed_roots": result.failedRoots,
                    "scanned": result.scanned,
                    "reused": result.reused,
                    "changed": result.changed,
                    "removed": result.removed,
                    "invalidated_settlements": result.invalidatedSettlements,
                ],
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "RECONCILE_FAILED", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    /// PUT/POST /v1/simigo/roots {"path": "/abs/work/dir"} — register (or
    /// refresh) a work root in the authoritative database. Absolute paths
    /// only; the directory must exist. Idempotent.
    private func handleSimigoRootsPutRequest(
        _ request: HTTPRequest, context: ConnectionContext
    ) async throws {
        let body = request.body
        guard !body.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let rawPath = object["path"] as? String,
            !rawPath.isEmpty, rawPath.hasPrefix("/")
        else {
            sendJSON(
                ["error": "INVALID_REQUEST", "detail": "expected a JSON body like {\"path\": \"/absolute/dir\"}"],
                status: 400, on: context.connection, context: context)
            return
        }
        let standardized = (rawPath as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir),
            isDir.boolValue
        else {
            sendJSON(
                ["error": "WORK_ROOT_NOT_FOUND", "detail": standardized],
                status: 422, on: context.connection, context: context)
            return
        }
        do {
            let db = try SimiGoESISDatabase(url: SimiGoPaths.databaseURL, createIfNeeded: true)
            try db.runMigrations()
            let rootID = "work-" + EnvManager.stableRootID(forPath: standardized)
            try db.upsertRoot(
                rootID: rootID, category: "work", displayName: standardized,
                locatorType: "path", status: "registered")
            let settle = try db.settleWorkRootContents(
                rootID: rootID, rootURL: URL(fileURLWithPath: standardized),
                carryText: false)
            sendJSON(
                [
                    "root_id": rootID, "path": standardized, "registered": true,
                    "content_settle": [
                        "scanned": settle.scanned, "reused": settle.reused,
                        "settled": settle.settled, "skipped": settle.skippedBinaryOrLarge,
                        "changed": settle.changed, "removed": settle.removed,
                        "invalidated_settlements": settle.invalidatedSettlements,
                        "objects_created": settle.objectsCreated,
                        "deduplicated": settle.deduplicated,
                    ],
                ],
                status: 200, on: context.connection, context: context)
        } catch {
            sendJSON(
                ["error": "DATABASE_ERROR", "detail": "\(error)"],
                status: 500, on: context.connection, context: context)
        }
    }

    private func handleLOCALBChallengeRequest(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async throws {
        guard context.transportSecurity.eligibleForLOCALBPairingBinding else {
            throw HTTPServerError.localbTransportNotTrusted
        }
        guard let authorization = localbRequestAuthorization else {
            throw HTTPServerError.localbAuthorizationUnavailable
        }
        guard let clientKeyID = request.headers["x-simigo-localb-client-key-id"]
        else {
            throw HTTPServerError.badRequest("Missing LOCALB client key id")
        }
        guard let body = try? JSONSerialization.jsonObject(with: request.body)
            as? [String: Any],
            let method = body["method"] as? String,
            let target = body["requestTarget"] as? String
        else {
            throw HTTPServerError.badRequest("Malformed challenge request body")
        }
        guard HTTPRequestHeadParser.isCanonicalMethodToken(method),
              target.hasPrefix("/"),
              !target.contains("#"),
              target.utf8.count <= HTTPRequestHeadParser.maxTargetBytes
        else {
            throw HTTPServerError.badRequest("Non-canonical challenge request")
        }
        let routePath = String(
            target.split(
                separator: "?",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first ?? ""
        )
        let routePolicy = Self.localbRoutePolicy(
            forMethod: method,
            routePath: routePath
        )
        guard case .protected(let permission) = routePolicy else {
            // Open routes are not protected (no challenge to issue);
            // denied routes — including branch operations — are refused
            // with an explicit denial, never a fallback to open access.
            if case .denied(let reason) = routePolicy {
                throw HTTPServerError.localbRouteDenied(reason: reason)
            }
            throw HTTPServerError.badRequest(
                "No protected route for the given method and target"
            )
        }
        let challenge: [UInt8]
        do {
            // Issuance performs the same registry validation as
            // authorization (unknown/revoked/under-privileged clients are
            // refused before consuming ledger capacity) plus per-client
            // pending and rate limits.
            challenge = try authorization.coordinator.issueRequestChallenge(
                clientKeyID: clientKeyID,
                permission: permission,
                checkpoint: try authorization.trustedCheckpoint()
            )
        } catch let status as LOCALBStatus {
            throw HTTPServerError.badRequest(status.rawValue)
        }
        sendJSON(
            [
                "challenge": Self.encodeLowerHex(challenge),
                "permission": permission.rawValue
            ],
            status: 200,
            on: context.connection,
            context: context
        )
    }

    private func route(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async throws {
        // LOCALB B3 gate: protected routes are dispatched ONLY after proof
        // verification, and only the verified request object (routePath for
        // routing, bodyRaw for the body, allowlisted headers) reaches the
        // switch below. Denied routes are refused here — before any handler
        // and regardless of proof material — and open routes are exactly
        // the enumerated set in localbRoutePolicy, so no route can bypass
        // this gate by being absent from the table.
        var request = request
        // Owner ruling 2026-10-26: the PLAINTEXT loopback listener is the
        // product's local developer/tool surface — protected routes are
        // served on it without the LOCALB proof ceremony (responses carry
        // "unprotected-by-LOCALB"). The TLS listener keeps the full B3
        // proof gate unchanged.
        let plaintextLoopback =
            !context.transportSecurity.isTLS
        switch Self.localbRoutePolicy(
            forMethod: request.method,
            routePath: request.path
        ) {
        case .open:
            break
        case .protected(let permission):
            if plaintextLoopback {
                break
            }
            request = try verifyLOCALBProtectedRequest(
                request,
                tablePermission: permission,
                context: context
            )
        case .denied(let reason):
            throw HTTPServerError.localbRouteDenied(reason: reason)
        }

        switch (request.method, request.path) {

        case ("OPTIONS", _):
            _ = sendResponse(
                status: 204,
                headers: corsHeaders(
                    extra: [
                        "Content-Length": "0"
                    ]
                ),
                body: Data(),
                on: context.connection,
                context: context,
                close: true
            )

        case ("POST", "/localb/auth/challenge"):
            try await handleLOCALBChallengeRequest(
                request,
                context: context
            )

        case ("GET", "/v1/simigo/search"),
             ("POST", "/v1/simigo/search"):
            try await handleSimigoSearchRequest(request, context: context)

        case ("GET", "/v1/simigo/env"):
            try await handleSimigoEnvRequest(request, context: context)

        case ("GET", "/v1/simigo/roots"):
            try await handleSimigoRootsRequest(request, context: context)

        case ("GET", "/v1/simigo/is/status"):
            try await handleSimigoCarrierStatusRequest(request, context: context)

        case ("GET", "/v1/simigo/is/settlement"):
            try await handleSimigoSettlementRequest(request, context: context)

        case ("GET", "/v1/simigo/is/dependency"):
            try await handleSimigoDependencyRequest(request, context: context)

        case ("GET", "/v1/simigo/is/file"):
            try await handleSimigoFileRequest(request, context: context)

        case ("GET", "/v1/simigo/is/object"):
            try await handleSimigoObjectRequest(request, context: context)

        case ("POST", "/v1/simigo/is/reconcile"):
            try await handleSimigoReconcileRequest(request, context: context)

        case ("POST", "/mcp"), ("GET", "/mcp"):
            await handleMCPRequest(request, context: context)

        case ("PUT", "/v1/simigo/roots"), ("POST", "/v1/simigo/roots"):
            try await handleSimigoRootsPutRequest(request, context: context)

        case ("GET", "/health"):
            let ok =
                await checkHealthHandler()

            sendJSON(
                [
                    "status": ok ? "ok" : "unavailable",
                    "model": modelId
                ],
                status: ok ? 200 : 503,
                on: context.connection,
                context: context
            )

        case ("HEAD", "/health"):
            let ok =
                await checkHealthHandler()

            let response: [String: Any] = [
                "status": ok ? "ok" : "unavailable",
                "model": modelId
            ]

            let body =
                (try? JSONSerialization.data(
                    withJSONObject: response
                )) ?? Data()

            _ = sendResponse(
                status: ok ? 200 : 503,
                headers: corsHeaders(
                    extra: [
                        "Content-Type":
                            "application/json; charset=utf-8",
                        "Content-Length":
                            "\(body.count)"
                    ]
                ),
                body: Data(),
                on: context.connection,
                context: context,
                close: true
            )

        case ("GET", "/v1/models"),
             ("GET", "/models"):

            var entry: [String: Any] = [
                "id": modelId,
                "object": "model",
                "created":
                    Int(
                        Date()
                            .timeIntervalSince1970
                    ),
                "owned_by": "simigo"
            ]

            // P1-1 能力契约：声明 + 实测 + 配置约束的三态透出
            //（未实测保持 unverified，不以无证据推断）。
            if let caps = capabilitiesProvider?(),
               let data = try? JSONEncoder().encode(caps),
               let obj = try? JSONSerialization.jsonObject(with: data)
                   as? [String: Any] {
                for key in ["backend", "architecture", "contextLength",
                            "capabilities", "runtime", "protocolEndpoints"] {
                    if let value = obj[key] { entry[key] = value }
                }
            }

            sendJSON(
                [
                    "object": "list",
                    "data": [entry]
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("GET", "/v1/models/\(modelId)"):

            sendJSON(
                [
                    "id": modelId,
                    "object": "model",
                    "created":
                        Int(
                            Date()
                                .timeIntervalSince1970
                        ),
                    "owned_by": "simigo"
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/branches/fork"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            guard
                let sessionId =
                    normalizeIdentifier(
                        json["session_id"] as? String
                    ),
                let sourceBranch =
                    normalizeIdentifier(
                        json["fork_from_branch"] as? String
                    ),
                let targetBranch =
                    normalizeIdentifier(
                        json["branch_id"] as? String
                    )
            else {
                sendError(
                    "branches/fork requires session_id, fork_from_branch, branch_id",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }

            let metadata =
                try await forkBranchHandler(
                    resolveExplicitAgentId(
                        from: json,
                        headers: request.headers
                    ),
                    sessionId,
                    sourceBranch,
                    targetBranch
                )

            sendJSON(
                [
                    "ok": true,
                    "session_id": sessionId,
                    "fork_from_branch": sourceBranch,
                    "branch_id": targetBranch,
                    "history_messages": metadata.history.count,
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/branches/delete"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            guard
                let sessionId =
                    normalizeIdentifier(
                        json["session_id"] as? String
                    ),
                let branchId =
                    normalizeIdentifier(
                        json["branch_id"] as? String
                    )
            else {
                sendError(
                    "branches/delete requires session_id, branch_id",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }

            try await deleteBranchHandler(
                resolveExplicitAgentId(
                    from: json,
                    headers: request.headers
                ),
                sessionId,
                branchId
            )

            sendJSON(
                [
                    "ok": true,
                    "session_id": sessionId,
                    "deleted_branch": branchId,
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/branches/list"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            guard
                let sessionId =
                    normalizeIdentifier(
                        json["session_id"] as? String
                    )
            else {
                sendError(
                    "branches/list requires session_id",
                    status: 400,
                    on: context.connection,
                    context: context
                )
                return
            }

            let branches = listBranchesHandler(
                resolveExplicitAgentId(
                    from: json,
                    headers: request.headers
                ),
                sessionId
            )

            sendJSON(
                [
                    "ok": true,
                    "session_id": sessionId,
                    "live_branches": branches.live,
                    "checkpoint_branches": branches.checkpoints,
                ],
                status: 200,
                on: context.connection,
                context: context
            )

        case ("POST", "/v1/chat/completions") where remoteBackend != nil,
             ("POST", "/chat/completions") where remoteBackend != nil:
            try await forwardToRemote(request, context: context)

        case ("POST", "/v1/completions") where remoteBackend != nil:
            try await forwardToRemote(request, context: context)

        case ("POST", "/completions") where remoteBackend != nil:
            try await forwardToRemote(request, context: context)

        case ("POST", "/v1/responses") where remoteBackend != nil:
            try await forwardToRemote(request, context: context)

        case ("GET", "/v1/models") where remoteBackend != nil:
            try await forwardToRemote(request, context: context)

        case ("POST", "/v1/chat/completions"),
             ("POST", "/chat/completions"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        case ("POST", "/v1/completions"),
             ("POST", "/completions"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleTextCompletionsStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleTextCompletionsNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        case ("POST", "/v1/responses"):

            let json =
                try decodeJSONObject(
                    request.body
                )

            if (json["stream"] as? Bool) == true {
                await handleResponsesStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            } else {
                await handleResponsesNonStreaming(
                    json,
                    headers: request.headers,
                    context: context
                )
            }

        default:
            sendError(
                "Endpoint not found",
                status: 404,
                on: context.connection,
                context: context
            )
        }
    }

    // MARK: - Identity Helpers

    func resolveClientRequestId(
        from json: [String: Any],
        headers: [String: String]
    ) -> String? {

        if let value =
            normalizeIdentifier(
                json["request_id"] as? String
            ) {
            return value
        }

        return normalizeIdentifier(
            headers["x-request-id"]
        )
    }

    func normalizedHeaderValue(
        _ value: String?
    ) -> String? {
        normalizeIdentifier(value)
    }

    func normalizeIdentifier(
        _ value: String?
    ) -> String? {

        guard let value else {
            return nil
        }

        let trimmed =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.count <= 128 {
            return trimmed
        }

        let prefix =
            String(trimmed.prefix(64))

        let digest =
            SHA256.hash(
                data: Data(trimmed.utf8)
            )
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
            .prefix(16)

        return "\(prefix)_\(digest)"
    }

    func resolveExplicitAgentId(
        from json: [String: Any],
        headers: [String: String]
    ) -> String? {

        if let value =
            normalizeIdentifier(
                json["agent_id"] as? String
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                headers["x-simigo-agent"]
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                headers["x-agent-id"]
            ) {
            return value
        }

        if let value =
            normalizeIdentifier(
                json["agent"] as? String
            ) {
            return value
        }

        if let metadata =
            json["metadata"] as? [String: Any] {

            if let value =
                normalizeIdentifier(
                    metadata["agent_id"] as? String
                ) {
                return value
            }

            if let value =
                normalizeIdentifier(
                    metadata["agent"] as? String
                ) {
                return value
            }
        }

        return nil
    }

    /// 本次 HTTP 请求在没有明确 Session 时使用的独立 Session。
    ///
    /// 注意：
    /// - 这是 execution/session identity，不是 KV identity。
    /// - 不参与跨请求 KV reuse 判断。
    /// - 每次调用都会生成新的 UUID。
    func makeRequestScopedSessionId(
        requestNamespace: String
    ) -> String {

        return "\(requestNamespace)-request:\(UUID().uuidString.lowercased())"
    }

    // MARK: - Execution Identity

    struct ResolvedExecutionIdentity: Sendable {
        let agentId: String?
        let sessionId: String
        let logicalBranchId: String
        let source: String
    }

    /// OpenAI Chat / Completions 的 Identity Resolution。
    ///
    /// 核心原则：
    ///
    /// 1. 显式 session_id / conversation_id / headers：
    ///    原样保留（只做长度规范化和 topology 解析）。
    ///
    /// 2. Codex thread_id：
    ///    保留为 Codex thread session。
    ///
    /// 3. 不再使用 user 作为 Session。
    ///
    /// 4. 不再根据 messages 前缀生成 Session。
    ///
    /// 5. 没有明确 Session 时，每个 HTTP request 使用独立 Session。
    ///
    /// 6. KV reuse 不在这里做，由 NativeMLX / KV Runtime 决定。
    func resolveExecutionIdentity(
        from json: [String: Any],
        headers: [String: String]
    ) -> ResolvedExecutionIdentity {

        let agentId =
            resolveExplicitAgentId(
                from: json,
                headers: headers
            )

        // 1. Explicit Session
        if let explicitSession =
            resolveExplicitSession(
                from: json,
                headers: headers
            ) {

            let topology =
                normalizedSessionTopology(
                    explicitSession
                )

            return ResolvedExecutionIdentity(
                agentId: agentId,
                sessionId: topology.sessionId,
                logicalBranchId:
                    topology.branchId
                    ?? resolveExplicitBranch(
                        from: json,
                        headers: headers
                    )
                    ?? "main",
                source:
                    topology.branchId == nil
                    ? "explicit_session"
                    : "explicit_session_topology"
            )
        }

        // 2. Codex Thread
        if let threadId =
            resolveThreadId(
                from: json,
                headers: headers
            ) {

            return ResolvedExecutionIdentity(
                agentId: agentId,
                sessionId:
                    "codex-thread:\(threadId)",
                logicalBranchId:
                    resolveExplicitBranch(
                        from: json,
                        headers: headers
                    )
                    ?? "main",
                source:
                    "codex.thread_id"
            )
        }

        // 3. No explicit Session.
        //
        // 这里绝对不能再从 messages 推导。
        //
        // 每个 HTTP request 独立。
        //
        // NativeMLX 后续仍可以：
        // - token prefix match
        // - tool fingerprint match
        // - physical KV reuse
        //
        // 因此不需要人为合并 Session。
        let requestSessionId =
            makeRequestScopedSessionId(
                requestNamespace: "openai"
            )

        return ResolvedExecutionIdentity(
            agentId: agentId,
            sessionId: requestSessionId,
            logicalBranchId:
                resolveExplicitBranch(
                    from: json,
                    headers: headers
                )
                ?? "main",
            source:
                "generated_request_session"
        )
    }

    /// 统一打印 OpenAI Execution Identity。
    ///
    /// 这条日志非常重要：
    ///
    /// [SimiGo Protocol] [EXECUTION]
    /// endpoint=chat.completions
    /// request=req-xxx
    /// clientRequest=...
    /// agent=...
    /// session=...
    /// branch=...
    ///
    /// 用于验证：
    /// - 两个不同 request 是否真的拿到不同 Session。
    /// - 是否存在意外 Session canonicalization。
    func printExecutionIdentity(
        endpoint: String,
        context: ConnectionContext,
        stream: Bool? = nil
    ) {
        // 到达锚点入 trace（2026-10-15）：GUI 进程 stdout 不可见，身份行
        // 此前只在内存里「到达过」。10-15 事故取证时无法从 trace 区分
        // 「活客户端管道化」与「孤儿请求排队放行」，每请求一行补齐。
        // r=/s= 用 6 位短 ID，与 [LC] 行可直连。
        // stream 标志（2026-10-16）：非流式请求死于此路径的零字节窗口
        // （undici 300s 拆连），取证时首行即可分流。
        RuntimeTraceLogger.shared.trace(
            "[PROTOCOL] arrive" +
            " r=\(String(context.requestId.dropFirst(4).prefix(6)))" +
            " endpoint=\(endpoint)" +
            (stream.map { " stream=\($0)" } ?? "") +
            " agent=\(context.agentId ?? "default")" +
            " s=\(context.sessionId.map { String($0.prefix(6)) } ?? "-")" +
            " branch=\(context.logicalBranchId ?? "main")"
        )

        print(
            "[SimiGo Protocol] " +
            "[EXECUTION] " +
            "endpoint=\(endpoint) " +
            "request=\(context.requestId) " +
            "clientRequest=\(context.clientRequestId ?? "-") " +
            "agent=\(context.agentId ?? "default") " +
            "session=\(context.sessionId ?? "-") " +
            "branch=\(context.logicalBranchId ?? "main")"
        )
    }

    // MARK: - Parameter Extraction

    func extractConfig(
        from json: [String: Any]
    ) -> ModelConfig {

        // UI 模型设置为兜底（2026-09-13）：请求未显式指定的字段落 UI 值，
        // 显式字段仍覆盖 UI——模型页采样参数此前只落 ModelConfig 硬编码
        // 默认（1.0/0.9/20），对协议请求完全不生效。
        var config = baseConfigProvider()

        if let maxTokens =
            json["max_completion_tokens"] as? Int
            ?? json["max_tokens"] as? Int {

            config.maxTokens =
                maxTokens
        }

        if let value =
            (json["temperature"] as? NSNumber)?
            .floatValue {

            config.temperature =
                value
        }

        if let value =
            (json["top_p"] as? NSNumber)?
            .floatValue {

            config.topP =
                value
        }

        if let value =
            json["top_k"] as? Int {

            config.topK =
                value
        }

        if let value =
            (json["min_p"] as? NSNumber)?
            .floatValue {

            config.minP =
                value
        }

        if let value =
            (json["repeat_penalty"] as? NSNumber)?
            .floatValue {

            config.repeatPenalty =
                value
        }

        if let value =
            (json["presence_penalty"] as? NSNumber)?
            .floatValue {

            config.presencePenalty =
                value
        }

        if let disableThinking =
            json["disable_thinking"] as? Bool {

            config.disableThinking =
                disableThinking

        } else if let enableThinking =
                    json["enable_thinking"] as? Bool {

            config.disableThinking =
                !enableThinking
        }

        // P0-5 验收入口：请求级 KV 配置（kvFingerprint 变更 → 旧缓存失效）。
        if let kvObj = json["kvCache"] as? [String: Any] {
            var settings = KVCacheSettings()
            if let strategy = kvObj["strategy"] as? String {
                settings.strategy = strategy
            }
            if let maxTokens = kvObj["maxTokens"] as? Int {
                settings.maxTokens = maxTokens
            }
            if let preserved = kvObj["preservedPrefixTokens"] as? Int {
                settings.preservedPrefixTokens = preserved
            }
            config.kvCache = settings
        }

        return config
    }

    // MARK: - Response Helpers

    func sendJSON(
        _ object: [String: Any],
        status: Int,
        on connection: NWConnection,
        context: ConnectionContext
    ) {

        guard
            let data =
                try? JSONSerialization.data(
                    withJSONObject:
                        object
                )
        else {
            return
        }

        var headers =
            corsHeaders()

        headers["Content-Type"] =
            "application/json; charset=utf-8"

        headers["Content-Length"] =
            "\(data.count)"

        headers["X-Request-Id"] =
            context.requestId

        if let clientRequestId =
            context.clientRequestId {

            headers["X-Client-Request-Id"] =
                clientRequestId
        }

        _ = sendResponse(
            status: status,
            headers: headers,
            body: data,
            on: connection,
            context: context,
            close: true
        )
    }

    @discardableResult
    func sendResponse(
        status: Int,
        headers: [String: String],
        body: Data,
        on connection: NWConnection,
        context: ConnectionContext,
        close: Bool
    ) -> Bool {

        guard !context.closed else {
            return false
        }

        // LOCALB B1: every response declares its transport protection level.
        // The value comes exclusively from the server-side listener state
        // captured at accept(); plaintext responses are explicitly marked
        // "unprotected-by-LOCALB".
        var headers = headers
        headers["X-SimiGo-Protection"] =
            context.transportSecurity.protectionHeader

        var head =
            "HTTP/1.1 " +
            "\(status) " +
            "\(reasonPhrase(status))\r\n"

        for (key, value) in headers {
            head +=
                "\(key): \(value)\r\n"
        }

        if close {
            head += "Connection: close\r\n"
        }

        head += "\r\n"

        var packet =
            Data(head.utf8)

        packet.append(body)

        return enqueueSend(
            packet,
            context: context,
            close: close
        )
    }

    func sendSSEChunk(
        _ object: [String: Any],
        context: ConnectionContext
    ) {

        guard
            !context.closed,
            let data =
                try? JSONSerialization.data(
                    withJSONObject:
                        object
                )
        else {
            return
        }

        var payload =
            Data("data: ".utf8)

        payload.append(data)
        payload.append(
            contentsOf:
                "\n\n".utf8
        )

        _ = enqueueSend(
            payload,
            context: context,
            close: false
        )
    }

    func sendRaw(
        _ data: Data,
        context: ConnectionContext,
        close: Bool
    ) {
        _ = enqueueSend(
            data,
            context: context,
            close: close
        )
    }

    @discardableResult
    private func enqueueSend(
        _ data: Data,
        context: ConnectionContext,
        close: Bool
    ) -> Bool {

        guard context.canSend() else {
            return false
        }

        context.touchOutboundActivity()

        context.sendQueue.async {
            [weak self, weak context] in

            guard
                let self,
                let context,
                context.canSend()
            else {
                return
            }

            context.connection.send(
                content: data,
                isComplete: close,
                completion:
                    .contentProcessed {
                        [weak self, weak context] error in

                        guard
                            let self,
                            let context
                        else {
                            return
                        }

                        if error != nil {

                            self.terminate(
                                context,
                                cancelGeneration: true
                            )

                        } else if close {

                            self.finish(context)

                            context.connection.cancel()
                        }
                    }
            )
        }

        return true
    }

    /// OpenAI 风格错误体构造（2026-10-16 从 sendError 提取，行为不变）：
    /// 非流式 keepalive 模式头已恒 200，错误需以同构体承载。
    func errorBody(
        message: String,
        status: Int,
        errorKind: String? = nil,
        reasonCode: String? = nil
    ) -> [String: Any] {

        let errorType: String

        switch status {
        case 400, 404, 417:
            errorType =
                "invalid_request_error"

        case 413:
            errorType =
                "request_too_large"

        case 501:
            errorType =
                "not_implemented"

        case 503:
            errorType =
                "server_error"

        default:
            errorType =
                "server_error"
        }

        var error: [String: Any] = [
            "message": message,
            "type": errorType,
            "param": NSNull(),
            "code": NSNull()
        ]
        // Structured continuation contract v0.1: present ONLY when a kind is
        // supplied, so every legacy error body stays byte-for-byte unchanged.
        if let errorKind {
            error["error_kind"] = errorKind
            error["reason_code"] = reasonCode as Any ?? NSNull()
        }
        return ["error": error]
    }

    func sendError(
        _ message: String,
        status: Int,
        on connection: NWConnection,
        context: ConnectionContext,
        errorKind: String? = nil,
        reasonCode: String? = nil
    ) {

        sendJSON(
            errorBody(
                message: message,
                status: status,
                errorKind: errorKind,
                reasonCode: reasonCode
            ),
            status: status,
            on: connection,
            context: context
        )
    }

    func reasonPhrase(
        _ status: Int
    ) -> String {

        switch status {
        case 200:
            return "OK"

        case 204:
            return "No Content"

        case 400:
            return "Bad Request"

        case 404:
            return "Not Found"

        case 413:
            return "Request Entity Too Large"

        case 417:
            return "Expectation Failed"

        case 500:
            return "Internal Server Error"

        case 501:
            return "Not Implemented"

        case 503:
            return "Service Unavailable"

        default:
            return "Error"
        }
    }

    // MARK: - JSON

    private func decodeJSONObject(
        _ body: Data
    ) throws -> [String: Any] {

        guard
            !body.isEmpty,

            let json =
                try? JSONSerialization.jsonObject(
                    with: body
                ) as? [String: Any]
        else {
            throw HTTPServerError.badRequest(
                "Malformed JSON body"
            )
        }

        return json
    }

    // MARK: - Remote OpenAI-compatible Backend

    private func forwardToRemote(
        _ request: HTTPRequest,
        context: ConnectionContext
    ) async throws {
        guard let backend = remoteBackend else {
            sendError("Remote backend unavailable", status: 503, on: context.connection, context: context)
            return
        }

        let upstreamRequest: URLRequest
        do {
            // Reviewed remote-forward allowlist: only signed content
            // semantics cross this boundary. Client headers can never
            // select upstream credentials (Authorization is injected from
            // the configured backend below) or the upstream target (the
            // path AND query come from the verified request target).
            let upstreamHeaders = request.headers.filter {
                Self.localbRemoteForwardAllowlist().contains($0.key)
            }
            upstreamRequest = try backend.makeRequest(
                path: request.requestTarget,
                method: request.method,
                headers: upstreamHeaders,
                body: request.body
            )
        } catch {
            sendError(error.localizedDescription, status: 400, on: context.connection, context: context)
            return
        }

        let agent = request.headers["x-agent-id"]
            ?? request.headers["x-simigo-agent"]
        let execution = request.headers["x-simigo-execution-id"]
            ?? request.headers["x-request-id"]
            ?? context.requestId

        print(
            "[SimiGo Remote] [EXECUTION] endpoint=\(request.path) " +
            "request=\(context.requestId) agent=\(agent ?? "default") " +
            "execution=\(execution)"
        )

        let started = Date()
        let remoteSession = RemoteOpenAIBackend.makeURLSession()
        defer { remoteSession.finishTasksAndInvalidate() }

        if backend.isStreamingRequest(requestHeaders: request.headers, body: request.body) {
            do {
                let (bytes, response) = try await remoteSession.bytes(for: upstreamRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw HTTPServerError.badRequest("Remote backend returned a non-HTTP response")
                }

                var head =
                    "HTTP/1.1 \(httpResponse.statusCode) " +
                    "\(reasonPhrase(httpResponse.statusCode))\r\n"
                for (key, value) in backend.sanitizedResponseHeaders(httpResponse) {
                    head += "\(key): \(value)\r\n"
                }
                head += "\r\n"
                sendRaw(Data(head.utf8), context: context, close: false)

                var responseBytes = 0
                var pending = Data()
                let separator = Data("\n\n".utf8)

                for try await byte in bytes {
                    guard !context.closed else { break }
                    pending.append(byte)

                    if pending.count >= separator.count, pending.suffix(separator.count) == separator {
                        responseBytes += pending.count
                        sendRaw(pending, context: context, close: false)
                        pending.removeAll(keepingCapacity: true)
                    }
                }

                if !pending.isEmpty {
                    responseBytes += pending.count
                    sendRaw(pending, context: context, close: false)
                }
                sendRaw(Data(), context: context, close: true)

                print(
                    "[SimiGo Remote] [STREAM_COMPLETE] endpoint=\(request.path) " +
                    "status=\(httpResponse.statusCode) bytes=\(responseBytes) " +
                    "duration=\(String(format: "%.3f", Date().timeIntervalSince(started)))s " +
                    "agent=\(agent ?? "default") execution=\(execution)"
                )
            } catch {
                if context.canSend() {
                    sendError(
                        "Remote backend failed: \(error.localizedDescription)",
                        status: 502,
                        on: context.connection,
                        context: context
                    )
                }

                print(
                    "[SimiGo Remote] [STREAM_FAILED] endpoint=\(request.path) " +
                    "error=\(error.localizedDescription) agent=\(agent ?? "default") " +
                    "execution=\(execution)"
                )
            }
            return
        }

        do {
            let (data, response) = try await remoteSession.data(for: upstreamRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPServerError.badRequest("Remote backend returned a non-HTTP response")
            }

            var head =
                "HTTP/1.1 \(httpResponse.statusCode) " +
                "\(reasonPhrase(httpResponse.statusCode))\r\n"
            for (key, value) in backend.sanitizedResponseHeaders(httpResponse) {
                head += "\(key): \(value)\r\n"
            }
            head += "\r\n"

            sendRaw(Data(head.utf8), context: context, close: false)

            sendRaw(data, context: context, close: false)
            let responseBytes = data.count
            sendRaw(Data(), context: context, close: true)

            print(
                "[SimiGo Remote] [COMPLETE] endpoint=\(request.path) " +
                "status=\(httpResponse.statusCode) bytes=\(responseBytes) " +
                "duration=\(String(format: "%.3f", Date().timeIntervalSince(started)))s " +
                "agent=\(agent ?? "default") execution=\(execution)"
            )
        } catch {
            if context.canSend() {
                sendError(
                    "Remote backend failed: \(error.localizedDescription)",
                    status: 502,
                    on: context.connection,
                    context: context
                )
            }

            print(
                "[SimiGo Remote] [FAILED] endpoint=\(request.path) " +
                "error=\(error.localizedDescription) agent=\(agent ?? "default") " +
                "execution=\(execution)"
            )
        }
    }

    // MARK: - HTTP Parsing

    /// Pure request-head parser — the single interpretation point between the
    /// raw request bytes and everything downstream (verification, routing,
    /// dispatch). LOCALB B3 parser-gate guarantees:
    ///
    /// - The request-line method token is preserved exactly: it must already
    ///   be canonical uppercase ASCII (letters/digits/hyphen, 1–16 bytes). A
    ///   lowercase method is rejected, never silently uppercased.
    /// - The exact origin-form request target (query included) is preserved
    ///   verbatim; the route path is derived exactly once from that validated
    ///   target and must never be re-derived after authorization.
    /// - Duplicate header names (case-insensitive) are rejected outright —
    ///   never resolved by dictionary overwrite.
    /// - Body framing is Content-Length only (plain decimal digits); any
    ///   Transfer-Encoding header is rejected.
    /// - HTTP/1.1 requires exactly one non-empty Host; the authority comes
    ///   from that single accepted value.
    enum HTTPRequestHeadParser {

        struct Head {
            let method: String
            let requestTarget: String
            let path: String
            let authority: String
            let headers: [String: String]
            let contentLength: Int
        }

        static let maxTargetBytes = 8_192
        static let maxMethodBytes = 16

        // RFC 9112 §5.1 token characters. Field names are case-
        // insensitive, so BOTH cases are valid raw tokens; the parser
        // normalizes to lower-case after validation.
        private static let tokenNameCharacters = Set(
            "abcdefghijklmnopqrstuvwxyz"
                + "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                + "0123456789!#$%&'*+-.^_`|~"
        )

        static func parse(_ headerText: String) throws -> Head {
            let lines = headerText.components(separatedBy: "\r\n")

            guard let requestLine = lines.first else {
                throw HTTPServerError.badRequest("Missing request line")
            }

            guard requestLine.utf8.count <= HTTPServer.maxHeaderLineBytes else {
                throw HTTPServerError.payloadTooLarge
            }

            // Strict request-line parsing (RFC 9112 §3): exactly three
            // SP-separated components. Empty subsequences are NOT omitted,
            // so leading, trailing, or doubled spaces yield a wrong part
            // count (or an empty method/version token) and are rejected —
            // never silently normalized.
            let requestParts = requestLine.split(
                separator: " ",
                omittingEmptySubsequences: false
            )

            guard requestParts.count == 3 else {
                throw HTTPServerError.badRequest("Malformed request line")
            }

            let method = String(requestParts[0])
            guard isCanonicalMethodToken(method) else {
                throw HTTPServerError.badRequest(
                    "Non-canonical HTTP method: \(method)"
                )
            }

            let target = String(requestParts[1])

            guard let version = validateVersion(String(requestParts[2])) else {
                throw HTTPServerError.badRequest("Unsupported HTTP version")
            }

            try validateTarget(target)

            // The route path is derived exactly once, here, from the same
            // validated target bytes that a request proof must sign.
            let path = String(
                target.split(
                    separator: "?",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                ).first ?? ""
            )

            guard !path.isEmpty else {
                throw HTTPServerError.badRequest("Empty request target")
            }

            var headers: [String: String] = [:]
            var seenNames = Set<String>()
            var headerCount = 0

            for line in lines.dropFirst() {
                if line.isEmpty { continue }
                headerCount += 1

                guard headerCount <= HTTPServer.maxHeaderCount else {
                    throw HTTPServerError.payloadTooLarge
                }

                guard line.utf8.count <= HTTPServer.maxHeaderLineBytes else {
                    throw HTTPServerError.payloadTooLarge
                }

                guard let colon = line.firstIndex(of: ":") else {
                    throw HTTPServerError.badRequest("Malformed header")
                }

                // RFC 9112 §5.1: whitespace between a header field name
                // and the colon MUST be rejected. The RAW name is validated
                // as a token first (SP/HTAB are not token characters);
                // only then is the case normalized. Illegal whitespace is
                // never trimmed into acceptance.
                let rawName = String(line[..<colon])
                guard !rawName.isEmpty,
                      tokenNameCharacters.isSuperset(of: rawName)
                else {
                    throw HTTPServerError.badRequest("Malformed header name")
                }
                let name = rawName.lowercased()

                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)

                guard !value.utf8.contains(where: { $0 < 0x20 || $0 == 0x7F })
                else {
                    throw HTTPServerError.badRequest(
                        "Header value contains control characters"
                    )
                }

                // Duplicate names (including case variants) are rejected
                // instead of letting dictionary assignment pick a winner.
                guard seenNames.insert(name).inserted else {
                    throw HTTPServerError.badRequest(
                        "Duplicate header: \(name)"
                    )
                }

                headers[name] = value
            }

            // Framing: Content-Length only. Any Transfer-Encoding header —
            // even an empty one — is ambiguous with chunked framing and is
            // rejected.
            if let transferEncoding = headers["transfer-encoding"] {
                throw HTTPServerError.unsupportedTransferEncoding(
                    transferEncoding.isEmpty ? "(empty)" : transferEncoding
                )
            }

            let contentLength: Int
            if let rawLength = headers["content-length"] {
                guard let parsed = parseStrictContentLength(rawLength) else {
                    throw HTTPServerError.badRequest("Invalid Content-Length")
                }
                contentLength = parsed
            } else {
                contentLength = 0
            }

            guard contentLength <= HTTPServer.maxBodyBytes else {
                throw HTTPServerError.payloadTooLarge
            }

            // Authority comes from the single accepted Host value.
            let host = headers["host"]
            if version == "HTTP/1.1" {
                guard let host, !host.isEmpty else {
                    throw HTTPServerError.badRequest(
                        "HTTP/1.1 requires a non-empty Host header"
                    )
                }
            }

            return Head(
                method: method,
                requestTarget: target,
                path: path,
                authority: host ?? "",
                headers: headers,
                contentLength: contentLength
            )
        }

        static func isCanonicalMethodToken(_ token: String) -> Bool {
            let bytes = token.utf8
            guard (1...maxMethodBytes).contains(bytes.count) else {
                return false
            }
            return bytes.allSatisfy { byte in
                (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
                    || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
                    || byte == UInt8(ascii: "-")
            }
        }

        private static func validateVersion(_ raw: String) -> String? {
            let upper = raw.uppercased()
            return (upper == "HTTP/1.1" || upper == "HTTP/1.0") ? upper : nil
        }

        private static func validateTarget(_ target: String) throws {
            guard target.hasPrefix("/") else {
                throw HTTPServerError.badRequest(
                    "Request target must be origin-form"
                )
            }

            guard !target.contains("#") else {
                throw HTTPServerError.badRequest(
                    "Request target must not contain a fragment"
                )
            }

            guard target.utf8.allSatisfy({ $0 > 0x20 && $0 != 0x7F }) else {
                throw HTTPServerError.badRequest(
                    "Request target contains whitespace or control characters"
                )
            }

            guard target.utf8.count <= maxTargetBytes else {
                throw HTTPServerError.payloadTooLarge
            }
        }

        private static func parseStrictContentLength(_ raw: String) -> Int? {
            guard !raw.isEmpty else { return nil }
            var value = 0
            for byte in raw.utf8 {
                guard (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
                else {
                    return nil
                }
                let digit = Int(byte - UInt8(ascii: "0"))
                if value > (Int.max - digit) / 10 { return nil }
                value = value * 10 + digit
            }
            return value
        }
    }

    private func readRequest(
        from connection: NWConnection
    ) async throws -> HTTPRequest {

        var buffer =
            Data()

        let delimiter =
            Data(
                "\r\n\r\n".utf8
            )

        while
            buffer.range(
                of: delimiter
            ) == nil {

            guard
                let chunk =
                    try await connection.receiveAsync(
                        min: 1,
                        max:
                            Self.receiveChunkSize
                    ),

                !chunk.isEmpty
            else {
                throw HTTPServerError.clientDisconnected
            }

            buffer.append(chunk)

            if buffer.count >
                Self.maxHeaderBytes {

                throw HTTPServerError.payloadTooLarge
            }
        }

        guard
            let headerRange =
                buffer.range(
                    of: delimiter
                )
        else {
            throw HTTPServerError.badRequest(
                "Malformed headers"
            )
        }

        guard
            headerRange.lowerBound <=
                Self.maxHeaderBytes
        else {
            throw HTTPServerError.payloadTooLarge
        }

        guard
            let headerText =
                String(
                    data:
                        buffer[
                            ..<headerRange
                                .lowerBound
                        ],
                    encoding: .utf8
                )
        else {
            throw HTTPServerError.badRequest(
                "Headers are not valid UTF-8"
            )
        }

        let head = try Self.HTTPRequestHeadParser.parse(
            headerText
        )

        if let expect =
            head.headers["expect"] {

            let normalizedExpect =
                expect
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased()

            if normalizedExpect.isEmpty {
                // 无 Expect，继续
            } else if normalizedExpect == "100-continue" {
                // HTTP/1.1 规范行为：告知客户端继续发送请求体。
                // （curl 对 >1KB 请求体自动附带此头；拒绝会让部分 LAN 客户端超时）
                connection.send(
                    content:
                        Data(
                            "HTTP/1.1 100 Continue\r\n\r\n".utf8
                        ),
                    completion:
                        .contentProcessed { _ in }
                )
            } else {
                throw HTTPServerError
                    .expectationFailed
            }
        }

        let bodyStart =
            headerRange.upperBound

        var body =
            buffer.subdata(
                in:
                    bodyStart..<buffer.count
            )

        let contentLength = head.contentLength

        if contentLength == 0,
           !body.isEmpty {

            throw HTTPServerError.badRequest(
                "Request body requires Content-Length"
            )
        }

        if body.count >
            contentLength {

            body =
                body.prefix(
                    contentLength
                )
        }

        while
            body.count <
            contentLength {

            guard
                let chunk =
                    try await connection.receiveAsync(
                        min: 1,
                        max:
                            min(
                                Self.receiveChunkSize,
                                contentLength -
                                    body.count
                            )
                    ),

                !chunk.isEmpty
            else {
                throw HTTPServerError.clientDisconnected
            }

            let remaining =
                contentLength -
                body.count

            if chunk.count >
                remaining {

                body.append(
                    chunk.prefix(
                        remaining
                    )
                )

                break
            }

            body.append(chunk)
        }

        guard
            body.count ==
                contentLength
        else {
            throw HTTPServerError.clientDisconnected
        }

        return HTTPRequest(
            method: head.method,
            path: head.path,
            requestTarget: head.requestTarget,
            authority: head.authority,
            headers: head.headers,
            body: body
        )
    }
}

// MARK: - Thread-Safe Value

nonisolated final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        lock.lock()
        defer {
            lock.unlock()
        }

        return _value
    }

    func set(_ value: T) {
        lock.lock()
        defer {
            lock.unlock()
        }

        _value = value
    }

    func mutate(
        _ transform: (inout T) -> Void
    ) {
        lock.lock()
        defer {
            lock.unlock()
        }

        transform(&_value)
    }

    @discardableResult
    func mutateReturning<R>(
        _ transform: (inout T) -> R
    ) -> R {

        lock.lock()
        defer {
            lock.unlock()
        }

        return transform(&_value)
    }
}

// MARK: - NSLock Helper

private extension NSLock {
    nonisolated func withLock<T>(
        _ body: () throws -> T
    ) rethrows -> T {

        lock()
        defer {
            unlock()
        }

        return try body()
    }
}

// MARK: - NWConnection Async Receive

private extension NWConnection {
    func receiveAsync(
        min: Int = 1,
        max: Int = 32 * 1024
    ) async throws -> Data? {

        try await withCheckedThrowingContinuation {
            continuation in

            receive(
                minimumIncompleteLength: min,
                maximumLength: max
            ) {
                data,
                _,
                _,
                error in

                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else {
                    continuation.resume(
                        returning: data
                    )
                }
            }
        }
    }
}
