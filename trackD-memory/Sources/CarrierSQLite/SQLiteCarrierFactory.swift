import Foundation
import CarrierInterface

/// C7 integrity reporter for the A1 composition: registry cross-checks plus
/// POSIX entity-file verification (digest match, orphans on disk).
public struct SQLiteCarrierIntegrityReporter: CarrierIntegrityReporter {
    let core: SQLiteCore
    let entities: POSIXEntityStore

    public func integrityReport() async throws -> CarrierIntegrityReport {
        var issues: [CarrierIntegrityIssue] = []

        let representationRows = try await core.query(
            "SELECT representation_id, information_id, revision_id, digest, byte_count, media_type, created_at FROM representations",
            read: POSIXEntityStore.readRepresentation
        )
        let locatorRows = try await core.query(
            """
            SELECT locator_id, information_id, revision_id, representation_id, scheme, value, created_at, retired_at
            FROM locators
            """,
            read: SQLiteLocatorIndex.read
        )
        let availabilityRows = try await core.query(
            "SELECT information_id, revision_id, representation_id, state, reason, observed_at FROM availability ORDER BY seq",
            read: SQLiteAvailabilityStore.read
        )

        var referencedDigests: Set<String> = []
        for representation in representationRows {
            referencedDigests.insert(representation.digest)
            let matching = locatorRows.filter { $0.representationID == representation.representationID }
            if matching.isEmpty {
                issues.append(
                    CarrierIntegrityIssue(
                        kind: .orphanRepresentation,
                        informationID: representation.informationID,
                        representationID: representation.representationID,
                        detail: "representation has no locator record"
                    )
                )
            }
            for locator in matching where
                locator.informationID != representation.informationID ||
                locator.revisionID != representation.revisionID {
                issues.append(
                    CarrierIntegrityIssue(
                        kind: .locatorMismatch,
                        informationID: locator.informationID,
                        representationID: locator.representationID,
                        detail: "locator endpoints do not match representation"
                    )
                )
            }
            let observed = availabilityRows.last { $0.representationID == representation.representationID }
            if observed == nil {
                issues.append(
                    CarrierIntegrityIssue(
                        kind: .unavailableCurrentObject,
                        informationID: representation.informationID,
                        representationID: representation.representationID,
                        detail: "representation has no availability observation"
                    )
                )
            }
        }

        for orphanDigest in try entities.orphanFiles(referenced: referencedDigests) {
            issues.append(
                CarrierIntegrityIssue(
                    kind: .orphanRepresentation,
                    informationID: nil,
                    representationID: nil,
                    detail: "entity file \(orphanDigest) is not referenced by the registry"
                )
            )
        }

        return CarrierIntegrityReport(issues: issues, checkedAt: Date())
    }
}

extension SQLiteCarrierFactory {
    /// Smoke-level backup (G8): consistent DB snapshot + entity copy.
    /// F8 trap fires after the DB snapshot, before the entity copy.
    public func backup(from: SQLiteCarrierBundle, to dest: URL) async throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try await from.core.runOutsideTransaction("VACUUM INTO ?", bind: { $0.bindText(1, dest.appendingPathComponent("registry.sqlite").path) })
        CrashGate.trap("F8")
        let entities = rootURL.appendingPathComponent("entities")
        let destEntities = dest.appendingPathComponent("entities")
        if FileManager.default.fileExists(atPath: entities.path) {
            try FileManager.default.copyItem(at: entities, to: destEntities)
        }
        try? "".write(to: dest.appendingPathComponent("BACKUP_COMPLETE"), atomically: true, encoding: .utf8)
    }

    /// Restore a completed backup into a fresh root. F9 trap fires after the
    /// entity copy, before the completion marker.
    public func restore(from backup: URL, to target: URL) throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: backup.appendingPathComponent("registry.sqlite"),
                                         to: target.appendingPathComponent("registry.sqlite"))
        if FileManager.default.fileExists(atPath: backup.appendingPathComponent("entities").path) {
            try FileManager.default.copyItem(at: backup.appendingPathComponent("entities"),
                                             to: target.appendingPathComponent("entities"))
        }
        CrashGate.trap("F9")
        try? "".write(to: target.appendingPathComponent("RESTORE_COMPLETE"), atomically: true, encoding: .utf8)
    }
}

/// A1 composition root: SQLite registry + FTS5 search + POSIX entity store,
/// composed into the shared carrier-neutral runtime.
public struct SQLiteCarrierBundle: Sendable {
    public let runtime: InformationSpaceRuntime
    public let core: SQLiteCore
    public let representations: POSIXEntityStore
    public let integrity: SQLiteCarrierIntegrityReporter
}

public struct SQLiteCarrierFactory: Sendable {
    public let rootURL: URL

    /// - Parameters:
    ///   - rootURL: isolated data root; the database and entity store live here.
    ///     Must be outside the Lab working tree (frozen protocol PB-F4).
    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func make() throws -> SQLiteCarrierBundle {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let core = try SQLiteCore(path: rootURL.appendingPathComponent("registry.sqlite").path)
        let representations = POSIXEntityStore(core: core, rootURL: rootURL)
        let integrity = SQLiteCarrierIntegrityReporter(core: core, entities: representations)
        let runtime = InformationSpaceRuntime(
            composition: CarrierComposition(
                registry: SQLiteInformationRegistry(core: core),
                representations: representations,
                locators: SQLiteLocatorIndex(core: core),
                relations: SQLiteRelationHistoryStore(core: core),
                sessions: SQLiteSessionInformationStore(core: core),
                search: SQLiteDerivedSearchIndex(core: core),
                availability: SQLiteAvailabilityStore(core: core),
                integrity: integrity
            )
        )
        return SQLiteCarrierBundle(
            runtime: runtime,
            core: core,
            representations: representations,
            integrity: integrity
        )
    }
}

/// CarrierRuntimeFactory conformance for the conformance suite. Each suite
/// run gets a fresh isolated temporary data root.
public struct SQLiteTemporaryRuntimeFactory: CarrierRuntimeFactory {
    public init() {}

    public func make() async throws -> InformationSpaceRuntime {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccvs01-a1-\(UUID().uuidString)", isDirectory: true)
        return try SQLiteCarrierFactory(rootURL: root).make().runtime
    }
}
