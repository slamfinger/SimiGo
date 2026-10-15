import SwiftUI
import AppKit

@main
struct MenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // 菜单栏与窗口自 2026-10-15 起由 StatusBarCoordinator 直管（AppKit
    // NSStatusItem + NSPopover）：MenuBarExtra(.window) 在系统睡眠唤醒后
    // 点击静默失效（点击受理、按钮高亮、面板零创建），弃用该场景路径。
    // 空 Settings 场景仅作 App body 占位；SwiftUI.Settings 全名修饰以
    // 区别于本地 Settings 视图。
    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}

// MARK: - Menu Panel

struct MenuPanelView: View {
    @EnvironmentObject private var svc: Service
    @State private var networkModeIsLAN = false
    @State private var isChangingNetworkMode = false
    @State private var showBackendSwitch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statusHeader
            networkSlider.padding(.horizontal, 4)

            Divider().padding(.vertical, 2)

            MenuRowButton(
                title: svc.isRunning ? "启动 / 切换（停止）" : "启动 / 切换",
                icon: svc.isRunning ? "stop.circle" : "arrow.2.squarepath"
            ) {
                withAnimation(.easeOut(duration: 0.15)) {
                    showBackendSwitch.toggle()
                }
            }

            if showBackendSwitch {
                MenuRowButton(
                    title: backendButtonTitle("MLX", selection: .mlx),
                    icon: "cpu",
                    leading: 12,
                    disabled: ((!svc.isRunning || svc.backendSelection != .mlx) && !svc.canStartLocal(.mlx)) || isChangingNetworkMode
                ) {
                    Task { @MainActor in await toggleBackend(.mlx) }
                }

                MenuRowButton(
                    title: backendButtonTitle("LLaMA.cpp", selection: .llamaCpp),
                    icon: "shippingbox",
                    leading: 12,
                    disabled: ((!svc.isRunning || svc.backendSelection != .llamaCpp) && !svc.canStartLocal(.gguf)) || isChangingNetworkMode
                ) {
                    Task { @MainActor in await toggleBackend(.llamaCpp) }
                }

                MenuRowButton(
                    title: backendButtonTitle(svc.cloudProviderName, selection: .cloud),
                    icon: "cloud",
                    leading: 12,
                    disabled: svc.backendSelection == .cloud && !svc.hasStartTarget || isChangingNetworkMode
                ) {
                    Task { @MainActor in await toggleBackend(.cloud) }
                }
            }

            Divider().padding(.vertical, 2)

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
                disabled: svc.isRunning || svc.backendSelection == .cloud || isChangingNetworkMode
            ) {
                selectModel()
            }

            MenuRowButton(title: "复制 API 地址", icon: "doc.on.doc") {
                copyAPIEndpoint()
            }

            Divider().padding(.vertical, 2)

            MenuRowButton(title: "设置...", icon: "gearshape") {
                StatusBarCoordinator.shared.openSettingsWindow()
            }

            MenuRowButton(title: "Execution State Graph...", icon: "circle.hexagongrid") {
                StatusBarCoordinator.shared.openStateGraphWindow()
            }

            Divider().padding(.vertical, 2)

            MenuRowButton(title: "退出", icon: "xmark.circle") {
                quitApp()
            }
        }
        .padding(6)
        .frame(width: 190)
        .onAppear {
            syncNetworkMode()
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
        let containerWidth: CGFloat = 178
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
                .offset(x: targetOffset)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: networkModeIsLAN)

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
        .onTapGesture(count: 1, coordinateSpace: .local) { location in
            let wantsLAN = location.x >= thumbWidth
            Task { @MainActor in await switchNetworkMode(toLAN: wantsLAN) }
        }
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

        guard svc.hasStartTarget else {
            svc.status = toLAN ? "✅ 局域网模式已启用" : "✅ 本机模式已启用"
            return
        }

            await svc.startSelected()

        if !svc.isRunning {
            withAnimation(.easeOut(duration: 0.16)) {
                networkModeIsLAN = oldMode
            }
            svc.status = "⚠️ 网络模式切换失败，已恢复原模式"
        }
    }

    // MARK: - Service

    @MainActor
    private func toggleBackend(_ selection: BackendSelection) async {
        if svc.isRunning && svc.backendSelection == selection {
            await svc.stop()
        } else {
            await svc.start(selection)
        }
    }

    private func backendButtonTitle(_ name: String, selection: BackendSelection) -> String {
        let action = svc.isRunning && svc.backendSelection == selection ? "停止" : "启动"
        return "\(name) · \(action)"
    }

    @MainActor
    private func restartService() {
        guard svc.hasStartTarget else { return }

        svc.status = "正在重启..."
        Task { @MainActor in
            await svc.restartSelected()
        }
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
                svc.selectModel(url.path)
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
    var leading: CGFloat = 0
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
            .padding(.leading, 8 + leading)
            .padding(.trailing, 8)
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
