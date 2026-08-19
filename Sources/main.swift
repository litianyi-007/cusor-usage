import AppKit
import Foundation

// 无头自测模式：验证 token 解析、真实 API 调用、钥匙串/文件存取。
// 用法：./CursorUsage --selfcheck
if CommandLine.arguments.contains("--selfcheck") {
    exit(SelfCheck.run())
}

// 进程启动即在主线程，安全地用 MainActor 包裹
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 纯菜单栏常驻：不占用 Dock 图标
    app.setActivationPolicy(.accessory)
    app.run()
}