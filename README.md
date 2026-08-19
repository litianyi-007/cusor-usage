# CursorUsage — macOS 菜单栏 Cursor 用量查看器

原生 Swift 实现的 macOS 菜单栏常驻小程序：点击菜单栏图标弹出用量面板，实时拉取
`https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`，
同时展示 **Cursor Models**（auto 池）与 **Other Models**（api 池）两个用量池。
内置 token 设置入口（保存到 macOS 钥匙串）。

> ⚠️ 非官方工具，接口为逆向调研所得（见 [RESEARCH.md](RESEARCH.md)），字段可能随 Cursor 版本变化。
> 本项目不隶属于 Cursor，不收集任何数据，token 只存本机。

## 功能

- 菜单栏常驻（`LSUIElement`，无 Dock 图标），图标旁实时显示合计用量百分比（如 `15%`）
- 用量面板：
  - **Cursor Models**：`planUsage.autoPercentUsed` + **美元花费**（`GetAggregatedUsageEvents` 按 `autoBucketModels` 归属求和，实测合计 == `totalSpend`）
  - **Other Models**：`planUsage.apiPercentUsed` + 美元花费
  - **Included total**：`planUsage.totalPercentUsed` + 已用/限额/剩余金额（美分）
  - **Top 模型**（按花费前 3）、计费周期起止与“N 天后重置”、按量付费额度（有值时）
- 刷新：打开面板即拉最新，面板打开期间每 60s 自动刷新，后台每 5min 刷新
- 设置（面板内 ⚙️）：
  - 粘贴 accessToken → 保存到 macOS 钥匙串（加密）
  - 自动读取 Cursor 本地登录态（默认，无需手动维护）
  - 清除手动 token

## 环境要求

- macOS 12+（开发机为 macOS 26.6）
- Xcode 命令行工具（`swiftc`，用于本地构建）
- 本机已登录 Cursor 桌面端（自动读取模式需要）；或手动粘贴 token

## 构建 / 启动

```bash
cd /Users/litianyi/Documents/Code/_ai-goods/cusor-usage

make build     # 仅编译二进制 build/CursorUsage
make selfcheck # 无头自测：真实 token 解析 + 真实 API + 钥匙串/文件存取
./run.sh       # 构建 + 打包 .app + 启动（菜单栏出现图标）
```

退出：点面板底部电源键，或 `pkill CursorUsage`。

## token 从哪来、存哪里

| 来源 | 说明 |
|---|---|
| 自动读取（默认） | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` 的 `cursorAuth/accessToken`（JWT，约 2 个月有效），**只读打开，不回写** |
| 手动粘贴 | 设置里粘贴 → **macOS 钥匙串**（`com.cursorusage.menubar`，`kSecAttrAccessibleAfterFirstUnlock`）；钥匙串不可用时兜底写入 `~/Library/Application Support/CursorUsage/config.json`（chmod 600，仓库外） |

- token **绝不写入仓库**（`.gitignore` 已排除 `build/`、`token.txt`、`*.token`；配置在仓库外路径）
- 代码不打印 token；请求仅走 HTTPS

## 验证步骤

1. **无头自测**（推荐先跑）：

   ```bash
   make selfcheck
   ```

   期望输出（本机实测结果）：`token 来源：Cursor 本地自动读取`、`GetCurrentPeriodUsage HTTP 200`、
   `Cursor Models (autoPercentUsed): …%`、`Other Models (apiPercentUsed): …%`、
   `GetAggregatedUsageEvents: … totalCents 合计 $… (planUsage.totalSpend $…, 误差 $…)`、
   `池拆分: Cursor Models $… / Other Models $…`、`钥匙串 写入/读取/清除 正常`、`exit=0`。
   任何 `[FAIL]` 即有问题。

2. **界面验证**：`./run.sh` → 菜单栏出现图标（含百分比）→ 点击弹出面板：
   - 能看到两条用量条（Cursor Models / Other Models）+ 合计与金额、周期
   - ⚙️ 设置：粘贴 token → 保存 → 面板立即刷新；或直接点“自动读取 Cursor 本地”
   - 点其他位置面板收起；再点图标重新弹出并拉取最新

## 常见问题

- **提示“未找到 accessToken”**：本机没登录 Cursor，或 state.vscdb 路径不同；去 ⚙️ 手动粘贴 token。
- **HTTP 401**：token 过期/失效；重新“自动读取”或粘贴新 token。
- **面板显示“响应中没有 planUsage”**：账户形态与 Ultra 不同（如旧版 request-based 账户），按缺失字段降级展示。
- **钥匙串保存失败**：极少数受限环境；会自动回退到 600 权限本地文件。

## 目录结构

```
Sources/main.swift       入口（--selfcheck / GUI）
Sources/AppDelegate.swift 状态栏图标 + popover + 定时刷新
Sources/CursorAPI.swift  Connect JSON 客户端 + Codable 模型
Sources/TokenStore.swift 钥匙串 / 600 文件 / Cursor 本地只读
Sources/PanelModel.swift 面板状态机（@MainActor）
Sources/UsagePanel.swift SwiftUI 面板（双池用量条 + 设置区）
Sources/Info.plist        .app 打包配置（LSUIElement）
Makefile / run.sh         构建、自测、启动
```
