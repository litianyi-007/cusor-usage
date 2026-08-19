import AppKit

/// 抽象派风格字母 C 图标渲染器（设计空间 100×100，任意尺寸缩放）。
/// 主形：渐变描边的粗“C”弧（右侧开口）+ 抽象点缀（橙色圆点 / 绿色小弧 / 粉色方块 / 白色圆点）。
enum CursorIcon {

    static func make(size: CGFloat) -> NSImage {
        let s = size / 100.0
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let center = CGPoint(x: 50 * s, y: 52 * s)
        let radius = 34 * s
        let lineWidth = 17 * s

        // ---- 主 C 弧：渐变描边（右侧开口，抽象弧形） ----
        let arc = CGMutablePath()
        // 330°(右下) 顺时针扫过 270°(下) 180°(左) 90°(上) 到 30°(右上)，右侧留缺口 → 字母 C
        arc.addArc(center: center, radius: radius,
                   startAngle: Self.deg2rad(330), endAngle: Self.deg2rad(30),
                   clockwise: true)
        let stroked = arc.copy(strokingWithWidth: lineWidth,
                               lineCap: .round, lineJoin: .round, miterLimit: 10)
        ctx.addPath(stroked)
        ctx.clip()

        let bounds = stroked.boundingBox
        let colors = [
            NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1).cgColor,   // 蓝
            NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.98, alpha: 1).cgColor,   // 紫
            NSColor(calibratedRed: 0.93, green: 0.29, blue: 0.60, alpha: 1).cgColor,   // 粉
            NSColor(calibratedRed: 0.98, green: 0.59, blue: 0.20, alpha: 1).cgColor,   // 橙
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors,
                                     locations: [0, 0.38, 0.72, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: bounds.minX, y: bounds.minY),
                                   end: CGPoint(x: bounds.maxX, y: bounds.maxY),
                                   options: [])
        }
        ctx.restoreGState()

        // ---- 抽象点缀 ----
        // 橙色圆点（C 缺口内侧）
        ctx.setFillColor(NSColor(calibratedRed: 0.98, green: 0.59, blue: 0.20, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: 76 * s, y: 52 * s, width: 15 * s, height: 15 * s))

        // 绿色小弧（左下，向心呼应主弧）
        let subArc = CGMutablePath()
        subArc.addArc(center: CGPoint(x: 33 * s, y: 30 * s), radius: 12 * s,
                      startAngle: Self.deg2rad(15), endAngle: Self.deg2rad(160), clockwise: false)
        ctx.addPath(subArc.copy(strokingWithWidth: 6 * s, lineCap: .round, lineJoin: .round, miterLimit: 10))
        ctx.setStrokeColor(NSColor(calibratedRed: 0.20, green: 0.85, blue: 0.55, alpha: 1).cgColor)
        ctx.strokePath()

        // 粉色旋转方块（左上）
        ctx.saveGState()
        ctx.translateBy(x: 30 * s, y: 78 * s)
        ctx.rotate(by: Self.deg2rad(28))
        ctx.setFillColor(NSColor(calibratedRed: 0.93, green: 0.29, blue: 0.60, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -6.5 * s, y: -6.5 * s, width: 13 * s, height: 13 * s))
        ctx.restoreGState()

        // 白色小圆点（中央偏下）
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fillEllipse(in: CGRect(x: 45 * s, y: 43 * s, width: 10 * s, height: 10 * s))

        return image
    }

    private static func deg2rad(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}
