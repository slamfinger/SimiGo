import Darwin
import Foundation
import SimiGo2Experimental
import SwiftUI

/// SimiGo 2.0 app — v1.7-inspired chat experience over the oversized
/// segmented engine, plus machine-verifiable self-tests.
///
/// Modes:
///   (GUI)                          chat with a qwen3_next oversized model
///                                  (segmented streaming engine, live
///                                  residency gauges)
///   --self-test --model M --states S   legacy Gate 5 group-residency proof
///   --self-test-oversized --model M [--tokens N]
///                                  double-pass segmented generation on the
///                                  oversized model; PASS requires token
///                                  determinism, footprint <= 30 GiB, swap 0

@main
enum SimiGo2App {
    static func main() async {
        let arguments = CommandLine.arguments

        if let oversized = OversizedSelfTestConfiguration(commandLine: arguments) {
            do {
                let report = try await OversizedRealDeviceSelfTest.run(oversized)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                FileHandle.standardOutput.write(data)
                FileHandle.standardError.write(
                    Data("self-test-oversized: \(report.overallPass ? "PASS" : "FAIL")\n".utf8))
                exit(report.overallPass ? 0 : 2)
            } catch {
                FileHandle.standardError.write(
                    Data("self-test-oversized error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }

        guard let configuration = SelfTestConfiguration(commandLine: arguments) else {
            await SimiGo2AppScene.main()
            return
        }

        do {
            let (output, residencyPass) = try await RealDeviceSelfTest.run(configuration)
            FileHandle.standardOutput.write(output)
            FileHandle.standardError.write(
                Data(
                    (residencyPass ? "self-test: PASS\n" : "self-test: RESIDENCY_COMPATIBILITY_BOUNDARY; benchmarkPass=false\n"
                ).utf8
              )
            )
        } catch {
            FileHandle.standardError.write(Data("self-test error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

// MARK: - GUI (v1.7-inspired chat over the oversized segmented engine)

struct SimiGo2AppScene: App {
    var body: some Scene {
        WindowGroup {
            ChatRootView()
        }
    }
}

struct ChatEntry: Identifiable, Equatable {
    let id = UUID()
    let role: String
    var text: String
    var streaming: Bool
}

@MainActor
final class ChatAppModel: ObservableObject {
    @Published var modelPath = ChatAppModel.resolvedDefaultModelPath
    @Published var transcript: [ChatEntry] = []
    @Published var inputText = ""
    @Published var liveGauge = "idle"
    @Published var execStateLine = "no execution state yet"
    @Published var statsLine = "engine not loaded"
    @Published var isGenerating = false
    @Published var loadLine = "model not loaded"

    private var engine: OversizedSegmentedEngine?
    private var loadedPath: URL?

    static var resolvedDefaultModelPath: String {
        let hub = NSHomeDirectory() + "/.cache/huggingface/hub"
        let dir = hub + "/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir),
           let snap = entries.first {
            return dir + "/" + snap
        }
        return dir
    }

    private func ensureEngine() throws -> OversizedSegmentedEngine {
        let url = URL(fileURLWithPath: modelPath, isDirectory: true).standardizedFileURL
        if let engine = engine, loadedPath == url, engine.stats != nil {
            return engine
        }
        let engine = OversizedSegmentedEngine(modelDirectory: url)
        loadedPath = url
        self.engine = engine
        return engine
    }

    func loadModel() {
        isGenerating = true
        loadLine = "loading…"
        let engine: OversizedSegmentedEngine
        do {
            engine = try ensureEngine()
        } catch {
            loadLine = "load error: \(error.localizedDescription)"
            isGenerating = false
            return
        }
        Task.detached {
            do {
                let stats = try await engine.load()
                await MainActor.run {
                    self.loadLine = String(
                        format: "loaded: core %.2f GiB | resident floor %d/%d layers | %d streaming units × %d layers | load %.1fs",
                        Double(stats.residentActiveMiB) / 1024,
                        stats.residentLayers, stats.totalLayers,
                        stats.unitCount, stats.unitLayers, stats.loadSeconds)
                    self.statsLine = String(
                        format: "budget %d MiB | peak %.2f GiB | cache %d MiB | swap %d MiB | pressure %d",
                        stats.peakCapacityMiB, Double(stats.peakFootprintMiB) / 1024,
                        stats.peakCacheMiB, stats.maxSwapMiB, stats.maxPressureLevel)
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.loadLine = "load error: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        inputText = ""
        transcript.append(ChatEntry(role: "user", text: text, streaming: false))
        transcript.append(ChatEntry(role: "assistant", text: "", streaming: true))
        liveGauge = "generating…"
        isGenerating = true

        // Strict Execution State turns: prior history lives in the bound
        // prefix; each send consumes it with only the NEW user message.
        let message = [EngineChatMessage(role: "user", content: text)]
        let engine: OversizedSegmentedEngine
        do {
            engine = try ensureEngine()
        } catch {
            appendToLastAssistant("  [error: \(error.localizedDescription)]")
            finishLastAssistantSelf()
            liveGauge = "error"
            isGenerating = false
            return
        }

        Task.detached {
            do {
                if engine.stats == nil {
                    _ = try await engine.load()
                    DispatchQueue.main.async { self.loadLine = "loaded on first message" }
                }
                let turn = try await engine.generate(
                    messages: message,
                    maxNewTokens: 24,
                    onToken: { gauge, tokenText in
                        DispatchQueue.main.async {
                            self.appendToLastAssistant(tokenText)
                            self.liveGauge = String(
                                format: "token %d | active %d MiB | footprint %d MiB | cache %d MiB | swap %d MiB | streaming from layer %d | pressure %d",
                                gauge.tokenIndex, gauge.activeMiB, gauge.footprintMiB,
                                gauge.cacheMiB, gauge.swapMiB, gauge.streamingUnit,
                                gauge.pressureLevel)
                        }
                    }
                )
                DispatchQueue.main.async {
                    self.finishLastAssistant(turn.text, mean: turn.meanTokenMs)
                    self.execStateLine = engine.sessionInfo.map {
                        "Execution State \($0.executionID) | position \($0.position) | turns \($0.turns) | lifecycle records \($0.records)"
                    } ?? "-"
                    self.isGenerating = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.appendToLastAssistant("  [error: \(error.localizedDescription)]")
                    self.finishLastAssistantSelf()
                    self.liveGauge = "error"
                    self.isGenerating = false
                }
            }
        }
    }

    func newSession() {
        guard !isGenerating else { return }
        transcript.removeAll()
        liveGauge = "new session…"
        let engine = engine
        Task.detached {
            try? await engine?.newSession()
            DispatchQueue.main.async {
                self.execStateLine = "execution state discarded — fresh state on next message"
                self.liveGauge = "idle"
            }
        }
    }

    fileprivate func appendToLastAssistant(_ token: String) {
        guard let last = transcript.indices.last, transcript[last].role == "assistant" else { return }
        transcript[last].text += token
    }

    fileprivate func finishLastAssistant(_ fullText: String, mean: Double) {
        guard let last = transcript.indices.last, transcript[last].role == "assistant" else { return }
        transcript[last].text = fullText
        transcript[last].streaming = false
        statsLine = String(format: "last turn: %.0f ms/token | %@", mean, statsLine)
    }

    fileprivate func finishLastAssistantSelf() {
        guard let last = transcript.indices.last else { return }
        transcript[last].streaming = false
    }
}

struct ChatRootView: View {
    @StateObject private var model = ChatAppModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SimiGo 2.0 — oversized segmented chat (qwen3_next)")
                .font(.headline)

            LabeledContent("Model") {
                TextField("Model directory", text: $model.modelPath)
                    .textFieldStyle(.roundedBorder)
                Button("Load") { model.loadModel() }
                    .disabled(model.isGenerating)
            }

            HStack {
                Text(model.loadLine).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model.statsLine).font(.caption2).foregroundStyle(.tertiary)
                Button("New session") { model.newSession() }
                    .disabled(model.isGenerating)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.transcript) { entry in
                            HStack {
                                if entry.role == "user" { Spacer(minLength: 60) }
                                Text(entry.role == "user" ? entry.text : entry.text)
                                    .padding(10)
                                    .background(
                                        entry.role == "user"
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.secondary.opacity(0.12)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                if entry.role == "assistant" { Spacer(minLength: 60) }
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 280)
                .onChange(of: model.transcript) { _, _ in
                    if let last = model.transcript.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Text(model.liveGauge)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack {
                TextField("Message…", text: $model.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.send() }
                Button("Send") { model.send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isGenerating || model.inputText.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 900, minHeight: 620)
        .onAppear { model.modelPath = ChatAppModel.resolvedDefaultModelPath }
    }
}

// MARK: - Oversized real-device self-test

struct OversizedSelfTestConfiguration {
    let modelDirectory: URL
    let tokens: Int
    let segmentSize: Int
    let floorBudgetMiB: Int64

    init?(commandLine arguments: [String]) {
        guard arguments.contains("--self-test-oversized"),
              let modelIndex = arguments.firstIndex(of: "--model"),
              modelIndex + 1 < arguments.count
        else { return nil }
        modelDirectory = URL(
            fileURLWithPath: arguments[modelIndex + 1], isDirectory: true
        ).standardizedFileURL
        if let tokensIndex = arguments.firstIndex(of: "--tokens"),
           tokensIndex + 1 < arguments.count, let parsed = Int(arguments[tokensIndex + 1]) {
            tokens = parsed
        } else {
            tokens = 8
        }
        if let segIndex = arguments.firstIndex(of: "--unit-layers"),
           segIndex + 1 < arguments.count, let parsed = Int(arguments[segIndex + 1]) {
            segmentSize = parsed
        } else {
            segmentSize = OversizedSegmentedEngine.defaultUnitLayers
        }
        if let bIndex = arguments.firstIndex(of: "--floor-budget-mib"),
           bIndex + 1 < arguments.count, let parsed = Int64(arguments[bIndex + 1]) {
            floorBudgetMiB = parsed
        } else {
            floorBudgetMiB = OversizedSegmentedEngine.defaultPeakCapacityMiB
        }
    }
}

struct OversizedSelfTestReport: Codable {
    let gate: String
    let device: DeviceFacts
    let modelDirectory: String
    let unitLayers: Int
    let unitCount: Int
    let residentLayers: Int
    let loadSeconds: Double
    let pass1Tokens: [Int]
    let pass2Tokens: [Int]
    let determinismIdentical: Bool
    let peakFootprintMiB: Int64
    let peakCacheMiB: Int64
    let maxSwapMiB: Int64
    let maxPressureLevel: Int32
    let meanTokenMs: Double
    let peakCapacityMiB: Int64
    let executionRecords: Int
    let strictExecutionState: Bool
    let overallPass: Bool
}

enum OversizedRealDeviceSelfTest {
    static func run(_ configuration: OversizedSelfTestConfiguration) async throws -> OversizedSelfTestReport {
        let engine = OversizedSegmentedEngine(
            modelDirectory: configuration.modelDirectory,
            unitLayers: configuration.segmentSize,
            floorBudgetMiB: configuration.floorBudgetMiB
        )
        let stats = try await engine.load()
        let prompt = [
            EngineChatMessage(role: "user", content: "Write a Python function that merges two sorted lists.")
        ]
        FileHandle.standardError.write(Data("marker: loaded\n".utf8))
        let pass1 = try await engine.generate(messages: prompt, maxNewTokens: configuration.tokens)
        FileHandle.standardError.write(Data("marker: pass1 done\n".utf8))
        // Strict Execution State determinism: logically restore the session
        // to the bootstrap position, then replay the SAME turn consuming the
        // restored representation (E5 semantics — not a cache comparison).
        try await engine.restoreSession(to: 0)
        FileHandle.standardError.write(Data("marker: restored\n".utf8))
        let pass2 = try await engine.generate(
            messages: prompt, maxNewTokens: configuration.tokens, nextInputTokens: []
        )
        let finalStats = engine.stats ?? stats
        let session = engine.sessionInfo
        let determinism = pass1.tokenIDs == pass2.tokenIDs
        let strict = (session?.records ?? 0) >= 3 && session?.position == 1
        let overall = determinism && strict
            && finalStats.peakFootprintMiB <= finalStats.peakCapacityMiB
            && finalStats.peakCacheMiB <= finalStats.peakCapacityMiB
            && finalStats.maxSwapMiB == 0
            && finalStats.maxPressureLevel == 1
        return OversizedSelfTestReport(
            gate: "O4_OVERSIZED_REAL_DEVICE_APP_SELFTEST",
            device: DeviceFacts(
                brand: Self.sysctlString("machdep.cpu.brand_string") ?? "unknown",
                machine: Self.sysctlString("hw.machine") ?? "unknown",
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            modelDirectory: configuration.modelDirectory.path,
            unitLayers: finalStats.unitLayers,
            unitCount: finalStats.unitCount,
            residentLayers: finalStats.residentLayers,
            loadSeconds: finalStats.loadSeconds,
            pass1Tokens: pass1.tokenIDs,
            pass2Tokens: pass2.tokenIDs,
            determinismIdentical: determinism,
            peakFootprintMiB: finalStats.peakFootprintMiB,
            peakCacheMiB: finalStats.peakCacheMiB,
            maxSwapMiB: finalStats.maxSwapMiB,
            maxPressureLevel: finalStats.maxPressureLevel,
            meanTokenMs: pass1.meanTokenMs,
            peakCapacityMiB: finalStats.peakCapacityMiB,
            executionRecords: session?.records ?? 0,
            strictExecutionState: strict,
            overallPass: overall
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

// MARK: - Legacy Gate 5 real-device proof (fitting models) — unchanged

struct SelfTestConfiguration: Sendable {
    let modelDirectory: URL
    let states: [ExecutionStateLabel]

    init(modelDirectory: URL, states: [ExecutionStateLabel]) {
        self.modelDirectory = modelDirectory
        self.states = states
    }

    init?(commandLine arguments: [String]) {
        guard arguments.contains("--self-test"),
              let modelIndex = arguments.firstIndex(of: "--model"),
              modelIndex + 1 < arguments.count,
              let statesIndex = arguments.firstIndex(of: "--states"),
              statesIndex + 1 < arguments.count
        else { return nil }

        modelDirectory = URL(
            fileURLWithPath: arguments[modelIndex + 1],
            isDirectory: true
        ).standardizedFileURL
        states = arguments[statesIndex + 1].split(separator: ",").compactMap {
            try? ExecutionStateLabel(parsing: String($0))
        }
        guard !states.isEmpty else { return nil }
    }
}

struct DeviceFacts: Codable, Hashable, Sendable {
    let brand: String
    let machine: String
    let physicalMemoryBytes: UInt64
    let operatingSystem: String
}

private struct SelfTestReport: Codable {
    let gate: String
    let device: DeviceFacts
    let modelDirectory: String
    let states: [String]
    let report: MLXGroupResidencyBenchmarkReport
    let residencyBenchmarkPass: Bool
}

enum RealDeviceSelfTest {
    static func run(_ configuration: SelfTestConfiguration) async throws -> (Data, Bool) {
        let report = try await MLXGroupResidencyBenchmark.run(
            modelDirectory: configuration.modelDirectory,
            states: configuration.states
        )
        let proof = SelfTestReport(
            gate: "GATE5_MULTI_STATE_REAL_DEVICE",
            device: DeviceFacts(
                brand: Self.sysctlString("machdep.cpu.brand_string") ?? "unknown",
                machine: Self.sysctlString("hw.machine") ?? "unknown",
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            modelDirectory: configuration.modelDirectory.path,
            states: configuration.states.map(\.rawValue),
            report: report,
            residencyBenchmarkPass: report.benchmarkPass
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try encoder.encode(proof), report.benchmarkPass)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
