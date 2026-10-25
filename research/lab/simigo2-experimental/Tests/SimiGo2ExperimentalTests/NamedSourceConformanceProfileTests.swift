import XCTest

@testable import SimiGo2Experimental

final class NamedSourceConformanceProfileTests: XCTestCase {
  private func outcome(
    promptID: String,
    position: Int,
    topOne: Int,
    contained: Bool = true,
    rank: Int? = 0
  ) -> NamedSourceConformanceProfile.SeedEvidence.PerPositionOutcome {
    .init(
      promptID: promptID,
      position: position,
      llamaTopOneTokenID: topOne,
      referenceInLlamaTopK: contained,
      referenceRankInLlama: rank
    )
  }

  private func evidence(seed: Int, outcomes: [NamedSourceConformanceProfile.SeedEvidence.PerPositionOutcome]) -> NamedSourceConformanceProfile.SeedEvidence {
    .init(
      seed: seed,
      positionCount: outcomes.count,
      topOneAgreementCount: outcomes.count - outcomes.filter { $0.referenceRankInLlama != 0 }.count,
      topOneAgreementRatio: Double(outcomes.count - outcomes.filter { $0.referenceRankInLlama != 0 }.count) / Double(outcomes.count),
      topKContainmentCount: outcomes.filter(\.referenceInLlamaTopK).count,
      maximumReferenceRank: outcomes.compactMap(\.referenceRankInLlama).max() ?? 0,
      topOneFlipCount: outcomes.filter { $0.referenceRankInLlama != 0 }.count,
      perPositionOutcomes: outcomes
    )
  }

  func testTwoSeedIdenticalNearBoundaryOutcomesPass() {
    let outcomes = [
      outcome(promptID: "P1", position: 0, topOne: 10),
      outcome(promptID: "P6", position: 8, topOne: 20, rank: 1),
    ]
    let result = NamedSourceConformanceProfile.evaluate(evidence: [
      evidence(seed: 42, outcomes: outcomes),
      evidence(seed: 43, outcomes: outcomes),
    ])

    XCTAssertTrue(result.pass)
    XCTAssertEqual([], result.failureReasons)
    XCTAssertEqual(2, result.seedCount)
    XCTAssertEqual(2, result.topOneFlipCount)
  }

  func testSingleSeedFails() {
    let outcomes = [outcome(promptID: "P1", position: 0, topOne: 10)]
    let result = NamedSourceConformanceProfile.evaluate(evidence: [
      evidence(seed: 42, outcomes: outcomes)
    ])

    XCTAssertFalse(result.pass)
    XCTAssertTrue(result.failureReasons.contains("INSUFFICIENT_SEEDS"))
  }

  func testRankThreeFails() {
    let outcomes = [
      outcome(promptID: "P1", position: 0, topOne: 10),
      outcome(promptID: "P6", position: 8, topOne: 20, rank: 3),
    ]
    let repeated = [evidence(seed: 42, outcomes: outcomes), evidence(seed: 43, outcomes: outcomes)]
    let result = NamedSourceConformanceProfile.evaluate(evidence: repeated)

    XCTAssertFalse(result.pass)
    XCTAssertTrue(result.failureReasons.contains("MAX_REFERENCE_RANK_FAILURE"))
  }

  func testSeedOutcomeMismatchFails() {
    let first = [
      outcome(promptID: "P1", position: 0, topOne: 10),
      outcome(promptID: "P6", position: 8, topOne: 20, rank: 1),
    ]
    let second = [
      outcome(promptID: "P1", position: 0, topOne: 99),
      outcome(promptID: "P6", position: 8, topOne: 20, rank: 1),
    ]
    let result = NamedSourceConformanceProfile.evaluate(evidence: [
      evidence(seed: 42, outcomes: first),
      evidence(seed: 43, outcomes: second),
    ])

    XCTAssertFalse(result.pass)
    XCTAssertTrue(result.failureReasons.contains("SEED_OUTCOME_MISMATCH"))
  }
}
