import Foundation

public enum O6FixedPrefixPhaseStudy {
    public struct SizeReport: Encodable, Sendable {
        public let prefixTokenLength: Int
        public let segmentSize: Int
        public let segmentCount: Int
        public let sourceArtifact: String
        public let report: O6SegmentPhaseProfiler.Report
    }

    public struct Summary: Encodable, Sendable {
        public let status: String
        public let protocolVersion: String
        public let boundary: String
        public let modelDirectory: String
        public let prefixTokenIDCount: Int
        public let prefixTokenLengths: [Int]
        public let segmentSizes: [Int]
        public let measuredSamplesPerSize: Int
        public let sizeReports: [SizeReport]
        public let overallPass: Bool
    }

    public static let protocolVersion = "LAB.MLX.O6.FIXED.PREFIX.PHASE.STUDY.V1"
    public static let boundary =
        "SAME_LEADING_TOKEN_IDS / TEXT_TOKENIZER_CONFOUND_CONTROLLED / SMALL_SAMPLE / "
        + "NO_EXECUTION_STATE_ACTION / NOT_A_PERFORMANCE_BENCHMARK"

    public static func run(
        modelDirectory: URL,
        prefixTokenIDs: [Int],
        prefixTokenLengths: [Int] = [8, 64],
        segmentSize: Int = 8,
        measuredSamplesPerSize: Int = 3
    ) async throws -> Summary {
        precondition(prefixTokenIDs.count >= (prefixTokenLengths.max() ?? 0))
        precondition(!prefixTokenLengths.isEmpty && measuredSamplesPerSize > 0)
        var reports: [SizeReport] = []
        for length in prefixTokenLengths {
            let artifact = "mlx-fixed-prefix-phase-p\(length)-s\(segmentSize).json"
            let report = try await O6SegmentPhaseProfiler.runFixedPrefix(
                modelDirectory: modelDirectory,
                prefixTokenIDs: prefixTokenIDs,
                prefixTokenLength: length,
                segmentSize: segmentSize,
                measuredSamples: measuredSamplesPerSize
            )
            let data = try JSONEncoder().encode(report)
            try data.write(to: URL(fileURLWithPath: artifact))
            reports.append(
                SizeReport(
                    prefixTokenLength: length,
                    segmentSize: segmentSize,
                    segmentCount: report.segmentCount,
                    sourceArtifact: artifact,
                    report: report
                )
            )
        }
        let allPass = reports.allSatisfy { $0.report.overallPass }
        return Summary(
            status: allPass ? "PASS_WITH_BOUNDARY" : "FAIL",
            protocolVersion: protocolVersion,
            boundary: boundary,
            modelDirectory: modelDirectory.path,
            prefixTokenIDCount: prefixTokenIDs.count,
            prefixTokenLengths: prefixTokenLengths,
            segmentSizes: [segmentSize],
            measuredSamplesPerSize: measuredSamplesPerSize,
            sizeReports: reports,
            overallPass: allPass
        )
    }
}
