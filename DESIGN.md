# 实现方案

## 技术选型：原生 Swift（AppKit + SwiftUI），零第三方依赖

| 备选 | 结论 |
|---|---|
| **原生 Swift**（NSStatusItem + NSPopover + SwiftUI 面板） | ✅ 采用：单二进制、无运行时依赖、系统原生菜单栏体验、钥匙串/SQLite 直接走系统框架（Security / SQLite3），swiftc 直接编译（本机已装 Xcode，已验证可编译） |
| Electron / Tauri | 太重，几百 MB 运行时，为一个小面板不值 |
| Python + rumps | 依赖 PyObjC 安装，且 rumps 只有菜单下拉、无原生 popover 面板体验 |
| Swift Package / Xcode 工程 | 不必要；单目录多文件 + swiftc 足够 |

目标系统：macOS 12+（本机 26.6）。应用以 `LSUIElement` 打包（无 Dock 图标、纯菜单栏常驻），ad-hoc 签名本地运行。

## 文件结构

```
cursor-usage/
├── RESEARCH.md              调研结论（接口协议/响应解析/token 存放）
├── DESIGN.md                本文件
├── README.md                构建/启动/验证说明
├── Makefile                 build / app / selfcheck / run 目标
├── run.sh                   一键：构建 + 打包 + open
├── Sources/
│   ├── main.swift           入口：--selfcheck 无头自测；否则启动 NSApplication
│   ├── SelfCheck.swift      无头自测：token 解析 → 真实 API → 钥匙串/文件存取
│   ├── AppDelegate.swift    状态栏图标、popover 开关、后台定时刷新
│   ├── CursorAPI.swift      Connect JSON 客户端 + Codable 模型（GetCurrentPeriodUsage / GetPlanInfo）
│   ├── TokenStore.swift     钥匙串(首选) + 600 配置文件(兜底) + Cursor 本地只读自动读取
│   ├── PanelModel.swift     面板状态机（@MainActor ObservableObject）
│   └── UsagePanel.swift     SwiftUI：用量面板（Cursor/Other 双池 + 合计 + 周期 + 设置区）
└── build/                   （生成物，已 gitignore）
```

## 关键设计

### 数据流

```
点击状态栏图标
  → popover 弹出，触发 refresh()
  → TokenStore.resolveToken() 依次尝试：
      1) 钥匙串手动 token（设置里保存的，优先级最高）
      2) 本地配置文件兜底 token
      3) Cursor 本地 state.vscdb 只读读取 cursorAuth/accessToken（默认路径，自动模式）
  → CursorAPI.fetchPeriodUsage(token)：
      POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage
      headers: Authorization: Bearer … / Content-Type: application/json
               / Connect-Protocol-Version: 1
      body: {}
  → 解析 PeriodUsage（Codable）
  → 面板渲染：Cursor Models = autoPercentUsed，Other Models = apiPercentUsed，合计 = totalPercentUsed
  → 状态栏标题同步显示合计百分比（如 “15%”）
```

自动刷新：面板打开期间每 60s 刷新一次；后台每 5min 刷新一次（更新状态栏百分比）。错误时面板显示错误 + 引导去设置；状态栏回到纯图标。

### 面板内容（SwiftUI，宽 ~330pt）

- **头部**：图标 + “Cursor 用量” + 套餐/邮箱（GetPlanInfo + 本地 cachedEmail）
- **用量条 ×3**：
  - `Cursor Models` — autoPercentUsed（绿色→橙→红按阈值变色）
  - `Other Models` — apiPercentUsed
  - `Included total` — totalPercentUsed + 金额 `已用 $X / 限额 $Y / 剩余 $Z`（美分 ÷ 100）
- **周期**：`2026-08-16 → 2026-09-19 · 23 天后重置`
- **按量付费**（有值时）：pooled / individual used·limit
- **底部**：刷新按钮 · 更新时间 · 设置(⚙️) · 退出
- **设置区**（面板内展开，不用独立 sheet，避免 transient popover 与 sheet 冲突）：
  - SecureField 粘贴 token
  - 保存到钥匙串 / 自动读取 Cursor 本地 / 清除
  - 显示当前来源与提示文案（token 只存钥匙串或 600 权限文件，绝不入仓库）

### 安全设计

- token 首选存 **macOS 钥匙串**（`kSecAttrAccessibleAfterFirstUnlock`，系统加密）
- 兜底 `~/Library/Application Support/CursorUsage/config.json`（chmod 600，仓库外）
- 自动读取 Cursor 本地状态库：`SQLITE_OPEN_READONLY` + `busy_timeout`，只读不回写
- 全代码不打印 token；仓库 `.gitignore` 覆盖 `build/`、`token.txt`、`*.token`

### 验证策略

- `make selfcheck`（`--selfcheck` 无头模式）：真实调用本机 token + API，逐项打印 `[ok]/[warn]/[FAIL]`，可用于 CI/终端验证
- `make run`：打包 .app 并 `open`，肉眼验证菜单栏入口与面板
