import AppKit
import SwiftUI

/// 产品截图模式：真实拉取数据后用 ImageRenderer 渲染面板 PNG（深色产品图）。
/// 用法：CursorUsage --screenshot <输出目录> [--with-settings]
enum Screenshot {

    @MainActor
    static func run() async -> Int32 {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--screenshot"), idx + 1 < args.count else {
            print("用法: CursorUsage --screenshot <输出目录> [--with-settings]")
            return 1
        }
        let outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        let withSettings = args.contains("--with-settings")

        // 初始化 AppKit 并固定深色外观，保证渲染与产品图一致
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let model = PanelModel()
        await model.loadData()

        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var ok = true
        model.showSettings = false
        ok = render(view: UsagePanelView(model: model),
                    to: outDir.appendingPathComponent("panel.png"),
                    size: CGSize(width: 820, height: 640)) && ok

        if withSettings {
            model.showSettings = true
            ok = render(view: UsagePanelView(model: model),
                        to: outDir.appendingPathComponent("panel-settings.png"),
                        size: CGSize(width: 820, height: 860)) && ok
        }

        ok = renderMenubar(to: outDir.appendingPathComponent("menubar.png"),
                           percent: model.statusTitle) && ok
        return ok ? 0 : 1
    }

    /// 深色桌面背景 + 带阴影的面板卡片
    @MainActor
    private static func render<Content: View>(view: Content, to url: URL, size: CGSize) -> Bool {
        let content = ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.12, blue: 0.18),
                         Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            view
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .windowBackgroundColor)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.5), radius: 32, y: 16)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("[screenshot] 渲染失败: \(url.lastPathComponent)")
            return false
        }
        do {
            try png.write(to: url)
            print("[screenshot] 已写出 \(url.path)")
            return true
        } catch {
            print("[screenshot] 写入失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 模拟菜单栏条：图标 + 合计百分比
    @MainActor
    private static func renderMenubar(to url: URL, percent: String) -> Bool {
        var icon = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: nil)
        if icon == nil { icon = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil) }
        guard let baseIcon = icon else { return false }
        let sized = baseIcon.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 30, weight: .medium))!

        let img = NSImage(size: NSSize(width: 220, height: 88))
        img.lockFocus()
        NSColor(white: 0.09, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 220, height: 88).fill()
        sized.draw(in: NSRect(x: 22, y: 20, width: 48, height: 48))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        NSAttributedString(string: " " + percent, attributes: attrs)
            .draw(at: NSPoint(x: 76, y: 20))
        img.unlockFocus()

        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        try? png.write(to: url)
        print("[screenshot] 已写出 \(url.path)")
        return true
    }

    /// App 图标主图（1024×1024 圆角渐变 + 白色光标符号 + gauge 弧）
    @MainActor
    private static func masterIcon(size: CGFloat) -> NSImage? {
        let s = size
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        defer { img.unlockFocus() }

        let rect = NSRect(origin: .zero, size: NSSize(width: s, height: s))
        let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.215, yRadius: s * 0.215)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.42, green: 0.50, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.45, alpha: 1),
        ])!
        gradient.draw(in: path, angle: -70)

        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.45, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let d = symbol.size
            symbol.draw(in: NSRect(x: (s - d.width) / 2, y: (s - d.height) / 2, width: d.width, height: d.height))
        }

        let gauge = NSBezierPath()
        gauge.appendArc(withCenter: NSPoint(x: s / 2, y: s * 0.29), radius: s * 0.205,
                        startAngle: 150, endAngle: 390, clockwise: false)
        gauge.lineWidth = s * 0.045
        NSColor.white.withAlphaComponent(0.92).setStroke()
        gauge.stroke()
        return img
    }

    /// App 图标 PNG（2048×2048 实际渲染，视网膜 2x）。
    /// 用法：CursorUsage --icon <输出路径/icon.png>
    @MainActor
    static func renderIcon(to url: URL) -> Bool {
        guard let master = masterIcon(size: 1024) else { return false }
        guard let tiff = master.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: url)
            print("[screenshot] 已写出 \(url.path)")
            return true
        } catch {
            print("[screenshot] 图标写入失败: \(error.localizedDescription)")
            return false
        }
    }

    /// App 图标 .icns：进程内直接把各尺寸 PNG 封装为 icns 容器（无需 iconutil/sips）。
    /// 用法：CursorUsage --icns <输出路径/AppIcon.icns>
    @MainActor
    static func renderIcns(to url: URL) -> Bool {
        guard let master = masterIcon(size: 1024) else { return false }
        // PNG 型 icns 块：类型 + 长度(含 8 字节头) + PNG 数据
        let entries: [(type: String, size: Int)] = [
            ("icp4", 16), ("icp5", 32), ("icp6", 64),
            ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
        ]
        var chunks: [Data] = []
        for entry in entries {
            let resized = NSImage(size: NSSize(width: entry.size, height: entry.size))
            resized.lockFocus()
            master.draw(in: NSRect(x: 0, y: 0, width: entry.size, height: entry.size),
                        from: .zero, operation: .copy, fraction: 1)
            resized.unlockFocus()
            guard let tiff = resized.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                return false
            }
            var chunk = Data()
            chunk.append(Data(entry.type.utf8))
            withUnsafeBytes(of: UInt32(png.count + 8).bigEndian) { chunk.append(contentsOf: $0) }
            chunk.append(png)
            chunks.append(chunk)
        }
        var data = Data()
        data.append(Data("icns".utf8))
        withUnsafeBytes(of: UInt32(8 + chunks.reduce(0) { $0 + $1.count }).bigEndian) { data.append(contentsOf: $0) }
        for c in chunks { data.append(c) }
        do {
            try data.write(to: url)
            print("[screenshot] 已写出 \(url.path) (\(entries.count) 个尺寸)")
            return true
        } catch {
            print("[screenshot] icns 写入失败: \(error.localizedDescription)")
            return false
        }
    }
}
