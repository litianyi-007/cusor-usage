import AppKit
import SwiftUI

// MARK: - Headless 诊断模式
//
// 用法:
//   CursorUsage --dump [--from-cursor]   拉取当前周期用量并打印解析结果后退出(不启动 GUI)
//   CursorUsage --keychain-test          钥匙串存取自检(写入→读取→删除,不涉及真实 token)
// --from-cursor:允许从 Cursor 本地状态库读取 token(默认只读 Keychain/兜底文件)。

if CommandLine.arguments.contains("--dump") {
    runDump()
    exit(0)
}

if CommandLine.arguments.contains("--keychain-test") {
    let dummy = "test-token-\(UUID().uuidString)"
    let saved = TokenStore.saveToKeychain(dummy)
    let readBack = TokenStore.readFromKeychain() == dummy
    TokenStore.deleteFromKeychain()
    let deleted = TokenStore.readFromKeychain() == nil
    print("keychain save=\(saved) readMatch=\(readBack) delete=\(deleted)")
    exit(saved && readBack && deleted ? 0 : 3)
}

// MARK: - App 主体

let app = NSApplication.shared
// 顶层代码运行在主线程,主线程上安全地构造 @MainActor 的 AppDelegate
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory) // 菜单栏常驻,不占 Dock
app.run()

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: UsagePanel?
    private var settingsWindow: NSWindow?
    private let store = UsageStore.shared
    private var contextMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        store.startAutoRefresh()
        Task { await store.refresh() }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill",
                                   accessibilityDescription: "Cursor 用量")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // 左键:弹出用量面板;右键:菜单
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        contextMenu = NSMenu()
        let refreshItem = NSMenuItem(title: "刷新用量", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        contextMenu.addItem(refreshItem)
        let settingsItem = NSMenuItem(title: "设置 Token…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)
        contextMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
    }

    // MARK: - 状态栏点击

    @objc private func statusItemClicked(_ sender: Any?) {
        let type = NSApp.currentEvent?.type
        if type == .rightMouseUp || type == .rightMouseDown {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        togglePanel()
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        if panel == nil {
            panel = UsagePanel(store: store) { [weak self] in
                self?.openSettings()
            }
        }
        guard let panel, let button = statusItem.button else { return }
        // 面板打开前按需刷新(60 秒内不重复拉取)
        Task { await store.refreshIfStale() }
        panel.show(under: button)
    }

    // MARK: - 动作

    @objc private func refreshClicked() {
        Task { await store.refresh() }
    }

    @objc private func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            initialToken: TokenStore.load(allowCursor: true) ?? "",
            onClose: { [weak self] in self?.settingsWindow?.orderOut(nil) },
            onTokenSaved: { [weak self] in
                Task { await self?.store.refresh() }
            }
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cursor Usage 设置"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}

// MARK: - 用量面板(NSPanel,浮于状态栏下方)

final class UsagePanel: NSPanel {
    init(store: UsageStore, onOpenSettings: @escaping () -> Void) {
        let content = UsagePanelView(store: store, onOpenSettings: onOpenSettings)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor
        contentView = hosting
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 定位在状态栏图标正下方,并保证不超出屏幕
    func show(under button: NSButton) {
        let width = contentView?.fittingSize.width ?? 330
        let height = contentView?.fittingSize.height ?? 320
        guard let screen = button.window?.screen ?? NSScreen.main else { return }
        let statusFrame = button.window?.frame ?? .zero
        let vf = screen.visibleFrame
        let x = min(max(statusFrame.midX - width / 2, vf.minX + 8), vf.maxX - width - 8)
        let y = statusFrame.minY - height - 6
        setFrame(NSRect(x: x, y: max(y, vf.minY + 8), width: width, height: height), display: true)
        orderFrontRegardless()
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Headless 诊断输出

func runDump() {
    let allowCursor = CommandLine.arguments.contains("--from-cursor")
    guard let token = TokenStore.load(allowCursor: allowCursor) else {
        print("ERROR: 未找到 accessToken(可加 --from-cursor 从 Cursor 本地状态库读取)")
        exit(2)
    }
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let usage: CurrentPeriodUsageResponse = try await UsageClient.fetchCurrentPeriodUsage(token: token)
            let plan: PlanInfoResponse? = try? await UsageClient.fetchPlanInfo(token: token)
            print(dumpText(usage: usage, plan: plan?.planInfo))
        } catch {
            print("ERROR: \(error.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
}

func dumpText(usage: CurrentPeriodUsageResponse, plan: PlanInfoResponse.PlanInfo?) -> String {
    var lines: [String] = []
    lines.append("== Cursor 当前周期用量(GetCurrentPeriodUsage)==")
    if let plan {
        lines.append("套餐:\(plan.planName ?? "?") \(plan.price ?? "")")
    }
    lines.append("计费周期:\(UsageFormat.date(usage.billingCycleStart)) → \(UsageFormat.date(usage.billingCycleEnd))")
    if let pu = usage.planUsage {
        lines.append("总花费:\(UsageFormat.cents(pu.totalSpend))  计入额度:\(UsageFormat.cents(pu.includedSpend))  赠送:\(UsageFormat.cents(pu.bonusSpend))")
        lines.append("Other Models 池:已用 \(UsageFormat.cents(pu.includedSpend)) / \(UsageFormat.cents(pu.limit))  剩余 \(UsageFormat.cents(pu.remaining))")
        if let t = pu.totalPercentUsed {
            lines.append(String(format: "综合用量:%.2f%%", t))
        }
        if let a = pu.autoPercentUsed {
            lines.append(String(format: "Cursor models(Auto):%.2f%%%@", a, pu.autoSpend.map { "  (\(UsageFormat.cents($0)))" } ?? ""))
        }
        if let b = pu.apiPercentUsed {
            lines.append(String(format: "Other models(API):%.2f%%%@", b, pu.apiSpend.map { "  (\(UsageFormat.cents($0)))" } ?? ""))
        }
        if let rem = pu.remainingBonus {
            lines.append("赠送额度剩余:\(rem ? "是" : "否")")
        }
    }
    if let sl = usage.spendLimitUsage {
        if let i = sl.individualLimit, i > 0 {
            lines.append("按需(个人):已用 \(UsageFormat.cents(sl.individualUsed)) / \(UsageFormat.cents(i))")
        }
        if let p = sl.pooledLimit, p > 0 {
            lines.append("按需(团队池):已用 \(UsageFormat.cents(sl.pooledUsed)) / \(UsageFormat.cents(p))")
        }
    }
    if let m = usage.displayMessage {
        lines.append("服务端消息:\(m)")
    }
    if let m = usage.autoModelSelectedDisplayMessage {
        lines.append("Auto 模式消息:\(m)")
    }
    if let m = usage.namedModelSelectedDisplayMessage {
        lines.append("API 模式消息:\(m)")
    }
    if let models = usage.autoBucketModels {
        lines.append("Auto 桶模型(\(models.count) 个):\(models.prefix(8).joined(separator: ", "))\(models.count > 8 ? " …" : "")")
    }
    return lines.joined(separator: "\n")
}
