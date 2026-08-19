import AppKit
import Foundation

// 注意：本文件顶层代码必须保持【同步】。一旦顶层出现 await，主入口变为异步上下文，
// MainActor.run/app.run() 会阻塞主 actor 且不再排空主队列，导致所有 Task/定时器不执行
//（症状：面板一直转圈、自动弹出失效）。

// 无头自测模式：验证 token 解析、真实 API 调用、钥匙串/文件存取。
if CommandLine.arguments.contains("--selfcheck") {
    exit(SelfCheck.run())
}

// 产品截图模式：真实数据渲染面板 PNG。
// 用法：./CursorUsage --screenshot <输出目录> [--with-settings]
if CommandLine.arguments.contains("--screenshot") {
    exit(Screenshot.screenshotSync())
}

// App 图标：生成 1024px PNG（--icon <路径>）或直接生成 .icns（--icns <路径>）
if let idx = CommandLine.arguments.firstIndex(of: "--icon"), CommandLine.arguments.count > idx + 1 {
    exit(Screenshot.iconSync(to: URL(fileURLWithPath: CommandLine.arguments[idx + 1])) ? 0 : 1)
}
if let idx = CommandLine.arguments.firstIndex(of: "--icns"), CommandLine.arguments.count > idx + 1 {
    exit(Screenshot.icnsSync(to: URL(fileURLWithPath: CommandLine.arguments[idx + 1])) ? 0 : 1)
}

// GUI 模式：纯菜单栏常驻（无 Dock 图标）。
// 进程启动即在真实主线程，用 assumeIsolated 安全包裹；app.run() 让主线程运行 run loop，
// 从而正常排空主队列/主 actor 任务（fetch、定时器、面板自动重排都依赖这一点）。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
