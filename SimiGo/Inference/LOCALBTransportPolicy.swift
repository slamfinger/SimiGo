import Foundation
import LOCALBCore

/// Single LOCALB transport-policy decision point for every HTTPServer
/// construction site in the product (NativeMLX, OversizedRuntime,
/// RemoteOpenAIRuntime). No listener path may bypass it.
///
/// Policy (B1 security-mode matrix, amended by owner ruling 2026-10-26):
/// - LAN bind (non-loopback): ALWAYS secure. A missing or corrupt LOCALB
///   transport identity makes server startup fail closed; plaintext is
///   never a fallback on the LAN. The legacy env opt-in is ignored here.
/// - Loopback bind: PLAINTEXT by default — the local 127.0.0.1:8000 API is
///   the product's own developer/tool surface (plain OpenAI-compatible
///   HTTP, matching the 2.1.x behaviour operators rely on). An operator can
///   still force TLS on loopback with SIMIGO_TRANSPORT=secure; pairing and
///   the proof gate remain active on the secure path wherever it is used.
/// - Identity loading is read-only: the product runtime never creates or
///   repairs identities; creation belongs to the explicit first-run
///   ceremony (LOCALBHostBootstrap.prepareFirstRun).
public enum LOCALBTransportPolicy {
    public enum Decision: Sendable {
        case tls(identity: LOCALBTransportIdentityHandle)
        case legacyPlaintext
        case failClosed(LOCALBStatus)

        var securityMode: HTTPServer.LOCALBSecurityMode {
            switch self {
            case .tls, .failClosed: .secure
            case .legacyPlaintext: .legacyPlaintextCompat
            }
        }
    }

    /// Environment opt-in for the legacy plaintext compatibility mode.
    /// Honored ONLY on loopback binds; never on LAN.
    public static let legacyTransportEnvValue = "legacy-http"

    public static func decide(
        bindHost: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        identityStore: LOCALBTransportIdentityStore = LOCALBTransportIdentityStore()
    ) -> Decision {
        let normalized = bindHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isLoopback = normalized == "127.0.0.1" || normalized == "localhost" || normalized == "::1"

        // Loopback: plaintext is the default (owner ruling 2026-10-26 — the
        // local API is the product's developer/tool surface). SIMIGO_TRANSPORT
        // keeps its legacy meaning; an explicit "secure" forces TLS on
        // loopback for operators who pair local clients.
        if isLoopback {
            let opt = environment["SIMIGO_TRANSPORT"]?.lowercased()
            if opt == "secure" {
                // fall through to the secure path below
            } else {
                return .legacyPlaintext
            }
        }

        // Secure path (mandatory on LAN; loopback only under an explicit
        // SIMIGO_TRANSPORT=secure): the identity must load read-only and be
        // fully verified. Missing or corrupt → fail closed.
        do {
            return .tls(identity: try identityStore.loadExisting())
        } catch let status as LOCALBStatus {
            return .failClosed(status)
        } catch {
            return .failClosed(.transportIdentityMissing)
        }
    }

    /// Applies a decision to a server before start(). A .failClosed decision
    /// leaves the server in secure mode AND records the ORIGINAL typed
    /// status, so start() throws that exact status (corrupt vs missing vs
    /// mismatch) instead of flattening every cause into
    /// transportIdentityMissing.
    public static func apply(
        _ decision: Decision,
        to server: HTTPServer
    ) {
        server.configureLOCALBSecurityMode(decision.securityMode)
        switch decision {
        case .tls(let identity):
            server.configureLOCALBTransport(identity: identity)
        case .failClosed(let status):
            server.recordLOCALBTransportFailure(status)
        case .legacyPlaintext:
            break
        }
    }
}
