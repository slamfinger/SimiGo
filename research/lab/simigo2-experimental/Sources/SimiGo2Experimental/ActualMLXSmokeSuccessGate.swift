import SimiGoRuntimeContract

/// Explicit, layer-separated acceptance checks for the isolated MLX smoke.
/// Execution State advancement, Information Space settlements, and Swift
/// runtime application are related but distinct carrier states.
public enum ActualMLXSmokeSuccessGate {
    public static let requiredSettlementIDs = [
        "REAL-COLLECTION",
        "REAL-SEGMENT",
        "REAL-1",
        "REAL-2",
        "REAL-3",
        "REAL-4",
        "REAL-5",
        "REAL-6",
        "REAL-7",
    ]

    public struct Observation {
        public let reportAdvanced: Bool
        public let reportState: String
        public let finalPosition: Int64
        public let finalLifecycle: String
        public let boundRepresentationTokenCount: Int
        public let executionStateStatus: String
        public let runtimeApplicationStatus: String
        public let settlementStates: [String: String]
        public let pendingObligationsRead: Bool
        public let pendingObligationCount: Int
        public let carrierObjectsVerified: Bool
        public let carrierDatabasePresent: Bool

        public init(
            reportAdvanced: Bool,
            reportState: String,
            finalPosition: Int64,
            finalLifecycle: String,
            boundRepresentationTokenCount: Int,
            executionStateStatus: String,
            runtimeApplicationStatus: String,
            settlementStates: [String: String],
            pendingObligationsRead: Bool,
            pendingObligationCount: Int,
            carrierObjectsVerified: Bool,
            carrierDatabasePresent: Bool
        ) {
            self.reportAdvanced = reportAdvanced
            self.reportState = reportState
            self.finalPosition = finalPosition
            self.finalLifecycle = finalLifecycle
            self.boundRepresentationTokenCount = boundRepresentationTokenCount
            self.executionStateStatus = executionStateStatus
            self.runtimeApplicationStatus = runtimeApplicationStatus
            self.settlementStates = settlementStates
            self.pendingObligationsRead = pendingObligationsRead
            self.pendingObligationCount = pendingObligationCount
            self.carrierObjectsVerified = carrierObjectsVerified
            self.carrierDatabasePresent = carrierDatabasePresent
        }
    }

    public static func evaluate(_ observation: Observation) -> (passed: Bool, checks: [String: Bool]) {
        let requiredSettlementsSettled = !observation.settlementStates.isEmpty
            && requiredSettlementIDs.allSatisfy { id in
                observation.settlementStates[id] == "SETTLED"
            }
        let checks: [String: Bool] = [
            "report_advanced": observation.reportAdvanced && observation.reportState == "ADVANCED",
            "execution_state_advanced": observation.executionStateStatus == "ADVANCED",
            "runtime_application_applied": observation.runtimeApplicationStatus == "APPLIED_SWIFT",
            "required_settlements_settled": requiredSettlementsSettled,
            "final_position_one": observation.finalPosition == 1,
            "final_lifecycle_active": observation.finalLifecycle == "active",
            "representation_bound": observation.boundRepresentationTokenCount > 0,
            "no_pending_obligations": observation.pendingObligationsRead
                && observation.pendingObligationCount == 0,
            "carrier_objects_verified": observation.carrierObjectsVerified,
            "carrier_database_present": observation.carrierDatabasePresent,
        ]
        return (checks.values.allSatisfy { $0 }, checks)
    }
}

