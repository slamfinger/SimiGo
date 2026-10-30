import Foundation
import CryptoKit
import SimiGoRuntimeContract

/// W4/A — 请求预算快速失败（owner 2026-10-29 裁定 Q1=(a)/Q2/Q3=503）。
///
/// 判定的是「这一轮预填在当前预算内是否来得及」，不是「模型能不能答」。
/// 三个身份必须同时匹配才允许共享速度样本：模型、tokenizer、聊天模板。
/// 无匹配样本时**不伪造**速度：要么用同身份校准记录，要么用同一渲染后
/// prompt 的历史观测，否则门未生效（如实记录，禁止报作已拦截）。

// MARK: - Verdict

public struct RequestBudgetIdentity: Hashable, Sendable {
    public let model: String
    public let tokenizer: String
    public let template: String

    public init(model: String, tokenizer: String, template: String) {
        self.model = model
        self.tokenizer = tokenizer
        self.template = template
    }
}

public enum RequestBudgetVerdictKind: String, Sendable {
    /// Estimated inside budget.
    case admitWithinBudget
    /// Estimated over budget from matched rate samples.
    case rejectEstimated
    /// Over budget from a prior real attempt on the exact same payload.
    case rejectPriorAttempt
    /// A prior attempt on this payload completed inside budget.
    case admitPriorAttempt
    /// Gate inactive: no matched sample, no calibration record, no observation.
    case insufficientSamples
    /// Gate inactive: render/tokenize failed.
    case estimateUnavailable
    /// Gate inactive: explicit local disable.
    case disabled
    /// Gate inactive: exact-payload identity cannot be defined (empty transcript).
    case emptyTranscript
    /// Gate inactive: prefix pool may supply a warm representation this gate
    /// cannot model (research mode; default off).
    case poolActive
    /// Gate inactive: a branch checkpoint may restore a representation this
    /// gate cannot model (research mode; default off).
    case restoreActive

    /// Trace / response spelling (snake_case). The raw value stays the Swift
    /// case name so decoding/log parsing elsewhere is unaffected.
    public var wireName: String {
        switch self {
        case .admitWithinBudget: return "admit_within_budget"
        case .rejectEstimated: return "reject_estimated"
        case .rejectPriorAttempt: return "reject_prior_attempt"
        case .admitPriorAttempt: return "admit_prior_attempt"
        case .insufficientSamples: return "insufficient_samples"
        case .estimateUnavailable: return "estimate_unavailable"
        case .disabled: return "disabled"
        case .emptyTranscript: return "empty_transcript"
        case .poolActive: return "pool_active"
        case .restoreActive: return "restore_active"
        }
    }
}

public struct RequestBudgetVerdict: Sendable {
    public let kind: RequestBudgetVerdictKind
    public let promptTokens: Int
    public let estimatedPrefillMs: Int
    public let budgetMs: Int
    public let prefillBudgetMs: Int
    public let samples: Int
    public let bucket: String
    public let promptDigest: String
    public let rateTokPerSecond: Double?
    public let priorProcessed: Int?
    public let priorTotal: Int?
    public let priorElapsedMs: Int?
    public let priorRequestID: String?
    /// True when this verdict was served from the TTL reject cache instead of
    /// a fresh decision. Requirement 5: a repeated over-budget payload must not
    /// redo the full render/estimate before being refused again.
    public let cached: Bool
    /// #136/W4: the memory-pool prefix boundary this verdict credited — the
    /// longest entry that passed the SAME gate adoption uses (namespace, ES
    /// identity, chain-hash reconcile, bind authority). Zero whenever anything
    /// about the candidate fails to prove out, so the estimate falls back to a
    /// full cold prefill. A candidate merely existing is never credit. No
    /// default value on purpose: every construction site must state the credit.
    public let memoryMatchedTokens: Int

    public var isReject: Bool {
        kind == .rejectEstimated || kind == .rejectPriorAttempt
    }

    public var gateWasActive: Bool {
        switch kind {
        case .admitWithinBudget, .rejectEstimated, .rejectPriorAttempt, .admitPriorAttempt:
            return true
        case .insufficientSamples, .estimateUnavailable, .disabled, .emptyTranscript,
             .poolActive, .restoreActive:
            return false
        }
    }

    func withCached() -> RequestBudgetVerdict {
        RequestBudgetVerdict(
            kind: kind, promptTokens: promptTokens,
            estimatedPrefillMs: estimatedPrefillMs, budgetMs: budgetMs,
            prefillBudgetMs: prefillBudgetMs, samples: samples, bucket: bucket,
            promptDigest: promptDigest, rateTokPerSecond: rateTokPerSecond,
            priorProcessed: priorProcessed, priorTotal: priorTotal,
            priorElapsedMs: priorElapsedMs, priorRequestID: priorRequestID,
            cached: true, memoryMatchedTokens: memoryMatchedTokens)
    }

    /// A runtime that cannot evaluate at all (server torn down mid-request).
    /// Inactive, never a refusal.
    static func unavailable() -> RequestBudgetVerdict {
        RequestBudgetVerdict(
            kind: .estimateUnavailable, promptTokens: 0, estimatedPrefillMs: 0,
            budgetMs: 0, prefillBudgetMs: 0, samples: 0, bucket: "unknown",
            promptDigest: "", rateTokPerSecond: nil, priorProcessed: nil,
            priorTotal: nil, priorElapsedMs: nil, priorRequestID: nil,
            cached: false, memoryMatchedTokens: 0)
    }
}

// MARK: - Controller

public final class RequestBudgetController: @unchecked Sendable {

    public static let shared = RequestBudgetController()

    /// ADR 2026-10-30：prefill 时长不再作为准入条件。判定、estMs 与样本
    /// 仍然计算并 trace（观测用途），但没有任何请求会因此被拒绝。
    /// 这不代表 W4 问题「已修复」：原规格被 owner 裁定撤销（路线错误），
    /// #138 的样本污染仍是独立未关闭项。
    public static let admissionEnforcementEnabled = false

    private struct RateKey: Hashable {
        let identity: RequestBudgetIdentity
        let bucket: String
    }

    private struct Sample {
        let tokens: Int
        let seconds: Double
        let at: Date
        let source: String
    }

    private struct Observation {
        let processed: Int
        let total: Int
        let elapsed: Double
        let at: Date
        let requestID: String
        let completed: Bool
        /// The bucket this attempt actually prefilled. A hot delta rate must
        /// never be used to project a later cold prefill of the same payload.
        let bucket: String
    }

    private struct CachedReject {
        let verdict: RequestBudgetVerdict
        let at: Date
        /// Evidence revision the refusal was derived from (#138). A newer
        /// sample/observation/calibration seed makes this refusal stale: the
        /// next decide re-derives instead of replaying it for the rest of the
        /// TTL. A fixed TTL alone let a single bad early measurement suppress
        /// legitimate retries long after better evidence existed.
        let evidenceEpoch: UInt64
    }

    /// 最近 K 笔；P10 只用这几笔（owner 裁定：最近 K 笔 P10 + 时间衰减）。
    private static let sampleWindow = 8
    /// 2h 内的样本按原值；更老的样本按 1.25× 耗时折算（更悲观），
    /// 超过 7 天直接不参与——机器换页/温度变化后老读数不再代表当前。
    private static let freshSampleAge: TimeInterval = 2 * 3600
    private static let maxSampleAge: TimeInterval = 7 * 24 * 3600
    private static let staleSamplePenalty = 1.25
    /// 同一 payload 的观测保留 30 min：足够覆盖 #121 的 0.2s 重试节奏。
    private static let observationTTL: TimeInterval = 1800
    /// 重复拒绝命中缓存，不再渲染/分词（要求 5）。
    private static let rejectCacheTTL: TimeInterval = 600
    /// 校准记录（§6 产物）最长使用 30 天。
    private static let calibrationMaxAge: TimeInterval = 30 * 24 * 3600
    /// 样本少时提高安全边际；样本足量后回到设计值。
    private static let fewSampleCount = 3
    private static let fewSampleMargin = 1.5
    private static let steadyMargin = 1.25

    private let lock = NSLock()
    private var samples: [RateKey: [Sample]] = [:]
    private var calibrationSamples: [RateKey: [Sample]] = [:]
    private var observations: [String: Observation] = [:]
    private var rejectCache: [String: CachedReject] = [:]
    private var promptDigestsByRequest: [String: (digest: String, at: Date)] = [:]
    private var lastCalibrationWrite = Date.distantPast
    private var calibrationLoaded = false
    /// Bumped whenever the evidence a verdict can be derived from changes
    /// (new rate sample, new per-payload observation, calibration seeds).
    private var evidenceEpoch: UInt64 = 0

    private init() {}

    // MARK: Recording

    /// 真实预填完成后写入样本。`tokens` 必须是本轮真正预填的 token 数
    /// （冷 = 全量；热 = delta，即 promptTokens - cacheHitTokens），
    /// `seconds` 必须是引擎报的 promptTime（没有则用墙钟）。
    public func recordPrefillSample(
        identity: RequestBudgetIdentity,
        bucket: String,
        tokens: Int,
        seconds: Double,
        source: String,
        at now: Date = Date()
    ) {
        guard tokens > 0, seconds > 0, seconds.isFinite, seconds < 6 * 3600 else { return }
        let key = RateKey(identity: identity, bucket: bucket)
        lock.lock()
        var list = samples[key] ?? []
        list.append(Sample(tokens: tokens, seconds: seconds, at: now, source: source))
        if list.count > Self.sampleWindow {
            list.removeFirst(list.count - Self.sampleWindow)
        }
        samples[key] = list
        evidenceEpoch &+= 1
        lock.unlock()
        persistCalibrationIfNeeded()
    }

    /// 失败/取消轮的观测：用于「同一 payload 不被当成全新请求」。
    public func recordObservedAttempt(
        identity: RequestBudgetIdentity,
        bucket: String,
        promptDigest: String,
        processed: Int,
        total: Int,
        elapsed: Double,
        requestID: String,
        completed: Bool,
        at now: Date = Date()
    ) {
        guard !promptDigest.isEmpty, total > 0 else { return }
        let key = Self.observationKey(identity: identity, digest: promptDigest)
        lock.lock()
        // 同 payload 最新一次观测覆盖旧的：客户端重试的就是同一条。
        observations[key] = Observation(
            processed: processed, total: total, elapsed: max(0, elapsed),
            at: now, requestID: requestID, completed: completed, bucket: bucket)
        evidenceEpoch &+= 1
        pruneLocked(now: now)
        lock.unlock()
    }

    public func rememberPromptDigest(requestID: String, digest: String, at now: Date = Date()) {
        guard !digest.isEmpty else { return }
        lock.lock()
        promptDigestsByRequest[requestID] = (digest, now)
        lock.unlock()
    }

    public func promptDigest(requestID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = promptDigestsByRequest[requestID],
              Date().timeIntervalSince(entry.at) < Self.observationTTL else { return nil }
        return entry.digest
    }

    public func forgetRequest(requestID: String) {
        lock.lock()
        promptDigestsByRequest.removeValue(forKey: requestID)
        lock.unlock()
    }

    // MARK: Decision

    /// `tokens` is the counted prefill work for this turn BEFORE any memory-pool
    /// credit (cold = whole rendered prompt, hot = the delta).
    /// `memoryMatchedTokens` is the credit the caller proved against the
    /// in-memory prefix pool (#136): that many leading tokens are already
    /// represented by a boundary that passed the ADOPTION gate, so this turn
    /// actually pays `tokens - credit`. The subtraction lives here, in one
    /// place, so no estimate can be built from the full prompt while a refusal
    /// cache key or projection uses the shortened one. Callers pass 0 unless
    /// the whole gate passed — an unproven candidate never shortens anything,
    /// and a credit can never claim the entire prompt (at least one token is
    /// always estimated as work).
    public func decide(
        identity: RequestBudgetIdentity,
        bucket: String,
        promptDigest: String,
        tokens: Int,
        budgetMs: Int,
        maxTokens: Int,
        memoryMatchedTokens: Int = 0,
        now: Date = Date()
    ) -> RequestBudgetVerdict {
        let matched = max(0, min(memoryMatchedTokens, max(0, tokens - 1)))
        let remaining = max(1, tokens - matched)
        let prefillBudgetMs = Self.prefillBudgetMs(budgetMs: budgetMs, maxTokens: maxTokens)
        guard budgetMs > 0 else {
            return verdict(
                .disabled, tokens: tokens, estimatedMs: 0,
                budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
                samples: 0, bucket: bucket, digest: promptDigest,
                rate: nil, observation: nil, matched: matched)
        }
        guard tokens > 0, !promptDigest.isEmpty else {
            return verdict(
                .emptyTranscript, tokens: tokens, estimatedMs: 0,
                budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
                samples: 0, bucket: bucket, digest: promptDigest,
                rate: nil, observation: nil, matched: matched)
        }

        loadCalibrationIfNeeded(now: now)
        let cacheKey = Self.rejectKey(
            identity: identity, bucket: bucket, budgetMs: budgetMs,
            maxTokens: maxTokens, digest: promptDigest, matched: matched)
        lock.lock()
        let cached = rejectCache[cacheKey]
        let observation = observations[Self.observationKey(identity: identity, digest: promptDigest)]
        let liveSamples = samples[RateKey(identity: identity, bucket: bucket)] ?? []
        let seeds = calibrationSamples[RateKey(identity: identity, bucket: bucket)] ?? []
        let epoch = evidenceEpoch
        pruneLocked(now: now)
        if let cached, cached.evidenceEpoch != epoch {
            // #138: the evidence this refusal was derived from has changed.
            // Replay would keep blocking on a measurement that no longer
            // holds; drop it and decide again on the current evidence.
            rejectCache.removeValue(forKey: cacheKey)
        }
        lock.unlock()

        if let cached, cached.evidenceEpoch == epoch,
            now.timeIntervalSince(cached.at) < Self.rejectCacheTTL
        {
            return cached.verdict.withCached()
        }

        // R2/R3：同一 payload 的真实观测优先于任何速度推测。观测只在同
        // 桶内可比——热轮的 delta 速率不能拿去推算随后被逐出后的冷预填。
        if let observation, observation.bucket == bucket,
            now.timeIntervalSince(observation.at) <= Self.observationTTL
        {
            if !observation.completed, observation.processed > 0, observation.elapsed > 0 {
                // 未完成轮：观测到的耗时只是下界，按已处理比例外推**本轮真正
                // 要付的那一段**——内存池已证明的边界不再计入待预填 token，
                // 否则取消→重试闭环会被上一轮的全量观测永远判死（W4）。
                let projected = observation.elapsed * Double(remaining)
                    / Double(observation.processed)
                let measuredRate = Double(observation.processed) / observation.elapsed
                if projected * 1000 > Double(prefillBudgetMs) {
                    let v = verdict(
                        .rejectPriorAttempt, tokens: tokens,
                        estimatedMs: Int(projected * 1000),
                        budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
                        samples: 0, bucket: bucket, digest: promptDigest,
                        rate: measuredRate, observation: observation, matched: matched)
                    lock.lock()
                    rejectCache[cacheKey] = CachedReject(
                        verdict: v, at: now, evidenceEpoch: epoch)
                    lock.unlock()
                    return v
                }
            }
            if observation.completed, observation.elapsed > 0, observation.processed > 0 {
                let measuredRate = Double(observation.processed) / observation.elapsed
                let projected = Double(remaining) / max(measuredRate, 0.001)
                    * Self.steadyMargin
                if projected * 1000 > Double(prefillBudgetMs) {
                    let v = verdict(
                        .rejectPriorAttempt, tokens: tokens,
                        estimatedMs: Int(projected * 1000),
                        budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
                        samples: 0, bucket: bucket, digest: promptDigest,
                        rate: measuredRate, observation: observation, matched: matched)
                    lock.lock()
                    rejectCache[cacheKey] = CachedReject(
                        verdict: v, at: now, evidenceEpoch: epoch)
                    lock.unlock()
                    return v
                }
                return verdict(
                    .admitPriorAttempt, tokens: tokens,
                    estimatedMs: Int(projected * 1000),
                    budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
                    samples: 0, bucket: bucket, digest: promptDigest,
                    rate: measuredRate, observation: observation, matched: matched)
            }
        }

        // R1/R3：匹配身份的速率样本（内存 + 校准记录）。
        let merged = (liveSamples + seeds).sorted { $0.at > $1.at }
        let usable = merged.prefix(Self.sampleWindow).map { sample -> Sample in
            guard now.timeIntervalSince(sample.at) > Self.freshSampleAge else { return sample }
            return Sample(
                tokens: sample.tokens,
                seconds: sample.seconds * Self.staleSamplePenalty,
                at: sample.at, source: sample.source)
        }.filter { now.timeIntervalSince($0.at) <= Self.maxSampleAge }

        guard !usable.isEmpty else {
            // R4：门未生效。不得伪装成拦截，也不得用假样本填充。
            return verdict(
                .insufficientSamples, tokens: tokens, estimatedMs: 0,
                budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
                samples: 0, bucket: bucket, digest: promptDigest,
                rate: nil, observation: nil, matched: matched)
        }

        let rate = Self.p10(usable.map { Double($0.tokens) / $0.seconds })
        let margin = usable.count < Self.fewSampleCount
            ? Self.fewSampleMargin : Self.steadyMargin
        let estimatedSeconds = Double(remaining) / max(rate, 0.001) * margin
        let estimatedMs = Int(estimatedSeconds * 1000)
        if estimatedMs > prefillBudgetMs {
            let v = verdict(
                .rejectEstimated, tokens: tokens, estimatedMs: estimatedMs,
                budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
                samples: usable.count, bucket: bucket, digest: promptDigest,
                rate: rate, observation: nil, matched: matched)
            lock.lock()
            rejectCache[cacheKey] = CachedReject(
                verdict: v, at: now, evidenceEpoch: epoch)
            lock.unlock()
            return v
        }
        return verdict(
            .admitWithinBudget, tokens: tokens, estimatedMs: estimatedMs,
            budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
            samples: usable.count, bucket: bucket, digest: promptDigest,
            rate: rate, observation: nil, matched: matched)
    }

    // MARK: Budget math

    /// `prefill_budget = budget - reserve`。reserve 给生成留时间：
    /// `max_tokens` 是上限不是耗时预测，若不封顶，4096 的默认上限会
    /// 把任何请求都判成超预算。因此封顶 15s，并以下限 20 tok/s 作为
    /// 保守假设（这是安全假设，不是性能常数）。
    static func prefillBudgetMs(budgetMs: Int, maxTokens: Int) -> Int {
        let tokenCap = max(0, maxTokens)
        let projected = Double(tokenCap) / 20.0 * 1000
        let reserve = max(5000.0, min(15000.0, projected))
        return max(0, budgetMs - Int(reserve))
    }

    static func p10(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = max(0, Int((Double(sorted.count - 1) * 0.10).rounded(.down)))
        return sorted[rank]
    }

    private static func observationKey(identity: RequestBudgetIdentity, digest: String) -> String {
        "\(identity.model)|\(identity.tokenizer)|\(identity.template)|\(digest)"
    }

    /// The reject cache is keyed by the credit too: a refusal computed while the
    /// pool had nothing provable must not keep suppressing the same payload
    /// after a cancel put an adoptable boundary in it. `maxTokens` is part of
    /// the key because it decides the generation reserve, hence the prefill
    /// budget the refusal was measured against: a refusal computed for a
    /// 60 s-generation request must not be replayed for a short-generation
    /// retry that has more prefill room.
    private static func rejectKey(
        identity: RequestBudgetIdentity, bucket: String, budgetMs: Int,
        maxTokens: Int, digest: String, matched: Int
    ) -> String {
        "\(identity.model)|\(identity.tokenizer)|\(identity.template)|\(bucket)"
            + "|\(budgetMs)|\(maxTokens)|\(matched)|\(digest)"
    }

    private func verdict(
        _ kind: RequestBudgetVerdictKind,
        tokens: Int,
        estimatedMs: Int,
        budgetMs: Int,
        prefillBudgetMs: Int,
        samples: Int,
        bucket: String,
        digest: String,
        rate: Double?,
        observation: Observation?,
        matched: Int = 0,
        cached: Bool = false
    ) -> RequestBudgetVerdict {
        RequestBudgetVerdict(
            kind: kind, promptTokens: tokens, estimatedPrefillMs: estimatedMs,
            budgetMs: budgetMs, prefillBudgetMs: prefillBudgetMs,
            samples: samples, bucket: bucket, promptDigest: digest,
            rateTokPerSecond: rate,
            priorProcessed: observation?.processed,
            priorTotal: observation?.total,
            priorElapsedMs: observation.map { Int($0.elapsed * 1000) },
            priorRequestID: observation?.requestID,
            cached: cached, memoryMatchedTokens: matched)
    }

    private func pruneLocked(now: Date) {
        observations = observations.filter {
            now.timeIntervalSince($0.value.at) <= Self.observationTTL
        }
        rejectCache = rejectCache.filter {
            now.timeIntervalSince($0.value.at) < Self.rejectCacheTTL
        }
        promptDigestsByRequest = promptDigestsByRequest.filter {
            now.timeIntervalSince($0.value.at) < Self.observationTTL
        }
    }

    // MARK: Calibration record (§6)

    private struct CalibrationFile: Codable {
        struct Record: Codable {
            struct Entry: Codable {
                let tokens: Int
                let seconds: Double
                let at: Double
                let source: String
            }
            let model: String
            let tokenizer: String
            let template: String
            let bucket: String
            let samples: [Entry]
        }
        var version: Int
        var records: [Record]
    }

    static var calibrationURL: URL {
        SimiGoPaths.managedRoot().appendingPathComponent("budget-calibration.json")
    }

    /// §6 校准与真机运行共用同一份记录：校准跑出来的实测速率在重启后
    /// 仍能让第一笔请求有据可判，而不是必然落到「样本不足放行」。
    private func loadCalibrationIfNeeded(now: Date) {
        lock.lock()
        let alreadyLoaded = calibrationLoaded
        calibrationLoaded = true
        lock.unlock()
        guard !alreadyLoaded else { return }

        let url = Self.calibrationURL
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CalibrationFile.self, from: data),
              file.version == 1 else { return }
        var loaded: [RateKey: [Sample]] = [:]
        for record in file.records {
            let identity = RequestBudgetIdentity(
                model: record.model, tokenizer: record.tokenizer, template: record.template)
            let key = RateKey(identity: identity, bucket: record.bucket)
            let entries = record.samples.compactMap { entry -> Sample? in
                let at = Date(timeIntervalSince1970: entry.at)
                guard now.timeIntervalSince(at) <= Self.calibrationMaxAge,
                      entry.tokens > 0, entry.seconds > 0, entry.seconds.isFinite else { return nil }
                return Sample(
                    tokens: entry.tokens, seconds: entry.seconds,
                    at: at, source: "calibration:" + entry.source)
            }
            guard !entries.isEmpty else { continue }
            loaded[key] = Array(entries.sorted { $0.at > $1.at }.prefix(Self.sampleWindow))
        }
        lock.lock()
        calibrationSamples = loaded
        if !loaded.isEmpty { evidenceEpoch &+= 1 }
        lock.unlock()
    }

    /// 首次判定前调用，把 §6 校准记录读进来。
    public func prepare(now: Date = Date()) {
        loadCalibrationIfNeeded(now: now)
    }

    private func persistCalibrationIfNeeded() {
        let now = Date()
        lock.lock()
        guard now.timeIntervalSince(lastCalibrationWrite) > 5 else {
            lock.unlock()
            return
        }
        lastCalibrationWrite = now
        let snapshot = samples
        lock.unlock()

        var records: [CalibrationFile.Record] = []
        for (key, list) in snapshot {
            let entries = list.map {
                CalibrationFile.Record.Entry(
                    tokens: $0.tokens, seconds: $0.seconds,
                    at: $0.at.timeIntervalSince1970, source: $0.source)
            }
            records.append(.init(
                model: key.identity.model,
                tokenizer: key.identity.tokenizer,
                template: key.identity.template,
                bucket: key.bucket,
                samples: entries))
        }
        guard !records.isEmpty else { return }
        let file = CalibrationFile(version: 1, records: records)
        guard let data = try? JSONEncoder().encode(file) else { return }
        let url = Self.calibrationURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Test hooks

    /// Tests only: drop all state so cases cannot leak into each other. The
    /// persisted calibration record is part of that state — reloading it after
    /// a reset would count samples twice.
    func resetForTesting() {
        lock.lock()
        samples.removeAll()
        calibrationSamples.removeAll()
        observations.removeAll()
        rejectCache.removeAll()
        promptDigestsByRequest.removeAll()
        evidenceEpoch = 0
        lastCalibrationWrite = .distantPast
        calibrationLoaded = false
        lock.unlock()
        try? FileManager.default.removeItem(at: Self.calibrationURL)
    }

    func recordCalibrationSampleForTesting(
        identity: RequestBudgetIdentity, bucket: String,
        tokens: Int, seconds: Double, at: Date
    ) {
        lock.lock()
        var list = calibrationSamples[RateKey(identity: identity, bucket: bucket)] ?? []
        list.append(Sample(tokens: tokens, seconds: seconds, at: at, source: "calibration:test"))
        calibrationSamples[RateKey(identity: identity, bucket: bucket)] = list
        evidenceEpoch &+= 1
        lock.unlock()
    }
}

// MARK: - Post-load warm-up

/// #138 — the first prefill that completes after a model load pays the
/// engine's first-run cost (kernel compilation, weight residency). That
/// timing is not throughput: feeding it into the P10 window drags the rate
/// down to the cold-start floor and the gate then refuses legitimate large
/// prompts for as long as those samples stay in the window. The warm-up turn
/// is consumed once per load cycle and neither seeds the rate window nor
/// leaves a "completed" observation for its payload.
struct PostLoadWarmupTracker: Sendable {
    private var measuredSinceLoad = false

    /// True while the first completed prefill after the last load is still
    /// unpaid.
    var isWarmupTurn: Bool { !measuredSinceLoad }

    /// A load (service start or resume) starts a new warm-up cycle.
    mutating func modelLoaded() {
        measuredSinceLoad = false
    }

    /// The first turn that completes its prefill consumes the warm-up and is
    /// reported as such; every later turn is measured normally.
    mutating func consumeCompletedPrefill() -> Bool {
        if measuredSinceLoad { return false }
        measuredSinceLoad = true
        return true
    }
}

// MARK: - Prompt digest

public enum RequestBudgetDigest {
    /// 渲染后 token 序列的 SHA256。token id 已隐含 tokenizer 与模板，
    /// 因此同 digest + 同模型身份 = 同一份会被引擎读取的输入。
    public static func of(tokens: [Int32], model: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(model.utf8))
        var little = tokens.map { $0.littleEndian }
        little.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress, buffer.count > 0 else { return }
            hasher.update(
                data: Data(
                    bytes: base,
                    count: buffer.count * MemoryLayout<Int32>.size))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
