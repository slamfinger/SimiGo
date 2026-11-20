import XCTest
@testable import SimiGo

final class KVCacheSettingsTests: XCTestCase {
    func testNilSettingsMapToNilConfiguration() throws {
        XCTAssertNil(try NativeMLX.makeKVCacheConfiguration(nil))
    }

    func testAffinePresetsMapToOfficialStrategies() throws {
        let fourBit = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "affine4"))
        XCTAssertEqual(fourBit?.strategy, .affine(.fourBit))

        let eightBit = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "affine8"))
        XCTAssertEqual(eightBit?.strategy, .affine(.eightBit))
    }

    func testTurboPresetsMapToOfficialStrategies() throws {
        let quality = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "turboQuality"))
        XCTAssertEqual(quality?.strategy, .turboQuant(.qualityFirst))

        let balanced = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "turboBalanced"))
        XCTAssertEqual(balanced?.strategy, .turboQuant(.balanced))

        let memory = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "turboMemory"))
        XCTAssertEqual(memory?.strategy, .turboQuant(.memoryFirst))
    }

    func testFullPrecisionIsTheDefaultStrategy() throws {
        let none = try NativeMLX.makeKVCacheConfiguration(KVCacheSettings())
        XCTAssertEqual(none?.strategy, .fullPrecision)

        let explicit = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "fullPrecision"))
        XCTAssertEqual(explicit?.strategy, .fullPrecision)
    }

    func testCapacityMappingUsesOfficialDefaults() throws {
        let config = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "affine4", maxTokens: 8192))
        XCTAssertEqual(config?.capacity?.maxTokens, 8192)
        XCTAssertEqual(config?.capacity?.preservedPrefixTokens, 4)

        let custom = try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(maxTokens: 4096, preservedPrefixTokens: 8))
        XCTAssertEqual(custom?.capacity?.maxTokens, 4096)
        XCTAssertEqual(custom?.capacity?.preservedPrefixTokens, 8)
    }

    func testUnknownStrategyFailsFast() {
        XCTAssertThrowsError(try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(strategy: "aggressive")))
    }

    func testPreservedPrefixRequiresCapacity() {
        XCTAssertThrowsError(try NativeMLX.makeKVCacheConfiguration(
            KVCacheSettings(preservedPrefixTokens: 8)))
    }

    func testModelConfigDecodesOptionalKVCache() throws {
        // ModelConfig 的合成解码要求全部非可选键，用编解码往返验证：
        let withoutKV = try JSONDecoder().decode(
            ModelConfig.self, from: try JSONEncoder().encode(ModelConfig()))
        XCTAssertNil(withoutKV.kvCache)

        var withKV = ModelConfig()
        withKV.kvCache = KVCacheSettings(strategy: "affine4", maxTokens: 8192)
        let decoded = try JSONDecoder().decode(
            ModelConfig.self, from: try JSONEncoder().encode(withKV))
        XCTAssertEqual(
            decoded.kvCache, KVCacheSettings(strategy: "affine4", maxTokens: 8192))
    }

    func testPrefillEstimateOnlyTokenizesWhenByteBoundCanCrossATier() {
        XCTAssertFalse(NativeMLX.shouldRefinePrefillContextEstimate(
            roughContextTokens: 15_999,
            maximumContextTokens: 63_999))
        XCTAssertTrue(NativeMLX.shouldRefinePrefillContextEstimate(
            roughContextTokens: 60_000,
            maximumContextTokens: 64_000))
        XCTAssertFalse(NativeMLX.shouldRefinePrefillContextEstimate(
            roughContextTokens: 100_000,
            maximumContextTokens: 110_000))
    }

    func testPrefillEstimateRefinesMaterialUnderestimateForWarmSession() {
        let refined = NativeMLX.refinedPrefillContextEstimate(
            roughContextTokens: 60_000,
            cacheTokensBefore: 50_000,
            exactIncomingContentTokens: 18_000,
            reusedSession: true)
        XCTAssertEqual(refined, 68_000)
    }

    func testPrefillEstimateKeepsCheapEstimateWhenTokenizerDoesNotCrossStepTier() {
        let estimate = NativeMLX.refinedPrefillContextEstimate(
            roughContextTokens: 60_000,
            cacheTokensBefore: 50_000,
            exactIncomingContentTokens: 12_000,
            reusedSession: true)
        XCTAssertEqual(estimate, 60_000)
    }

    func testPrefillEstimateCorrectsSmallDeltaThatCrossesNinetySixKTier() {
        let estimate = NativeMLX.refinedPrefillContextEstimate(
            roughContextTokens: 90_000,
            cacheTokensBefore: 89_000,
            exactIncomingContentTokens: 11_000,
            reusedSession: true)
        XCTAssertEqual(estimate, 100_000)
    }

    func testColdPrefillEstimateDoesNotAddAStaleCachePrefix() {
        let estimate = NativeMLX.refinedPrefillContextEstimate(
            roughContextTokens: 40_000,
            cacheTokensBefore: 30_000,
            exactIncomingContentTokens: 70_000,
            reusedSession: false)
        XCTAssertEqual(estimate, 70_000)
    }

    func testPrefillEstimateFallsBackToCheapEstimateWithoutTokenizerResult() {
        let estimate = NativeMLX.refinedPrefillContextEstimate(
            roughContextTokens: 60_000,
            cacheTokensBefore: 50_000,
            exactIncomingContentTokens: nil,
            reusedSession: true)
        XCTAssertEqual(estimate, 60_000)
    }

}
