import Crypto
import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// Two-phase full-sequence margin attribution for CrossBackendTokenProbe V2.
/// Phase 1 evaluates the complete MLX greedy trajectory with MLX only. Phase 2
/// queries llama-server at every prefix of that trajectory with llama-server
/// only. The backends never share a process interval.
public enum CrossBackendMarginProbe {
  public static let phase1SteadySwapDeltaLimitBytes: Int64 = 768 * 1024 * 1024
  public static let phase2SteadySwapDeltaLimitBytes: Int64 = 512 * 1024 * 1024

  public struct Candidate: Codable, Sendable {
    public let rank: Int
    public let tokenID: Int
    public let logprob: Double
    public let token: String?
  }

  public enum Scope: String, Codable, Sendable {
    case all
    case mismatches
  }

  public struct AcceptanceGate: Codable, Sendable {
    public let topOneFlipsAllowed: Bool
    public let topKContainmentRequired: Bool
    public let maxReferenceRankLimit: Int
    public let positions: Int
    public let topOneFlipCount: Int
    public let topKContainmentCount: Int
    public let maxObservedReferenceRank: Int
    public let pass: Bool
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

  public struct Position: Codable, Sendable {
    public let position: Int
    public let referenceTokenID: Int
    public let referenceToken: String
    public let topOneTokenID: Int
    public let topOneLogprob: Double
    public let topOneMargin: Double
    public let referenceLogprob: Double
    public let referenceMargin: Double
    public let referenceRank: Int
    public let topOneMatchesReference: Bool
    public let candidates: [Candidate]
  }

  public struct CaseSummary: Codable, Sendable {
    public let positions: Int
    public let mlxSelfConsistentCount: Int
    public let mlxSelfConsistentRatio: Double
    public let llamaTopOneAgreementCount: Int?
    public let llamaTopOneAgreementRatio: Double?
    public let referenceInLlamaTopKCount: Int?
    public let referenceInLlamaTopKRatio: Double?
    public let meanReferenceRankInLlama: Double?
    public let maxReferenceRankInLlama: Int?
    public let meanMlxTopOneMargin: Double
    public let meanLlamaTopOneMargin: Double?
  }

  public struct Case: Codable, Sendable {
    public let promptID: String
    public let family: String
    public let promptTokenIDs: [Int]
    public let promptTokenCount: Int
    public let generatedTokenCount: Int
    public let positions: [Position]
    public let summary: CaseSummary
  }

  public struct Record: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let sourceComparePath: String
    public let sourceCompareSHA256: String
    public let scope: Scope
    public let sourceCaseCount: Int
    public let selectedCaseCount: Int
    public let sourceIdentityCaseCount: Int
    public let sourceMismatchCaseCount: Int
    public let mlxModelDirectory: String
    public let mlxModelType: String
    public let topK: Int
    public let cases: [Case]
    public let resource: ResourceChecks
    public let resourceSnapshots: [ResourceSnapshot]
    public let checks: [String: Bool]
    public let overallPass: Bool
  }

  public struct ComparePosition: Codable, Sendable {
    public let position: Int
    public let referenceTokenID: Int
    public let mlxTopOneTokenID: Int
    public let mlxSelfConsistent: Bool
    public let mlxTopOneMargin: Double
    public let llamaTopOneTokenID: Int
    public let llamaTopOneMatchesReference: Bool
    public let referenceInLlamaTopK: Bool
    public let referenceRankInLlama: Int?
    public let referenceLogprobInLlama: Double?
    public let referenceMarginInLlama: Double?
    public let llamaTopOneMargin: Double?
    public let candidates: [Candidate]
  }

  public struct CompareCase: Codable, Sendable {
    public let promptID: String
    public let family: String
    public let promptTokenCount: Int
    public let generatedTokenCount: Int
    public let positions: [ComparePosition]
    public let summary: CaseSummary
  }

  public struct CompareReport: Codable, Sendable {
    public let status: String
    public let protocolVersion: String
    public let boundary: String
    public let recordPath: String
    public let recordSHA256: String
    public let scope: Scope
    public let seed: Int
    public let llamaModelPath: String?
    public let topK: Int
    public let cases: [CompareCase]
    public let resource: ResourceChecks
    public let resourceSnapshots: [ResourceSnapshot]
    public let checks: [String: Bool]
    public let positionCount: Int
    public let llamaTopOneAgreementCount: Int
    public let llamaTopOneAgreementRatio: Double
    public let acceptanceGate: AcceptanceGate
    public let overallPass: Bool
  }

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

  public static let recordProtocolVersion = "LAB.CROSSBACKEND.MARGIN.RECORD.V2"
  public static let compareProtocolVersion = "LAB.CROSSBACKEND.MARGIN.COMPARE.V2"
  public static let recordBoundary =
    "PHASE1_MLX_ONLY / FULL_MLX_GREEDY_TRAJECTORY / PER_POSITION_TOP_K_MARGIN / "
    + "RESOURCE_ISOLATION_SNAPSHOT / NOT_A_QUANTIZATION_EQUIVALENCE_CLAIM"
  public static let compareBoundary =
    "PHASE2_LLAMA_ONLY / SAME_MLX_TRAJECTORY_PREFIXES / PER_POSITION_TOP_K_MARGIN / "
    + "NOT_A_QUANTIZATION_EQUIVALENCE_CLAIM"

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
    snapshots: [ResourceSnapshot], baselineSwap: Int64, limit: Int64
  ) -> ResourceChecks {
    let samplesValid = !snapshots.isEmpty && snapshots.allSatisfy { $0.swapUsedBytes >= 0 }
    let steadyDelta = samplesValid
      ? snapshots.map { max(0, $0.swapUsedBytes - baselineSwap) }.max() ?? 0
      : Int64.max
    return ResourceChecks(
      steadySwapDeltaLimitBytes: limit,
      steadySwapDeltaBytes: samplesValid ? steadyDelta : -1,
      swapSamplesValid: samplesValid,
      swapDeltaWithinLimit: samplesValid && steadyDelta <= limit
    )
  }

  static func sourceCases(
    from sourceComparePath: String
  ) throws -> (cases: [CrossBackendTokenProbe.CompareCase], digest: String) {
    let url = URL(fileURLWithPath: sourceComparePath)
    let data = try Data(contentsOf: url)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let root = try JSONSerialization.jsonObject(with: data)
    guard let object = root as? [String: Any],
          let items = object["cases"] as? [[String: Any]]
    else {
      throw SourceDecodingFailure(underlying: DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "invalid source compare report")
      ))
    }
    let cases = try items.map { item -> CrossBackendTokenProbe.CompareCase in
      guard
        let promptID = item["promptID"] as? String,
        let family = item["family"] as? String,
        let prompt = item["prompt"] as? String,
        let promptTokenIDs = item["promptTokenIDs"] as? [Int],
        let mlx = item["mlxGeneratedTokenIDs"] as? [Int],
        let llama = item["llamaGeneratedTokenIDs"] as? [Int],
        let mlxText = item["mlxText"] as? String,
        let llamaText = item["llamaText"] as? String,
        let identical = item["tokenSequenceIdentical"] as? Bool,
        let textIdentical = item["textIdentical"] as? Bool
      else {
        throw SourceDecodingFailure(underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "invalid source compare case")
        ))
      }
      return CrossBackendTokenProbe.CompareCase(
        promptID: promptID,
        family: family,
        prompt: prompt,
        promptTokenIDs: promptTokenIDs,
        mlxGeneratedTokenIDs: mlx,
        llamaGeneratedTokenIDs: llama,
        mlxText: mlxText,
        llamaText: llamaText,
        tokenSequenceIdentical: identical,
        textIdentical: textIdentical
      )
    }
    return (cases, digest)
  }

  static func summarize(
    positions: [Position], llamaTopOneAgreement: [Bool]?, referenceInTopK: [Bool]?,
    referenceRanks: [Int?]?, llamaTopOneMargins: [Double]?
  ) -> CaseSummary {
    let count = max(positions.count, 1)
    let mlxSelf = positions.filter(\.topOneMatchesReference).count
    let llamaAgreement = llamaTopOneAgreement?.filter { $0 }.count
    let referenceContained = referenceInTopK?.filter { $0 }.count
    let ranks = referenceRanks?.compactMap { $0 } ?? []

    func mean(_ values: [Double]) -> Double? {
      values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    return CaseSummary(
      positions: positions.count,
      mlxSelfConsistentCount: mlxSelf,
      mlxSelfConsistentRatio: Double(mlxSelf) / Double(count),
      llamaTopOneAgreementCount: llamaAgreement,
      llamaTopOneAgreementRatio: llamaAgreement.map { Double($0) / Double(count) },
      referenceInLlamaTopKCount: referenceContained,
      referenceInLlamaTopKRatio: referenceContained.map { Double($0) / Double(count) },
      meanReferenceRankInLlama: mean(ranks.map(Double.init)),
      maxReferenceRankInLlama: referenceRanks?.compactMap { $0 }.max(),
      meanMlxTopOneMargin: mean(positions.map(\.topOneMargin)) ?? 0,
      meanLlamaTopOneMargin: mean(llamaTopOneMargins ?? [])
    )
  }

  public static func runRecord(
    modelDirectory: URL,
    sourceComparePath: String,
    scope: Scope = .mismatches,
    topK: Int = 16
  ) async throws -> Record {
    let (allSourceCases, sourceDigest) = try sourceCases(from: sourceComparePath)
    let selectedCases = scope == .all
      ? allSourceCases
      : allSourceCases.filter { !$0.tokenSequenceIdentical }
    precondition(!selectedCases.isEmpty, "selected source compare scope has no cases")
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
    snapshots.append(snapshot("MLX_MODEL_LOADED", start: start, baselineSwap: baselineSwap))

    var cases: [Case] = []
    for source in selectedCases {
      let fullTokens = source.promptTokenIDs + source.mlxGeneratedTokenIDs
      let positions: [Position] = await container.perform { context -> [Position] in
        let sequenceLogits = context.model(
          MLXArray(fullTokens, [1, fullTokens.count]), cache: nil
        )[0]
        eval(sequenceLogits)
        return source.mlxGeneratedTokenIDs.enumerated().map { position, target in
          let row = sequenceLogits[source.promptTokenIDs.count + position - 1]
          let values = row.asArray(Float.self)
          let ordered = values.enumerated().sorted { $0.element > $1.element }
          let maxLogit = ordered.first?.element ?? -.infinity
          let logSumExp = maxLogit + log(values.reduce(0) { $0 + exp($1 - maxLogit) })
          let candidates = ordered.prefix(topK).map { entry in
            Candidate(
              rank: entry.offset,
              tokenID: entry.offset,
              logprob: Double(entry.element - logSumExp),
              token: context.tokenizer.decode(
                tokenIds: [entry.offset], skipSpecialTokens: true
              )
            )
          }
          let rankByID = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($1.offset, $0) }
          )
          let referenceRank = rankByID[target] ?? Int.max
          let topOneLogprob = ordered.first.map { Double($0.element - logSumExp) } ?? -.infinity
          let secondLogprob = ordered.dropFirst().first.map { Double($0.element - logSumExp) }
          let referenceLogprob = Double(values[referenceRank] - logSumExp)
          return Position(
            position: position,
            referenceTokenID: target,
            referenceToken: context.tokenizer.decode(
              tokenIds: [target], skipSpecialTokens: true
            ),
            topOneTokenID: ordered.first?.offset ?? -1,
            topOneLogprob: topOneLogprob,
            topOneMargin: topOneLogprob - (secondLogprob ?? topOneLogprob),
            referenceLogprob: referenceLogprob,
            referenceMargin: topOneLogprob - referenceLogprob,
            referenceRank: referenceRank,
            topOneMatchesReference: ordered.first?.offset == target,
            candidates: candidates
          )
        }
      }
      cases.append(
        Case(
          promptID: source.promptID,
          family: source.family,
          promptTokenIDs: source.promptTokenIDs,
          promptTokenCount: source.promptTokenIDs.count,
          generatedTokenCount: source.mlxGeneratedTokenIDs.count,
          positions: positions,
          summary: summarize(
            positions: positions,
            llamaTopOneAgreement: nil,
            referenceInTopK: nil,
            referenceRanks: nil,
            llamaTopOneMargins: nil
          )
        )
      )
      Memory.clearCache()
      snapshots.append(
        snapshot("CASE_\(source.promptID)_COMPLETE", start: start, baselineSwap: baselineSwap)
      )
    }
    snapshots.append(snapshot("END", start: start, baselineSwap: baselineSwap))
    let resource = resourceChecks(
      snapshots: snapshots,
      baselineSwap: baselineSwap,
      limit: phase1SteadySwapDeltaLimitBytes
    )
    let checks = [
      "CASE_COUNT_COMPLETE": cases.count == selectedCases.count,
      "POSITION_COUNTS_COMPLETE": cases.allSatisfy {
        $0.positions.count == $0.generatedTokenCount
      },
      "TOP_K_COMPLETE": cases.allSatisfy { caseItem in
        caseItem.positions.allSatisfy { $0.candidates.count == topK }
      },
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
      scope: scope,
      sourceCaseCount: allSourceCases.count,
      selectedCaseCount: selectedCases.count,
      sourceIdentityCaseCount: allSourceCases.filter(\.tokenSequenceIdentical).count,
      sourceMismatchCaseCount: allSourceCases.filter { !$0.tokenSequenceIdentical }.count,
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
    scope: Scope = .mismatches,
    topK: Int = 16,
    seed: Int = 42
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

    var compareCases: [CompareCase] = []
    for recorded in record.cases {
      let sourceCasePromptIDs = recorded.promptTokenIDs
      var positions: [ComparePosition] = []
      var agreements: [Bool] = []
      var contained: [Bool] = []
      var ranks: [Int?] = []
      for recordedPosition in recorded.positions {
        let prefix = sourceCasePromptIDs + Array(
          recorded.positions[0..<recordedPosition.position].map(\.referenceTokenID)
        )
        let body: [String: Any] = [
          "prompt": prefix,
          "n_predict": 1,
          "temperature": 0.0,
          "seed": seed,
          "cache_prompt": false,
          "return_tokens": true,
          "n_probs": topK,
        ]
        var request = URLRequest(url: URL(string: "http://\(host):\(port)/completion")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
          throw LLAMAServerExecutorError.badStatus(
            (response as? HTTPURLResponse)?.statusCode ?? -1
          )
        }
        let completion = try JSONDecoder().decode(LLAMACompletion.self, from: data)
        let probability = completion.completionProbabilities?.first
        let candidates = (probability?.topLogprobs ?? []).enumerated().map { index, entry in
          Candidate(
            rank: index,
            tokenID: entry.id,
            logprob: entry.logprob,
            token: entry.token
          )
        }
        let referenceLogprob = candidates.first { $0.tokenID == recordedPosition.referenceTokenID }?
          .logprob
        let referenceRank = candidates.first { $0.tokenID == recordedPosition.referenceTokenID }?
          .rank
        let llamaTopOne = probability?.id ?? completion.tokens?.first ?? -1
        let llamaTopOneLogprob = probability?.logprob ?? candidates.first?.logprob
        let llamaSecondLogprob = candidates.dropFirst().first?.logprob
        let llamaTopOneMargin = (llamaTopOneLogprob != nil && llamaSecondLogprob != nil)
          ? llamaTopOneLogprob! - llamaSecondLogprob!
          : nil
        let agreement = llamaTopOne == recordedPosition.referenceTokenID
        agreements.append(agreement)
        let inTopK = referenceRank != nil
        contained.append(inTopK)
        ranks.append(referenceRank)
        positions.append(
          ComparePosition(
            position: recordedPosition.position,
            referenceTokenID: recordedPosition.referenceTokenID,
            mlxTopOneTokenID: recordedPosition.topOneTokenID,
            mlxSelfConsistent: recordedPosition.topOneMatchesReference,
            mlxTopOneMargin: recordedPosition.topOneMargin,
            llamaTopOneTokenID: llamaTopOne,
            llamaTopOneMatchesReference: agreement,
            referenceInLlamaTopK: inTopK,
            referenceRankInLlama: referenceRank,
            referenceLogprobInLlama: referenceLogprob,
            referenceMarginInLlama: referenceLogprob.map { llamaTopOneLogprob! - $0 },
            llamaTopOneMargin: llamaTopOneMargin,
            candidates: candidates
          )
        )
      }
      let summary = summarize(
        positions: recorded.positions,
        llamaTopOneAgreement: agreements,
        referenceInTopK: contained,
        referenceRanks: ranks,
        llamaTopOneMargins: positions.compactMap(\.llamaTopOneMargin)
      )
      compareCases.append(
        CompareCase(
          promptID: recorded.promptID,
          family: recorded.family,
          promptTokenCount: recorded.promptTokenCount,
          generatedTokenCount: recorded.generatedTokenCount,
          positions: positions,
          summary: summary
        )
      )
      snapshots.append(
        snapshot("CASE_\(recorded.promptID)_COMPLETE", start: start, baselineSwap: baselineSwap)
      )
    }
    snapshots.append(snapshot("END", start: start, baselineSwap: baselineSwap))
    let resource = resourceChecks(
      snapshots: snapshots,
      baselineSwap: baselineSwap,
      limit: phase2SteadySwapDeltaLimitBytes
    )
    let allPositions = compareCases.flatMap(\.positions)
    let agreementCount = allPositions.filter(\.llamaTopOneMatchesReference).count
    let checks = [
      "RECORD_VALID": record.overallPass,
      "RECORD_SCOPE_MATCH": record.scope == scope,
      "RECORD_MODEL_DIRECTORY_MATCH": record.mlxModelDirectory == modelDirectory.path,
      "CASE_COUNT_COMPLETE": compareCases.count == record.cases.count,
      "POSITION_COUNT_COMPLETE": allPositions.count == record.cases.reduce(0) {
        $0 + $1.generatedTokenCount
      },
      "TOP_K_COMPLETE": allPositions.allSatisfy { $0.candidates.count == topK },
      "RESOURCE_SWAP_SAMPLES_VALID": resource.swapSamplesValid,
      "RESOURCE_SWAP_DELTA_WITHIN_LIMIT": resource.swapDeltaWithinLimit,
    ]
    let acceptanceGate = AcceptanceGate(
      topOneFlipsAllowed: true,
      topKContainmentRequired: true,
      maxReferenceRankLimit: 2,
      positions: allPositions.count,
      topOneFlipCount: allPositions.count - agreementCount,
      topKContainmentCount: allPositions.filter(\.referenceInLlamaTopK).count,
      maxObservedReferenceRank: allPositions.compactMap(\.referenceRankInLlama).max() ?? Int.max,
      pass: allPositions.allSatisfy { $0.referenceInLlamaTopK }
        && (allPositions.compactMap(\.referenceRankInLlama).max() ?? Int.max) <= 2
    )
    let overallPass = checks.values.allSatisfy { $0 } && acceptanceGate.pass

    return CompareReport(
      status: acceptanceGate.pass ? "PASS_WITH_BOUNDARY" : "FAIL",
      protocolVersion: compareProtocolVersion,
      boundary: compareBoundary,
      recordPath: recordPath,
      recordSHA256: recordDigest,
      scope: scope,
      seed: seed,
      llamaModelPath: props.modelPath,
      topK: topK,
      cases: compareCases,
      resource: resource,
      resourceSnapshots: snapshots,
      checks: checks,
      positionCount: allPositions.count,
      llamaTopOneAgreementCount: agreementCount,
      llamaTopOneAgreementRatio: allPositions.isEmpty
        ? 0
        : Double(agreementCount) / Double(allPositions.count),
      acceptanceGate: acceptanceGate,
      overallPass: overallPass
    )
  }

  struct SourceDecodingFailure: Error, CustomStringConvertible, LocalizedError {
    let underlying: any Error
    var description: String { "\(underlying)" }
    var errorDescription: String? { description }
  }
}
