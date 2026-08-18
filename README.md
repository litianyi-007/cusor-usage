# Cursor Usage — macOS 菜单栏用量插件

在 macOS System Bar(菜单栏)常驻显示 Cursor 当前计费周期用量,面板同时展示 **Cursor models** 与 **Other models** 两个池的用量,并支持在设置中保存/修改 accessToken。

---

## 一、调研结论

### 1.1 接口协议:Connect RPC v1(JSON over HTTP)

官方没有公开文档;协议与字段来自**实测抓包 + Cursor 桌面应用内嵌的 proto 定义** + 社区逆向文档([OpenUsage](https://github.com/PowerUserZ/OpenTokenUsage/blob/main/docs/providers/cursor.md))。结论:

| 项 | 值 |
|---|---|
| 端点 | `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` |
| 协议 | Connect RPC v1(JSON over HTTP,非 gRPC-web 二进制、非 REST) |
| 请求头 | `Authorization: Bearer <accessToken>`、`Content-Type: application/json`、`Connect-Protocol-Version: 1` |
| 请求体 | `{}`(proto 可选字段:`teamId`、`includePooledUsage`;个人账户用默认即可) |
| 错误格式 | 非 2xx 时返回 Connect 错误:`{"code":"unauthenticated","message":"Error",...}`(已实测 401) |

**实测**:无 token / 假 token → HTTP 401 + `{"code":"unauthenticated",...}`;真实 token → HTTP 200。请求字段名用 lowerCamelCase(Connect JSON 默认)。

### 1.2 响应解析:金额与百分比都在 `planUsage`

响应 proto 字段(取自 Cursor 应用内嵌定义,`workbench.desktop.main.js` 中 `aiserver.v1.GetCurrentPeriodUsageResponse`):

```
billingCycleStart / billingCycleEnd      unix 毫秒(JSON 中为字符串)
planUsage.totalSpend / includedSpend / bonusSpend / remaining / limit   全部为「分」,÷100 = 美元
planUsage.autoSpend? / apiSpend? / autoLimit? / apiLimit?               可选,后端未填充时为 null
planUsage.autoPercentUsed? / apiPercentUsed? / totalPercentUsed?        %
planUsage.remainingBonus? / bonusTooltip?
spendLimitUsage.{totalSpend, pooledLimit?, pooledUsed?, pooledRemaining?,
                 individualLimit?, individualUsed, individualRemaining?, limitType, ...}   按需额度
displayThreshold(基点,200=2%) / enabled / displayMessage
autoModelSelectedDisplayMessage? / namedModelSelectedDisplayMessage?
autoBucketModels[]   Auto 桶包含的模型名列表
```

### 1.3 「Cursor models vs Other models」的映射(关键)

Cursor 官方文档([usage-limits](https://cursor.com/help/models-and-usage/usage-limits.md)、[models-and-pricing](https://cursor.com/docs/models-and-pricing.md))说明每个套餐有两个用量池:

- **Cursor Models 池**:第一方模型(Cursor Grok 4.6/4.5、Composer 2.5),额度「慷慨」;
- **Other Models 池**:第三方模型(OpenAI/Anthropic/Google 等),按模型 API 价计费(Ultra 为 $400)。

GetCurrentPeriodUsage 响应中没有字面量 `cursorModels/otherModels` 字段,但 **Cursor 应用自己的代码**给出了权威映射(`firstPartyPercentUsed: planUsage.autoPercentUsed, thirdPartyPercentUsed: planUsage.apiPercentUsed`),即:

| 面板项 | 字段 | 含义 |
|---|---|---|
| **Cursor models(Auto)** | `planUsage.autoPercentUsed`(+可选 `autoSpend`) | Auto 桶(composer / cursor-grok 等 `autoBucketModels`)用量 |
| **Other models(API)** | `planUsage.apiPercentUsed`(+可选 `apiSpend`) | 指定第三方模型用量 |
| Other Models 池金额 | `limit`(额度)/ `includedSpend`(已用)/ `remaining`(剩余) | used% = `includedSpend/limit`,与服务端 `displayMessage` 一致 |
| 综合用量 | `totalPercentUsed` | 跨两个池的加权综合 % |

> 不确定点(如实说明):`autoPercentUsed`/`apiPercentUsed` 的精确分母(权重口径)后端未公开;`autoSpend/apiSpend/autoLimit/apiLimit` 为可选字段,本机实测响应中未填充。面板对缺失字段显示「—」,不影响核心展示。`includePooledUsage=true` 实测返回与默认相同(该参数可能只对团队账户生效)。

### 1.4 Token 从哪来、怎么存

- **来源(实测本机)**:`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`(SQLite)的 `cursorAuth/accessToken`。该 token 是 **JWT(HS256,含 `offline_access` scope),有效期约 2 个月**;另有 `cursorAuth/refreshToken`、`cursorAuth/cachedEmail`、`cursorAuth/stripeMembershipType` 等键。也可以从 Cursor → Settings → Accounts 复制。
- **刷新**:`POST https://api2.cursor.sh/oauth/token` `{grant_type:"refresh_token", client_id:"KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB", refresh_token}` → `{access_token, id_token, shouldLogout}`。⚠️ Auth0 刷新会轮换旧 refresh token:由插件发起刷新若不写回 vscdb,会让 Cursor 本体掉登录。**本插件不做自动刷新**,而是提供「从 Cursor 自动读取」——每次读取 Cursor 当前有效 token(只读,零副作用);token 过期时在 Cursor 重新登录即可。
- **存放**:macOS Keychain(generic password,service `ai-goods.cursor-usage`)优先,兜底文件 `~/Library/Application Support/CursorUsage/token.txt`(0600)。**任何 token 都不会写入项目仓库**(仓库内无 token 存储逻辑,`.gitignore` 排除相关文件)。

---

## 二、实现方案

- **技术栈**:原生 Swift + AppKit/SwiftUI,零第三方依赖,仅用系统自带框架(Xcode 工具链)。菜单栏用 `NSStatusItem`,用量面板用无边框 `NSPanel`(SwiftUI 内容),设置用独立小窗口。
- **文件结构**:

```
cusor-usage/
├── Makefile                 # build / bundle / run / test-dump / install / clean
├── Info.plist               # LSUIElement=true(不占 Dock)
├── .gitignore
├── README.md
└── Sources/
    ├── main.swift           # AppDelegate、状态栏图标、面板/设置窗口、--dump 诊断模式
    ├── UsageModels.swift    # GetCurrentPeriodUsage / GetPlanInfo 响应模型(注释含字段来源)
    ├── UsageClient.swift    # Connect RPC v1 客户端(POST + 三个请求头 + 错误解析)
    ├── TokenStore.swift     # Keychain + 兜底文件 + 从 Cursor vscdb 只读
    ├── UsageStore.swift     # 全局状态:拉取/缓存/定时刷新(5 分钟)
    ├── UsagePanelView.swift # 面板 UI:两个池的用量 + 金额 + 按需额度 + 服务端消息
    └── SettingsView.swift   # 设置窗口:粘贴/保存 token、一键从 Cursor 读取
```

- **交互**:状态栏图标左键 → 弹出用量面板;右键 → 菜单(刷新 / 设置 Token / 退出);面板内含「刷新」「设置 Token…」按钮;面板打开时若数据超过 60 秒自动刷新。

---

## 三、本地启动与验证

前置:macOS 13+,已装 Xcode 命令行工具;本机已登录 Cursor(用于自动读取 token)。

```bash
cd /Users/litianyi/Documents/Code/_ai-goods/cusor-usage

# 1) 编译
make build            # → build/CursorUsage(可执行文件)

# 2) 无 GUI 验证:真实拉取当前周期用量并打印解析结果(token 从 Cursor 本地读取)
make test-dump
# 或
./build/CursorUsage --dump --from-cursor

# 3) 打包 .app 并启动菜单栏常驻
make run              # 或 make bundle 后 open build/CursorUsage.app

# 4) 可选:安装到 /Applications
make install
```

验证要点:

1. `test-dump` 应打印计费周期、套餐、Other Models 池金额(已用/额度/剩余)、Cursor models / Other models 百分比、服务端消息等;
2. 状态栏出现柱状图图标;左键弹出面板,能看到两个池的用量与进度条;
3. 右键 → 设置 Token…:粘贴 token 保存到钥匙串,或点「从 Cursor 自动读取」;保存后面板自动刷新;
4. 断网 / token 失效时面板显示明确错误(如 HTTP 401 → 提示更新 token)。

---

## 四、已知限制

- `autoSpend/apiSpend` 等可选字段当前账户未返回,金额列显示「—」;
- 官方文档([usage-limits](https://cursor.com/help/models-and-usage/usage-limits.md))可能随版本变化;接口字段以 Cursor 应用内嵌 proto 为准,应用升级后字段可能增删;
- 不做 token 自动刷新(原因见 1.4,避免破坏 Cursor 本体会话)。
