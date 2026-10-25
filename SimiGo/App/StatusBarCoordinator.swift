import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // G1/G3 controlled headless gate (env-gated). Default GUI path unchanged:
        // only engages when SIMIGO_HEADLESS_ROLE is present, and fail-closes on an
        // unsupported role / missing parameters BEFORE any model work.
        let headless = SimiGoG1G3Entry.evaluate()
        if headless.requested {
            guard let role = headless.role else {
                FileHandle.standardError.write(
                    ("headless fail-closed: " + (headless.error ?? "unknown") + "\n").data(using: .utf8)!)
                exit(2)
            }
            // Keep AppKit's main loop alive (do not pump a nested runloop here: that
            // ends the accessory app). Returning from applicationDidFinishLaunching lets
            // NSApp.run continue servicing the main queue, which drives the @MainActor
            // task below; exit(code) terminates once the model work finishes. Requires a
            // bundle id distinct from any running SimiGo instance to avoid the
            // LaunchServices single-instance handoff.
            FileHandle.standardError.write(("headless-entered role=\(role.rawValue) pid=\(getpid())\n").data(using: .utf8)!)
            Task { @MainActor in
                FileHandle.standardError.write("headless-task-started\n".data(using: .utf8)!)
                let code = await SimiGoG1G3Entry.run(role: role)
                FileHandle.standardError.write(("headless-task-done rc=\(code)\n").data(using: .utf8)!)
                exit(code)
            }
            return
        }
        // Generation-environment bootstrap gate (SIMIGO_ENV_BOOTSTRAP=1):
        // provisions the managed tree, llama.cpp, hf, and the blank ES/IS
        // database (+ optional SIMIGO_WORKROOT registration), then exits. It
        // is the one-command path from a bare install to a root where
        // Execution State / Information Space can run; it never starts a model
        // or a listener.
        let envBootstrap = SimiGoEnvBootstrapEntry.evaluate()
        if envBootstrap.requested {
            guard envBootstrap.valid else {
                FileHandle.standardError.write(
                    ("env-bootstrap fail-closed: " + (envBootstrap.error ?? "unknown") + "\n")
                        .data(using: .utf8)!)
                exit(2)
            }
            FileHandle.standardError.write("env-bootstrap-entered\n".data(using: .utf8)!)
            Task { @MainActor in
                let code = await SimiGoEnvBootstrapEntry.run()
                exit(code)
            }
            return
        }
        // LOCALB local-management gate (env-gated, isolated roots only). The
        // product ships the first-run ceremony / pairing primitives but no
        // surface called them, so a never-activated host could not bind its
        // listener at all. This gate only routes an explicit operator command
        // to those existing APIs; it never activates on an ordinary launch.
        let management = SimiGoLocalBManagementEntry.evaluate()
        if management.requested {
            guard let role = management.role else {
                FileHandle.standardError.write(
                    ("localb-mgmt fail-closed: " + (management.error ?? "unknown") + "\n").data(using: .utf8)!)
                exit(2)
            }
            FileHandle.standardError.write(
                ("localb-mgmt-entered role=\(role.rawValue) pid=\(getpid())\n").data(using: .utf8)!)
            Task { @MainActor in
                let code = await SimiGoLocalBManagementEntry.run(role: role)
                exit(code)
            }
            return
        }
        StatusBarCoordinator.shared.start()
        // Autonomous, idempotent first-run bootstrap off the main thread.
        Task.detached(priority: .utility) {
            _ = SimiGoBootstrapRunner.launchIfNeeded()
        }
    }
}

/// AppKit 直管菜单栏：NSStatusItem + NSPopover + NSWindow。
/// 取代 MenuBarExtra(.window)——后者在系统睡眠唤醒后点击静默失效
/// （2026-10-15 实证：performClick 受理、按钮高亮，面板零创建）。
@MainActor
final class StatusBarCoordinator: NSObject {
    static let shared = StatusBarCoordinator()

    private let svc = Service.shared
    private let stateGraph = ExecutionStateGraphStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindowController: NSWindowController?
    private var stateGraphWindowController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var popoverClosedAt = Date.distantPast

    private override init() {
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp])
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuPanelView().environmentObject(svc)
        )
        popover.delegate = self

        // objectWillChange 在属性变更前同步发出；经 MainActor Task
        // 跳到变更完成后再刷新图标。
        svc.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshIcon() }
            }
            .store(in: &cancellables)
        refreshIcon()
    }

    // MARK: - Icon

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }

        let name: String
        let color: NSColor

        if svc.status.hasPrefix("⚠️") {
            name = "exclamationmark.triangle.fill"
            color = .systemYellow
        } else if !svc.isRunning {
            name = "bolt"
            color = .labelColor
        } else {
            name = "bolt.fill"
            switch svc.memoryPressure {
            case "critical": color = .systemRed
            case "warn": color = .systemOrange
            default: color = .systemGreen
            }
        }

        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "SimiGo")?
            .withSymbolConfiguration(configuration)
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else if Date().timeIntervalSince(popoverClosedAt) > 0.25 {
            // .transient 在点击图标瞬间先合上面板；冷却窗口防 action 再掀开
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    // MARK: - Windows

    func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let controller = settingsWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(
            rootView: Settings().environmentObject(svc)
        ))
        window.title = "设置"
        window.styleMask.remove(.resizable) // 对齐原场景 .windowResizability(.contentSize)
        window.setContentSize(NSSize(width: 420, height: 480))
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
    }

    func openStateGraphWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let controller = stateGraphWindowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(
            rootView: ExecutionStateGraphView()
                .environmentObject(stateGraph)
                .environmentObject(svc)
        ))
        window.title = "Execution State"
        window.setContentSize(NSSize(width: 820, height: 560))
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.delegate = self
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        stateGraphWindowController = controller
        controller.showWindow(nil)
    }
}

extension StatusBarCoordinator: NSPopoverDelegate, NSWindowDelegate {
    func popoverDidClose(_ notification: Notification) {
        popoverClosedAt = Date()
    }

    // 关窗即释放控制器，下次开窗重建视图（对齐原 WindowGroup 语义）
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === settingsWindowController?.window {
            window.delegate = nil
            settingsWindowController = nil
        } else if window === stateGraphWindowController?.window {
            window.delegate = nil
            stateGraphWindowController = nil
        }
    }
}
