// SPDX-License-Identifier: MIT

// NATIVE MLXArray-LEVEL STORAGE-IDENTITY TESTS
//
// These exercise the real accessor added at the mlx-swift native boundary
// (`mlx_array_get_storage_identity` -> `MLXArray.mlxStorageIdentity`) against
// actual MLX arrays. They deliberately do NOT use contract-layer mocks: the
// question is whether the native runtime's `Data` descriptor + allocator
// buffer handle genuinely reveal aliasing. Small tensors only; no model load,
// no G3 execution.
//
// The GPU metallib is not present in this build environment, so every array is
// materialized on the CPU device via `Device.withDefaultDevice(.cpu)`.
//
// The four cases the reviewer required:
//   (a) different MLXArray wrappers over the SAME buffer  -> .shared
//   (b) a view of the same buffer with a different OFFSET -> .shared
//   (c) independently allocated arrays with EQUAL content -> .distinct
//   (d) an unmaterialized / unconfirmable backing         -> .indeterminate
// Plus the two-axis evidence rule: a missing or colliding-but-partial signal
// must never be upgraded to `.distinct`.

import Foundation
import Testing
import MLX

struct G3MLXArrayStorageIdentityTests {

    /// The GPU metallib is present in the built `mlx-swift_Cmlx.bundle`, but the
    /// CLI `swift test` runner does not register that bundle for MLX's automatic
    /// lookup, so the first Metal device query fails. We point MLX at the real
    /// metallib explicitly: honor `SIMIGO_MLX_METALLIB` when given, otherwise
    /// auto-locate the bundle beside the test resources. Without a reachable
    /// metallib the CPU backend still initializes the Metal device, so these
    /// tests must not silently skip — they fail loudly instead of faking evidence.
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
        // Last resort: the swift-testing runner does not expose the resource
        // bundle via Bundle.main, so scan the package's .build output for the
        // first built `default.metallib` inside the Cmlx bundle.
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

    // MARK: (a) same buffer, different wrapper

    /// `reshaped` produces a new `MLXArray` (new ArrayDesc / wrapper) but must
    /// share the base array's underlying storage. The identity has to see through
    /// the wrapper and report `.shared`.
    @Test func reshapedViewSharesStorage() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let base = ones([8], dtype: .float32)
            base.eval()
            let view = base.reshaped([2, 4])
            view.eval()

            let a = base.mlxStorageIdentity
            let b = view.mlxStorageIdentity

            #expect(a.materialized)
            #expect(b.materialized)
            // Wrapper (ObjectIdentifier-style / ArrayDesc) level they differ; the
            // storage identity must still connect them.
            #expect(a.relationship(to: b) == .shared,
                    "reshaped view must alias the base buffer (data=\(a.dataDescriptor) base=\(a.bufferHandle) view=\(b.bufferHandle))")
        }
    }

    // MARK: (b) same buffer, different offset

    /// `asStrided` with a nonzero offset gives a distinct logical view whose
    /// elements start later, but it is carved from the SAME allocator buffer. The
    /// base buffer handle must match, so the relationship is `.shared`.
    @Test func offsetViewOfSameBufferIsShared() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let base = MLXArray([0, 1, 2, 3, 4, 5, 6, 7])
            base.eval()
            // Strided view starting one element in — different offset, same buffer.
            let offsetView = asStrided(base, [7], strides: [1], offset: 1)
            offsetView.eval()

            let a = base.mlxStorageIdentity
            let b = offsetView.mlxStorageIdentity

            #expect(a.materialized)
            #expect(b.materialized)
            #expect(a.relationship(to: b) == .shared,
                    "offset view must still share the base allocation (base=\(a.bufferHandle) offset=\(b.bufferHandle))")
        }
    }

    // MARK: (c) independent allocations, equal content

    /// Two separately allocated arrays holding the SAME values must NOT be
    /// mis-flagged as sharing storage. This is the false-positive the reviewer
    /// warned about — content equality is not allocation aliasing.
    @Test func independentEqualArraysAreDistinct() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let x = ones([8], dtype: .float32)
            let y = ones([8], dtype: .float32)
            x.eval()
            y.eval()

            let a = x.mlxStorageIdentity
            let b = y.mlxStorageIdentity

            #expect(a.materialized)
            #expect(b.materialized)
            #expect(a.relationship(to: b) == .distinct,
                    "two independent allocations must not be conflated (x=\(a.bufferHandle) y=\(b.bufferHandle))")
        }
    }

    // MARK: (d) unmaterialized backing fails closed

    /// A pending (unevaluated) computation has no observable `Data` yet. It must
    /// report `materialized == false` and refuse to certify distinctness against
    /// anything — `.indeterminate`, so any mutable-isolation claim fails closed.
    @Test func unmaterializedArrayIsIndeterminate() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let base = ones([4], dtype: .float32)
            base.eval()
            // `base * 2` is a lazy op; not evaluated here, so no backing is exposed.
            let pending = base * 2

            let lazy = pending.mlxStorageIdentity
            #expect(!lazy.materialized,
                    "an unevaluated array must not expose a storage identity")

            // Even against a fully materialized, genuinely different array, the lazy
            // side forces indeterminate — we never upgrade "cannot confirm" to distinct.
            let other = zeros([4], dtype: .float32)
            other.eval()
            #expect(lazy.relationship(to: other.mlxStorageIdentity) == .indeterminate)
        }
    }

    // MARK: two-axis evidence rule (pure value type)

    /// A missing evidence axis (one side unmaterialized with only a partial,
    /// non-colliding signal) must never yield `.distinct`; the safe verdict is
    /// `.indeterminate`. Conversely any single colliding axis means `.shared`.
    @Test func partialEvidenceNeverUpgradesToDistinct() {
        let full = MLXArrayStorageIdentity(dataDescriptor: 0xAA00, bufferHandle: 0xBB00, materialized: true)

        // Unmaterialized with a single non-colliding buffer: cannot certify distinct.
        let partial = MLXArrayStorageIdentity(dataDescriptor: 0, bufferHandle: 0xCCCC, materialized: false)
        #expect(full.relationship(to: partial) == .indeterminate)

        // Same buffer but the other side says unmaterialized: still shared via the
        // one colliding axis — a collision outranks the missing signal.
        let colliding = MLXArrayStorageIdentity(dataDescriptor: 0, bufferHandle: 0xBB00, materialized: false)
        #expect(full.relationship(to: colliding) == .shared)

        // Descriptor-only collision (buffer axes differ) still counts as shared.
        let descriptorOnly = MLXArrayStorageIdentity(dataDescriptor: 0xAA00, bufferHandle: 0xDDDD, materialized: true)
        #expect(full.relationship(to: descriptorOnly) == .shared)
    }

    /// Sanity: identity with itself is reflexive-shared and materialized.
    @Test func identityIsReflexive() {
        mlx()
        Device.withDefaultDevice(.cpu) {
            let base = ones([3], dtype: .float32)
            base.eval()
            let a = base.mlxStorageIdentity
            #expect(a.materialized)
            #expect(a.bufferHandle != 0)
            #expect(a.relationship(to: a) == .shared)
        }
    }
}
