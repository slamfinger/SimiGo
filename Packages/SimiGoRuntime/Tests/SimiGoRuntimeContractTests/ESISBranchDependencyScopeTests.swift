import Foundation
import XCTest
@testable import SimiGoRuntimeContract

final class ESISBranchDependencyScopeTests: XCTestCase {
    private func database() throws -> (URL, ESISDatabase) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-branch-scope-\(UUID().uuidString).sqlite3")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func state(_ db: ESISDatabase, id: String, parent: String? = nil,
                       branchID: String? = nil) throws {
        try db.recordExecutionState(
            id: id, parentID: parent, modelIdentity: "branch-scope-test",
            position: 0, continuationID: "continuation-\(id)", anchor: "anchor-\(id)",
            lifecycle: "active", createdAt: Date(), branchID: branchID)
    }

    private func settlement(_ db: ESISDatabase, stateID: String) throws -> String {
        let settled = try SettlementAuthority.authorize(
            generatedText: "alpha beta gamma",
            contractJSON: InformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    func testWriteGraphPersistsForkBranchAndContinuationInheritance() throws {
        let (url, db) = try database()
        defer { db.close(); cleanup(url) }

        func graphState(_ id: String, parentID: String?, branchID: String?) -> ESISDatabase.GraphState {
            ESISDatabase.GraphState(
                id: id, parentID: parentID, modelIdentity: "branch-scope-test",
                createdAt: Date(), position: 0, continuationID: "continuation-\(id)",
                nextInput: "input-\(id)", anchor: "anchor-\(id)", prefix: [],
                lifecycle: "active", checkpointIDs: [], branchID: branchID)
        }

        try db.writeGraph(states: [
            graphState("root", parentID: nil, branchID: nil),
            graphState("fork-a", parentID: "root", branchID: "branch-a"),
            graphState("fork-a-child", parentID: "fork-a", branchID: nil)
        ], checkpoints: [])

        let stored = try db.readGraph().states
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        XCTAssertEqual(byID["root"]?.branchID, "root")
        XCTAssertEqual(byID["fork-a"]?.branchID, "branch-a")
        XCTAssertEqual(byID["fork-a-child"]?.branchID, "branch-a")
    }

    func testBranchLocalInvalidationStaysWithinOneBranch() throws {
        let (url, db) = try database()
        defer { db.close(); cleanup(url) }

        try state(db, id: "root")
        let base = try settlement(db, stateID: "root")

        try state(db, id: "a-root", parent: "root", branchID: "branch-a")
        let a = try settlement(db, stateID: "a-root")
        try db.addDependency(fromSettlement: a, toSettlement: base)
        try state(db, id: "a-child", parent: "a-root")
        let aChild = try settlement(db, stateID: "a-child")
        try db.addDependency(fromSettlement: aChild, toSettlement: a, scope: .branchLocal)

        try state(db, id: "b-root", parent: "root", branchID: "branch-b")
        let b = try settlement(db, stateID: "b-root")
        try db.addDependency(fromSettlement: b, toSettlement: base)
        try state(db, id: "b-child", parent: "b-root")
        let bChild = try settlement(db, stateID: "b-child")
        try db.addDependency(fromSettlement: bChild, toSettlement: b, scope: .branchLocal)

        let invalidated = Set(try db.invalidateSettlement(a))
        XCTAssertTrue(invalidated.contains(a))
        XCTAssertTrue(invalidated.contains(aChild))
        XCTAssertFalse(invalidated.contains(b))
        XCTAssertFalse(invalidated.contains(bChild))
        XCTAssertEqual(try db.settlementValidity(aChild), "invalid")
        XCTAssertEqual(try db.settlementValidity(b), "valid")
        XCTAssertEqual(try db.settlementValidity(bChild), "valid")
    }

    func testSharedBaseInvalidationFansOutAcrossSiblingBranches() throws {
        let (url, db) = try database()
        defer { db.close(); cleanup(url) }

        try state(db, id: "root")
        let base = try settlement(db, stateID: "root")

        try state(db, id: "a-root", parent: "root", branchID: "branch-a")
        let a = try settlement(db, stateID: "a-root")
        try db.addDependency(fromSettlement: a, toSettlement: base)
        try state(db, id: "a-child", parent: "a-root")
        let aChild = try settlement(db, stateID: "a-child")
        try db.addDependency(fromSettlement: aChild, toSettlement: a, scope: .branchLocal)

        try state(db, id: "b-root", parent: "root", branchID: "branch-b")
        let b = try settlement(db, stateID: "b-root")
        try db.addDependency(fromSettlement: b, toSettlement: base)
        try state(db, id: "b-child", parent: "b-root")
        let bChild = try settlement(db, stateID: "b-child")
        try db.addDependency(fromSettlement: bChild, toSettlement: b, scope: .branchLocal)

        let invalidated = Set(try db.invalidateSettlement(base))
        XCTAssertTrue(invalidated.isSuperset(of: [base, a, aChild, b, bChild]))
        for id in [base, a, aChild, b, bChild] {
            XCTAssertEqual(try db.settlementValidity(id), "invalid", id)
        }
    }

    func testBranchLocalDependencyRejectsCrossBranchEdge() throws {
        let (url, db) = try database()
        defer { db.close(); cleanup(url) }

        try state(db, id: "root")
        try state(db, id: "a-root", parent: "root", branchID: "branch-a")
        let a = try settlement(db, stateID: "a-root")
        try state(db, id: "b-root", parent: "root", branchID: "branch-b")
        let b = try settlement(db, stateID: "b-root")

        XCTAssertThrowsError(
            try db.addDependency(fromSettlement: b, toSettlement: a, scope: .branchLocal))
    }
}
