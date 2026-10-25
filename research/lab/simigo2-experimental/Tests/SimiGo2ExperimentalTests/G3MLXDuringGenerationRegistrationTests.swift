// SPDX-License-Identifier: MIT

// NATIVE DURING-GENERATION REGISTRATION TESTS (MLX layer)
//
// The contract layer proves the CHANNEL is live: the dual-arm runner seals each
// arm, obtains its G3AllocationRegistrar, and threads it into the gated
// continuation. These tests close the other half — that a REAL MLXArray allocated
// during generation is mapped by the SAME native identity read the pre-generation
// snapshot used, and that the sealed owner therefore genuinely constrains it:
//
//   * a materialized array yields a CONFIRMED storage id (never the Swift wrapper
//     id, never the ArrayDesc `id()`), so it can be compared across arms;
//   * a buffer that aliases the peer's live mutable storage (a reshaped view of
//     the peer's tensor) is REFUSED, and the refusal is recorded;
//   * an independently allocated equal-content tensor is ADMITTED — content
//     equality is not aliasing, so the channel is not a blanket refusal;
//   * an unmaterialized (lazy) allocation has no confirmable identity and is
//     REFUSED fail-closed;
//   * a collection of KV buffers is enumerated per buffer, so one aliased block
//     inside an otherwise fresh list is still caught.
//
// Small tensors only; no model load, no G3 execution, no emitter trust registered.

import Foundation
import Testing
import MLX
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

struct G3MLXDuringGenerationRegistrationTests {

    /// Metal device initialization, identical to the storage-identity suite: the
    /// CLI test runner does not register the built Cmlx bundle for MLX's automatic
    /// lookup, so the metallib is located explicitly rather than the tests
    /// silently skipping (a skipped isolation test is not evidence).
    private static let ensureRuntime: Void = {
        let fm = FileManager.default
        if let path = ProcessInfo.processInfo.environment["SIMIGO_MLX_METALLIB"],
           !path.isEmpty, fm.fileExists(atPath: path) {
            GPU.metallib = URL(fileURLWithPath: path)
            return
        }
        let relative = "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.bundleURL.appendingPathComponent("../Resources")]
        for base in bases {
            let cand = base?.appendingPathComponent(relative)
            if let cand, fm.fileExists(atPath: cand.path) {
                GPU.metallib = cand
                return
            }
        }
        let build = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(".build")
        if let enumerator = fm.enumerator(at: build, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator
            where url.path.hasSuffix(relative) {
                GPU.metallib = url
                break
            }
        }
    }()

    private func mlx() { _ = Self.ensureRuntime }

    // MARK: Model-free arm builders

    private func resource(
        _ role: G3ResourceRole, id: String, arm: String, access: G3ResourceAccess = .armExclusiveMutable
    ) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: arm, access: access, storage: .confirmed(id))
    }

    /// A per-arm owner whose fixed mutable stores are arm-unique, so two of these
    /// pass the pre-generation snapshot and only a DURING-generation allocation can
    /// break isolation.
    private func makeArm(_ arm: String, writeRoot: String) -> G3ArmResourceOwner {
        G3ArmResourceOwner(
            armID: RuntimeArmID(arm), isolationUnitID: "iso-\(arm)",
            modelWeights: resource(.modelWeights, id: "weights-\(arm)", arm: arm, access: .sharedReadOnly),
            modelContentSHA256: String(repeating: "a", count: 64),
            tokenizerData: OwnedResource(
                role: .tokenizerData, ownerLabel: arm, access: .sharedReadOnly, storage: .indeterminate),
            tokenizerContentSHA256: String(repeating: "b", count: 64),
            kvCache: resource(.kvCache, id: "kv-\(arm)", arm: arm),
            prefixCache: resource(.prefixCache, id: "prefix-\(arm)", arm: arm),
            runtimeScratch: resource(.runtimeScratch, id: "scratch-\(arm)", arm: arm),
            mutableResources: [resource(.extraMutable, id: "extra-\(arm)", arm: arm)],
            writeRoot: writeRoot)
    }

    /// Map a real object exactly the way the wired probe does.
    private func mapped(_ object: AnyObject, role: G3ResourceRole, arm: String) -> [OwnedResource] {
        G3MLXRuntimeResourceProbe.mapAllocation(object, role: role, armLabel: arm)
    }

    /// Map a layer-indexed cache collection through the same production entry point.
    private func mapped(_ arrays: [MLXArray], role: G3ResourceRole, arm: String) -> [OwnedResource] {
        G3MLXRuntimeResourceProbe.mapAllocation(arrays, role: role, armLabel: arm)
    }

    // MARK: A real allocation gets a confirmable identity

    @Test func materializedAllocationMapsToConfirmedStorageIdentity() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let block = ones([16], dtype: .float32)
            block.eval()

            let mapped = mapped(block, role: .kvCache, arm: "ES+IS")
            #expect(mapped.count == 1)
            let storage = mapped[0].storage
            #expect(storage.isConfirmed, "a materialized buffer must be confirmable, got \(storage)")
            // Keyed on the native axes, not on ObjectIdentifier / ArrayDesc ids.
            let si = block.mlxStorageIdentity
            #expect(storage.confirmedID == "mlx:d=\(si.dataDescriptor):b=\(si.bufferHandle)")
            #expect(mapped[0].access == .armExclusiveMutable)
        }
    }

    // MARK: An allocation aliasing the peer is refused by the sealed owner

    @Test func allocationAliasingPeerStorageIsRefused() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let es = makeArm("ES+IS", writeRoot: "/tmp/g3/es")
            let armB = makeArm("IS-only", writeRoot: "/tmp/g3/is")
            // The snapshot passes: each arm's own mutable stores are disjoint.
            #expect(G3OwnershipIsolation.check(es, armB).passed)
            es.seal(against: armB)
            armB.seal(against: es)

            // Arm ES+IS materializes a KV block during generation; arm IS-only's
            // next block is a VIEW of that same buffer (a real MLX aliasing shape).
            let esBlock = ones([8], dtype: .float32)
            esBlock.eval()
            let aliasView = esBlock.reshaped([4, 2])
            aliasView.eval()

            guard let registrar = armB.makeRegistrar() else {
                Issue.record("a sealed owner must hand out a registrar")
                return
            }
            try registrar.registerAll(mapped(esBlock, role: .kvCache, arm: "ES+IS"))

            #expect(throws: G3AllocationRegistrar.RegistrationError.self) {
                try registrar.registerAll(mapped(aliasView, role: .kvCache, arm: "IS-only"))
            }
            // The refusal is recorded, not swallowed: the run report surfaces it.
            let violations = es.allocationViolations + armB.allocationViolations
            #expect(violations.contains { $0.hasPrefix("shared_mutable_storage") },
                    "got \(violations)")
        }
    }

    // MARK: An independent equal-content allocation is admitted

    @Test func independentEqualAllocationIsAdmitted() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let es = makeArm("ES+IS", writeRoot: "/tmp/g3/es")
            let armB = makeArm("IS-only", writeRoot: "/tmp/g3/is")
            es.seal(against: armB)
            armB.seal(against: es)

            let peer = ones([8], dtype: .float32)
            peer.eval()
            let mine = ones([8], dtype: .float32)   // identical content, own buffer
            mine.eval()

            guard let registrar = es.makeRegistrar() else {
                Issue.record("a sealed owner must hand out a registrar")
                return
            }
            try registrar.registerAll(mapped(peer, role: .kvCache, arm: "IS-only"))
            // Content equality is not aliasing — refusing this would make the
            // channel useless as a control, so this is the positive case.
            try registrar.registerAll(mapped(mine, role: .kvCache, arm: "ES+IS"))
            #expect(es.allocationViolations.isEmpty)
            #expect(es.confirmedMutableIDs.contains {
                $0 == mapped(mine, role: .kvCache, arm: "ES+IS")[0].storage.confirmedID
            })
        }
    }

    // MARK: An unobservable allocation fails closed

    @Test func unmaterializedAllocationIsRefusedFailClosed() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let es = makeArm("ES+IS", writeRoot: "/tmp/g3/es")
            let armB = makeArm("IS-only", writeRoot: "/tmp/g3/is")
            es.seal(against: armB)
            armB.seal(against: es)

            let base = ones([4], dtype: .float32)
            base.eval()
            let lazy = base * 2          // never evaluated: no backing to observe

            let mapped = mapped(lazy, role: .runtimeScratch, arm: "ES+IS")
            #expect(!mapped[0].storage.isConfirmed,
                    "an unevaluated array must not present a confirmed identity")

            guard let registrar = es.makeRegistrar() else {
                Issue.record("a sealed owner must hand out a registrar")
                return
            }
            #expect(throws: G3AllocationRegistrar.RegistrationError.violation(
                        reason: "indeterminate_storage_identity(runtime_scratch)")) {
                try registrar.registerAll(mapped)
            }
        }
    }

    // MARK: A KV list is enumerated per buffer

    @Test func collectionAllocationIsEnumeratedPerBuffer() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let es = makeArm("ES+IS", writeRoot: "/tmp/g3/es")
            let armB = makeArm("IS-only", writeRoot: "/tmp/g3/is")
            es.seal(against: armB)
            armB.seal(against: es)

            // Two genuinely fresh layers plus one that aliases an IS-only buffer.
            let peerLayer = ones([4], dtype: .float32)
            peerLayer.eval()
            let freshA = zeros([4], dtype: .float32); freshA.eval()
            let freshB = zeros([4], dtype: .float32); freshB.eval()
            let aliased = peerLayer.reshaped([2, 2]); aliased.eval()

            guard let registrar = es.makeRegistrar() else {
                Issue.record("a sealed owner must hand out a registrar")
                return
            }
            try registrar.registerAll(mapped(peerLayer, role: .kvCache, arm: "IS-only"))

            let layers: [MLXArray] = [freshA, freshB, aliased]
            let mappedLayers = mapped(layers, role: .kvCache, arm: "ES+IS")
            // head aggregate + one entry per buffer, so every block is compared.
            #expect(mappedLayers.count == layers.count + 1)
            #expect(throws: G3AllocationRegistrar.RegistrationError.self) {
                try registrar.registerAll(mappedLayers)
            }
            #expect(es.allocationViolations.contains { $0.hasPrefix("shared_mutable_storage") },
                    "a single aliased block inside a mostly-fresh list must still be caught")
        }
    }

    // MARK: Registration is not a pre-run snapshot

    @Test func allocationAdmittedByOneArmIsVisibleToThePeerLive() throws {
        mlx()
        try Device.withDefaultDevice(.cpu) {
            let es = makeArm("ES+IS", writeRoot: "/tmp/g3/es")
            let armB = makeArm("IS-only", writeRoot: "/tmp/g3/is")
            // Snapshot decision before the allocation: the two arms are isolated.
            #expect(G3OwnershipIsolation.check(es, armB).passed)
            es.seal(against: armB)
            armB.seal(against: es)

            let block = ones([4], dtype: .float32)
            block.eval()
            let resources = mapped(block, role: .prefixCache, arm: "ES+IS")
            let id = try #require(resources[0].storage.confirmedID)

            guard let esRegistrar = es.makeRegistrar(),
                  let isRegistrar = armB.makeRegistrar() else {
                Issue.record("a sealed owner must hand out a registrar")
                return
            }
            // The peer cannot see a buffer ES+IS has not allocated yet.
            #expect(!armB.confirmedMutableIDs.contains(id))
            #expect(!es.confirmedMutableIDs.contains(id))

            try esRegistrar.registerAll(resources)
            // The allocation enters the LIVE set the peer is checked against, so
            // the isolation decision now covers a buffer that did not exist when
            // the pre-generation snapshot was taken.
            #expect(es.confirmedMutableIDs.contains(id))

            // A wrapper the other arm materializes over the SAME buffer is refused
            // purely because of the during-generation registration — the snapshot
            // could never have caught it.
            let peerView = block.reshaped([2, 2])
            peerView.eval()
            #expect(throws: G3AllocationRegistrar.RegistrationError.self) {
                try isRegistrar.registerAll(mapped(peerView, role: .prefixCache, arm: "IS-only"))
            }
            #expect(armB.allocationViolations.contains { $0.hasPrefix("shared_mutable_storage") },
                    "got \(armB.allocationViolations)")
        }
    }
}
