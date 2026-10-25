// Read-only observability for the G1/G3 native headless experiments (task §5).
//
// This recorder ONLY OBSERVES. It never participates in cache-hit decisions,
// KV lifecycle, or the inference loop; every hook is a single increment placed
// next to an existing trace line or engine-reported value. Each counter carries
// its definition, counting level, and data source so a report can cite it.
//
// Levels:
//   * ENGINE_RUNTIME  — value measured by the mlx runtime for the executed
//     request (e.g. actual prefilled prompt tokens, actual cache-hit tokens,
//     actual generation tokens). NOT the caller's requested token count.
//   * LIFECYCLE_EVENT — an event the runtime itself logs (reuse miss, pool bind,
//     checkpoint save, resume/suspend).
// Any metric that cannot be directly observed is left absent and reported as
// NOT_INSTRUMENTED by the consumer; nothing here is inferred or faked.
import Foundation

public final class NativeMLXObservation: @unchecked Sendable {
    private let lock = NSLock()

    // Engine-runtime token observables for the most recent generate pass.
    private var _prefillTokensObserved: Int? = nil      // actual tokens prefilled (progress.total)
    private var _promptTokens: Int? = nil               // engine-reported prompt tokens
    private var _cacheHitTokens: Int? = nil             // engine-reported cached/reused tokens
    private var _generationTokens: Int? = nil           // engine-reported decode tokens
    private var _cacheReuseMode: String? = nil          // engine-reported reuse mode (cold/restore/…)
    private var _reusedSession = false

    // Lifecycle event counters for this process/instance.
    private var reuseMiss = 0
    private var prefixMismatch = 0
    private var poolBindHit = 0        // prefix-pool snapshot load (cacheLoad)
    private var poolBindFailed = 0
    private var cacheSave = 0          // branch-checkpoint save
    private var checkpointFailed = 0
    private var coldRebuild = 0        // new-session cold prefill (no existing session)
    private var lifecycleResume = 0
    private var lifecycleSuspend = 0
    private var generatePasses = 0
    // Memory-reclaim lifecycle observables (LOGICAL level, not physical pages).
    private var referenceRelease = 0
    private var sessionsReleasedAtRelease = 0
    private var sessionsAfterRelease = -1
    private var containerPresentBefore = false
    private var containerAbsentAfter = false
    private var resourceReclaim = 0
    // Ordered lifecycle log: makes event ORDER auditable (counts alone cannot).
    private var eventSeq = 0
    private var eventLog: [[String: Any]] = []
    private let startedAt = Date()

    /// Caller must already hold `lock`.
    nonisolated private func appendEventLocked(_ name: String) {
        eventSeq += 1
        eventLog.append([
            "seq": eventSeq,
            "event": name,
            "at_ms": Int(Date().timeIntervalSince(startedAt) * 1000),
        ])
    }

    nonisolated public init() {}

    nonisolated func notePrefillTotal(_ total: Int) { lock.withLock { _prefillTokensObserved = total } }
    nonisolated func noteEngineTokens(prompt: Int?, cacheHit: Int?, generation: Int?, mode: String?, reused: Bool) {
        lock.withLock {
            if let prompt { _promptTokens = prompt }
            if let cacheHit { _cacheHitTokens = cacheHit }
            if let generation { _generationTokens = generation }
            _cacheReuseMode = mode ?? _cacheReuseMode
            _reusedSession = reused
            generatePasses += 1
        }
    }
    nonisolated func noteReuseMiss()      { lock.withLock { reuseMiss += 1; appendEventLocked("reuse_miss") } }
    nonisolated func notePrefixMismatch() { lock.withLock { prefixMismatch += 1; appendEventLocked("prefix_mismatch") } }
    nonisolated func notePoolBindHit()    { lock.withLock { poolBindHit += 1; appendEventLocked("pool_bind_hit") } }
    nonisolated func notePoolBindFailed() { lock.withLock { poolBindFailed += 1; appendEventLocked("pool_bind_failed") } }
    nonisolated func noteCacheSave()      { lock.withLock { cacheSave += 1; appendEventLocked("cache_save") } }
    nonisolated func noteCheckpointFailed(){ lock.withLock { checkpointFailed += 1; appendEventLocked("checkpoint_failed") } }
    nonisolated func noteColdRebuild()    { lock.withLock { coldRebuild += 1; appendEventLocked("cold_rebuild") } }
    nonisolated func noteResume()         { lock.withLock { lifecycleResume += 1; appendEventLocked("lifecycle_resume") } }
    nonisolated func noteSuspend()        { lock.withLock { lifecycleSuspend += 1; appendEventLocked("lifecycle_suspend") } }
    /// Cache/model REFERENCE release at the suspend path. All four values are
    /// READ FROM RUNTIME STATE by the caller before/after the mutation — this
    /// recorder never asserts them. Proves logical reference release only.
    nonisolated func noteReferenceRelease(sessionsReleased: Int, sessionsAfter: Int,
                                          containerPresentBefore: Bool, containerAbsentAfter: Bool) {
        lock.withLock {
            referenceRelease += 1
            sessionsReleasedAtRelease = sessionsReleased
            sessionsAfterRelease = sessionsAfter
            self.containerPresentBefore = containerPresentBefore
            self.containerAbsentAfter = containerAbsentAfter
            appendEventLocked("reference_release")
        }
    }
    /// Explicit resource-reclaim OPERATION invoked (Memory.clearCache returned).
    /// Records invocation only; reclaimed bytes are not observable here.
    nonisolated func noteResourceReclaim() {
        lock.withLock { resourceReclaim += 1; appendEventLocked("resource_reclaim") }
    }

    /// Machine-readable snapshot with per-field definition, level, and source.
    nonisolated public func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "observed_at_epoch_ms": Int(Date().timeIntervalSince1970 * 1000),
            "generate_passes": generatePasses,
            "prefill_tokens_observed": _prefillTokensObserved ?? NSNull(),
            "prompt_tokens_engine_reported": _promptTokens ?? NSNull(),
            "cache_hit_tokens_engine_reported": _cacheHitTokens ?? NSNull(),
            "generation_tokens_engine_reported": _generationTokens ?? NSNull(),
            "cache_reuse_mode_engine_reported": _cacheReuseMode ?? NSNull(),
            "reused_session": _reusedSession,
            "events": [
                "reuse_miss": reuseMiss,
                "prefix_mismatch": prefixMismatch,
                "pool_bind_hit_cacheLoad": poolBindHit,
                "pool_bind_failed": poolBindFailed,
                "cache_save_checkpoint": cacheSave,
                "checkpoint_failed": checkpointFailed,
                "cold_rebuild": coldRebuild,
                "lifecycle_resume": lifecycleResume,
                "lifecycle_suspend": lifecycleSuspend,
                "reference_release": referenceRelease,
                "sessions_released_at_release": sessionsReleasedAtRelease,
                "sessions_after_release": sessionsAfterRelease,
                "model_container_present_before": containerPresentBefore,
                "model_container_absent_after": containerAbsentAfter,
                "model_container_ref_dropped": (containerPresentBefore && containerAbsentAfter),
                "resource_reclaim": resourceReclaim,
            ],
            "events_ordered": eventLog,
            "definitions": [
                "prefill_tokens_observed": "LEVEL=ENGINE_RUNTIME; SOURCE=NativeMLX prefill.progress(total); actual tokens the engine prefilled for the executed request (not requested tokens).",
                "cache_hit_tokens_engine_reported": "LEVEL=ENGINE_RUNTIME; SOURCE=info.cachedPromptTokenCount/reportedCacheHit; tokens reused from KV, engine measured.",
                "generation_tokens_engine_reported": "LEVEL=ENGINE_RUNTIME; SOURCE=info.generationTokenCount; decode tokens ≈ forward passes at token granularity (approximate; per-layer forward NOT_INSTRUMENTED).",
                "cache_reuse_mode_engine_reported": "LEVEL=ENGINE_RUNTIME; SOURCE=info.cacheReuseMode; cold => prior compute re-prefilled.",
                "reference_release": "LEVEL=LIFECYCLE_EVENT; SOURCE=suspend path state mutation; sessions_before/after and container_present_before/absent_after are READ FROM RUNTIME STATE by the caller (not asserted by the recorder). model_container_ref_dropped is derived as present_before && absent_after. Proves in-process logical REFERENCE release only — NOT that ARC/MLX freed memory back to the OS.",
                "resource_reclaim": "LEVEL=LIFECYCLE_EVENT; SOURCE=Memory.clearCache() returned; count of explicit MLX cache-reclaim OPERATIONS INVOKED on the production suspend path. Records invocation only — reclaimed bytes are not observable here, and this is NOT physical page return.",
                "physical_page_return": "NOT_INSTRUMENTED/BLOCKED — malloc_zone_pressure_relief is only an allocator HINT; no independent evidence the OS reclaimed physical pages (footprint/RSS diffs are explicitly excluded by the gate definition).",
                "forward_calls": "NOT_INSTRUMENTED (no per-forward hook in this layer; use generation_tokens as an ENGINE_RUNTIME token-granularity proxy, explicitly labelled).",
            ],
        ]
    }
}
