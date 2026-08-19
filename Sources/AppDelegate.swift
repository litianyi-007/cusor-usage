import AppKit
import SwiftUI
import Combine

/// 菜单栏面板窗口：无边框、非激活面板、可成为 key（支持 SecureField 输入）
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panel: MenuPanel?
    private let model = PanelModel()
    private var cancellables = Set<AnyCancellable>()
    private var backgroundTimer: Timer?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        PanelModel.diagnose("didFinishLaunching: statusItem 就绪")
        setupPanel()
        PanelModel.diagnose("didFinishLaunching: panel 就绪")
        setupMonitors()
        PanelModel.diagnose("didFinishLaunching: monitors 就绪")

        // 状态栏标题同步合计百分比（如 “15%”）
        model.$statusTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                MainActor.assumeIsolated {
                    self?.statusItem?.button?.title = title
                }
            }
            .store(in: &cancellables)

        // 面板内容变化（加载完成/设置展开等）→ 自动重排尺寸与位置
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.relayoutPanel() }
            }
            .store(in: &cancellables)

        PanelModel.diagnose("didFinishLaunching: sinks 就绪，准备 refresh")
        model.refresh()
        PanelModel.diagnose("didFinishLaunching: refresh 已触发")

        // 后台每 5 分钟刷新一次，保持状态栏百分比新鲜
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.refresh()
            }
        }

        // 调试：CURSORUSAGE_AUTOSHOW=1 时启动后自动弹出面板（验证定位/加载用）
        if ProcessInfo.processInfo.environment["CURSORUSAGE_AUTOSHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if ProcessInfo.processInfo.environment["CURSORUSAGE_AUTOSHOW_SETTINGS"] == "1" {
                    self?.model.openSettings()
                }
                self?.showPanel()
            }
        }
    }

    // MARK: - 状态栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // 抽象派字母 C + 用量百分比（彩色图标，不设 template 以保留渐变）
            button.image = CursorIcon.make(size: 17)
            button.image?.isTemplate = false
            button.title = ""
            button.action = #selector(togglePanel(_:))
            button.target = self
        }
        statusItem = item
    }

    // MARK: - 面板（自定位，替代 NSPopover：位置可控、内容变化自动重排）

    private func setupPanel() {
        let contentVC = NSHostingController(rootView: UsagePanelView(model: model))
        let p = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.contentViewController = contentVC
        panel = p
        logPanel("初始化面板")
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let button = statusItem?.button else { return }
        logPanel("显示面板")
        NSApp.activate(ignoringOtherApps: true) // 先激活再显示，避免 popover 式跳动
        model.refresh()                          // 每次打开都拉最新
        layoutPanel(panel: panel, button: button) // 显示前先按内容定尺寸并定位（不依赖异步）
        panel.makeKeyAndOrderFront(nil)
        logPanel("面板已显示 frame=\(NSStringFromRect(panel.frame)) screen=\(button.window?.screen.map { NSStringFromRect($0.visibleFrame) } ?? "?")")
    }

    private func hidePanel() {
        guard let panel, panel.isVisible else { return }
        logPanel("隐藏面板")
        panel.orderOut(nil)
    }

    /// 面板可见时的异步重排（数据加载完成/设置展开等触发）
    private func relayoutPanel() {
        guard let panel, panel.isVisible, let button = statusItem?.button else { return }
        layoutPanel(panel: panel, button: button)
    }

    /// 按内容 fittingSize 调整尺寸并定位到状态栏按钮正下方
    private func layoutPanel(panel: NSPanel, button: NSStatusBarButton) {
        let fitting = panel.contentViewController?.view.fittingSize ?? NSSize(width: 340, height: 300)
        let width = max(300, min(fitting.width, 380))
        let height = max(140, min(fitting.height, 900))
        let size = NSSize(width: width, height: height)
        if abs(panel.frame.width - size.width) > 1 || abs(panel.frame.height - size.height) > 1 {
            panel.setContentSize(size)
        }
        positionPanel(panel: panel, button: button)
    }

    /// 定位：按钮中点在菜单栏正下方，屏幕内钳制
    private func positionPanel(panel: NSPanel, button: NSStatusBarButton) {
        guard let window = button.window else {
            PanelModel.diagnose("position: button.window 为 nil，兜底居中")
            panel.center()
            return
        }
        let buttonScreenFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        var x = buttonScreenFrame.midX - size.width / 2
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let y = buttonScreenFrame.minY - size.height - 8
        PanelModel.diagnose("position: winFrame=\(NSStringFromRect(window.frame)) btnOnScreen=\(NSStringFromRect(buttonScreenFrame)) screen=\(NSStringFromRect(screenFrame)) -> x=\(String(format: "%.0f", x)) y=\(String(format: "%.0f", y))")
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 事件监控（点击外部关闭 / Esc 关闭）

    private func setupMonitors() {
        // 其他应用内的鼠标点击 → 关闭面板
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let point = event.locationInWindow // 全局监控的事件坐标即屏幕坐标
                if !panel.frame.contains(point) {
                    self.hidePanel()
                }
            }
        }
        // Esc 关闭
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hidePanel()
                return nil
            }
            return event
        }
        // 应用失活（如 Cmd+Tab）也关闭
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    // MARK: - 日志

    private func logPanel(_ message: String) {
        NSLog("[CursorUsage] %@", message)
    }
}
