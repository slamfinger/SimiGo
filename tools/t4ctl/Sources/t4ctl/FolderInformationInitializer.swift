import Foundation
import InformationCore

/// Minimal first-snapshot initializer for a physical folder.
///
/// It observes the current folder tree, forms Information for text files and
/// directory inventories, and persists them through the existing SQLiteStore.
/// It does not copy payloads, watch changes, or add new semantics.
struct FolderInformationInitializer {
  enum ExtractionStatus: String, Codable, Sendable {
    case stored
    case skipped
    case failed
  }

  enum InitializationError: Error, LocalizedError {
    case folderDoesNotExist(String)
    case notADirectory(String)
    case enumerationFailed(String, underlying: Error)

    var errorDescription: String? {
      switch self {
      case .folderDoesNotExist(let path):
        return "folder does not exist: \(path)"
      case .notADirectory(let path):
        return "not a directory: \(path)"
      case .enumerationFailed(let path, let underlying):
        return "could not enumerate folder \(path): \(underlying)"
      }
    }
  }

  struct Entry: Codable, Sendable {
    let identity: String
    let source: String
    let extractionStatus: ExtractionStatus
    let extractionMode: String?
    let contentLength: Int?
    let sourceTime: Date?
    let reason: String?
  }

  struct Report: Codable, Sendable {
    let folder: String
    let database: String
    let directoriesScanned: Int
    let filesScanned: Int
    let informationFormed: Int
    let informationStored: Int
    let extractionSucceeded: Int
    let extractionSkipped: Int
    let extractionFailed: Int
    let entries: [Entry]
    let failures: [String]
  }

  private let producedAt: Date
  private let producedBy = "t4ctl-folder-initializer"

  init(producedAt: Date = Date()) {
    self.producedAt = producedAt
  }

  func initialize(folderPath: String, databasePath: String) throws -> Report {
    let rootURL = URL(fileURLWithPath: folderPath, isDirectory: true).resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
      throw InitializationError.folderDoesNotExist(rootURL.path)
    }
    guard isDirectory.boolValue else {
      throw InitializationError.notADirectory(rootURL.path)
    }

    let store = try SQLiteStore(path: databasePath)
    var entries: [Entry] = []
    var failures: [String] = []
    var directoriesScanned = 0
    var filesScanned = 0
    var formed = 0
    var stored = 0
    var succeeded = 0
    var skipped = 0
    var failed = 0

    func sourceTime(_ url: URL) -> Date? {
      try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func appendEntry(
      identity: InformationID,
      source: URL,
      status: ExtractionStatus,
      mode: String?,
      content: String?,
      reason: String?
    ) {
      entries.append(
        Entry(
          identity: identity.rawValue,
          source: source.path,
          extractionStatus: status,
          extractionMode: mode,
          contentLength: content?.utf8.count,
          sourceTime: sourceTime(source),
          reason: reason
        ))
    }

    func storeInformation(_ content: String, source: URL, mode: String) throws {
      let provenance = Provenance(
        producedAt: producedAt,
        producedBy: producedBy,
        source: source.path,
        sourceTime: sourceTime(source),
        extractionMode: mode
      )
      let identity = store.makeInformationID(content: content, provenance: provenance)
      let information = Information(
        identity: identity,
        content: content,
        provenance: provenance
      )
      appendEntry(
        identity: identity,
        source: source,
        status: .stored,
        mode: mode,
        content: content,
        reason: nil
      )
      formed += 1
      succeeded += 1
      try store.store(information)
      stored += 1
    }

    func inventoryContent(for directory: URL, directChildren: [URL]) -> String {
      let names =
        directChildren
        .map { child -> (isDirectory: Bool, name: String) in
          let isDirectory =
            (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
          return (isDirectory, child.lastPathComponent)
        }
        .sorted {
          if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
          return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        .map { "\($0.isDirectory ? "directory" : "file")\t\($0.name)" }
        .joined(separator: "\n")

      return """
        FOLDER_SNAPSHOT
        path\t\(directory.path)
        direct_entries\t\(directChildren.count)
        \(names)
        """
    }

    func scan(directory: URL) throws {
      directoriesScanned += 1
      let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [
          .isDirectoryKey, .isRegularFileKey, .contentModificationDateKey,
        ],
        options: []
      )

      _ = try storeInformation(
        inventoryContent(for: directory, directChildren: contents),
        source: directory,
        mode: "directory-inventory"
      )

      for item in contents.sorted(by: { $0.path < $1.path }) {
        let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let isDirectory = values.isDirectory ?? false
        let isRegularFile = values.isRegularFile ?? false
        let child = directory.appendingPathComponent(
          item.lastPathComponent,
          isDirectory: isDirectory
        )

        if isDirectory {
          try scan(directory: child)
          continue
        }
        guard isRegularFile else {
          filesScanned += 1
          skipped += 1
          appendEntry(
            identity: InformationID(rawValue: "not-formed:\(child.path)"),
            source: child,
            status: .skipped,
            mode: nil,
            content: nil,
            reason: "not a regular file"
          )
          continue
        }

        filesScanned += 1
        let name = child.lastPathComponent.lowercased()
        guard name.hasSuffix(".txt") || name.hasSuffix(".md") || name.hasSuffix(".markdown") else {
          skipped += 1
          appendEntry(
            identity: InformationID(rawValue: "not-formed:\(child.path)"),
            source: child,
            status: .skipped,
            mode: nil,
            content: nil,
            reason: "unsupported or non-text format"
          )
          continue
        }

        do {
          let content = try String(contentsOf: child, encoding: .utf8)
          if content.isEmpty {
            skipped += 1
            appendEntry(
              identity: InformationID(rawValue: "not-formed:\(child.path)"),
              source: child,
              status: .skipped,
              mode: "verbatim-text",
              content: nil,
              reason: "empty text is not representable by current SQLiteStore decode"
            )
          } else {
            try storeInformation(content, source: child, mode: "verbatim-text")
          }
        } catch {
          failed += 1
          let reason = "text extraction failed: \(error)"
          failures.append("\(child.path): \(reason)")
          appendEntry(
            identity: InformationID(rawValue: "not-formed:\(child.path)"),
            source: child,
            status: .failed,
            mode: "verbatim-text",
            content: nil,
            reason: reason
          )
        }
      }
    }

    do {
      try scan(directory: rootURL)
    } catch {
      throw InitializationError.enumerationFailed(rootURL.path, underlying: error)
    }

    return Report(
      folder: rootURL.path,
      database: URL(fileURLWithPath: databasePath).standardizedFileURL.path,
      directoriesScanned: directoriesScanned,
      filesScanned: filesScanned,
      informationFormed: formed,
      informationStored: stored,
      extractionSucceeded: succeeded,
      extractionSkipped: skipped,
      extractionFailed: failed,
      entries: entries,
      failures: failures
    )
  }
}
