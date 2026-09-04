import SwiftUI
import AppKit

struct Settings: View {
    @EnvironmentObject var svc: Service
    @StateObject private var envMgr = EnvManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - 生成 / Decode 参数
                sectionBox("生成 / Decode 参数") {
                    HStack(spacing: 12) {
                        paramRow("Temp", value: $svc.config.temperature, range: 0...2, step: 0.1)
                        paramRow("Top-P", value: $svc.config.topP, range: 0...1, step: 0.05)
                        intRow("Top-K", value: $svc.config.topK, width: 50)
                    }
                    HStack(spacing: 12) {
                        paramRow("Min-P", value: $svc.config.minP, range: 0...0.3, step: 0.01)
                        intRow("Max Tokens", value: $svc.config.maxTokens, width: 60)
                    }
                    HStack(spacing: 12) {
                        paramRow("Presence", value: $svc.config.presencePenalty, range: 0...2, step: 0.1)
                        paramRow("Repeat", value: $svc.config.repeatPenalty, range: 0.8...2, step: 0.05)
                    }
                    HStack(spacing: 16) {
                        Toggle("禁用思考", isOn: $svc.config.disableThinking)
                        Toggle("Trust Remote", isOn: $svc.config.trustRemoteCode)
                    }
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 12) {
                        intRow("Speculative 草稿数", value: $svc.config.specDraftNMax, width: 60)
                        Text("共用参数").font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                    Text("用于支持 Speculative Decode 的运行时。没有草稿模型时不会启用；数值表示每轮最多生成的草稿 Token 数。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("当前值：\(svc.config.specDraftNMax)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // MARK: - LLaMA.cpp
                sectionBox("LLaMA.cpp (GGUF)") {
                    HStack {
                        intRow("GPU Layers", value: $svc.config.gpuLayers, width: 60)
                        intRow("Context", value: $svc.config.ctxSize, width: 60)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        Toggle("Jinja", isOn: $svc.config.jinja)
                        Toggle("FlashAttn", isOn: $svc.config.flashAttention)
                        Toggle("MTP", isOn: $svc.config.useMTP)
                    }
                }

                // MARK: - 统一命令控制台
                sectionBox("统一命令控制台") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("输入命令，例如 hf download ... / llama-server ...", text: $envMgr.commandInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                executeCommand()
                            }

                        HStack(spacing: 8) {
                            Button("下载") {
                                Task {
                                    await envMgr.downloadModel(command: envMgr.commandInput)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(envMgr.isDownloading)

                            Button("升级") {
                                Task {
                                    await envMgr.setupEnvironment()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(envMgr.commandStatus == "构建中")

                            Button(envMgr.isRecording ? "停止记录" : "记录") {
                                if envMgr.isRecording {
                                    envMgr.stopTraceRecording()
                                } else {
                                    envMgr.startTraceRecording()
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("复制") {
                                copyCommandLog()
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }

                        Text("状态：\(envMgr.commandStatus)")
                            .font(.caption)
                            .foregroundColor(envMgr.isRecording ? .orange : .secondary)

                        if envMgr.isDownloading || !envMgr.commandLog.isEmpty {
                            commandLogView(log: envMgr.commandLog)
                        }
                    }
                }

                // MARK: - 操作
                HStack(spacing: 12) {
                    Button("保存默认") {
                        svc.saveCurrentConfigAsModelDefault()
                    }

                    Button("重启服务") {
                        svc.saveCurrentConfigAsModelDefault()
                        Task {
                            await svc.restart(path: svc.modelPath)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("重置") {
                        AppConfig.resetAll()
                    }
                    .foregroundColor(.red)
                }
                .padding(.horizontal)

                Text("SimiGo v4.5")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
    }

    // MARK: - Command Actions
    private func executeCommand() {
        let command = envMgr.commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        Task {
            await envMgr.executeCommand(command)
        }
    }

    private func copyCommandLog() {
        let text = envMgr.commandLog
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - 极简复用组件
    @ViewBuilder
    private func sectionBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.horizontal)
        Divider()
    }

    private func paramRow(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .frame(width: 80, alignment: .leading)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func intRow(_ label: String, value: Binding<Int>, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .frame(width: 80, alignment: .leading)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    @ViewBuilder
    private func logPanel(title: String, isBusy: Bool, buttonTitle: String, progress: Double, log: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isBusy ? .orange : .secondary)
                Spacer()
                Button(buttonTitle, action: action)
                    .disabled(isBusy)
                    .buttonStyle(.borderedProminent)
            }

            if isBusy || !log.isEmpty {
                logView(progress: progress, log: log)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func logView(progress: Double, log: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(log)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }

            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
        .frame(height: 140)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3))
        )
    }

    @ViewBuilder
    private func commandLogView(log: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(log.isEmpty ? "等待命令输出..." : log)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(log.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .id("COMMAND_LOG_BOTTOM")
            }
            .onChange(of: log) { _, _ in
                proxy.scrollTo("COMMAND_LOG_BOTTOM", anchor: .bottom)
            }
        }
        .frame(minHeight: 180, maxHeight: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3))
        )
    }
}
