# CursorUsage — Product Description · 产品说明

> 双语产品描述：可用于应用商店/发布页/项目简介。Bilingual listing copy.
> CursorUsage is an unofficial tool and is not affiliated with, endorsed by, or connected to Cursor (Anysphere, Inc.).
> 本工具为个人开发，与 Cursor / Anysphere 无任何隶属或背书关系。

---

## English

**Name:** CursorUsage
**Tagline:** Your Cursor usage, one click away in the macOS menu bar.

**Short description (one-liner):**
A lightweight, native macOS menu bar app that shows your Cursor plan usage in real time — Cursor Models and Other Models pools, in dollars and percent.

**What it does:**
CursorUsage lives quietly in your menu bar and polls Cursor's billing-cycle usage on demand. Click the icon and a compact panel opens with:

- **Cursor Models** usage — percent (`autoPercentUsed`) and exact dollar spend this cycle (derived per-model from Cursor's usage aggregation endpoint; verified to sum exactly to `planUsage.totalSpend`).
- **Other Models** usage — same, for third-party models (Claude / GPT, etc.).
- **Included total** — used / limit / remaining allowance in USD, plus combined percent.
- **Top models by spend**, billing cycle dates with a "resets in N days" countdown, and on-demand (pay-as-you-go) budget when present.
- **Token settings** — paste an access token and save it to the macOS Keychain, or simply let the app auto-read Cursor's local login state. The token never leaves your machine and is never stored in the repository.

**Why you'd want it:**
Cursor's in-app usage page is a few clicks away; CursorUsage puts the numbers in the menu bar — refreshed automatically (on open, every 60 s while open, every 5 min in background) — so you can spot runaway spend before your monthly allowance runs out.

**Tech highlights:**
Pure Swift (AppKit + SwiftUI), zero third-party dependencies, single lightweight binary, `LSUIElement` menu-bar-only app (no Dock icon), Connect RPC v1 (JSON over HTTP) client, Keychain-backed token storage with a 600-perm file fallback outside the repo.

**Target users:** Cursor Pro / Pro Plus / Ultra (usage-based) users on macOS who want a quick, always-visible view of their included usage.

**System requirements:** macOS 12+, Xcode command-line tools for building from source.

**Privacy:** No telemetry, no analytics, no network calls except to Cursor's own `api2.cursor.sh` endpoints with your token.

---

## 中文

**名称：** CursorUsage
**标语：** 菜单栏一键查看 Cursor 用量。

**一句话简介：**
原生 macOS 菜单栏小工具，实时展示 Cursor 套餐用量——Cursor Models 与 Other Models 两个池，金额与百分比一目了然。

**功能说明：**
CursorUsage 常驻菜单栏，按需拉取当前计费周期的用量。点击图标弹出紧凑面板：

- **Cursor Models 用量**——本周期百分比（`autoPercentUsed`）与精确美元花费（按模型从 Cursor 用量聚合接口归属求和，实测合计与 `planUsage.totalSpend` 分毫不差）。
- **Other Models 用量**——同样的口径，针对第三方模型（Claude / GPT 等）。
- **合计用量**——已用 / 限额 / 剩余美元金额 + 综合百分比。
- **Top 模型**（按花费）、计费周期起止与“N 天后重置”倒计时、按量付费预算（有值时）。
- **Token 设置**——粘贴 accessToken 保存到 macOS 钥匙串，或直接自动读取 Cursor 本地登录态。token 不离开本机、绝不写入仓库。

**适用场景：**
Cursor 应用内的用量页需要多步跳转；CursorUsage 把数字放到菜单栏——自动刷新（打开即拉取、打开期间每 60 秒、后台每 5 分钟）——让你在月额度耗尽前及时发现异常消耗。

**技术亮点：**
纯 Swift（AppKit + SwiftUI）零第三方依赖、单文件轻量二进制、`LSUIElement` 纯菜单栏应用（无 Dock 图标）、Connect RPC v1（JSON over HTTP）客户端、钥匙串存储 token 并提供仓库外 600 权限文件兜底。

**目标用户：** macOS 上的 Cursor Pro / Pro Plus / Ultra（按量计费）用户，希望随时可见自己的套餐用量。

**系统要求：** macOS 12+，源码构建需要 Xcode 命令行工具。

**隐私：** 无遥测、无统计、除使用你的 token 调用 Cursor 官方 `api2.cursor.sh` 端点外不做任何网络请求。
