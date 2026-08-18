# Cursor Usage — macOS 菜单栏用量插件

在 macOS System Bar(菜单栏)常驻显示 Cursor 当前计费周期用量,点击图标弹出面板,
同时展示 **Cursor models** 与 **Other models** 两个用量池;设置入口可保存 / 修改 accessToken
(存 macOS 钥匙串,绝不入库)。

---

## 一、调研结论

### 1.1 接口协议:Connect RPC v1(JSON over HTTP)

官方**没有**公开文档(公开的是 Enterprise 级 Admin/Analytics API,与本接口无关)。协议结论来自:
本机**实机请求验证**(2026-08-19,HTTP 200)+ 社区逆向文档
([OpenTokenUsage / Cursor provider](https://github.com/PowerUserZ/OpenTokenUsage/blob/main/docs/providers/cursor.md))
+ [Cursor-Usage-Status 扩展源码](https://github.com/ClearMeasureLabs/Cursor-Usage-Status)。

| 项 | 值 |
|---|---|
| 端点 | `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` |
| 协议 | **Connect RPC v1(JSON over HTTP)** —— 不是 gRPC-web 二进制帧,不是 REST;普通 JSON POST 即可 |
| 请求头 | `Authorization: Bearer <accessToken>`(必需)<br>`Content-Type: application/json`(必需)<br>`Connect-Protocol-Version: 1`(必需) |
| 请求体 | `{}`(proto 可选字段 teamId / includePooledUsage 等,个人账户默认即可) |
| 错误 | 非 2xx 返回 Connect 错误 JSON,如 401:`{"code":"unauthenticated","message":"Error",...}` |

同一服务(同鉴权方式)下还有:
`GetPlanInfo`(套餐名/价格)、`GetFilteredUsageEvents`(逐条事件,分页 `{"page":N,"pageSize":M}`)、
`GetAggregatedUsageEvents`(按模型聚合,`{}` 即可)。
实测 `GET /api/usage/summary` 在 api2.cursor.sh 上 **404**(那是 cursor.com 网页端、Cookie 鉴权的接口,不在本工具范围)。

### 1.2 响应解析:金额与百分比都在 `planUsage`

实机响应(已核对字段,金额单位**分** cents,÷100 = 美元;时间戳为 unix 毫秒字符串):

```jsonc
{
  "billingCycleStart": "1786904477000",  "billingCycleEnd": "1789582877000",
  "planUsage": {
    "totalSpend": 18883,  "includedSpend": 18883,  "remaining": 21117,  "limit": 40000,
    "remainingBonus": false,
    "autoPercentUsed": 2.7715,   // Cursor models 池 %
    "apiPercentUsed": 26.68,     // Other models 池 %
    "totalPercentUsed": 7.5532   // 综合 %
  },
  "spendLimitUsage": { "limitType": "user" },        // 按需额度;本账户未启用,无金额字段
  "displayThreshold": 200, "enabled": true,
  "displayMessage": "You've used 47% of your included usage",
  "autoModelSelectedDisplayMessage": "...", "namedModelSelectedDisplayMessage": "...",
  "autoBucketModels": ["default","composer-2.5","cursor-grok-4.5", ...]   // Cursor 第一方模型名单
}
```

### 1.3 「Cursor models vs Other models」映射(关键)

Cursor 界面/文档把用量分成两个池。`GetCurrentPeriodUsage` 响应里没有字面量 `cursorModels/otherModels`
字段,但权威映射来自 Cursor 应用自身代码(`firstPartyPercentUsed = planUsage.autoPercentUsed`,
`thirdPartyPercentUsed = planUsage.apiPercentUsed`),与 [omarchy agent-usage-cursor 收集器](https://github.com/basecamp/omarchy/pull/7087) 一致:

| 面板项 | 字段 | 含义 |
|---|---|---|
| **Cursor models** | `planUsage.autoPercentUsed` | Auto 桶(= `autoBucketModels` 名单)用量 % |
| **Other models** | `planUsage.apiPercentUsed` | 指定第三方模型(API)用量 % |
| Other 池金额 | `limit`(额度)/ `includedSpend`(已用)/ `remaining`(剩余) | 与 `displayMessage` 口径一致 |
| 综合用量 | `totalPercentUsed` | 跨池加权综合 % |

**两个池的美元拆分**:接口可选字段 `autoSpend/apiSpend` 本机实测**未填充**(null),因此本工具用
`GetAggregatedUsageEvents` 的 `totalCents` 按 `autoBucketModels` 归属求和得到。
**验证**:本机实测 aggregations 的 totalCents 之和 = 18882.90 分 ≈ `planUsage.totalSpend` 18883 分(误差 <0.01 分)。
归属规则:名单精确命中;Cursor 第一方模型另有前缀启发式(`cursor-` / `composer` / `vega` / `grok`),
与实测模型名(cursor-grok-4.6-*、composer-* 等)一致;第三方(claude-* / gpt-*)归 Other 池。

> 不确定点(如实标注):
> - `autoPercentUsed` / `apiPercentUsed` 的分母(权重口径)未公开,故 `totalPercentUsed` ≠ 两者之和
>   (实测 7.55% vs 2.77% + 26.68%);% 直接透传服务端值。
> - `autoSpend/apiSpend/autoLimit/apiLimit` 为可选字段,本账户未返回;面板优先用接口字段,缺失时用聚合拆分。
> - `GetFilteredUsageEvents` 已实测可用(71 条事件),面板当前用聚合接口做池拆分,未做逐条明细页。
> - 协议为「Connect RPC v1 JSON」;同一端点理论上也接受 gRPC-web 二进制帧,但 JSON 帧已足够且更简单。

### 1.4 Token 从哪来、如何安全存放

- **来源(本机实测)**:`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`(SQLite)
  中键 `cursorAuth/accessToken`。它是 **JWT**(HS256,scope 含 `offline_access`),本机实测有效期约 2 个月;
  同库还有 `cursorAuth/refreshToken`、`cursorAuth/stripeMembershipType` 等。也可在 Cursor → Settings → Accounts 复制。
- **刷新机制(调研到,但故意不做)**:`POST https://api2.cursor.sh/oauth/token`
  `{"grant_type":"refresh_token","client_id":"KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB","refresh_token":"..."}`
  → `{"access_token","id_token","shouldLogout"}`。⚠️ Auth0 刷新会**轮换**旧 refresh token:插件若自动刷新
  且不写回 vscdb,会让 Cursor 本体掉登录。因此本插件**只读** Cursor 的 token,不触发刷新;
  token 过期时在 Cursor 里重新登录即可,再点「从 Cursor 自动读取」。
- **存放(安全)**:macOS **Keychain**(generic password,service `ai-goods.cursor-usage`)优先;
  兜底文件 `~/Library/Application Support/CursorUsage/token.txt`(0600 权限,仅 Keychain 不可用时)。
  **accessToken 绝不写入项目仓库**(仓库无任何 token 存储逻辑,`.gitignore` 已排除)。

---

## 二、实现方案

- **技术栈**:原生 Swift + AppKit/SwiftUI,**零第三方依赖**,仅系统框架(Xcode 工具链)。
  菜单栏用 `NSStatusItem`,用量面板用无边框 `NSPanel`(SwiftUI 内容),设置用独立窗口。
  编译产物做 **ad-hoc codesign**(否则较新 macOS 上 Keychain 返回 errSecMissingEntitlement)。
- **交互**:状态栏图标(含综合用量百分比标题)左键 → 弹出用量面板;右键 → 菜单
  (刷新用量 / 设置 Token… / 退出);面板含「刷新」「设置 Token…」按钮;面板打开时数据超 60 秒自动刷新;
  后台每 5 分钟自动刷新;`LSUIElement=true` 不占 Dock。
- **文件结构**:

```
cusor-usage/
├── Makefile                 # build / bundle / run / test-dump / dump-json / smoke-test / test-keychain / install / clean
├── Info.plist               # LSUIElement=true(菜单栏常驻,不占 Dock)
├── .gitignore               # 排除 build/ 与 token 文件
├── README.md                # 本文档
└── Sources/
    ├── main.swift           # AppDelegate、状态栏图标+百分比标题、面板/设置窗口、--dump/--dump-json/--keychain-test/--smoke-test
    ├── UsageModels.swift    # GetCurrentPeriodUsage / GetPlanInfo / GetAggregatedUsageEvents 响应模型(注释含字段来源)
    ├── UsageClient.swift    # Connect RPC v1 客户端(POST + 三个必需请求头 + 错误解析)
    ├── TokenStore.swift     # Keychain + 兜底 0600 文件 + 从 Cursor vscdb 只读 + JWT 有效期解析
    ├── UsageStore.swift     # 全局状态:拉取/缓存/定时刷新 + 两个池的美元拆分(aggregations × autoBucketModels)
    ├── UsagePanelView.swift # 面板 UI:两个池用量/金额/进度条、Top 模型花费、按需额度、服务端消息
    └── SettingsView.swift   # 设置窗口:粘贴/保存 token、从 Cursor 一键读取、token 有效期展示
```

---

## 三、可运行实现(交付内容)

- 菜单栏常驻程序 `build/CursorUsage`(或打包 `build/CursorUsage.app`);
- 面板同时展示 **Cursor models(Auto)** 与 **Other models(API)** 的百分比 + 美元花费,
  以及 Other 池金额(已用/额度/剩余)、综合用量、Top 5 模型花费、按需额度、服务端消息、计费周期;
- 设置入口:右键菜单 / 面板按钮「设置 Token…」,支持粘贴保存到钥匙串、从 Cursor 本地自动读取、显示 token 有效期;
- 无 GUI 验证模式:`--dump`、`--dump-json`、`--keychain-test`、`--smoke-test`。

---

## 四、本地启动与验证

前置:macOS 13+,已装 Xcode 命令行工具;本机已登录 Cursor(用于自动读取 token)。

```bash
cd /Users/litianyi/Documents/Code/_ai-goods/cusor-usage

# 1) 编译(自动 ad-hoc 签名)
make build            # → build/CursorUsage

# 2) 无 GUI 验证:真实拉取当前周期用量并打印解析结果(token 从 Cursor 本地只读)
make test-dump
# 或原始 JSON + 池拆分:
make dump-json

# 3) 打包 .app 并启动菜单栏常驻
make run              # open build/CursorUsage.app

# 4) 可选:安装到 /Applications
make install
```

验证要点:

1. `make test-dump` 应打印计费周期、套餐、Other 池金额、Cursor models / Other models 百分比、
   美元拆分(合计应等于 totalSpend)与 Top 模型花费;
2. 状态栏出现柱状图图标(右侧带综合用量百分比);左键弹出面板,可见两个池的用量与进度条;
3. 右键 → 设置 Token…:粘贴 token 保存到钥匙串,或点「从 Cursor 自动读取」;保存后面板自动刷新;
4. 断网 / token 失效时面板显示明确错误(HTTP 401 → 提示更新 token);
5. `make smoke-test` / `make test-keychain` 可分别自检 GUI 启动与钥匙串存取。

---

## 五、已知限制

- `autoPercentUsed/apiPercentUsed` 的分母权重口径未公开(见 1.3),% 为服务端原值透传;
- `autoSpend/apiSpend` 可选字段当前账户未返回,池金额为聚合拆分(误差与 totalSpend < 0.01 分,已实测);
- 不做 token 自动刷新(原因见 1.4,避免轮换 Cursor 本体的 refresh token);
- 接口为未公开协议,字段/端点可能随 Cursor 版本变化;以实机响应为准,应用升级后需回归验证。
