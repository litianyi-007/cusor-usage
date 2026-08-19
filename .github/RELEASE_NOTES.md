# CursorUsage v0.3.0

## What's new · 更新内容

- 🎨 菜单栏图标改为抽象派风格字母 **C** + 实时用量百分比（渐变弧 + 几何点缀）
- ⚙️ 设置按钮改为 **toggle**：再次点击即收起设置（与设置区内收起按钮共两处入口），并带激活态高亮
- 🔧 修复：面板一直转圈（主队列饥饿 / URLSession 释放 / 次要请求阻塞）
- 📍 修复：面板远离菜单栏（自定位 NSPanel，内容变化自动重排）
- ✅ 设置无反馈修复（任何状态下都可展开设置）
- 🛠 工程化：GitHub Actions CI + Release 自动打包（zip / dmg），VERSION 单源版本维护

## Install · 安装

- Download `CursorUsage-<ver>-macOS.zip` (or `.dmg`), unzip, and move `CursorUsage.app` to `/Applications`.
- 下载 zip/dmg，解压后把 `CursorUsage.app` 拖入「应用程序」。

> ⚠️ The app is **ad-hoc signed** (local build, not notarized). On first launch, right-click the app → **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/CursorUsage.app` in Terminal if Gatekeeper blocks it.
> 应用为 ad-hoc 签名（未公证）。首次打开如被 Gatekeeper 拦截：右键应用 →「打开」，或终端执行 `xattr -dr com.apple.quarantine /Applications/CursorUsage.app`。

## Notes · 说明

- Unofficial tool, not affiliated with Cursor. API is reverse-engineered and may change. 非官方工具，接口可能随时变化。
- Token 只保存在本机钥匙串（或 600 权限本地文件），绝不入仓库/上传。
