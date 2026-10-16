import Foundation
import LOCALBCore

/// Production lifecycle adapter between the LOCALB first-run ceremony and
/// every default HTTPServer construction site (NativeMLX, OversizedRuntime,
/// RemoteOpenAIRuntime). When the host has completed first-run activation,
/// ordinary startup resolves a fully verified `LOCALBHostRuntimeContext`
/// from the standard host directory and configures BOTH the TLS transport
/// identity AND request authorization from that one context. When the host
/// has NOT been activated, startup falls back to the transport-only secure
/// default and protected routes stay fail-closed (503) — availability is
/// never restored by opening protected routes.
///
/// A persisted trusted checkpoint that fails registry verification is a
/// fail-closed condition: `resolveOperational` throws the typed
/// LOCALBStatus instead of silently degrading to a weaker configuration.
enum LOCALBHostRuntime {

    static let registryDirectoryName = "registry"
    static let checkpointFileName = "trusted-checkpoint.json"

    /// Standard host directory: `~/.simigo/localb`.
    static func defaultHostDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo", isDirectory: true)
            .appendingPathComponent("localb", isDirectory: true)
    }

    static func registryRoot(in hostDirectory: URL) -> URL {
        hostDirectory.appendingPathComponent(
            registryDirectoryName, isDirectory: true
        )
    }

    static func checkpointURL(in hostDirectory: URL) -> URL {
        hostDirectory.appendingPathComponent(checkpointFileName)
    }

    enum Resolution {
        /// The host completed first-run activation and opened operational
        /// with a fully verified registry/keychain/transport identity.
        case operational(LOCALBHostRuntimeContext)
        /// No trusted checkpoint exists yet (first-run ceremony not done).
        /// Protected routes remain fail-closed under the transport policy.
        case notInitialized
    }

    private struct CheckpointFile: Codable {
        let lineageID: String
        let sequence: UInt64
        let headHashHex: String
    }

    /// Persists the operator-recorded checkpoint at activation time. The
    /// file lives OUTSIDE the registry directory by design: the registry
    /// must verify against a checkpoint it cannot rewrite. Called only by
    /// the activation ceremony; ordinary startup reads it, never writes it.
    static func persistTrustedCheckpoint(
        _ checkpoint: LOCALBRegistryCheckpoint,
        in hostDirectory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: hostDirectory,
            withIntermediateDirectories: true
        )
        let payload = CheckpointFile(
            lineageID: checkpoint.lineageID,
            sequence: checkpoint.sequence,
            headHashHex: Self.encodeLowerHex(checkpoint.headHash)
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(
            to: checkpointURL(in: hostDirectory),
            options: [.atomic, .completeFileProtection]
        )
    }

    /// Loads the persisted trusted checkpoint. Returns nil only when the
    /// file is absent (host not activated); a present-but-corrupt file is a
    /// fail-closed error, not a silent first-run state.
    static func loadPersistedTrustedCheckpoint(
        in hostDirectory: URL
    ) throws -> LOCALBRegistryCheckpoint? {
        let url = checkpointURL(in: hostDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LOCALBStatus.registryCorrupt
        }
        guard let payload = try? JSONDecoder().decode(
            CheckpointFile.self, from: data
        ),
              let headHash = Self.decodeLowerHex(
            payload.headHashHex, count: 32
        )
        else {
            throw LOCALBStatus.registryCorrupt
        }
        return try LOCALBRegistryCheckpoint(
            lineageID: payload.lineageID,
            sequence: payload.sequence,
            headHash: headHash
        )
    }

    /// Lower-case hex encode (LOCALBBinary is package-internal).
    private static func encodeLowerHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Lower-case hex decode of exactly `count` bytes; any other shape is
    /// treated as a corrupt checkpoint file.
    private static func decodeLowerHex(
        _ value: String, count: Int
    ) -> [UInt8]? {
        let chars = Array(value.utf8)
        guard chars.count == count * 2 else { return nil }
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
        bytes.reserveCapacity(count)
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

    /// Ordinary-startup resolution. Never creates or repairs any key or
    /// registry state; verification failures propagate as typed
    /// LOCALBStatus errors for fail-closed startup.
    static func resolveOperational(
        hostDirectory: URL,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) throws -> Resolution {
        guard let checkpoint = try loadPersistedTrustedCheckpoint(
            in: hostDirectory
        ) else {
            return .notInitialized
        }
        let context = try LOCALBHostBootstrap.openOperational(
            rootURL: registryRoot(in: hostDirectory),
            trustedCheckpoint: checkpoint,
            keychainStore: keychainStore,
            transportIdentityStore: transportIdentityStore
        )
        return .operational(context)
    }

    /// Default-path wiring for every HTTPServer construction site with no
    /// caller-supplied LOCALB configuration. Operational host → transport
    /// identity + request authorization from one verified context (the
    /// legacy plaintext opt-in is IGNORED here: an activated host never
    /// serves protected routes in the clear). Not activated → transport
    /// policy only; protected routes stay fail-closed.
    static func applyDefault(
        to server: HTTPServer,
        bindHost: String,
        hostDirectory: URL? = nil,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) throws {
        let directory = hostDirectory ?? defaultHostDirectory()
        switch try resolveOperational(
            hostDirectory: directory,
            keychainStore: keychainStore,
            transportIdentityStore: transportIdentityStore
        ) {
        case .operational(let context):
            server.configureLOCALBTransport(identity: context.transportIdentity)
            server.configureLOCALBRequestAuthorization(
                coordinator: context.pairingCoordinator(),
                trustedCheckpoint: { try context.currentTrustedCheckpoint() }
            )
        case .notInitialized:
            LOCALBTransportPolicy.apply(
                LOCALBTransportPolicy.decide(
                    bindHost: bindHost,
                    identityStore: transportIdentityStore
                ),
                to: server
            )
        }
    }
}
