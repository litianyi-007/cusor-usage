import AppKit
import SwiftUI
import Combine

/// 菜单栏面板窗口：无边框、非激活面板、可成为 key（支持 SecureField 输入）
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 液态玻璃模式的透明边距（容纳投影），0 = 传统模式
    var glassInset: CGFloat = 0

    /// 玻璃实际占用的屏幕区域（扣除透明边距）；点击判定用
    var glassScreenFrame: NSRect {
        guard glassInset > 0, let cv = contentView else { return frame }
        let inWindow = cv.convert(cv.bounds.insetBy(dx: glassInset, dy: glassInset), to: nil)
        return convertToScreen(inWindow)
    }
}

/// 液态玻璃专用宿主视图：透明边距区域的点击返回 nil（点击穿透，不进面板交互）
final class GlassHostingView<Content: View>: NSHostingView<Content> {
    var glassInset: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hit, glassInset > 0 else { return hit }
        return bounds.insetBy(dx: glassInset, dy: glassInset).contains(point) ? hit : nil
    }
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
        let p = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        // 注意：hasShadow 在传统模式下保留（不透明内容 → 正常柔和投影）；
        // 玻璃模式必须关闭 —— 全透明无边框窗口的 AppKit 投影会渲染成窗口外围一圈实心黑框，
        // 投影由 PanelBackdrop 的 SwiftUI .shadow 负责（柔和、随玻璃形状）。
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        if #available(macOS 26.0, *) {
            // 液态玻璃模式：四周留透明边距容纳投影（上 10pt 贴菜单栏，左右下更宽），
            // 边距区域点击不进面板交互（GlassHostingView.hitTest 返回 nil）
            p.hasShadow = false
            let hosting = GlassHostingView(rootView: AnyView(
                UsagePanelView(model: model)
                    .padding(.top, 10)
                    .padding(.leading, 20)
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)))
            hosting.glassInset = 20
            p.glassInset = 20
            p.contentView = hosting
        } else {
            p.hasShadow = true
            p.contentViewController = NSHostingController(rootView: AnyView(UsagePanelView(model: model)))
        }
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
    private func layoutPanel(panel: MenuPanel, button: NSStatusBarButton) {
        let fitting = panel.contentView?.fittingSize ?? NSSize(width: 340, height: 300)
        let width = max(300, min(fitting.width, 380))
        let height = max(140, min(fitting.height, 900))
        let size = NSSize(width: width, height: height)
        if abs(panel.frame.width - size.width) > 1 || abs(panel.frame.height - size.height) > 1 {
            panel.setContentSize(size)
        }
        positionPanel(panel: panel, button: button)
    }

    /// 定位：按钮中点在菜单栏正下方，屏幕内钳制
    private func positionPanel(panel: MenuPanel, button: NSStatusBarButton) {
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
        // 传统模式：面板顶 8pt 悬于菜单栏下方；液态玻璃模式：窗口顶与菜单栏底齐平
        //（透明边距上移，玻璃顶仍约 10pt 悬于菜单栏下方；窗口不压菜单栏，避免吞掉相邻状态栏项点击）
        let y = buttonScreenFrame.minY - size.height - 8 + (panel.glassInset > 0 ? 8 : 0)
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
                if !panel.glassScreenFrame.contains(point) {
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
