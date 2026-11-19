import Foundation
import AppKit
import SwiftUI
import Combine
import Synchronization
import SystemConfiguration

public enum InferenceNodeDefaults {
    nonisolated public static let apiPort: Int = 8000
    nonisolated public static let defaultBindHost: String = "127.0.0.1"
    nonisolated public static let lanBindHost: String = "0.0.0.0"

    /// Bonjour SRV points to macOS LocalHostName, not the service label or
    /// the potentially DNS-overridden gethostname value.
    nonisolated public static var localAdvertisedHost: String {
        let store = SCDynamicStoreCreate(
            nil,
            "com.slamfinger.SimiGo" as CFString,
            nil,
            nil
        )
        let systemName = store.flatMap {
            SCDynamicStoreCopyLocalHostName($0) as String?
        }
        return advertisedMDNSHost(
            systemLocalHostName: systemName,
            fallbackHostName: ProcessInfo.processInfo.hostName
        )
    }

    nonisolated public static func advertisedMDNSHost(
        systemLocalHostName: String?,
        fallbackHostName: String
    ) -> String {
        let systemName = systemLocalHostName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return mdnsHost(
            from: (systemName?.isEmpty == false ? systemName : nil)
                ?? fallbackHostName
        )
    }

    nonisolated public static func mdnsHost(from hostName: String) -> String {
        let value = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !value.isEmpty else { return "localhost" }
        return value.contains(".") ? value : "\(value).local"
    }

    nonisolated public static func isLANBindHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == lanBindHost || normalized == "::" || normalized == "*"
    }

    /// Keep the local API port stable; LAN TLS uses the adjacent port.
    nonisolated public static func lanListenerPort(forConfiguredPort port: Int) -> Int {
        port == 65535 ? 65534 : port + 1
    }

    /// Reverse a listener port without corrupting the configured-port boundary.
    /// Prefer the known configured value when it already maps to this listener;
    /// derive from the listener only when the shared snapshot is stale.
    nonisolated public static func configuredPort(
        forListenerPort listenerPort: Int,
        isLANEnabled: Bool,
        currentConfiguredPort: Int
    ) -> Int {
        guard isLANEnabled else { return listenerPort }
        if lanListenerPort(forConfiguredPort: currentConfiguredPort) == listenerPort {
            return currentConfiguredPort
        }
        return max(1, min(65535, listenerPort - 1))
    }
}

public struct InferenceNodeConfiguration: Sendable, Equatable {
    public struct Snapshot: Sendable, Equatable {
        public let bindHost: String
        public let advertisedHost: String
        public let port: Int
        public let bonjourEnabled: Bool

        public var isLANEnabled: Bool {
            InferenceNodeDefaults.isLANBindHost(bindHost)
        }

        /// The configured port remains the loopback/API port.
        public var listenerPort: Int {
            isLANEnabled
                ? InferenceNodeDefaults.lanListenerPort(forConfiguredPort: port)
                : port
        }

        /// Separate loopback-only plaintext endpoint for built-in local clients.
        public var localCompatibilityPort: Int? {
            isLANEnabled ? port : nil
        }

        public var scheme: String { isLANEnabled ? "https" : "http" }

        public var baseURLString: String {
            "\(scheme)://\(advertisedHost):\(listenerPort)"
        }

        public var apiBaseURLString: String {
            "\(baseURLString)/v1"
        }

        public var internalHost: String {
            switch bindHost {
            case InferenceNodeDefaults.lanBindHost, "::", "*":
                return InferenceNodeDefaults.defaultBindHost
            default:
                return bindHost
            }
        }

        public var internalBaseURLString: String {
            // Internal health and slot probes use the local plaintext endpoint.
            "http://\(internalHost):\(port)"
        }

        public var healthURLString: String {
            "\(internalBaseURLString)/health"
        }

        public var slotsURLString: String {
            "\(internalBaseURLString)/slots"
        }

        public func url(path: String = "") -> URL? {
            URL(string: "\(baseURLString)\(path)")
        }

        public func internalURL(path: String = "") -> URL? {
            URL(string: "\(internalBaseURLString)\(path)")
        }
    }

    private static let sharedStore = Mutex(
        Snapshot(
            bindHost: InferenceNodeDefaults.defaultBindHost,
            advertisedHost: InferenceNodeDefaults.defaultBindHost,
            port: InferenceNodeDefaults.apiPort,
            bonjourEnabled: true
        )
    )

    private let snapshotValue: Snapshot

    public var bindHost: String { snapshotValue.bindHost }
    public var advertisedHost: String { snapshotValue.advertisedHost }
    /// The primary listener port (TLS when LAN is enabled).
    public var port: Int { snapshotValue.listenerPort }
    public var configuredPort: Int { snapshotValue.port }
    public var localCompatibilityPort: Int? { snapshotValue.localCompatibilityPort }
    public var bonjourEnabled: Bool { snapshotValue.bonjourEnabled }
    public var isLANEnabled: Bool { snapshotValue.isLANEnabled }
    public var baseURLString: String { snapshotValue.baseURLString }
    public var apiBaseURLString: String { snapshotValue.apiBaseURLString }
    public var internalBaseURLString: String { snapshotValue.internalBaseURLString }

    public init(
        bindHost: String = InferenceNodeDefaults.defaultBindHost,
        advertisedHost: String? = nil,
        port: Int = InferenceNodeDefaults.apiPort,
        bonjourEnabled: Bool = true
    ) {
        let normalizedBindHost = Self.normalizeHost(bindHost)
        let resolvedAdvertisedHost = Self.normalizeHost(
            advertisedHost ?? Self.defaultAdvertisedHost(for: normalizedBindHost))

        self.snapshotValue = Snapshot(
            bindHost: normalizedBindHost,
            advertisedHost: resolvedAdvertisedHost,
            port: port,
            bonjourEnabled: bonjourEnabled
        )
    }

    public func snapshot() -> Snapshot {
        snapshotValue
    }

    public static var shared: InferenceNodeConfiguration {
        sharedStore.withLock { value in
            InferenceNodeConfiguration(snapshot: value)
        }
    }

    public static func configure(
        bindHost: String,
        advertisedHost: String? = nil,
        port: Int = InferenceNodeDefaults.apiPort,
        bonjourEnabled: Bool = true
    ) {
        let normalizedBindHost = normalizeHost(bindHost)
        let resolvedAdvertisedHost = normalizeHost(
            advertisedHost ?? defaultAdvertisedHost(for: normalizedBindHost))

        let snapshot = Snapshot(
            bindHost: normalizedBindHost,
            advertisedHost: resolvedAdvertisedHost,
            port: port,
            bonjourEnabled: bonjourEnabled
        )

        sharedStore.withLock { value in
            value = snapshot
        }
    }

    public static func configureLocal(
        port: Int = InferenceNodeDefaults.apiPort,
        bonjourEnabled: Bool = true
    ) {
        configure(
            bindHost: InferenceNodeDefaults.defaultBindHost,
            advertisedHost: InferenceNodeDefaults.defaultBindHost,
            port: port,
            bonjourEnabled: bonjourEnabled
        )
    }

    public static func configureLAN(
        advertisedHost: String = InferenceNodeDefaults.localAdvertisedHost,
        port: Int = InferenceNodeDefaults.apiPort,
        bonjourEnabled: Bool = true
    ) {
        configure(
            bindHost: InferenceNodeDefaults.lanBindHost,
            advertisedHost: advertisedHost,
            port: port,
            bonjourEnabled: bonjourEnabled
        )
    }

    public static func fromEnvironment(
        defaultPort: Int = InferenceNodeDefaults.apiPort
    ) -> InferenceNodeConfiguration {
        let environment = ProcessInfo.processInfo.environment

        let bindHost = normalizeHost(
            environment["SIMIGO_HOST"] ?? InferenceNodeDefaults.defaultBindHost
        )

        let advertisedHost = environment["SIMIGO_ADVERTISED_HOST"].map(normalizeHost)

        let port = Int(environment["SIMIGO_PORT"] ?? "") ?? defaultPort

        let bonjourEnabled: Bool = {
            guard let raw = environment["SIMIGO_BONJOUR"]?.lowercased() else { return true }
            return raw != "0" && raw != "false" && raw != "off"
        }()

        return InferenceNodeConfiguration(
            bindHost: bindHost,
            advertisedHost: advertisedHost,
            port: port,
            bonjourEnabled: bonjourEnabled
        )
    }

    private init(snapshot: Snapshot) {
        self.snapshotValue = snapshot
    }

    private static func defaultAdvertisedHost(for bindHost: String) -> String {
        InferenceNodeDefaults.isLANBindHost(bindHost)
            ? InferenceNodeDefaults.localAdvertisedHost
            : bindHost
    }

    private static func normalizeHost(_ host: String) -> String {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? InferenceNodeDefaults.defaultBindHost : value
    }
}
