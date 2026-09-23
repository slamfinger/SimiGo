import Darwin
import Foundation
import SimiGo2Experimental
import SwiftUI

@main
enum SimiGo2App {
    static func main() async {
        guard let configuration = SelfTestConfiguration(commandLine: CommandLine.arguments) else {
            await SimiGo2AppScene.main()
            return
        }

        do {
            let output = try await RealDeviceSelfTest.run(configuration)
            FileHandle.standardOutput.write(output)
            FileHandle.standardError.write(Data("self-test: PASS\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("self-test error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

struct SimiGo2AppScene: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    @State private var modelPath = "/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d"
    @State private var states = "STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL"
    @State private var output = "Ready."
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SimiGo 2.0 Experimental — MLX real-device proof")
                .font(.headline)

            LabeledContent("Model") {
                TextField("Model directory", text: $modelPath)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("States") {
                TextField("Execution states", text: $states)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Run Gate 5") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                if isRunning {
                    ProgressView()
                    Text("Running real MLX inference…")
                }
            }

            TextEditor(text: .constant(output))
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 360)
        }
        .padding(18)
        .frame(minWidth: 860, minHeight: 520)
    }

    private func run() {
        isRunning = true
        output = "Running…"
        Task {
            do {
                let parsedStates = try states.split(separator: ",").map {
                    try ExecutionStateLabel(parsing: String($0))
                }
                let configuration = SelfTestConfiguration(
                    modelDirectory: URL(fileURLWithPath: modelPath, isDirectory: true),
                    states: parsedStates
                )
                let data = try await RealDeviceSelfTest.run(configuration)
                output = String(decoding: data, as: UTF8.self)
            } catch {
                output = "ERROR: \(error.localizedDescription)"
            }
            isRunning = false
        }
    }
}

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

private struct DeviceFacts: Codable, Hashable, Sendable {
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
}

enum RealDeviceSelfTest {
    static func run(_ configuration: SelfTestConfiguration) async throws -> Data {
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
            report: report
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(proof)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
