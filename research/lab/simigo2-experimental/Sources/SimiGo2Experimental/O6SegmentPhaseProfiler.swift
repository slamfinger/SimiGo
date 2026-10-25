import Foundation
import MLX
import MLXLMCommon
import Tokenizers

public struct O6SegmentPhaseMeasurement: Encodable, Sendable {
    public let segmentIndex: Int
    public let layerRange: String
    public let materializeMs: Double
    public let forwardMs: Double
    public let releaseMs: Double
    public let materializeTransitionDelta: Int
}

public struct O6TokenPhaseProfile: Encodable, Sendable {
    public let inputTokenCount: Int
    public let embedMs: Double
    public let segments: [O6SegmentPhaseMeasurement]
    public let logitsMs: Double
    public let totalMs: Double
    public let generatedTokenID: Int
    public let peakFootprintMiB: Int64
    public let maxSwapMiB: Int64
    public let segmentTransitions: Int
}

/// One targeted phase-attribution probe. This is not a throughput benchmark.
public enum O6SegmentPhaseProfiler {
    public struct Measurement: Encodable, Sendable {
        public let sampleIndex: Int
        public let profile: O6TokenPhaseProfile
    }

    public struct Report: Encodable, Sendable {
        public let status: String
        public let protocolVersion: String
        public let boundary: String
        public let modelDirectory: String
    public let prefixTokenLength: Int
    public let prefixTokenIDs: [Int]
    public let segmentSize: Int
        public let segmentCount: Int
        public let measuredSamples: Int
        public let generatedTokenIDs: [Int]
        public let measurements: [Measurement]
        public let peakFootprintMiB: Int64
        public let maxSwapMiB: Int64
        public let segmentTransitions: Int
        public let overallPass: Bool
    }

    public static let protocolVersion = "LAB.MLX.O6.SEGMENT.PHASE.PROFILE.V1"
    public static let boundary =
        "PHASE_ISOLATED_ONE_TOKEN_PROFILE / SMALL_SAMPLE / NO_EXECUTION_STATE_ACTION / "
        + "NOT_A_PERFORMANCE_BENCHMARK"

    public static func run(
        modelDirectory: URL,
        seedText: String = "def is_palindrome(s):",
        inputText: String = "Explain it briefly.",
        prefixTokenLength: Int = 64,
        segmentSize: Int = 8,
        measuredSamples: Int = 1
    ) async throws -> Report {
        precondition(prefixTokenLength > 0 && measuredSamples > 0)
        let core = try await O6SegmentedCore(
            modelDirectory: modelDirectory, segmentSize: segmentSize
        )
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: modelDirectory)
        let seedTokens = tokenizer.encode(text: seedText, addSpecialTokens: true)
        let inputTokens = tokenizer.encode(text: inputText, addSpecialTokens: false)
        var prefix = seedTokens + inputTokens
        while prefix.count < prefixTokenLength {
            prefix.append(contentsOf: inputTokens)
        }
        prefix = Array(prefix.prefix(prefixTokenLength))

        // Warm the token path once so measured samples do not include first-touch load.
        _ = try core.greedy(prefix: prefix, maxTokens: 1)

        var measurements: [Measurement] = []
        var generated: [Int] = []
        var rollingPrefix = prefix
        for index in 0..<measuredSamples {
            let profile = try core.profileToken(
                prefix: rollingPrefix, nextInputTokens: []
            )
            generated.append(profile.generatedTokenID)
            rollingPrefix.append(profile.generatedTokenID)
            measurements.append(Measurement(sampleIndex: index, profile: profile))
        }

        let structuralPass = measurements.allSatisfy { measurement in
            measurement.profile.segments.count == core.segments.count
            && measurement.profile.segments.allSatisfy { $0.materializeTransitionDelta == 1 }
            && measurement.profile.maxSwapMiB == 0
        }

        return Report(
            status: structuralPass ? "PASS" : "FAIL",
            protocolVersion: protocolVersion,
            boundary: boundary,
            modelDirectory: modelDirectory.path,
            prefixTokenLength: prefixTokenLength,
            prefixTokenIDs: prefix,
            segmentSize: segmentSize,
            segmentCount: core.segments.count,
            measuredSamples: measurements.count,
            generatedTokenIDs: generated,
            measurements: measurements,
            peakFootprintMiB: core.peakFootprintMiB,
            maxSwapMiB: core.maxSwapMiB,
            segmentTransitions: core.segmentTransitions,
            overallPass: structuralPass
        )
    }

    public static func runFixedPrefix(
        modelDirectory: URL,
        prefixTokenIDs: [Int],
        prefixTokenLength: Int,
        segmentSize: Int = 8,
        measuredSamples: Int = 3
    ) async throws -> Report {
        precondition(prefixTokenIDs.count >= prefixTokenLength)
        precondition(prefixTokenLength > 0 && measuredSamples > 0)
        let core = try await O6SegmentedCore(
            modelDirectory: modelDirectory, segmentSize: segmentSize
        )
        let prefix = Array(prefixTokenIDs.prefix(prefixTokenLength))

        _ = try core.greedy(prefix: prefix, maxTokens: 1)

        var measurements: [Measurement] = []
        var generated: [Int] = []
        var rollingPrefix = prefix
        for index in 0..<measuredSamples {
            let profile = try core.profileToken(prefix: rollingPrefix, nextInputTokens: [])
            generated.append(profile.generatedTokenID)
            rollingPrefix.append(profile.generatedTokenID)
            measurements.append(Measurement(sampleIndex: index, profile: profile))
        }

        let structuralPass = measurements.allSatisfy { measurement in
            measurement.profile.segments.count == core.segments.count
            && measurement.profile.segments.allSatisfy { $0.materializeTransitionDelta == 1 }
            && measurement.profile.maxSwapMiB == 0
        }

        return Report(
            status: structuralPass ? "PASS" : "FAIL",
            protocolVersion: "LAB.MLX.O6.SEGMENT.PHASE.PROFILE.FIXED.V1",
            boundary: "FIXED_TOKEN_IDS / CONTENT_CONFOUND_CONTROLLED / SMALL_SAMPLE / "
                + "NO_EXECUTION_STATE_ACTION / NOT_A_PERFORMANCE_BENCHMARK",
            modelDirectory: modelDirectory.path,
            prefixTokenLength: prefixTokenLength,
            prefixTokenIDs: prefix,
            segmentSize: segmentSize,
            segmentCount: core.segments.count,
            measuredSamples: measurements.count,
            generatedTokenIDs: generated,
            measurements: measurements,
            peakFootprintMiB: core.peakFootprintMiB,
            maxSwapMiB: core.maxSwapMiB,
            segmentTransitions: core.segmentTransitions,
            overallPass: structuralPass
        )
    }
}
