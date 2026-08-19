# CursorUsage v0.4.0

## What's new · 更新内容

- ✨ **macOS 26 液态玻璃（Liquid Glass）面板**：原生 SwiftUI `glassEffect` —— 随壁纸取色的半透明玻璃、玻璃边缘高光、24pt 连续圆角、柔和悬浮投影；透明边距不进交互，窗口不压菜单栏；macOS 12–25 自动回退经典卡片
- 🎨 玻璃质感用量条（半透明轨道 + 渐变填充 + 顶部高光 + 细描边）、发丝分隔线
- 🔧 修复：液态玻璃面板外围的实心黑框（全透明无边框窗口关闭 AppKit `hasShadow`，投影由 SwiftUI 负责）
- 🛠 CI 构建机升级 `macos-26`（液态玻璃代码需要 macOS 26 SDK 编译）

## Install · 安装

- Download `CursorUsage-<ver>-macOS.zip` (or `.dmg`), unzip, and move `CursorUsage.app` to `/Applications`.
- 下载 zip/dmg，解压后把 `CursorUsage.app` 拖入「应用程序」。

> ⚠️ The app is **ad-hoc signed** (local build, not notarized). On first launch, right-click the app → **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/CursorUsage.app` in Terminal if Gatekeeper blocks it.
> 应用为 ad-hoc 签名（未公证）。首次打开如被 Gatekeeper 拦截：右键应用 →「打开」，或终端执行 `xattr -dr com.apple.quarantine /Applications/CursorUsage.app`。

## Notes · 说明

- Unofficial tool, not affiliated with Cursor. API is reverse-engineered and may change. 非官方工具，接口可能随时变化。
- Token 只保存在本机钥匙串（或 600 权限本地文件），绝不入仓库/上传。
- Liquid Glass 面板需 macOS 26；低版本系统自动使用经典卡片样式。
