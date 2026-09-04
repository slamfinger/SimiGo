import SwiftUI
import AppKit

@main
struct MenuApp: App {
    init() {
        RuntimeLifecycleCoordinator.demoSelfCheck()
    }
    @Environment(\.openWindow) private var openWindow
    @StateObject private var svc = Service()
    @State private var networkModeIsLAN = false
    @State private var isChangingNetworkMode = false
    @GestureState private var networkDragOffset: CGFloat = 0

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 3) {
                statusHeader
                networkSlider.padding(.horizontal, 4)

                Divider().padding(.vertical, 2)

                MenuRowButton(
                    title: svc.isRunning ? "停止服务" : "启动服务",
                    icon: svc.isRunning ? "stop.fill" : "play.fill",
                    disabled: svc.modelPath.isEmpty || isChangingNetworkMode
                ) {
                    Task { @MainActor in await toggleService() }
                }

                if svc.isRunning {
                    MenuRowButton(
                        title: "重启服务",
                        icon: "arrow.clockwise",
                        disabled: isChangingNetworkMode
                    ) {
                        restartService()
                    }
                }

                Divider().padding(.vertical, 2)

                MenuRowButton(
                    title: "选择模型...",
                    icon: "folder",
                    disabled: svc.isRunning || isChangingNetworkMode
                ) {
                    selectModel()
                }

                MenuRowButton(title: "复制 API 地址", icon: "doc.on.doc") {
                    copyAPIEndpoint()
                }

                Divider().padding(.vertical, 2)

                MenuRowButton(title: "设置...", icon: "gearshape") {
                    openSettingsWindow()
                }

                Divider().padding(.vertical, 2)

                MenuRowButton(title: "退出", icon: "xmark.circle") {
                    quitApp()
                }
            }
            .padding(6)
            .frame(width: 160)
            .onAppear { syncNetworkMode() }
        } label: {
            Image(systemName: iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconColor)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "Settings") {
            Settings().environmentObject(svc)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 480)
    }

    // MARK: - Icon

    private var iconName: String {
        if svc.status.hasPrefix("⚠️") { return "exclamationmark.triangle.fill" }
        return svc.isRunning ? "bolt.fill" : "bolt"
    }

    private var iconColor: Color {
        if svc.status.hasPrefix("⚠️") { return .yellow }
        if !svc.isRunning { return .primary }

        switch svc.memoryPressure {
        case "critical": return .red
        case "warn": return .orange
        default: return .green
        }
    }

    // MARK: - Status

    private var statusHeader: some View {
        let node = svc.inferenceNode

        return HStack(spacing: 6) {
            Circle()
                .fill(svc.isRunning ? svc.pressureColor : Color.gray.opacity(0.6))
                .frame(width: 7, height: 7)

            Text(svc.status)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            Text(node.advertisedHost)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Network Slider

    private var networkSlider: some View {
        let containerWidth: CGFloat = 148
        let thumbWidth = containerWidth / 2
        let targetOffset = networkModeIsLAN ? thumbWidth : 0

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                )

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: thumbWidth - 4, height: 24)
                .padding(.horizontal, 2)
                .offset(x: min(max(targetOffset + networkDragOffset, 0), thumbWidth))
                .animation(
                    networkDragOffset == 0
                    ? .spring(response: 0.25, dampingFraction: 0.8)
                    : nil,
                    value: networkModeIsLAN
                )

            HStack(spacing: 0) {
                Text("本机")
                    .font(.system(size: 11, weight: networkModeIsLAN ? .regular : .semibold))
                    .foregroundColor(networkModeIsLAN ? .secondary : .white)
                    .frame(width: thumbWidth)

                Text("局域网")
                    .font(.system(size: 11, weight: networkModeIsLAN ? .semibold : .regular))
                    .foregroundColor(networkModeIsLAN ? .white : .secondary)
                    .frame(width: thumbWidth)
            }
        }
        .frame(width: containerWidth, height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($networkDragOffset) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    let dragDistance = value.translation.width
                    let threshold = thumbWidth / 2

                    if dragDistance > threshold && !networkModeIsLAN {
                        Task { @MainActor in await switchNetworkMode(toLAN: true) }
                    } else if dragDistance < -threshold && networkModeIsLAN {
                        Task { @MainActor in await switchNetworkMode(toLAN: false) }
                    }
                }
        )
        .opacity(isChangingNetworkMode ? 0.6 : 1.0)
    }

    // MARK: - Network Mode Sync

    @MainActor
    private func syncNetworkMode() {
        networkModeIsLAN = svc.inferenceNode.isLANEnabled
    }

    // MARK: - Network Mode Switch

    @MainActor
    private func switchNetworkMode(toLAN: Bool) async {
        guard !isChangingNetworkMode, toLAN != networkModeIsLAN else { return }

        let oldMode = networkModeIsLAN
        let wasRunning = svc.isRunning
        let modelPath = svc.modelPath

        isChangingNetworkMode = true
        defer { isChangingNetworkMode = false }

        withAnimation(.easeOut(duration: 0.16)) {
            networkModeIsLAN = toLAN
        }

        if wasRunning {
            svc.status = toLAN ? "正在切换到局域网模式..." : "正在切换到本机模式..."
            await svc.stop()
        }

        if toLAN {
            svc.configureLANNode()
        } else {
            svc.configureLocalNode()
        }

        networkModeIsLAN = svc.inferenceNode.isLANEnabled

        guard wasRunning else {
            svc.status = toLAN ? "✅ 已切换到局域网模式" : "✅ 已切换到本机模式"
            return
        }

        guard !modelPath.isEmpty else {
            svc.status = toLAN ? "✅ 局域网模式已启用" : "✅ 本机模式已启用"
            return
        }

        await svc.start(path: modelPath)

        if !svc.isRunning {
            withAnimation(.easeOut(duration: 0.16)) {
                networkModeIsLAN = oldMode
            }
            svc.status = "⚠️ 网络模式切换失败，已恢复原模式"
        }
    }

    // MARK: - Service

    @MainActor
    private func toggleService() async {
        if svc.isRunning {
            await svc.stop()
        } else {
            guard !svc.modelPath.isEmpty else { return }
            await svc.start(path: svc.modelPath)
        }
    }

    @MainActor
    private func restartService() {
        guard !svc.modelPath.isEmpty else { return }

        svc.status = "正在重启..."
        Task { @MainActor in
            await svc.restart(path: svc.modelPath)
        }
    }

    // MARK: - Settings

    @MainActor
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "Settings")
    }

    // MARK: - Model

    @MainActor
    private func selectModel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                svc.modelPath = url.path
                AppConfig.set(url.path, for: .modelPath)
            }
        }
    }

    // MARK: - Copy Endpoint

    @MainActor
    private func copyAPIEndpoint() {
        let endpoint = svc.inferenceAPIBaseURL

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(endpoint, forType: .string)

        let oldStatus = svc.status
        svc.status = "✅ API 地址已复制"

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            guard svc.status == "✅ API 地址已复制" else { return }
            svc.status = oldStatus
        }
    }

    // MARK: - Quit

    @MainActor
    private func quitApp() {
        Task {
            if svc.isRunning {
                await svc.stop()
            }
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - macOS Menu Row

private struct MenuRowButton: View {
    let title: String
    let icon: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16, alignment: .center)

                Text(title)
                    .font(.system(size: 12))

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered && !disabled ? Color.accentColor : Color.clear)
            )
            .foregroundColor(disabled ? .secondary.opacity(0.5) : (isHovered ? .white : .primary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered = $0 }
    }
}
