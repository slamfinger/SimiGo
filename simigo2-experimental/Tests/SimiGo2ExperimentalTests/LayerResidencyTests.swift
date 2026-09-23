import Foundation
import XCTest

@testable import SimiGo2Experimental

final class LayerResidencyTests: XCTestCase {
    private func inventory() -> LayerInventory {
        func tensor(_ name: String, bytes: Int64) -> TensorEntry {
            TensorEntry(id: name, file: "test.safetensors", dtype: "U32", shape: [1], byteCount: bytes)
        }

        return LayerGroupCatalog.qwen3CoderGroups(from: [
            tensor("model.embed_tokens.weight", bytes: 100),
            tensor("model.layers.0.self_attn.q_proj.weight", bytes: 50),
            tensor("model.layers.0.mlp.switch_mlp.down_proj.weight", bytes: 200),
            tensor("model.layers.20.mlp.switch_mlp.down_proj.weight", bytes: 300),
            tensor("model.layers.40.mlp.switch_mlp.down_proj.weight", bytes: 400)
        ])
    }

    func testQwen3PartitionGroupsSwitchMLPByLayerRange() {
        let inventory = inventory()
        let groups = Dictionary(uniqueKeysWithValues: inventory.groups.map { ($0.id, $0) })

        XCTAssertEqual(groups["CORE_NON_SWITCH"]?.tensorCount, 2)
        XCTAssertEqual(groups["SWITCH_MLP_L00_15"]?.tensorCount, 1)
        XCTAssertEqual(groups["SWITCH_MLP_L16_31"]?.tensorCount, 1)
        XCTAssertEqual(groups["SWITCH_MLP_L32_47"]?.tensorCount, 1)
    }

    func testPolicyAlwaysKeepsCoreAndMapsStateGroups() throws {
        let inventory = inventory()
        let policy = Qwen3CoderStatePolicy(inventory: inventory)

        XCTAssertEqual(
            policy.desiredGroupIDs(for: .stateA),
            ["CORE_NON_SWITCH", "SWITCH_MLP_L00_15"]
        )
        XCTAssertEqual(
            policy.desiredGroupIDs(for: .stateAll),
            Set(inventory.groups.map(\.id))
        )
    }

    func testEngineLoadsAndEvictsDeltasOnly() throws {
        var engine = LayerResidencyEngine(inventory: inventory(), policy: Qwen3CoderStatePolicy(inventory: inventory()))
        let first = try engine.transition(to: .stateA)
        let second = try engine.transition(to: .stateB)

        XCTAssertTrue(first.loadedGroupIDs.contains("CORE_NON_SWITCH"))
        XCTAssertTrue(first.loadedGroupIDs.contains("SWITCH_MLP_L00_15"))
        XCTAssertTrue(second.loadedGroupIDs.contains("SWITCH_MLP_L16_31"))
        XCTAssertTrue(second.evictedGroupIDs.contains("SWITCH_MLP_L00_15"))
        XCTAssertTrue(second.residentGroupIDs.contains("CORE_NON_SWITCH"))
    }

    func testLlamaCppLazyPolicyKeepsCoreAndAdmitsOptionalGroups() throws {
        let inventory = inventory()
        let policy = AnyLayerResidencyPolicy(
            kind: .llamaCppLazy,
            inventory: inventory,
            llamaOptions: LlamaCppControlOptions(
                maxOptionalResidentGroups: 2,
                usesMemoryMap: true,
                allowsLazyMaterialization: true,
                placement: "METAL_PREFERRED"
            )
        )

        XCTAssertEqual(
            policy.desiredGroupIDs(for: .stateA),
            ["CORE_NON_SWITCH", "SWITCH_MLP_L00_15"]
        )
        XCTAssertTrue(policy.desiredGroupIDs(for: .stateAB).contains("CORE_NON_SWITCH"))
        XCTAssertTrue(policy.desiredGroupIDs(for: .stateAB).contains("SWITCH_MLP_L00_15"))
        XCTAssertTrue(policy.desiredGroupIDs(for: .stateAB).contains("SWITCH_MLP_L16_31"))
    }

    func testResidencyBenchmarkReportsAllPolicies() throws {
        let reports = try ResidencyBenchmark.run(
            kinds: ResidencyPolicyKind.allCases,
            inventory: inventory(),
            states: [.stateA, .stateB, .stateAB]
        )

        XCTAssertEqual(reports.count, ResidencyPolicyKind.allCases.count)
        XCTAssertEqual(Set(reports.map(\.policy)), Set(ResidencyPolicyKind.allCases))
    }
}
