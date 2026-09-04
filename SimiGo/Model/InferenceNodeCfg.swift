import Foundation
import AppKit
import SwiftUI
import Combine
import Synchronization

public enum InferenceNodeDefaults {
    nonisolated public static let apiPort: Int = 8000
    nonisolated public static let defaultBindHost: String = "127.0.0.1"
    nonisolated public static let lanBindHost: String = "0.0.0.0"
}

public struct InferenceNodeConfiguration: Sendable, Equatable {
    public struct Snapshot: Sendable, Equatable {
        public let bindHost: String
        public let advertisedHost: String
        public let port: Int
        public let bonjourEnabled: Bool

        public var isLANEnabled: Bool {
            bindHost == InferenceNodeDefaults.lanBindHost || bindHost == "::" || bindHost == "*"
        }

        public var scheme: String { "http" }

        public var baseURLString: String {
            "\(scheme)://\(advertisedHost):\(port)"
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
            "\(scheme)://\(internalHost):\(port)"
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
    public var port: Int { snapshotValue.port }
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
        let resolvedAdvertisedHost = Self.normalizeHost(advertisedHost ?? normalizedBindHost)

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
        let resolvedAdvertisedHost = normalizeHost(advertisedHost ?? normalizedBindHost)

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
        advertisedHost: String = "SimiGo.local",
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

        let advertisedHost = normalizeHost(
            environment["SIMIGO_ADVERTISED_HOST"] ?? bindHost
        )

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

    private static func normalizeHost(_ host: String) -> String {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? InferenceNodeDefaults.defaultBindHost : value
    }
}
