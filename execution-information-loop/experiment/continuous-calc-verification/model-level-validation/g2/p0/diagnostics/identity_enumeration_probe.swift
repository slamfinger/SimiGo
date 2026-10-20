import Foundation
import CryptoKit

// Reproduces the enumeration rule of `EngineModelIdentity.compute`
// (EngineSessionBaseline.swift) on a given model directory and reports what it
// actually sees. No model is loaded; this only walks the filesystem.
//
// Purpose: explain the P0 reading `weights_digest == e3b0c442…` (the digest of
// the empty string) on an artifact that is demonstrably present.

let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let fm = FileManager.default
let enumeratorKeys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
let probeKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]

var yielded = 0
var regularTrue = 0
var symlinkTrue = 0
var weightLines: [String] = []
var tokenizerData = Data()

if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: enumeratorKeys) {
    for case let url as URL in enumerator {
        yielded += 1
        let values = try? url.resourceValues(forKeys: probeKeys)
        let all = try? url.resourceValues(forKeys: probeKeys)
        if all?.isSymbolicLink == true { symlinkTrue += 1 }
        guard values?.isRegularFile == true else { continue }
        regularTrue += 1
        let size = values?.fileSize ?? 0
        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
        let name = url.lastPathComponent
        if name.hasSuffix(".safetensors") {
            var hasher = SHA256()
            if let handle = try? FileHandle(forReadingFrom: url) {
                while true {
                    let chunk = handle.readData(ofLength: 1 << 20)
                    if chunk.isEmpty { break }
                    hasher.update(data: chunk)
                }
                try? handle.close()
            }
            let contentDigest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            weightLines.append("\(rel):\(size):\(contentDigest)")
        }
        let isTokenizerLike =
            name.hasPrefix("tokenizer") || name == "special_tokens_map.json"
            || name.hasPrefix("merges") || name.hasPrefix("vocab")
            || name.hasPrefix("chat_template")
        if isTokenizerLike, size <= 8 * 1024 * 1024,
            let contents = try? Data(contentsOf: url) {
            tokenizerData.append(contents)
        }
    }
}

func digest(_ lines: [String]) -> String {
    let canonical = lines.joined(separator: "\n")
    return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
}

print("""
{
  "root": "\(root.path)",
  "entries_yielded": \(yielded),
  "is_regular_file_true": \(regularTrue),
  "is_symbolic_link_true": \(symlinkTrue),
  "weight_lines": \(weightLines.count),
  "weights_digest": "\(digest(weightLines.sorted()))",
  "tokenizer_bytes_appended": \(tokenizerData.count),
  "tokenizer_digest": "\(digest([String(decoding: tokenizerData, as: UTF8.self)]))",
  "empty_digest": "\(digest([]))"
}
""")
