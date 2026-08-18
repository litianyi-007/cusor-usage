import AppKit
import SwiftUI

// MARK: - Headless 诊断 / 自检模式
//
// 用法:
//   CursorUsage --dump [--from-cursor]      拉取并打印解析后的用量文本后退出(不启动 GUI)
//   CursorUsage --dump-json [--from-cursor] 打印原始 JSON + 两个池的美元拆分
//   CursorUsage --keychain-test             钥匙串存取自检(写入→读取→删除,不涉及真实 token)
//   CursorUsage --smoke-test                启动菜单栏 GUI,4 秒后自动退出(验证 AppKit 路径)
// --from-cursor:允许从 Cursor 本地状态库读取 token(默认只读 Keychain/兜底文件)

if CommandLine.arguments.contains("--dump") {
    runDump(json: false)
    exit(0)
}
if CommandLine.arguments.contains("--dump-json") {
    runDump(json: true)
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

if CommandLine.arguments.contains("--smoke-test") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        print("SMOKE OK: status item created, run loop alive")
        NSApp.terminate(nil)
    }
}

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
        store.onUpdate = { [weak self] in self?.updateStatusTitle() }
        store.startAutoRefresh()
        Task { await store.refresh() }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill",
                                   accessibilityDescription: "Cursor 用量")
            button.imagePosition = .imageLeading
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

    // MARK: - 状态栏标题

    /// 状态栏图标旁显示综合用量百分比,悬浮提示显示详细数据
    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        if let pu = store.usage?.planUsage, let total = pu.totalPercentUsed {
            button.title = String(format: "%.1f%%", total)
            var tooltip = "Cursor 用量"
            if let p = store.planInfo?.planName { tooltip += " · \(p)" }
            tooltip += String(format: " · 综合 %.1f%%", total)
            if let a = pu.autoPercentUsed { tooltip += String(format: " · Cursor %.1f%%", a) }
            if let b = pu.apiPercentUsed { tooltip += String(format: " · Other %.1f%%", b) }
            button.toolTip = tooltip
        } else {
            button.title = ""
            button.toolTip = "Cursor 用量"
        }
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
        let width = contentView?.fittingSize.width ?? 340
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

func runDump(json: Bool) {
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
            let agg: AggregatedUsageEventsResponse? = try? await UsageClient.fetchAggregatedUsageEvents(token: token)
            if json {
                print(dumpJSON(usage: usage, plan: plan?.planInfo, agg: agg))
            } else {
                print(dumpText(usage: usage, plan: plan?.planInfo, agg: agg))
            }
        } catch {
            print("ERROR: \(error.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
}

/// 按 autoBucketModels 归属两个池的美元拆分(与 UsageStore.computePools 同口径)
private func poolSplit(usage: CurrentPeriodUsageResponse, agg: AggregatedUsageEventsResponse?) -> (cursor: Double, other: Double)? {
    guard let agg, let rows = agg.aggregations, !rows.isEmpty else { return nil }
    let auto = Set(usage.autoBucketModels ?? [])
    var cursor = 0.0
    var other = 0.0
    for row in rows {
        let name = row.modelLabel
        let cents = row.totalCents ?? 0
        let lower = name.lowercased()
        if auto.contains(name) || ["cursor-", "composer", "vega", "grok"].contains(where: { lower.hasPrefix($0) }) {
            cursor += cents
        } else {
            other += cents
        }
    }
    return (cursor, other)
}

func dumpJSON(usage: CurrentPeriodUsageResponse, plan: PlanInfoResponse.PlanInfo?, agg: AggregatedUsageEventsResponse?) -> String {
    var out: [String: Any] = [:]
    var u: [String: Any] = [:]
    if let d = try? JSONEncoder().encode(usage),
       let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
        u = o
    }
    out["usage"] = u
    if let plan {
        out["plan"] = ["planName": plan.planName ?? "", "price": plan.price ?? "", "includedAmountCents": plan.includedAmountCents ?? 0]
    }
    if let agg {
        out["aggregationSumCents"] = agg.aggregations?.reduce(0.0) { $0 + ($1.totalCents ?? 0) } ?? 0
    }
    if let split = poolSplit(usage: usage, agg: agg) {
        out["poolSpendCents"] = ["cursorModels": split.cursor, "otherModels": split.other,
                                 "sum": split.cursor + split.other,
                                 "planUsageTotalSpend": usage.planUsage?.totalSpend ?? 0]
    }
    out["tokenExpiry"] = TokenStore.tokenExpiry(TokenStore.load(allowCursor: true) ?? "")
        .map { ISO8601DateFormatter().string(from: $0) } ?? ""
    let data = (try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
}

func dumpText(usage: CurrentPeriodUsageResponse, plan: PlanInfoResponse.PlanInfo?, agg: AggregatedUsageEventsResponse?) -> String {
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
            lines.append(String(format: "Cursor models(Auto):%.2f%%%@", a, poolSpendText(cursor: true, usage: usage, agg: agg)))
        }
        if let b = pu.apiPercentUsed {
            lines.append(String(format: "Other models(API):%.2f%%%@", b, poolSpendText(cursor: false, usage: usage, agg: agg)))
        }
        if let rem = pu.remainingBonus {
            lines.append("赠送额度剩余:\(rem ? "是" : "否")")
        }
    }
    if let split = poolSplit(usage: usage, agg: agg) {
        lines.append(String(format: "美元拆分(按 autoBucketModels 归属):Cursor models %.2f / Other models %.2f (合计 %.2f,接口 totalSpend %.2f)",
                            split.cursor / 100.0, split.other / 100.0,
                            (split.cursor + split.other) / 100.0,
                            Double(usage.planUsage?.totalSpend ?? 0) / 100.0))
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
    if let agg, let rows = agg.aggregations, !rows.isEmpty {
        lines.append("按模型花费 Top 5:")
        for row in rows.sorted(by: { ($0.totalCents ?? 0) > ($1.totalCents ?? 0) }).prefix(5) {
            lines.append(String(format: "  %@  %@", row.modelLabel, UsageFormat.centsD(row.totalCents)))
        }
    }
    if let exp = TokenStore.tokenExpiry(TokenStore.load(allowCursor: true) ?? "") {
        lines.append("token 有效期至:\(UsageFormat.date(String(Int(exp.timeIntervalSince1970 * 1000))))")
    }
    return lines.joined(separator: "\n")
}

private func poolSpendText(cursor: Bool, usage: CurrentPeriodUsageResponse, agg: AggregatedUsageEventsResponse?) -> String {
    guard let split = poolSplit(usage: usage, agg: agg) else { return "" }
    let v = cursor ? split.cursor : split.other
    return String(format: "  ($%.2f)", v / 100.0)
}
