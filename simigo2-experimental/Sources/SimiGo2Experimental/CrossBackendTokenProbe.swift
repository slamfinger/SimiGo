import Crypto
import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// Two-phase, resource-isolated same-token-prefix observation. Phase 1 runs
/// only MLX and records rendered prompt IDs plus greedy outputs. Phase 2 runs
/// only llama-server and compares the recorded token IDs. The backends are
/// never resident in the same research process interval.
public enum CrossBackendTokenProbe {
  public static let steadySwapDeltaLimitBytes: Int64 = 512 * 1024 * 1024
  public static let loadSwapDeltaLimitBytes: Int64 = 1536 * 1024 * 1024

  public struct ResourceSnapshot: Codable, Sendable {
    public let label: String
    public let tMilliseconds: Int64
    public let physFootprintBytes: Int64
    public let residentBytes: Int64
    public let swapUsedBytes: Int64
    public let mlxActiveBytes: Int64
    public let mlxCacheBytes: Int64
    public let mlxPeakBytes: Int64
  }

  public struct RecordCase: Codable, Sendable {
    public let promptID: String
    public let family: String
    public let prompt: String
    public let promptTokenIDs: [Int]
    public let mlxGeneratedTokenIDs: [Int]
    public let mlxText: String
  }

  public struct ResourceChecks: Codable, Sendable {
    public let steadySwapDeltaLimitBytes: Int64
    public let loadSwapDeltaLimitBytes: Int64
    public let maxSwapDeltaBytes: Int64
    public let loadSwapDeltaBytes: Int64
    public let steadySwapDeltaBytes: Int64
    public let swapSamplesValid: Bool
    public let swapDeltaWithinLimit: Bool
  }

  public struct Record: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let mlxModelDirectory: String
    public let mlxModelType: String
    public let maxTokens: Int
    public let cases: [RecordCase]
    public let resource: ResourceChecks
    public let resourceSnapshots: [ResourceSnapshot]
    public let checks: [String: Bool]
    public let overallPass: Bool
  }

  public struct CompareCase: Codable, Sendable {
    public let promptID: String
    public let family: String
    public let prompt: String
    public let promptTokenIDs: [Int]
    public let mlxGeneratedTokenIDs: [Int]
    public let llamaGeneratedTokenIDs: [Int]
    public let mlxText: String
    public let llamaText: String
    public let tokenSequenceIdentical: Bool
    public let textIdentical: Bool
  }

  public struct CompareReport: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let recordPath: String
    public let recordSHA256: String
    public let llamaModelPath: String?
    public let host: String
    public let port: Int
    public let maxTokens: Int
    public let seed: Int
    public let cases: [CompareCase]
    public let resource: ResourceChecks
    public let resourceSnapshots: [ResourceSnapshot]
    public let checks: [String: Bool]
    public let outputIdentity: Bool
    public let identicalCaseCount: Int
    public let mismatchedCaseCount: Int
    public let identityRatio: Double
    public let overallPass: Bool
  }

  public static let recordProtocolVersion = "LAB.CROSSBACKEND.RAWTOKEN.RECORD.V2"
  public static let compareProtocolVersion = "LAB.CROSSBACKEND.RAWTOKEN.COMPARE.V2"
  public static let recordBoundary =
    "PHASE1_MLX_ONLY / CHECKPOINT_CHAT_TEMPLATE / GREEDY_TOKEN_RECORD / "
    + "RESOURCE_ISOLATION_SNAPSHOT / NOT_A_CROSSBACKEND_RESULT"
  public static let compareBoundary =
    "PHASE2_LLAMA_ONLY_AFTER_MLX_EXIT / SAME_RECORDED_TOKEN_PREFIX / "
    + "DIFFERENT_QUANTIZATION_AND_EXECUTION_ENGINES / NOT_A_SAME_CHECKPOINT_CLOSURE"

  static let prompts: [(id: String, family: String, text: String)] = [
    ("P1", "baseline", "Return exactly one word: ping"),
    ("P2", "counting", "Count from one to twelve."),
    ("P3", "list", "Name five colors."),
    ("P4", "code-transform", "Rewrite this Python function as a one-line lambda: def add(a, b): return a + b"),
    ("P5", "exact-json", "Return only this JSON and nothing else: {\"ok\":true}"),
    ("P6", "cjk", "用一句话解释什么是缓存。"),
    ("P7", "ambiguous-continuation", "Return the next number only: 2, 4, 8,"),
    ("P8", "long-prefix-code", "Analyze this Swift function and name its access level in one word: private func score(values: [Double]) -> Double? { guard !values.isEmpty else { return nil }; return values.reduce(0, +) / Double(values.count) }"),
    ("P9", "constraint", "Say only: READY"),
    ("P10", "repeat", "Repeat exactly: ABC ABC ABC"),
    ("P11", "docstring", "Complete the Python docstring in one sentence: def median(values):\n    \"\"\""),
    ("P12", "risk", "Explain one risk of force unwrapping in Swift."),
  ]

  static func globalSwapUsedBytes() -> Int64 {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
    process.arguments = ["-n", "vm.swapusage"]
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return -1 }
      let raw = String(decoding: data, as: UTF8.self)
      let parts = raw
        .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" })
        .map(String.init)
      guard let usedIndex = parts.firstIndex(of: "used") else { return -1 }
      for token in parts[(usedIndex + 1)...] {
        let digits = token.filter { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else { continue }
        let multiplier: Double
        if token.lowercased().hasSuffix("g") { multiplier = 1024 * 1024 * 1024 }
        else if token.lowercased().hasSuffix("m") { multiplier = 1024 * 1024 }
        else if token.lowercased().hasSuffix("k") { multiplier = 1024 }
        else { multiplier = 1 }
        return Int64((value * multiplier).rounded())
      }
      return -1
    } catch {
      return -1
    }
  }

  static func snapshot(
    _ label: String, start: ContinuousClock.Instant, baselineSwap: Int64
  ) -> ResourceSnapshot {
    let (footprint, resident) = O2BaselineProbe.physFootprintAndResident()
    let swapUsed = globalSwapUsedBytes()
    let mlx = Memory.snapshot()
    return ResourceSnapshot(
      label: label,
      tMilliseconds: Int64(
        Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000
      ),
      physFootprintBytes: footprint,
      residentBytes: resident,
      swapUsedBytes: swapUsed,
      mlxActiveBytes: Int64(mlx.activeMemory),
      mlxCacheBytes: Int64(mlx.cacheMemory),
      mlxPeakBytes: Int64(mlx.peakMemory)
    )
  }

  static func resourceChecks(
    snapshots: [ResourceSnapshot], baselineSwap: Int64, loadLabel: String? = nil
  ) -> ResourceChecks {
    let samplesValid = !snapshots.isEmpty && snapshots.allSatisfy { $0.swapUsedBytes >= 0 }
    let maxDelta = samplesValid
      ? snapshots.map { max(0, $0.swapUsedBytes - baselineSwap) }.max() ?? 0
      : Int64.max
    let loadSnapshot = loadLabel.flatMap { label in snapshots.first { $0.label == label } }
    let loadDelta = loadSnapshot.map { max(0, $0.swapUsedBytes - baselineSwap) } ?? 0
    let steadySnapshots: [ResourceSnapshot]
    if let loadSnapshot,
       let index = snapshots.firstIndex(where: { $0.label == loadSnapshot.label }),
       snapshots.index(after: index) < snapshots.endIndex {
      steadySnapshots = Array(snapshots[(snapshots.index(after: index))...])
    } else {
      steadySnapshots = snapshots
    }
    let steadyDelta = samplesValid && !steadySnapshots.isEmpty
      ? steadySnapshots.map { max(0, $0.swapUsedBytes - baselineSwap) }.max() ?? 0
      : Int64.max
    let withinLimit = samplesValid
      && loadDelta <= loadSwapDeltaLimitBytes
      && steadyDelta <= steadySwapDeltaLimitBytes
    return ResourceChecks(
      steadySwapDeltaLimitBytes: steadySwapDeltaLimitBytes,
      loadSwapDeltaLimitBytes: loadSwapDeltaLimitBytes,
      maxSwapDeltaBytes: samplesValid ? maxDelta : -1,
      loadSwapDeltaBytes: samplesValid ? loadDelta : -1,
      steadySwapDeltaBytes: samplesValid ? steadyDelta : -1,
      swapSamplesValid: samplesValid,
      swapDeltaWithinLimit: withinLimit
    )
  }

  public static func runRecord(
    modelDirectory: URL,
    maxTokens: Int
  ) async throws -> Record {
    let start = ContinuousClock.now
    let baselineSwap = globalSwapUsedBytes()
    var snapshots = [snapshot("START", start: start, baselineSwap: baselineSwap)]

    let container = try await LLMModelFactory.shared.loadContainer(
      from: modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )
    let modelType = await container.perform { context in
      String(describing: type(of: context.model))
    }
    snapshots.append(snapshot("MLX_MODEL_LOADED", start: start, baselineSwap: baselineSwap))

    var cases: [RecordCase] = []
    for item in prompts {
      let promptIDs = try await container.perform { context in
        try await ChatTemplateGeneration.promptTokenIDs(
          tokenizer: context.tokenizer,
          modelDirectory: modelDirectory,
          prompt: item.text
        )
      }
      let mlx = try await ChatTemplateGeneration.generateWithTokens(
        container: container,
        modelDirectory: modelDirectory,
        prompt: item.text,
        maxTokens: maxTokens
      )
      cases.append(
        RecordCase(
          promptID: item.id,
          family: item.family,
          prompt: item.text,
          promptTokenIDs: promptIDs,
          mlxGeneratedTokenIDs: mlx.tokenIDs,
          mlxText: mlx.text
        )
      )
      Memory.clearCache()
      snapshots.append(
        snapshot("CASE_\(item.id)_COMPLETE", start: start, baselineSwap: baselineSwap)
      )
    }

    Memory.clearCache()
    snapshots.append(snapshot("END", start: start, baselineSwap: baselineSwap))
    let resource = resourceChecks(
      snapshots: snapshots,
      baselineSwap: baselineSwap,
      loadLabel: "MLX_MODEL_LOADED"
    )
    let checks = [
      "CASE_COUNT_COMPLETE": cases.count == prompts.count,
      "MLX_GENERATIONS_NONEMPTY_AND_BOUNDED": cases.allSatisfy {
        !$0.mlxGeneratedTokenIDs.isEmpty
          && $0.mlxGeneratedTokenIDs.count <= maxTokens
      },
      "PROMPT_TOKENS_NONEMPTY": cases.allSatisfy { !$0.promptTokenIDs.isEmpty },
      "PROMPT_FAMILY_COUNT_COMPLETE": Set(cases.map(\.family)).count == prompts.count,
      "RESOURCE_LOAD_SWAP_DELTA_WITHIN_LIMIT": resource.loadSwapDeltaBytes <= resource.loadSwapDeltaLimitBytes,
      "RESOURCE_STEADY_SWAP_DELTA_WITHIN_LIMIT": resource.steadySwapDeltaBytes <= resource.steadySwapDeltaLimitBytes,
      "RESOURCE_SWAP_SAMPLES_VALID": resource.swapSamplesValid,
      "RESOURCE_SWAP_DELTA_WITHIN_LIMIT": resource.swapDeltaWithinLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return Record(
      status: overallPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: recordProtocolVersion,
      boundary: recordBoundary,
      mlxModelDirectory: modelDirectory.path,
      mlxModelType: modelType,
      maxTokens: maxTokens,
      cases: cases,
      resource: resource,
      resourceSnapshots: snapshots,
      checks: checks,
      overallPass: overallPass
    )
  }

  public static func runCompare(
    modelDirectory: URL,
    recordPath: String,
    host: String,
    port: Int,
    seed: Int
  ) async throws -> CompareReport {
    let recordURL = URL(fileURLWithPath: recordPath)
    let recordData = try Data(contentsOf: recordURL)
    let record = try JSONDecoder().decode(Record.self, from: recordData)
    let recordDigest = SHA256.hash(data: recordData)
    let recordSHA256 = recordDigest.map { String(format: "%02x", $0) }.joined()

    let start = ContinuousClock.now
    let baselineSwap = globalSwapUsedBytes()
    var snapshots = [snapshot("START", start: start, baselineSwap: baselineSwap)]

    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!
    )
    let props = try await executor.props()
    snapshots.append(snapshot("LLAMA_PROPS_RECEIVED", start: start, baselineSwap: baselineSwap))

    var cases: [CompareCase] = []
    for recorded in record.cases {
      let llama = try await executor.complete(
        tokenPrefix: recorded.promptTokenIDs,
        predictionTokens: record.maxTokens,
        seed: seed
      )
      let llamaTokens = llama.tokens ?? []
      cases.append(
        CompareCase(
          promptID: recorded.promptID,
          family: recorded.family,
          prompt: recorded.prompt,
          promptTokenIDs: recorded.promptTokenIDs,
          mlxGeneratedTokenIDs: recorded.mlxGeneratedTokenIDs,
          llamaGeneratedTokenIDs: llamaTokens,
          mlxText: recorded.mlxText,
          llamaText: llama.content,
          tokenSequenceIdentical: recorded.mlxGeneratedTokenIDs == llamaTokens,
          textIdentical: recorded.mlxText == llama.content
        )
      )
      snapshots.append(
        snapshot("CASE_\(recorded.promptID)_COMPLETE", start: start, baselineSwap: baselineSwap)
      )
    }
    snapshots.append(snapshot("END", start: start, baselineSwap: baselineSwap))

    let resource = resourceChecks(snapshots: snapshots, baselineSwap: baselineSwap)
    let checks = [
      "RECORD_VALID": record.overallPass,
      "RECORD_MODEL_DIRECTORY_MATCH": record.mlxModelDirectory == modelDirectory.path,
      "CASE_COUNT_COMPLETE": cases.count == record.cases.count,
      "LLAMA_GENERATIONS_NONEMPTY_AND_BOUNDED": cases.allSatisfy {
        !$0.llamaGeneratedTokenIDs.isEmpty
          && $0.llamaGeneratedTokenIDs.count <= record.maxTokens
      },
      "PROMPT_TOKENS_NONEMPTY": cases.allSatisfy { !$0.promptTokenIDs.isEmpty },
      "RESOURCE_LOAD_SWAP_DELTA_WITHIN_LIMIT": resource.loadSwapDeltaBytes <= resource.loadSwapDeltaLimitBytes,
      "RESOURCE_STEADY_SWAP_DELTA_WITHIN_LIMIT": resource.steadySwapDeltaBytes <= resource.steadySwapDeltaLimitBytes,
      "RESOURCE_SWAP_SAMPLES_VALID": resource.swapSamplesValid,
      "RESOURCE_SWAP_DELTA_WITHIN_LIMIT": resource.swapDeltaWithinLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }
    let outputIdentity = cases.allSatisfy(\.tokenSequenceIdentical)
    let identicalCaseCount = cases.filter(\.tokenSequenceIdentical).count

    return CompareReport(
      status: overallPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: compareProtocolVersion,
      boundary: compareBoundary,
      recordPath: recordPath,
      recordSHA256: recordSHA256,
      llamaModelPath: props.modelPath,
      host: host,
      port: port,
      maxTokens: record.maxTokens,
      seed: seed,
      cases: cases,
      resource: resource,
      resourceSnapshots: snapshots,
      checks: checks,
      outputIdentity: outputIdentity,
      identicalCaseCount: identicalCaseCount,
      mismatchedCaseCount: cases.count - identicalCaseCount,
      identityRatio: cases.isEmpty ? 0 : Double(identicalCaseCount) / Double(cases.count),
      overallPass: overallPass
    )
  }
}
