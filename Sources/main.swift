import AppKit
import Foundation

// 无头自测模式：验证 token 解析、真实 API 调用、钥匙串/文件存取。
// 用法：./CursorUsage --selfcheck
if CommandLine.arguments.contains("--selfcheck") {
    exit(SelfCheck.run())
}

// 产品截图模式：真实数据渲染面板 PNG。
// 用法：./CursorUsage --screenshot <输出目录> [--with-settings]
if CommandLine.arguments.contains("--screenshot") {
    let code = await Screenshot.run()
    exit(code)
}

// App 图标模式：生成 1024×1024 图标 PNG（或直接生成 .icns，无需外部工具）。
// 用法：./CursorUsage --icon <输出路径/icon.png> | --icns <输出路径/AppIcon.icns>
if let iconIdx = CommandLine.arguments.firstIndex(of: "--icon"), CommandLine.arguments.count > iconIdx + 1 {
    let ok = await MainActor.run {
        Screenshot.renderIcon(to: URL(fileURLWithPath: CommandLine.arguments[iconIdx + 1]))
    }
    exit(ok ? 0 : 1)
}
if let icnsIdx = CommandLine.arguments.firstIndex(of: "--icns"), CommandLine.arguments.count > icnsIdx + 1 {
    let ok = await MainActor.run {
        Screenshot.renderIcns(to: URL(fileURLWithPath: CommandLine.arguments[icnsIdx + 1]))
    }
    exit(ok ? 0 : 1)
}

// GUI 模式：纯菜单栏常驻（无 Dock 图标）
await MainActor.run {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
