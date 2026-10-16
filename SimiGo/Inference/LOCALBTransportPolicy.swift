import Foundation
import LOCALBCore

/// Single LOCALB transport-policy decision point for every HTTPServer
/// construction site in the product (NativeMLX, OversizedRuntime,
/// RemoteOpenAIRuntime). No listener path may bypass it.
///
/// Policy (B1 security-mode matrix):
/// - LAN bind (non-loopback): ALWAYS secure. A missing or corrupt LOCALB
///   transport identity makes server startup fail closed; plaintext is
///   never a fallback on the LAN. The legacy env opt-in is ignored here.
/// - Loopback bind: secure unless the operator EXPLICITLY opts into the
///   legacy plaintext compatibility mode via SIMIGO_TRANSPORT=legacy-http.
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

        if isLoopback,
           environment["SIMIGO_TRANSPORT"]?.lowercased() == legacyTransportEnvValue {
            return .legacyPlaintext
        }

        // Secure path (default; mandatory on LAN): the identity must load
        // read-only and be fully verified. Missing or corrupt → fail closed.
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
