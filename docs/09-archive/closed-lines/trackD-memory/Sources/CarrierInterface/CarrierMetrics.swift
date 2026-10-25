import Foundation

public struct CarrierMetricSummary: Hashable, Sendable {
    public let name: String
    public let count: Int
    public let errorCount: Int
    public let p50Seconds: Double?
    public let p95Seconds: Double?
    public let p99Seconds: Double?
    public let maxSeconds: Double?
    public let totalSeconds: Double

    public init(
        name: String,
        count: Int,
        errorCount: Int,
        p50Seconds: Double?,
        p95Seconds: Double?,
        p99Seconds: Double?,
        maxSeconds: Double?,
        totalSeconds: Double
    ) {
        self.name = name
        self.count = count
        self.errorCount = errorCount
        self.p50Seconds = p50Seconds
        self.p95Seconds = p95Seconds
        self.p99Seconds = p99Seconds
        self.maxSeconds = maxSeconds
        self.totalSeconds = totalSeconds
    }
}

public actor CarrierMetricsCollector {
    private var samples: [String: [Double]] = [:]
    private var errors: [String: Int] = [:]

    public init() {}

    public func record(name: String, seconds: Double) {
        samples[name, default: []].append(seconds)
    }

    public func recordError(name: String) {
        errors[name, default: 0] += 1
    }

    public func summary(_ name: String) -> CarrierMetricSummary? {
        let values = (samples[name] ?? []).sorted()
        guard !values.isEmpty else {
            return CarrierMetricSummary(
                name: name,
                count: 0,
                errorCount: errors[name] ?? 0,
                p50Seconds: nil,
                p95Seconds: nil,
                p99Seconds: nil,
                maxSeconds: nil,
                totalSeconds: 0
            )
        }

        func percentile(_ fraction: Double) -> Double {
            let rank = max(1, Int((fraction * Double(values.count)).rounded(.up)))
            return values[rank - 1]
        }

        return CarrierMetricSummary(
            name: name,
            count: values.count,
            errorCount: errors[name] ?? 0,
            p50Seconds: percentile(0.50),
            p95Seconds: percentile(0.95),
            p99Seconds: percentile(0.99),
            maxSeconds: values.last,
            totalSeconds: values.reduce(0, +)
        )
    }

    public func summaries() -> [CarrierMetricSummary] {
        Set(samples.keys).map { name in
            // This is safe in an actor method; summary only reads current state.
            let copied = samples
            let values = (copied[name] ?? []).sorted()
            guard !values.isEmpty else {
                return CarrierMetricSummary(
                    name: name,
                    count: 0,
                    errorCount: errors[name] ?? 0,
                    p50Seconds: nil,
                    p95Seconds: nil,
                    p99Seconds: nil,
                    maxSeconds: nil,
                    totalSeconds: 0
                )
            }

            func percentile(_ fraction: Double) -> Double {
                let rank = max(1, Int((fraction * Double(values.count)).rounded(.up)))
                return values[rank - 1]
            }

            return CarrierMetricSummary(
                name: name,
                count: values.count,
                errorCount: errors[name] ?? 0,
                p50Seconds: percentile(0.50),
                p95Seconds: percentile(0.95),
                p99Seconds: percentile(0.99),
                maxSeconds: values.last,
                totalSeconds: values.reduce(0, +)
            )
        }
        .sorted { $0.name < $1.name }
    }
}
