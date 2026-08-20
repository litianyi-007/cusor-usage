# CursorUsage v0.4.1

## What's new · 更新内容

- 🔧 **修正用量数据展示（字段语义错误）**：依据 Cursor 官方文档核实，套餐只有**两个用量池**——Cursor Models（第一方 Grok/Composer）与 Other Models（第三方，Ultra 含 $400），没有独立的 included usage 逻辑
- 📊 面板只展示两个池的用量（百分比 + 各池精确美元，按服务端 `tier` 归属求和）
- 🟦 菜单栏标题改为两池百分比（如 `7%/45%` = Cursor Models / Other Models）
- 🎨 黑鲸 / 帝王蟹标识资源更新为官方资源（DeepSeek Harness 官方仓库鲸鱼 favicon、ClawHive 官方应用 tray 图标）

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
- 用量语义参考 Cursor 官方文档 [usage-limits](https://cursor.com/help/models-and-usage/usage-limits.md) / [pricing](https://cursor.com/help/account-and-billing/pricing.md)。
