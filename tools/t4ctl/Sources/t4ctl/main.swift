// t4ctl — T4 execution boundary tool.
// Thin wrapper over the frozen InformationStore contract (S1–S6):
// initialize a physical folder, store a file's verbatim content, or fetch
// by identity. No query, list, delete, or semantics beyond the ruled contract.

import Foundation
import InformationCore

func usage() -> Never {
  print(
    """
    usage:
      t4ctl initialize <folder-path> [database-path]
      t4ctl store --db <path> --file <path>
      t4ctl fetch --db <path> --identity <id> --out <path>
    """
  )
  exit(2)
}

func arg(_ name: String) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  return args[i + 1]
}

let args = CommandLine.arguments
guard args.count >= 2 else { usage() }

if args[1] == "initialize" {
  guard args.count >= 3 else { usage() }
  let folderPath = args[2]
  let databasePath = args.count > 3 ? args[3] : folderPath + ".information.sqlite"
  let initializer = FolderInformationInitializer()
  let report = try initializer.initialize(
    folderPath: folderPath,
    databasePath: databasePath
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  print(String(decoding: try encoder.encode(report), as: UTF8.self))
  exit(0)
}

let dbPath = arg("--db") ?? (ProcessInfo.processInfo.environment["T4_DB"] ?? "")
if dbPath.isEmpty { usage() }
let store = try SQLiteStore(path: dbPath)

switch args[1] {
case "store":
  guard let file = arg("--file") else { usage() }
  let content = try String(contentsOfFile: file, encoding: .utf8)
  let provenance = Provenance(
    producedAt: Date(),
    producedBy: "t4ctl",
    source: (file as NSString).lastPathComponent
  )
  let identity = store.makeInformationID(content: content, provenance: provenance)
  let information = Information(
    identity: identity,
    content: content,
    provenance: provenance
  )
  try store.store(information)  // first-write-wins (S3 mirror)
  print("identity=\(identity.rawValue)")

case "fetch":
  guard let id = arg("--identity"), let out = arg("--out") else { usage() }
  let information = try store.fetch(by: InformationID(rawValue: id))
  guard let information else {
    print("not-found")
    exit(0)
  }
  try information.content.write(toFile: out, atomically: true, encoding: .utf8)
  print("found identity=\(information.identity.rawValue)")

default:
  usage()
}
