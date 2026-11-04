import Crypto
import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// Two-phase divergence attribution for CrossBackendTokenProbe mismatches.
/// Both backends receive the same teacher-forced common prefix; the probe
/// records next-token top-k logprobs. It is an observation, not a claim that
/// quantizations are equivalent.
public enum CrossBackendLogitProbe {
  public static let steadySwapDeltaLimitBytes: Int64 = 768 * 1024 * 1024

  public struct Candidate: Codable, Sendable {
    public let rank: Int
    public let tokenID: Int
    public let logprob: Double
    public let token: String?
  }

  public struct Case: Codable, Sendable {
    public let promptID: String
    public let family: String
    public let commonGeneratedPrefixLength: Int
    public let teacherPrefixTokenCount: Int
    public let teacherPrefixTokenIDs: [Int]
    public let mlxFirstDivergentTokenID: Int
    public let llamaFirstDivergentTokenID: Int
    public let candidates: [Candidate]
    public let mlxFirstRank: Int?
    public let llamaFirstRank: Int?
    public let mlxFirstLogprob: Double?
    public let llamaFirstLogprob: Double?
    public let topOneTokenID: Int
  }

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

  public struct ResourceChecks: Codable, Sendable {
    public let steadySwapDeltaLimitBytes: Int64
    public let steadySwapDeltaBytes: Int64
    public let swapSamplesValid: Bool
    public let swapDeltaWithinLimit: Bool
  }

  public struct Record: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let sourceComparePath: String
    public let sourceCompareSHA256: String
    public let mlxModelDirectory: String
    public let mlxModelType: String
    public let topK: Int
    public let cases: [Case]
    public let resource: ResourceChecks
    public let resourceSnapshots: [ResourceSnapshot]
    public let checks: [String: Bool]
    public let overallPass: Bool
  }

  public struct LlamaCase: Codable, Sendable {
    public let promptID: String
    public let family: String
    public let commonGeneratedPrefixLength: Int
    public let teacherPrefixTokenCount: Int
    public let llamaTopOneTokenID: Int
    public let candidates: [Candidate]
    public let mlxFirstRankInLlama: Int?
    public let llamaFirstRank: Int?
    public let mlxFirstLogprobInLlama: Double?
    public let llamaFirstLogprob: Double?
    public let topOneMatchesMlx: Bool
  }

  public struct CompareReport: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let recordPath: String
    public let recordSHA256: String
    public let llamaModelPath: String?
    public let topK: Int
    public let cases: [LlamaCase]
    public let resource: ResourceChecks
    public let resourceSnapshots: [ResourceSnapshot]
    public let checks: [String: Bool]
    public let topOneAgreementCount: Int
    public let topOneAgreementRatio: Double
    public let overallPass: Bool
  }

  public static let recordProtocolVersion = "LAB.CROSSBACKEND.LOGIT.RECORD.V1"
  public static let compareProtocolVersion = "LAB.CROSSBACKEND.LOGIT.COMPARE.V1"
  public static let recordBoundary =
    "PHASE1_MLX_ONLY / TEACHER_FORCED_DIVERGENCE_PREFIX / TOP_K_LOGPROB_RECORD / "
    + "RESOURCE_ISOLATION_SNAPSHOT / NOT_A_QUANTIZATION_EQUIVALENCE_CLAIM"
  struct SourceDecodingFailure: Error, CustomStringConvertible {
    let underlying: any Error
    var description: String { "\(underlying)" }
    var errorDescription: String? { description }
  }

  public static let compareBoundary =
    "PHASE2_LLAMA_ONLY / SAME_TEACHER_FORCED_DIVERGENCE_PREFIX / TOP_K_LOGPROB_COMPARE / "
    + "NOT_A_QUANTIZATION_EQUIVALENCE_CLAIM"

  public struct LLAMACandidate: Decodable, Sendable {
    let id: Int
    let logprob: Double
    let token: String?
  }

  public struct LLAMAProbability: Decodable, Sendable {
    let id: Int
    let logprob: Double
    let topLogprobs: [LLAMACandidate]

    enum CodingKeys: String, CodingKey {
      case id
      case logprob
      case topLogprobs = "top_logprobs"
    }
  }

  public struct LLAMACompletion: Decodable, Sendable {
    let tokens: [Int]?
    let content: String
    let completionProbabilities: [LLAMAProbability]?

    enum CodingKeys: String, CodingKey {
      case tokens
      case content
      case completionProbabilities = "completion_probabilities"
    }
  }

  static func snapshot(
    _ label: String, start: ContinuousClock.Instant, baselineSwap: Int64
  ) -> ResourceSnapshot {
    let (footprint, resident) = O2BaselineProbe.physFootprintAndResident()
    let swapUsed = CrossBackendTokenProbe.globalSwapUsedBytes()
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
    snapshots: [ResourceSnapshot], baselineSwap: Int64
  ) -> ResourceChecks {
    let samplesValid = !snapshots.isEmpty && snapshots.allSatisfy { $0.swapUsedBytes >= 0 }
    let steadyDelta = samplesValid
      ? snapshots.map { max(0, $0.swapUsedBytes - baselineSwap) }.max() ?? 0
      : Int64.max
    return ResourceChecks(
      steadySwapDeltaLimitBytes: steadySwapDeltaLimitBytes,
      steadySwapDeltaBytes: samplesValid ? steadyDelta : -1,
      swapSamplesValid: samplesValid,
      swapDeltaWithinLimit: samplesValid && steadyDelta <= steadySwapDeltaLimitBytes
    )
  }

  static func firstDivergence(_ left: [Int], _ right: [Int]) -> Int {
    var index = 0
    while index < min(left.count, right.count), left[index] == right[index] {
      index += 1
    }
    return index
  }

  public static func runRecord(
    modelDirectory: URL,
    sourceComparePath: String,
    topK: Int = 16
  ) async throws -> Record {
    let sourceURL = URL(fileURLWithPath: sourceComparePath)
    let sourceData = try Data(contentsOf: sourceURL)
    struct SourceCase {
      let promptID: String
      let family: String
      let promptTokenIDs: [Int]
      let mlxGeneratedTokenIDs: [Int]
      let llamaGeneratedTokenIDs: [Int]
      let tokenSequenceIdentical: Bool
    }

    struct SourceCompare {
      let cases: [SourceCase]
    }

    let object = try JSONSerialization.jsonObject(with: sourceData)
    guard
      let root = object as? [String: Any],
      let caseObjects = root["cases"] as? [[String: Any]]
    else {
      throw SourceDecodingFailure(underlying: DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "invalid source compare report")
      ))
    }
    let source = SourceCompare(
      cases: try caseObjects.map { item in
        guard
          let promptID = item["promptID"] as? String,
          let family = item["family"] as? String,
          let promptTokenIDs = item["promptTokenIDs"] as? [Int],
          let mlxGeneratedTokenIDs = item["mlxGeneratedTokenIDs"] as? [Int],
          let llamaGeneratedTokenIDs = item["llamaGeneratedTokenIDs"] as? [Int],
          let tokenSequenceIdentical = item["tokenSequenceIdentical"] as? Bool
        else {
          throw SourceDecodingFailure(underlying: DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "invalid source case")
          ))
        }
        return SourceCase(
          promptID: promptID,
          family: family,
          promptTokenIDs: promptTokenIDs,
          mlxGeneratedTokenIDs: mlxGeneratedTokenIDs,
          llamaGeneratedTokenIDs: llamaGeneratedTokenIDs,
          tokenSequenceIdentical: tokenSequenceIdentical
        )
      }
    )
    let sourceDigest = SHA256.hash(data: sourceData)
      .map { String(format: "%02x", $0) }.joined()
    let mismatched = source.cases.filter { !$0.tokenSequenceIdentical }
    precondition(!mismatched.isEmpty, "source compare report has no mismatch cases")

    let start = ContinuousClock.now
    let baselineSwap = CrossBackendTokenProbe.globalSwapUsedBytes()
    var snapshots = [snapshot("START", start: start, baselineSwap: baselineSwap)]
    let container = try await LLMModelFactory.shared.loadContainer(
      from: modelDirectory,
      using: #huggingFaceTokenizerLoader()
    )
    let modelType = await container.perform { context in
      String(describing: type(of: context.model))
    }
    snapshots.append(
      snapshot("MLX_MODEL_LOADED", start: start, baselineSwap: baselineSwap)
    )

    var cases: [Case] = []
    for sourceCase in mismatched {
      let common = firstDivergence(
        sourceCase.mlxGeneratedTokenIDs, sourceCase.llamaGeneratedTokenIDs
      )
      let teacherPrefix = sourceCase.promptTokenIDs + sourceCase.mlxGeneratedTokenIDs.prefix(common)
      let mlxFirst = sourceCase.mlxGeneratedTokenIDs[common]
      let llamaFirst = sourceCase.llamaGeneratedTokenIDs[common]
      let observation = await container.perform { context -> Case in
        let logits = context.model(
          MLXArray(teacherPrefix, [1, teacherPrefix.count]), cache: nil
        )[0, -1]
        eval(logits)
        let values = logits.asArray(Float.self)
        let ordered = values.enumerated().sorted { $0.element > $1.element }
        let maxValue = values.max() ?? -.infinity
        let logSumExp = maxValue + log(values.reduce(0) { $0 + exp($1 - maxValue) })
        let candidates = ordered.prefix(topK).enumerated().map { index, entry in
          Candidate(
            rank: index,
            tokenID: entry.offset,
            logprob: Double(entry.element - logSumExp),
            token: context.tokenizer.decode(tokenIds: [entry.offset], skipSpecialTokens: true)
          )
        }
        let ranks: [Int: Int] = Dictionary(uniqueKeysWithValues: ordered.enumerated().map {
          ($1.offset, $0)
        })
        Memory.clearCache()
        return Case(
          promptID: sourceCase.promptID,
          family: sourceCase.family,
          commonGeneratedPrefixLength: common,
          teacherPrefixTokenCount: teacherPrefix.count,
          teacherPrefixTokenIDs: teacherPrefix,
          mlxFirstDivergentTokenID: mlxFirst,
          llamaFirstDivergentTokenID: llamaFirst,
          candidates: Array(candidates),
          mlxFirstRank: ranks[mlxFirst],
          llamaFirstRank: ranks[llamaFirst],
          mlxFirstLogprob: ordered.first { $0.offset == mlxFirst }.map {
            Double($0.element - logSumExp)
          },
          llamaFirstLogprob: ordered.first { $0.offset == llamaFirst }.map {
            Double($0.element - logSumExp)
          },
          topOneTokenID: ordered.first?.offset ?? -1
        )
      }
      cases.append(observation)
      snapshots.append(
        snapshot(
          "CASE_\(sourceCase.promptID)_COMPLETE", start: start, baselineSwap: baselineSwap
        )
      )
    }

    snapshots.append(snapshot("END", start: start, baselineSwap: baselineSwap))
    let resource = resourceChecks(snapshots: snapshots, baselineSwap: baselineSwap)
    let checks = [
      "CASE_COUNT_COMPLETE": cases.count == mismatched.count,
      "TOP_K_COMPLETE": cases.allSatisfy { $0.candidates.count == topK },
      "TEACHER_PREFIXES_NONEMPTY": cases.allSatisfy { $0.teacherPrefixTokenCount > 0 },
      "RESOURCE_SWAP_SAMPLES_VALID": resource.swapSamplesValid,
      "RESOURCE_SWAP_DELTA_WITHIN_LIMIT": resource.swapDeltaWithinLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return Record(
      status: overallPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: recordProtocolVersion,
      boundary: recordBoundary,
      sourceComparePath: sourceComparePath,
      sourceCompareSHA256: sourceDigest,
      mlxModelDirectory: modelDirectory.path,
      mlxModelType: modelType,
      topK: topK,
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
    topK: Int = 16
  ) async throws -> CompareReport {
    let recordURL = URL(fileURLWithPath: recordPath)
    let recordData = try Data(contentsOf: recordURL)
    let record = try JSONDecoder().decode(Record.self, from: recordData)
    let recordDigest = SHA256.hash(data: recordData)
      .map { String(format: "%02x", $0) }.joined()

    let start = ContinuousClock.now
    let baselineSwap = CrossBackendTokenProbe.globalSwapUsedBytes()
    var snapshots = [snapshot("START", start: start, baselineSwap: baselineSwap)]
    let executor = LLAMAServerExecutionStateExecutor(
      baseURL: URL(string: "http://\(host):\(port)")!
    )
    let props = try await executor.props()
    snapshots.append(snapshot("LLAMA_PROPS_RECEIVED", start: start, baselineSwap: baselineSwap))

    var cases: [LlamaCase] = []
    for recorded in record.cases {
      let body: [String: Any] = [
        "prompt": recorded.teacherPrefixTokenIDs,
        "n_predict": 1,
        "temperature": 0.0,
        "seed": 42,
        "cache_prompt": false,
        "return_tokens": true,
        "n_probs": record.topK,
      ]
      var request = URLRequest(url: URL(string: "http://\(host):\(port)/completion")!)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw LLAMAServerExecutorError.badStatus(status)
      }
      let completion = try JSONDecoder().decode(LLAMACompletion.self, from: data)
      let probability = completion.completionProbabilities?.first
      let llamaTop = probability?.id ?? completion.tokens?.first ?? -1
      let candidates = (probability?.topLogprobs ?? []).enumerated().map { index, entry in
        Candidate(
          rank: index,
          tokenID: entry.id,
          logprob: entry.logprob,
          token: entry.token
        )
      }
      let rankByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.tokenID, $0.rank) })
      let logprobByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.tokenID, $0.logprob) })
      cases.append(
        LlamaCase(
          promptID: recorded.promptID,
          family: recorded.family,
          commonGeneratedPrefixLength: recorded.commonGeneratedPrefixLength,
          teacherPrefixTokenCount: recorded.teacherPrefixTokenCount,
          llamaTopOneTokenID: llamaTop,
          candidates: candidates,
          mlxFirstRankInLlama: rankByID[recorded.mlxFirstDivergentTokenID],
          llamaFirstRank: rankByID[recorded.llamaFirstDivergentTokenID],
          mlxFirstLogprobInLlama: logprobByID[recorded.mlxFirstDivergentTokenID],
          llamaFirstLogprob: probability?.logprob ?? logprobByID[llamaTop],
          topOneMatchesMlx: llamaTop == recorded.topOneTokenID
        )
      )
      snapshots.append(
        snapshot(
          "CASE_\(recorded.promptID)_COMPLETE", start: start, baselineSwap: baselineSwap
        )
      )
    }
    snapshots.append(snapshot("END", start: start, baselineSwap: baselineSwap))

    let resource = resourceChecks(snapshots: snapshots, baselineSwap: baselineSwap)
    let topOneAgreementCount = cases.filter(\.topOneMatchesMlx).count
    let checks = [
      "RECORD_VALID": record.overallPass,
      "RECORD_MODEL_DIRECTORY_MATCH": record.mlxModelDirectory == modelDirectory.path,
      "CASE_COUNT_COMPLETE": cases.count == record.cases.count,
      "TOP_K_COMPLETE": cases.allSatisfy { $0.candidates.count == record.topK },
      "RESOURCE_SWAP_SAMPLES_VALID": resource.swapSamplesValid,
      "RESOURCE_SWAP_DELTA_WITHIN_LIMIT": resource.swapDeltaWithinLimit,
    ]
    let overallPass = checks.values.allSatisfy { $0 }

    return CompareReport(
      status: overallPass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: compareProtocolVersion,
      boundary: compareBoundary,
      recordPath: recordPath,
      recordSHA256: recordDigest,
      llamaModelPath: props.modelPath,
      topK: record.topK,
      cases: cases,
      resource: resource,
      resourceSnapshots: snapshots,
      checks: checks,
      topOneAgreementCount: topOneAgreementCount,
      topOneAgreementRatio: cases.isEmpty ? 0 : Double(topOneAgreementCount) / Double(cases.count),
      overallPass: overallPass
    )
  }
}
