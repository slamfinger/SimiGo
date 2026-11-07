import Foundation
import LOCALBCore

// MARK: - Controlled LOCALB local-management entry (Service/HTTP closure)
//
// The product already ships the LOCALB primitives (first-run ceremony,
// checkpoint anchoring, pairing, per-request proof V2) but no surface calls
// them: `app_target_call_sites=0` for `prepareFirstRun` /
// `activateInitialSetup` / `persistTrustedCheckpoint`. On a host that was
// never activated the default resolution therefore stays fail-closed
// (`transportIdentityMissing`), `HTTPServer.start()` throws before an
// `NWListener` exists, and no request can ever be served.
//
// This entry is the missing LOCAL MANAGEMENT PLANE, nothing more. Every role
// below is a thin call into an existing package API:
//
//   prepare      -> LOCALBHostBootstrap.prepareFirstRun        (creates key + lineage 1)
//   activate     -> LOCALBHostBootstrap.activateInitialSetup   (operator checkpoint must equal head)
//                -> LOCALBHostRuntime.persistTrustedCheckpoint (the anchor later startups read)
//   pair-issue   -> LOCALBPairingCoordinator.issueCredential   (strict-headless, client key pre-bound)
//   pair-approve -> LOCALBPairingCoordinator.preparePairing
//                -> LOCALBPairingCoordinator.approveAndRegister
//   serve        -> NativeMLX.startWithLOCALB(nil, nil)        (the SAME call `Service` makes)
//   serve-service-> Service.shared.start(path:)                (the product's own Start facade,
//                   which forwards to that same call; used to judge the gate on the orchestration
//                   path itself rather than only on the runtime call it delegates to)
//
// It does NOT add a route, relax TLS, accept a caller-declared SPKI, skip the
// proof gate, or auto-activate on a normal launch: `evaluate` is gated on
// `SIMIGO_LOCALB_MGMT` and refuses to run unless an isolated `SIMIGO_HOME` is
// set, so no real `~/.simigo` state, credential or Keychain item is touched.
//
// `serve` is the activation TRIGGER only. Request dispatch stays the product
// path: TLS listener -> LOCALB proof gate -> generateHandler -> NativeMLX.

enum SimiGoLocalBManagementRole: String {
    case prepare
    case activate
    case pairIssue = "pair-issue"
    case pairApprove = "pair-approve"
    case serve
    case serveService = "serve-service"
    // S3-B (owner ruling 2026-11-05): the LOCALB owner management roles.
    // Local CLI operations only — no HTTP surface, no remote delegation,
    // no self-service elevation path for paired agents.
    case clientsList = "clients-list"
    case permissionsSet = "permissions-set"
    case clientRevoke = "client-revoke"
}

enum SimiGoLocalBManagementEntry {

    static let environmentKey = "SIMIGO_LOCALB_MGMT"

    struct Decision {
        let requested: Bool
        let role: SimiGoLocalBManagementRole?
        let error: String?
    }

    /// Fail closed on an unsupported role, a missing parameter, or a missing
    /// isolated root — always BEFORE any Keychain, registry or model work.
    static func evaluate(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Decision {
        guard let raw = env[environmentKey], !raw.isEmpty else {
            return Decision(requested: false, role: nil, error: nil)
        }
        guard let role = SimiGoLocalBManagementRole(rawValue: raw) else {
            return Decision(
                requested: true, role: nil,
                error: "unsupported \(environmentKey) '\(raw)' "
                    + "(allowed: prepare|activate|pair-issue|pair-approve|serve|serve-service)"
            )
        }
        // These roles create keys and registry state. They run against an
        // isolated managed root by default; the real home is a target only
        // under an explicit operator acknowledgement
        // (SIMIGO_LOCALB_ALLOW_REAL_ROOT=1). Real-root use exists because the
        // production identity now lives in the managed FILE keychain
        // (<root>/localb/…): re-running the first-run ceremony there is the
        // recovery path for a host whose login-Keychain identities are locked
        // to a previous build's code signature (transportIdentityMismatch /
        // AUTH_DENIED, 2026-10-26).
        let realRootAcknowledged = env["SIMIGO_LOCALB_ALLOW_REAL_ROOT"] == "1"
        guard realRootAcknowledged || ((env["SIMIGO_HOME"] ?? "").isEmpty == false) else {
            return Decision(
                requested: true, role: nil,
                error: "SIMIGO_HOME is required (or set "
                    + "SIMIGO_LOCALB_ALLOW_REAL_ROOT=1 to operate on the real "
                    + "managed root)"
            )
        }

        func missing(_ key: String) -> Decision {
            Decision(requested: true, role: nil, error: "\(key) missing")
        }
        switch role {
        case .prepare:
            break
        case .activate:
            guard env["SIMIGO_LOCALB_CHECKPOINT"]?.isEmpty == false else {
                return missing("SIMIGO_LOCALB_CHECKPOINT")
            }
        case .pairIssue:
            guard env["SIMIGO_LOCALB_CLIENT_PUBKEY_HEX"]?.isEmpty == false else {
                return missing("SIMIGO_LOCALB_CLIENT_PUBKEY_HEX")
            }
        case .pairApprove:
            for key in [
                "SIMIGO_LOCALB_CREDENTIAL_ID",
                "SIMIGO_LOCALB_SECRET_B64URL",
                "SIMIGO_LOCALB_CLIENT_PUBKEY_HEX",
                "SIMIGO_LOCALB_PAIRING_PROOF_HEX",
                "SIMIGO_LOCALB_TLS_SPKI_HEX",
                "SIMIGO_LOCALB_SRS_KEY_ID"
            ] where env[key]?.isEmpty != false {
                return missing(key)
            }
        case .serve, .serveService:
            guard env["SIMIGO_LOCALB_SERVE_MODEL"]?.isEmpty == false else {
                return missing("SIMIGO_LOCALB_SERVE_MODEL")
            }
        case .clientsList:
            break
        case .permissionsSet:
            for key in [
                "SIMIGO_LOCALB_CLIENT_KEY_ID",
                "SIMIGO_LOCALB_PERMISSIONS",
                "SIMIGO_LOCALB_REASON"
            ] where env[key]?.isEmpty != false {
                return missing(key)
            }
        case .clientRevoke:
            for key in [
                "SIMIGO_LOCALB_CLIENT_KEY_ID",
                "SIMIGO_LOCALB_REASON"
            ] where env[key]?.isEmpty != false {
                return missing(key)
            }
        }
        return Decision(requested: true, role: role, error: nil)
    }

    // MARK: - Entry point

    @MainActor
    static func run(role: SimiGoLocalBManagementRole) async -> Int32 {
        do {
            switch role {
            case .prepare: try runPrepare()
            case .activate: try runActivate()
            case .pairIssue: try runPairIssue()
            case .pairApprove: try runPairApprove()
            case .serve: try await runServe()
            case .serveService: try await runServeService()
            case .clientsList:
                emit(try clientsListPayload(
                    context: try requireOperationalContext()
                ))
            case .permissionsSet:
                emit(try permissionsSetPayload(
                    context: try requireOperationalContext(),
                    env: ProcessInfo.processInfo.environment
                ))
            case .clientRevoke:
                emit(try clientRevokePayload(
                    context: try requireOperationalContext(),
                    env: ProcessInfo.processInfo.environment
                ))
            }
            return 0
        } catch let status as LOCALBStatus {
            emit(["role": role.rawValue, "result": "fail-closed",
                  "localb_status": status.rawValue])
            return 3
        } catch let refused as FacadeStartRefused {
            // The facade swallows the runtime's typed throw into `status`; the
            // token is extracted, never invented: when the text carries no
            // LOCALB_ code the raw status string is what gets recorded.
            emit(["role": role.rawValue, "result": "fail-closed",
                  "binding": "Service.start(path:)",
                  "localb_status": typedStatus(in: refused.status),
                  "service_status": refused.status,
                  "listening": false])
            return 3
        } catch {
            emit(["role": role.rawValue, "result": "error",
                  "message": "\(error)"])
            return 4
        }
    }

    // MARK: - Roles

    private static func runPrepare() throws {
        let hostDirectory = LOCALBHostRuntime.defaultHostDirectory()
        let registryRoot = LOCALBHostRuntime.registryRoot(in: hostDirectory)
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: registryRoot
        )
        // The operator (the driving process) records this offline; activate
        // must hand the SAME values back and the ceremony refuses a mismatch.
        emit([
            "role": "prepare",
            "host_directory": hostDirectory.path,
            "registry_root": registryRoot.path,
            "lineage_id": pending.lineageID,
            "signer_key_id": pending.signerKeyID,
            "signer_generation": pending.signerGeneration,
            "sequence": pending.checkpoint.sequence,
            "head_hash_hex": pending.checkpoint.headHashHex,
            "checkpoint": "\(pending.lineageID):\(pending.checkpoint.sequence):"
                + pending.checkpoint.headHashHex,
            "offline_record": pending.offlineCheckpointRecord,
            "transport_spki_sha256": pending.transportSPKIHashHex,
            "protocol_version": LOCALBConstants.credentialProtocolVersion,
            "operational": false
        ])
    }

    private static func runActivate() throws {
        let hostDirectory = LOCALBHostRuntime.defaultHostDirectory()
        let expected = try parseCheckpoint(
            ProcessInfo.processInfo.environment["SIMIGO_LOCALB_CHECKPOINT"] ?? ""
        )
        let context = try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: LOCALBHostRuntime.registryRoot(in: hostDirectory),
            operatorRecordedCheckpoint: expected
        )
        // Persist only AFTER the ceremony accepted the operator's checkpoint:
        // the anchor file lives outside the registry the registry verifies.
        try LOCALBHostRuntime.persistTrustedCheckpoint(
            expected, in: hostDirectory
        )
        emit([
            "role": "activate",
            "host_directory": hostDirectory.path,
            "trusted_checkpoint_path": LOCALBHostRuntime
                .checkpointURL(in: hostDirectory).path,
            "lineage_id": context.lineageID,
            "signer_key_id": context.signerKeyID,
            "signer_generation": context.signerGeneration,
            "sequence": expected.sequence,
            "head_hash_hex": expected.headHashHex,
            "transport_spki_sha256": context.transportIdentity.spkiSHA256Hex,
            "operational": true
        ])
    }

    private static func runPairIssue() throws {
        let env = ProcessInfo.processInfo.environment
        let context = try requireOperationalContext()
        let clientKey = try decodeHex(
            env["SIMIGO_LOCALB_CLIENT_PUBKEY_HEX"] ?? "", count: 32
        )
        let scopeLabel = env["SIMIGO_LOCALB_SCOPE"].flatMap {
            $0.isEmpty ? nil : $0
        } ?? "localb-service-http"
        let presentation = try context.pairingCoordinator().issueCredential(
            scopeLabel: scopeLabel,
            tlsSPKIHash: context.transportIdentity.spkiSHA256Hex,
            srsKeyID: context.signerKeyID,
            mode: .strictHeadless,
            expectedClientPublicKeyRaw: clientKey,
            checkpoint: try context.currentTrustedCheckpoint()
        )
        let secret = try presentation.takeSecretBase64URLOnce()
        emit([
            "role": "pair-issue",
            "credential_id": presentation.credentialID,
            "secret_b64url": secret,
            "expires_at_milliseconds": presentation.expiresAtMilliseconds,
            "host_instance_id": presentation.hostInstanceID,
            "tls_spki_sha256": presentation.tlsSPKIHash,
            "srs_key_id": presentation.srsKeyID,
            "protocol_version": presentation.protocolVersion,
            "session_nonce_hex": presentation.sessionNonceHex,
            "scope_label": presentation.scopeLabel,
            "confirmation_mode": "strictHeadless"
        ])
    }

    private static func runPairApprove() throws {
        let env = ProcessInfo.processInfo.environment
        let context = try requireOperationalContext()
        let coordinator = context.pairingCoordinator()
        let submission = LOCALBPairingSubmission(
            credentialID: env["SIMIGO_LOCALB_CREDENTIAL_ID"] ?? "",
            secretRaw: try decodeBase64URL(
                env["SIMIGO_LOCALB_SECRET_B64URL"] ?? ""
            ),
            clientPublicKeyRaw: try decodeHex(
                env["SIMIGO_LOCALB_CLIENT_PUBKEY_HEX"] ?? "", count: 32
            ),
            proofSignatureRaw: try decodeHex(
                env["SIMIGO_LOCALB_PAIRING_PROOF_HEX"] ?? "", count: 64
            ),
            actualTLSSPKIHash: env["SIMIGO_LOCALB_TLS_SPKI_HEX"] ?? "",
            presentedSRSKeyID: env["SIMIGO_LOCALB_SRS_KEY_ID"] ?? "",
            protocolVersion: env["SIMIGO_LOCALB_PROTOCOL_VERSION"].flatMap {
                $0.isEmpty ? nil : $0
            } ?? LOCALBConstants.credentialProtocolVersion
        )
        let pending = try coordinator.preparePairing(
            submission,
            checkpoint: try context.currentTrustedCheckpoint()
        )
        // Strict-headless credentials are pre-bound to one client key, so the
        // interactive operator switch must stay OFF.
        let checkpoint = try coordinator.approveAndRegister(
            pending,
            operatorApproved: false,
            operatorAuthorizationReference: nil,
            checkpoint: try context.currentTrustedCheckpoint()
        )
        emit([
            "role": "pair-approve",
            "client_key_id": pending.clientKeyID,
            "client_key_fingerprint": pending.clientPublicKeyFingerprint,
            "scope_label": pending.scopeLabel,
            "credential_id": pending.credentialID,
            "confirmation_mode": "strictHeadless",
            "registry_sequence": checkpoint.sequence,
            "registry_head_hash_hex": checkpoint.headHashHex
        ])
    }

    /// Starts the inference runtime through the SAME default-resolution call
    /// the product's Start button reaches (`Service` -> `runtime.start` ->
    /// `startWithLOCALB(nil, nil)`). Nothing is injected: the LOCALB host is
    /// resolved from the isolated managed root, and a missing activation
    /// still fails closed with the original typed status.
    private static func runServe() async throws {
        let env = ProcessInfo.processInfo.environment
        let modelPath = env["SIMIGO_LOCALB_SERVE_MODEL"] ?? ""
        let port = Int(env["SIMIGO_LOCALB_SERVE_PORT"] ?? "")
            ?? InferenceNodeDefaults.apiPort
        let info = ModelInfo(path: modelPath, kind: .mlx)
        let runtime = NativeMLX(
            info: info, config: ModelConfig.fromModel(modelPath)
        )
        servingRuntime = runtime
        try await runtime.startWithLOCALB(
            info,
            port: port,
            localbTransportIdentity: nil,
            localbRequestAuthorization: nil
        )
        emit([
            "role": "serve",
            "port": port,
            "model_path": modelPath,
            "binding": "NativeMLX.startWithLOCALB(default LOCALB host resolution)",
            "listening": true
        ])
        while true {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    /// Retained for the process lifetime: releasing it would stop the server.
    private static var servingRuntime: NativeMLX?

    /// Same listener, but reached through the product's own orchestration
    /// surface: `Service.shared.start(path:)` -> `internalStart` ->
    /// `NativeMLX.start(path:port:)` -> `startWithLOCALB(nil, nil)`. Nothing is
    /// injected into either layer: the node address comes from the product's
    /// own resolution (`SIMIGO_PORT`, else the persisted port) and the LOCALB
    /// host from the isolated managed root, so a never-activated host still
    /// refuses before a listener exists.
    private static func runServeService() async throws {
        let env = ProcessInfo.processInfo.environment
        let modelPath = env["SIMIGO_LOCALB_SERVE_MODEL"] ?? ""
        let service = Service.shared

        // The facade catches the runtime's typed throw; a not-running service
        // after `start` therefore IS the fail-closed outcome, and its own status
        // text is the only truthful record of which gate refused.
        await service.start(path: modelPath)

        guard service.isRunning else {
            throw FacadeStartRefused(status: service.status)
        }
        emit([
            "role": "serve-service",
            "binding": "Service.start(path:)",
            "model_path": modelPath,
            "base_url": service.inferenceBaseURL,
            "api_base_url": service.inferenceAPIBaseURL,
            "listening": true,
            "service_is_running": service.isRunning,
            "service_status": service.status
        ])
        while true {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    /// The facade reports failures as status text; this only lifts an existing
    /// `LOCALB_*` token out of it, so a refusal keeps the same typed identity it
    /// would have had on the direct path.
    struct FacadeStartRefused: Error {
        let status: String
    }

    private static func typedStatus(in text: String) -> String {
        for token in text.split(whereSeparator: {
            !($0.isLetter || $0.isNumber || $0 == "_")
        }) where token.hasPrefix("LOCALB_") {
            return String(token)
        }
        return text
    }

    // MARK: - S3-B owner management roles

    /// CSV permission list → enum set. Unknown names fail closed; an empty
    /// list fails closed (a whole-set replacement with nothing is a revoke,
    /// and revocation has its own role).
    static func parsePermissionList(_ csv: String) throws -> Set<LOCALBPermission> {
        var result = Set<LOCALBPermission>()
        for token in csv.split(separator: ",").map({
            $0.trimmingCharacters(in: .whitespaces)
        }) {
            guard !token.isEmpty,
                  let permission = LOCALBPermission(rawValue: token) else {
                throw LOCALBStatus.invalidConfiguration
            }
            result.insert(permission)
        }
        guard !result.isEmpty else { throw LOCALBStatus.invalidConfiguration }
        return result
    }

    private static func requireClient(
        _ coordinator: LOCALBPairingCoordinator,
        clientKeyID: String,
        checkpoint: LOCALBRegistryCheckpoint
    ) throws -> LOCALBClientRegistryEntry {
        guard let client = try coordinator.listClients(checkpoint: checkpoint)
            .first(where: { $0.clientKeyID == clientKeyID }) else {
            throw LOCALBStatus.clientUnknown
        }
        return client
    }

    /// T1: the full client listing — read-only, no journal event.
    static func clientsListPayload(
        context: LOCALBHostRuntimeContext
    ) throws -> [String: Any] {
        let clients = try context.pairingCoordinator().listClients(
            checkpoint: try context.currentTrustedCheckpoint()
        )
        return [
            "role": "clients-list",
            "result": "ok",
            "clients": clients.map {
                [
                    "client_key_id": $0.clientKeyID,
                    "status": $0.status.rawValue,
                    "permissions": $0.permissions.map(\.rawValue).sorted(),
                    "registered_at_milliseconds": $0.registeredAtMilliseconds
                ]
            }
        ]
    }

    /// T2/T3/T7: permissions-set — a WHOLE-SET replacement. The current set
    /// is read and displayed (`from`), the target shown (`to`), and the
    /// journal is touched ONLY under SIMIGO_LOCALB_MGMT_CONFIRM=1. A
    /// confirmed write verifies that the journal sequence advanced by one
    /// and the head hash moved, then proves persistence through a fresh
    /// store opened over the same root (the restart-equivalent read).
    /// Unknown clients, empty/oversized reasons, and unknown permission
    /// names all fail closed before any write.
    static func permissionsSetPayload(
        context: LOCALBHostRuntimeContext,
        env: [String: String]
    ) throws -> [String: Any] {
        let coordinator = context.pairingCoordinator()
        let checkpoint = try context.currentTrustedCheckpoint()
        let clientKeyID = env["SIMIGO_LOCALB_CLIENT_KEY_ID"] ?? ""
        let reason = env["SIMIGO_LOCALB_REASON"] ?? ""
        let client = try requireClient(coordinator, clientKeyID: clientKeyID,
                                       checkpoint: checkpoint)
        guard !reason.isEmpty, reason.utf8.count <= 512 else {
            throw LOCALBStatus.invalidConfiguration
        }
        let to = try parsePermissionList(env["SIMIGO_LOCALB_PERMISSIONS"] ?? "")
        let from = client.permissions
        let confirm = env["SIMIGO_LOCALB_MGMT_CONFIRM"] == "1"

        var payload: [String: Any] = [
            "role": "permissions-set",
            "client_key_id": clientKeyID,
            "from": from.map(\.rawValue).sorted(),
            "to": to.map(\.rawValue).sorted(),
            "reason": reason,
            "confirmed": confirm
        ]

        if !confirm {
            // Dry-run: the journal MUST be untouched. The checkpoint values
            // reported are the pre-write head — the proof that nothing was
            // written is that they are unchanged afterwards.
            payload["result"] = "dry-run"
            payload["sequence"] = checkpoint.sequence
            payload["head_hash_hex"] = checkpoint.headHashHex
            return payload
        }

        let written = try coordinator.setClientPermissions(
            clientKeyID: clientKeyID, permissions: to, reason: reason,
            checkpoint: checkpoint
        )
        // Audit: the journal advanced by exactly one event and the head
        // moved. A write that reports success without both is a defect.
        guard written.sequence == checkpoint.sequence + 1,
              written.headHashHex != checkpoint.headHashHex else {
            throw LOCALBStatus.registryCorrupt
        }
        // Advance the persisted anchor: the next confirmed operation (and
        // the next process) must chain from THIS head, not the stale one.
        try LOCALBHostRuntime.persistTrustedCheckpoint(
            written, in: LOCALBHostRuntime.defaultHostDirectory()
        )
        // Restart-equivalent read: a fresh registry store + coordinator over
        // the same root, public surface only.
        let freshStore = LOCALBRegistryStore(
            rootURL: LOCALBHostRuntime.registryRoot(
                in: LOCALBHostRuntime.defaultHostDirectory()
            )
        )
        let freshCoordinator = LOCALBPairingCoordinator(registryStore: freshStore)
        let reloaded = try freshCoordinator.listClients(checkpoint: written)
        guard reloaded.first(where: { $0.clientKeyID == clientKeyID })?
            .permissions == to else {
            throw LOCALBStatus.registryCorrupt
        }
        payload["result"] = "written"
        payload["sequence"] = written.sequence
        payload["head_hash_hex"] = written.headHashHex
        payload["persisted"] = true
        return payload
    }

    /// T5: client-revoke — confirm-gated like permissions-set. A revoked
    /// client is terminal and observable through the fresh reload; the
    /// revoke of an unknown client fails closed.
    static func clientRevokePayload(
        context: LOCALBHostRuntimeContext,
        env: [String: String]
    ) throws -> [String: Any] {
        let coordinator = context.pairingCoordinator()
        let checkpoint = try context.currentTrustedCheckpoint()
        let clientKeyID = env["SIMIGO_LOCALB_CLIENT_KEY_ID"] ?? ""
        let reason = env["SIMIGO_LOCALB_REASON"] ?? ""
        let client = try requireClient(coordinator, clientKeyID: clientKeyID,
                                       checkpoint: checkpoint)
        guard !reason.isEmpty, reason.utf8.count <= 512 else {
            throw LOCALBStatus.invalidConfiguration
        }
        let confirm = env["SIMIGO_LOCALB_MGMT_CONFIRM"] == "1"

        var payload: [String: Any] = [
            "role": "client-revoke",
            "client_key_id": clientKeyID,
            "status_before": client.status.rawValue,
            "reason": reason,
            "confirmed": confirm
        ]

        if !confirm {
            payload["result"] = "dry-run"
            payload["sequence"] = checkpoint.sequence
            payload["head_hash_hex"] = checkpoint.headHashHex
            return payload
        }

        let written = try coordinator.revokeClient(
            clientKeyID: clientKeyID, reason: reason, checkpoint: checkpoint
        )
        guard written.sequence == checkpoint.sequence + 1,
              written.headHashHex != checkpoint.headHashHex else {
            throw LOCALBStatus.registryCorrupt
        }
        // Advance the persisted anchor: the next confirmed operation (and
        // the next process) must chain from THIS head, not the stale one.
        try LOCALBHostRuntime.persistTrustedCheckpoint(
            written, in: LOCALBHostRuntime.defaultHostDirectory()
        )
        let freshStore = LOCALBRegistryStore(
            rootURL: LOCALBHostRuntime.registryRoot(
                in: LOCALBHostRuntime.defaultHostDirectory()
            )
        )
        let freshCoordinator = LOCALBPairingCoordinator(registryStore: freshStore)
        let reloaded = try freshCoordinator.listClients(checkpoint: written)
        guard reloaded.first(where: { $0.clientKeyID == clientKeyID })?.status
            == .revoked else {
            throw LOCALBStatus.registryCorrupt
        }
        payload["result"] = "written"
        payload["status_after"] = LOCALBClientStatus.revoked.rawValue
        payload["sequence"] = written.sequence
        payload["head_hash_hex"] = written.headHashHex
        payload["persisted"] = true
        return payload
    }

    // MARK: - Helpers

    private static func requireOperationalContext() throws -> LOCALBHostRuntimeContext {
        switch try LOCALBHostRuntime.resolveOperational(
            hostDirectory: LOCALBHostRuntime.defaultHostDirectory()
        ) {
        case .operational(let context):
            return context
        case .notInitialized:
            throw LOCALBStatus.hostNotOperational
        }
    }

    /// `<lineage-uuid>:<sequence>:<head-hash-hex>` — the operator-recorded
    /// string `prepare` printed. Parsing is strict; a malformed record is a
    /// corrupt checkpoint, never a "first run" state.
    private static func parseCheckpoint(
        _ value: String
    ) throws -> LOCALBRegistryCheckpoint {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, let sequence = UInt64(parts[1]) else {
            throw LOCALBStatus.registryCorrupt
        }
        return try LOCALBRegistryCheckpoint(
            lineageID: String(parts[0]),
            sequence: sequence,
            headHash: try decodeHex(String(parts[2]), count: 32)
        )
    }

    private static func decodeHex(_ value: String, count: Int) throws -> [UInt8] {
        let chars = Array(value.utf8)
        guard chars.count == count * 2 else {
            throw LOCALBStatus.invalidConfiguration
        }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
            default: return nil
            }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let high = nibble(chars[index]), let low = nibble(chars[index + 1])
            else { throw LOCALBStatus.invalidConfiguration }
            bytes.append((high << 4) | low)
        }
        return bytes
    }

    private static func decodeBase64URL(_ value: String) throws -> [UInt8] {
        var standard = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard += "=" }
        guard let data = Data(base64Encoded: standard), !data.isEmpty else {
            throw LOCALBStatus.invalidCredentialSecret
        }
        return Array(data)
    }

    /// One-line JSON on stdout: the driving process reads the operator-facing
    /// values from here and never re-derives them.
    private static func emit(_ object: [String: Any]) {
        var payload = object
        payload["pid"] = ProcessInfo.processInfo.processIdentifier
        payload["simigo_home"] = ProcessInfo.processInfo
            .environment["SIMIGO_HOME"] ?? ""
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ), let line = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("mgmt-emit-failed\n".utf8))
            return
        }
        FileHandle.standardError.write(
            Data("mgmt-role-done role=\(object["role"] ?? "?")\n".utf8)
        )
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
