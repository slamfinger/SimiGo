import Foundation

/// Executable acceptance profile for a named-source MLX/LLAMA margin study.
/// Top-one flips are permitted only as observations; every fixed-trajectory
/// reference token must appear in LLAMA top-K with rank no greater than the
/// registered limit. A profile becomes certified only after two seeds pass and
/// their per-position outcomes are identical.
public enum NamedSourceConformanceProfile {
  public struct Gate: Codable, Equatable, Sendable {
    public let minimumSeedCount: Int
    public let topKContainmentRequired: Bool
    public let maximumReferenceRank: Int
    public let allowTopOneFlips: Bool
    public let requireIdenticalPerPositionSeedOutcomes: Bool

    public init(
      minimumSeedCount: Int = 2,
      topKContainmentRequired: Bool = true,
      maximumReferenceRank: Int = 2,
      allowTopOneFlips: Bool = true,
      requireIdenticalPerPositionSeedOutcomes: Bool = true
    ) {
      precondition(minimumSeedCount >= 2, "named-source profile requires at least two seeds")
      self.minimumSeedCount = minimumSeedCount
      self.topKContainmentRequired = topKContainmentRequired
      self.maximumReferenceRank = maximumReferenceRank
      self.allowTopOneFlips = allowTopOneFlips
      self.requireIdenticalPerPositionSeedOutcomes = requireIdenticalPerPositionSeedOutcomes
    }

    public static let cyberTielMatrixV2 = Gate(
      minimumSeedCount: 2,
      topKContainmentRequired: true,
      maximumReferenceRank: 2,
      allowTopOneFlips: true,
      requireIdenticalPerPositionSeedOutcomes: true
    )
  }

  public struct SeedEvidence: Codable, Equatable, Sendable {
    public let seed: Int
    public let positionCount: Int
    public let topOneAgreementCount: Int
    public let topOneAgreementRatio: Double
    public let topKContainmentCount: Int
    public let maximumReferenceRank: Int
    public let topOneFlipCount: Int
    public let perPositionOutcomes: [PerPositionOutcome]

    public struct PerPositionOutcome: Codable, Equatable, Sendable {
      public let promptID: String
      public let position: Int
      public let llamaTopOneTokenID: Int
      public let referenceInLlamaTopK: Bool
      public let referenceRankInLlama: Int?
    }
  }

  public struct Evaluation: Codable, Equatable, Sendable {
    public let profileID: String
    public let seedCount: Int
    public let positionCount: Int
    public let topOneAgreementRatio: Double
    public let topKContainmentCount: Int
    public let maximumObservedReferenceRank: Int
    public let topOneFlipCount: Int
    public let seedOutcomesIdentical: Bool
    public let checks: [String: Bool]
    public let pass: Bool
    public let failureReasons: [String]
  }

  public static let cyberTielMatrixV2ProfileID =
    "NAMED_SOURCE.CYBER_TIEL.MATRIX_V2.TOP16_RANK2.TWO_SEEDS"

  public static func evaluate(
    profileID: String = cyberTielMatrixV2ProfileID,
    gate: Gate = .cyberTielMatrixV2,
    evidence: [SeedEvidence]
  ) -> Evaluation {
    var failures: [String] = []

    let seedCount = evidence.count
    if seedCount < gate.minimumSeedCount {
      failures.append("INSUFFICIENT_SEEDS")
    }

    let seedIDs = evidence.map(\.seed)
    if Set(seedIDs).count != seedCount {
      failures.append("DUPLICATE_SEEDS")
    }

    guard let first = evidence.first else {
      return Evaluation(
        profileID: profileID,
        seedCount: seedCount,
        positionCount: 0,
        topOneAgreementRatio: 0,
        topKContainmentCount: 0,
        maximumObservedReferenceRank: Int.max,
        topOneFlipCount: 0,
        seedOutcomesIdentical: false,
        checks: [
          "SEED_COUNT": false,
          "UNIQUE_SEEDS": false,
          "POSITION_COUNTS_MATCH": false,
          "TOP_K_CONTAINMENT": false,
          "MAX_REFERENCE_RANK": false,
          "TOP_ONE_FLIP_POLICY": false,
          "SEED_OUTCOMES_IDENTICAL": false,
        ],
        pass: false,
        failureReasons: failures + ["NO_EVIDENCE"]
      )
    }

    let positionCount = first.positionCount
    let positionCountsMatch = evidence.allSatisfy { $0.positionCount == positionCount }
    if !positionCountsMatch {
      failures.append("POSITION_COUNT_MISMATCH")
    }

    var allOutcomes: [[SeedEvidence.PerPositionOutcome]] = evidence.map(\.perPositionOutcomes)
    for index in allOutcomes.indices {
      allOutcomes[index].sort { lhs, rhs in
        lhs.promptID == rhs.promptID
          ? lhs.position < rhs.position
          : lhs.promptID < rhs.promptID
      }
    }
    let seedOutcomesIdentical = allOutcomes.dropFirst().allSatisfy { $0 == allOutcomes[0] }
    if gate.requireIdenticalPerPositionSeedOutcomes, !seedOutcomesIdentical {
      failures.append("SEED_OUTCOME_MISMATCH")
    }

    let allPositions = evidence.flatMap(\.perPositionOutcomes)
    let contained = allPositions.filter(\.referenceInLlamaTopK).count
    let containmentPass = !gate.topKContainmentRequired || contained == allPositions.count
    if !containmentPass {
      failures.append("TOP_K_CONTAINMENT_FAILURE")
    }

    let maximumRank = allPositions.compactMap(\.referenceRankInLlama).max() ?? Int.max
    let rankPass = maximumRank <= gate.maximumReferenceRank
    if !rankPass {
      failures.append("MAX_REFERENCE_RANK_FAILURE")
    }

    let flipCount = allPositions.count - allPositions.filter {
      $0.referenceInLlamaTopK && ($0.referenceRankInLlama ?? Int.max) == 0
    }.count
    let flipPolicyPass = gate.allowTopOneFlips || flipCount == 0
    if !flipPolicyPass {
      failures.append("TOP_ONE_FLIP_NOT_ALLOWED")
    }

    // Agreement is an observation rather than a hard threshold. Profile output
    // keeps it explicit so consumers cannot mistake near-boundary flips for
    // full logits equivalence.
    let agreementRatios = evidence.map { evidence in
      evidence.positionCount == 0
        ? 0.0
        : Double(evidence.topOneAgreementCount) / Double(evidence.positionCount)
    }
    let meanAgreementRatio = agreementRatios.isEmpty
      ? 0
      : agreementRatios.reduce(0, +) / Double(agreementRatios.count)

    let checks = [
      "SEED_COUNT": seedCount >= gate.minimumSeedCount,
      "UNIQUE_SEEDS": Set(seedIDs).count == seedCount,
      "POSITION_COUNTS_MATCH": positionCountsMatch,
      "TOP_K_CONTAINMENT": containmentPass,
      "MAX_REFERENCE_RANK": rankPass,
      "TOP_ONE_FLIP_POLICY": flipPolicyPass,
      "SEED_OUTCOMES_IDENTICAL": seedOutcomesIdentical,
    ]
    let pass = checks.values.allSatisfy { $0 }

    return Evaluation(
      profileID: profileID,
      seedCount: seedCount,
      positionCount: positionCount,
      topOneAgreementRatio: meanAgreementRatio,
      topKContainmentCount: contained,
      maximumObservedReferenceRank: rankPass ? maximumRank : max(maximumRank, gate.maximumReferenceRank + 1),
      topOneFlipCount: flipCount,
      seedOutcomesIdentical: seedOutcomesIdentical,
      checks: checks,
      pass: pass,
      failureReasons: failures
    )
  }

  public static func seedEvidence(
    fromCompareData data: Data, defaultSeed: Int = 42
  ) throws -> SeedEvidence {
    let root = try JSONSerialization.jsonObject(with: data)
    guard let object = root as? [String: Any],
          let caseObjects = object["cases"] as? [[String: Any]],
          let acceptance = object["acceptanceGate"] as? [String: Any]
    else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid margin compare report"))
    }
    let outcomes: [SeedEvidence.PerPositionOutcome] = try caseObjects.flatMap { caseObject in
      guard let promptID = caseObject["promptID"] as? String,
            let positionObjects = caseObject["positions"] as? [[String: Any]]
      else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid margin compare case"))
      }
      return try positionObjects.map { positionObject in
        guard let position = positionObject["position"] as? Int,
              let llamaTopOneTokenID = positionObject["llamaTopOneTokenID"] as? Int,
              let referenceInLlamaTopK = positionObject["referenceInLlamaTopK"] as? Bool
        else {
          throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid margin compare position"))
        }
        return SeedEvidence.PerPositionOutcome(
          promptID: promptID,
          position: position,
          llamaTopOneTokenID: llamaTopOneTokenID,
          referenceInLlamaTopK: referenceInLlamaTopK,
          referenceRankInLlama: positionObject["referenceRankInLlama"] as? Int
        )
      }
    }
    let seed = (object["seed"] as? Int) ?? defaultSeed
    let positionCount = (object["positionCount"] as? Int) ?? outcomes.count
    let agreement = (object["llamaTopOneAgreementCount"] as? Int) ?? outcomes.filter { $0.referenceRankInLlama == 0 }.count
    return SeedEvidence(
      seed: seed,
      positionCount: positionCount,
      topOneAgreementCount: agreement,
      topOneAgreementRatio: positionCount == 0 ? 0 : Double(agreement) / Double(positionCount),
      topKContainmentCount: (acceptance["topKContainmentCount"] as? Int) ?? outcomes.filter { $0.referenceInLlamaTopK }.count,
      maximumReferenceRank: (acceptance["maxObservedReferenceRank"] as? Int) ?? outcomes.compactMap { $0.referenceRankInLlama }.max() ?? 0,
      topOneFlipCount: (acceptance["topOneFlipCount"] as? Int) ?? outcomes.filter { $0.referenceRankInLlama != 0 }.count,
      perPositionOutcomes: outcomes
    )
  }

  public static func seedEvidence(
    from report: CrossBackendMarginProbe.CompareReport
  ) -> SeedEvidence {
    SeedEvidence(
      seed: report.seed,
      positionCount: report.positionCount,
      topOneAgreementCount: report.llamaTopOneAgreementCount,
      topOneAgreementRatio: report.llamaTopOneAgreementRatio,
      topKContainmentCount: report.acceptanceGate.topKContainmentCount,
      maximumReferenceRank: report.acceptanceGate.maxObservedReferenceRank,
      topOneFlipCount: report.acceptanceGate.topOneFlipCount,
      perPositionOutcomes: report.cases.flatMap { caseItem in
        caseItem.positions.map { position in
          SeedEvidence.PerPositionOutcome(
            promptID: caseItem.promptID,
            position: position.position,
            llamaTopOneTokenID: position.llamaTopOneTokenID,
            referenceInLlamaTopK: position.referenceInLlamaTopK,
            referenceRankInLlama: position.referenceRankInLlama
          )
        }
      }
    )
  }
}
