import Foundation

public struct LayerDemandCSVRow: Sendable {
    public let experimentID: String
    public let sampleID: String
    public let category: String
    public let taskForm: String
    public let lengthBucket: String
    public let groupID: String
    public let evidenceKind: String
    public let baselineMetric: Double?
    public let interventionMetric: Double?
    public let demandMetric: Double?
    public let runtimeMilliseconds: Double?
    public let restored: Bool

    public init(
        experimentID: String,
        sampleID: String,
        category: String,
        taskForm: String,
        lengthBucket: String,
        groupID: String,
        evidenceKind: String,
        baselineMetric: Double?,
        interventionMetric: Double?,
        demandMetric: Double?,
        runtimeMilliseconds: Double?,
        restored: Bool
    ) {
        self.experimentID = experimentID
        self.sampleID = sampleID
        self.category = category
        self.taskForm = taskForm
        self.lengthBucket = lengthBucket
        self.groupID = groupID
        self.evidenceKind = evidenceKind
        self.baselineMetric = baselineMetric
        self.interventionMetric = interventionMetric
        self.demandMetric = demandMetric
        self.runtimeMilliseconds = runtimeMilliseconds
        self.restored = restored
    }
}

public enum LayerDemandCSV {
    public static let header = "experiment_id,sample_id,category,task_form,length_bucket,group_id,evidence_kind,baseline_metric,intervention_metric,demand_metric,runtime_ms,restored"

    public static func encode(_ rows: [LayerDemandCSVRow]) -> String {
        var lines = [header]
        lines.reserveCapacity(rows.count + 1)
        for row in rows {
            lines.append([
                field(row.experimentID),
                field(row.sampleID),
                field(row.category),
                field(row.taskForm),
                field(row.lengthBucket),
                field(row.groupID),
                field(row.evidenceKind),
                number(row.baselineMetric),
                number(row.interventionMetric),
                number(row.demandMetric),
                number(row.runtimeMilliseconds),
                row.restored ? "true" : "false"
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func field(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }
}
