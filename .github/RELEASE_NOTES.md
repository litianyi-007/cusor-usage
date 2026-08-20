# CursorUsage v0.5.0

## What's new · 更新内容

- ⚡ **打开面板先显示缓存数据，再静默请求更新**：再次打开不再闪 loading，秒开上次数据后后台刷新；首次打开（无缓存）才显示加载态；有缓存时请求失败也静默保留缓存
- 🔄 后台定时刷新（每 5 min）同样改为静默更新，不打断状态栏/面板展示
- 🔧 上一版已修正用量语义：官方只有两个用量池（Cursor Models / Other Models，Ultra 含 $400），面板只展示这两块，菜单栏显示两池百分比（如 `7%/45%`）

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
