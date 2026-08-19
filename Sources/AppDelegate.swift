import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let model = PanelModel()
    private var cancellables = Set<AnyCancellable>()
    private var backgroundTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        // 状态栏标题同步合计百分比（如 “15%”）
        model.$statusTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                MainActor.assumeIsolated {
                    self?.statusItem?.button?.title = title
                }
            }
            .store(in: &cancellables)

        model.refresh()

        // 后台每 5 分钟刷新一次，保持状态栏百分比新鲜
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.refresh()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            var image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Cursor 用量")
            if image == nil {
                image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Cursor 用量")
            }
            image?.isTemplate = true
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            image = image?.withSymbolConfiguration(config)
            button.image = image
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
    }

    private func setupPopover() {
        let p = NSPopover()
        p.behavior = .transient
        p.delegate = self
        p.contentViewController = NSHostingController(rootView: UsagePanelView(model: model))
        popover = p
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refresh() // 每次打开都拉最新
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
