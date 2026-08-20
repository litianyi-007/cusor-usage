# 调研结论：Cursor 用量接口与 token

> 调研时间：2026-08（本机实测验证）。Cursor 不提供该接口的官方公开文档，以下结论基于：
> 1. 本机真实调用（本机已登录 Cursor Ultra 账户，token 取自本地 Cursor 状态库）
> 2. 两个独立开源实现：[OpenTokenUsage](https://github.com/PowerUserZ/OpenTokenUsage/blob/main/docs/providers/cursor.md)、[ClearMeasureLabs/cursor-usage-status](https://github.com/clearmeasurelabs/cursor-usage-status)、[basecamp/omarchy PR #6604](https://github.com/basecamp/omarchy/pull/6604)（生产 collector）
> 3. [Cursor 官方 usage-limits 帮助文档](https://cursor.com/help/models-and-usage/usage-limits.md)：确认账户内存在两个独立的月用量池

---

## 1. 接口协议：Connect RPC v1（JSON over HTTP），不是 gRPC-web

| 项 | 值 |
|---|---|
| 协议 | **Connect RPC v1，JSON 传输**（不是 gRPC-web 二进制、不是 protobuf） |
| 方法/路径 | `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` |
| 请求体 | `{}`（空对象） |
| 鉴权 | `Authorization: Bearer <accessToken>` |

### 请求头（实测有效）

```
Authorization: Bearer <accessToken>
Content-Type: application/json
Connect-Protocol-Version: 1
Accept: application/json
User-Agent: cursorusage-menubar/0.1   (可选)
```

`Connect-Protocol-Version: 1` 是关键：它告诉服务端走 Connect JSON 协议而非二进制。不带它可能返回协议不匹配错误。

### 本机实测响应（Ultra 账户，字段即真实形态）

```jsonc
{
  "billingCycleStart": "1786904477000",        // 周期开始，unix 毫秒（字符串）
  "billingCycleEnd": "1789582877000",          // 周期结束，unix 毫秒（字符串）
  "planUsage": {
    "totalSpend": 19876,                       // 已用总额（美分，= includedSpend + bonusSpend）
    "includedSpend": 19876,                    // 计入套餐限额的用量（美分）
    "remaining": 20124,                        // 剩余（美分 = limit - includedSpend）
    "limit": 40000,                            // 套餐包含额度（美分，Ultra = $400）
    "remainingBonus": false,
    "bonusTooltip": "We work with model providers ...",
    "autoPercentUsed": 2.9444999999999997,     // ★ Cursor Models 池用量 %（池额度 ≈ $2000）
    "apiPercentUsed": 27.974,                  // ★ Other Models 池用量 %（池额度 ≈ $500）
    "totalPercentUsed": 7.9504                 // 总池用量 %（auto+API 池 ≈ $2500，含 bonus；非买断额度口径）
  },
  "spendLimitUsage": { "limitType": "user" },  // 按量付费预算（有值时才有 pooled/individual 字段）
  "displayThreshold": 200,                     // 阈值（万分之几，200 = 2%，推断用于告警）
  "enabled": true,
  "displayMessage": "You've used 50% of your included usage",
  "autoModelSelectedDisplayMessage": "You've used 8% of your included total usage",
  "namedModelSelectedDisplayMessage": "You've used 28% of your included API usage",
  "autoBucketModels": ["default","composer-1.5","composer-2","composer-2.5","vega","vega-medium", "...", "cursor-grok-4.5", "grok-4.5", "..."]  // 自动模式 = Cursor 自家模型清单
}
```

`planInfo`（辅助端点 `POST .../GetPlanInfo`，同样的三个头）实测返回：

```json
{ "planInfo": { "planName": "Ultra", "includedAmountCents": 40000, "price": "$200/mo",
                "billingCycleEnd": "1789582877000", "planOwner": "PLAN_OWNER_STRIPE" } }
```

### Cursor models vs Other models 的字段拆分（核心结论）

接口在 `GetCurrentPeriodUsage` 里给出的拆分是**隐式百分比**：

| 面板要展示的池 | 字段 | 语义依据 |
|---|---|---|
| **Cursor Models**（Cursor 自家模型：composer / vega / cursor-grok 等） | `planUsage.autoPercentUsed` | 自动模式（Auto）路由到 Cursor 自家模型池；官方文档确认 “Cursor Models: Cursor Grok 4.6/4.5、Composer 2.5”；实测池额度 ≈ **$2000**（花费 ÷ 百分比整除） |
| **Other Models**（第三方模型，按模型厂商价格计费） | `planUsage.apiPercentUsed` | 命名模型/API 模式走第三方池；官方文档 “Other Models: Third-party models, charged at model provider prices”；实测池额度 ≈ **$500** |
| **Included usage（买断额度消耗）** | `planUsage.includedSpend / planUsage.limit` | 官方 `displayMessage` 口径（“You've used 92% of your included usage”）；`limit` 即套餐买断额度（Ultra = $400） |
| **总池用量（含 bonus，参考）** | `planUsage.totalPercentUsed` | 两池花费合计 ÷ 总池（auto 池 + API 池 ≈ **$2500**，超出买断额度的部分为模型厂商赠送的 bonus 免费额度）；**不是**「$400 买断额度」的口径，勿与金额并排展示 |

- 交叉验证 1（omarchy 生产 collector）：`autoPercentUsed → label "Cursor Models"`，`apiPercentUsed → label "Other Models"`。
- 交叉验证 2（接口自述消息）：`autoModelSelectedDisplayMessage` 对应总池用量（15%，即 totalPercentUsed 口径），`namedModelSelectedDisplayMessage` 对应 “included API usage”（45%，即 apiPercentUsed 口径），`displayMessage` 对应买断额度（92%，includedSpend/limit 口径）。
- 官方文档口径：Pro/Pro Plus/Ultra 都是 “x 美元 API agent usage + 第一方模型池”，两池语义一致。

### 两个池的美元拆分：来自 `GetAggregatedUsageEvents`（重要补充）

`planUsage` 里没有 per-pool 美元字段（`autoSpend`/`apiSpend`/`autoLimit`/`apiLimit` 实测缺失）。**per-pool 美元拆分通过聚合端点拿到**：

```
POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents
（同样的三个请求头，body {}）
```

响应（本机实测）：

```jsonc
{
  "aggregations": [
    { "modelIntent": "claude-fable-5-thinking-max", "totalCents": 12094.52587, "tier": 1, "inputTokens": "...", ... },
    { "modelIntent": "cursor-grok-4.6-xhigh-fast",  "totalCents": 5556.84965,  "tier": 2, ... },
    ...
  ],
  "totalInputTokens": "6410291",
  "totalOutputTokens": "1295056",
  "totalCostCents": ...
}
```

**归属规则（权威标准 = `tier` 字段，2026-08 实测升级）**：`tier == 2` → Cursor Models 池（auto 池），`tier == 1` → Other Models 池（API 池）。数学验证：tier2 花费和 ÷ `autoPercentUsed` = $2000 整除、tier1 花费和 ÷ `apiPercentUsed` = $500 整除，与两池额度反推完全吻合。**`autoBucketModels` 清单并不完整**（实测不含 cursor-grok-4.6 系列，但其 tier=2 属 auto 池），只作 tier 缺失时的兜底，名称前缀（`cursor-`/`composer`/`vega`/`grok`）作最后兜底。

**一致性验证（本机实测）**：`aggregations[].totalCents` 之和 = $198.77 ≈ `planUsage.totalSpend` = $198.76（误差 $0.01，四舍五入）。池拆分结果：Cursor Models **$58.89** / Other Models **$139.87**（tier 分组结果一致）。

**池额度反推（推断，非接口直给）**：`池花费 ÷ 池百分比` 得出
`Cursor Models 池 ≈ $2000`（$58.89 ÷ 2.9445%）、`Other Models 池 ≈ $500`（$139.87 ÷ 27.974%），两个值都整除得很干净，且 `totalPercentUsed` 分母 = $2500 时三者一致（19876/250000 = 7.95%）。因此 `autoPercentUsed`/`apiPercentUsed` 的分母应是各自池额度而非 `planUsage.limit`（$400，那是 displayMessage “50%” 的口径）。

### 金额口径小结

| 数据 | 来源 | 单位 |
|---|---|---|
| 每池美元花费 | `GetAggregatedUsageEvents.aggregations[].totalCents` 按 `tier` 归属求和 | 分 |
| 每池百分比 | `planUsage.autoPercentUsed` / `apiPercentUsed` | % |
| Included 美元（已用/限额/剩余） | `planUsage.includedSpend/limit/remaining` | 分 |
| Included 百分比（面板主展示） | `includedSpend / limit × 100`（官方 displayMessage 口径，如 92%） | % |
| 总池用量（含 bonus，仅参考） | `planUsage.totalPercentUsed`（分母 ≈ $2500） | % |

### 其他探测过的端点（本机实测）

| 端点 | 结果 | 备注 |
|---|---|---|
| `POST .../GetPlanInfo` | 200，planName/price/includedAmountCents | 用于显示套餐名 |
| `POST .../GetAggregatedUsageEvents` | 200，per-model `totalCents` 聚合 | **两个池美元拆分的来源** |
| `POST .../GetUsageLimitPolicyStatus` | 200，`{canConfigureSpendLimit:true}` | 按量付费开关 |
| `POST .../GetUsageLimitStatusAndActiveGrants` | 200，on-demand 限额建议 | 按量付费相关 |
| `GET https://api2.cursor.sh/auth/usage` | 200，`{"gpt-4":{"numRequests":0,...},"startOfMonth":...}` | legacy request-based 形态，本账户基本为空（Enterprise 账户主要用这个） |
| `GET https://api2.cursor.sh/api/usage/summary` | 404 | 不存在 |

---

## 2. token 从哪来

### 主来源：Cursor 桌面端本地状态库（SQLite）

```
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
（Windows: %APPDATA%\Cursor\... ; Linux: ~/.config/Cursor/...）
```

表 `ItemTable`，键值对：

| key | 内容 |
|---|---|
| `cursorAuth/accessToken` | **JWT Bearer token**（本机实测：HS256，`aud=https://cursor.com`，`iss=https://authentication.cursor.sh`，签发 2026-08-19、exp 2026-10-16，**约 2 个月有效期**） |
| `cursorAuth/refreshToken` | 刷新凭证 |
| `cursorAuth/cachedEmail` | 账户邮箱 |
| `cursorAuth/stripeMembershipType` | 套餐档位（pro/ultra…） |
| `cursorAuth/stripeSubscriptionStatus` | 订阅状态 |

### 次来源：Cursor CLI keychain（`cursor-access-token` / `cursor-refresh-token`）

### 刷新机制（来源：OpenTokenUsage 文档；**未本机实测**，避免轮换 token 影响用户当前 Cursor 会话）

```
POST https://api2.cursor.sh/oauth/token
Content-Type: application/json
{ "grant_type": "refresh_token",
  "client_id": "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
  "refresh_token": "<refreshToken>" }
→ 200 { "access_token": "<new jwt>", "id_token": "...", "shouldLogout": false }
→ 无效时 { "access_token": "", ..., "shouldLogout": true }
```

`client_id: KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB` 是 Cursor 官方客户端 ID（两个独立实现一致）。刷新后把新 access token 写回来源。

### 结论（对本项目）

token 有效期长（约 2 个月），**手动粘贴 accessToken 到设置里即可长期使用**；同时支持“自动从 Cursor 本地读取”（每次打开面板读最新 token，无需手动维护）。

---

## 3. token 如何安全存放

| 方案 | 说明 | 本项目采用 |
|---|---|---|
| **macOS 钥匙串**（Security framework，`kSecClassGenericPassword`，`kSecAttrAccessibleAfterFirstUnlock`） | 系统级加密，随用户解锁，非沙箱应用无需额外授权 | ✅ 首选（设置里“保存到钥匙串”） |
| 本地配置文件兜底 | `~/Library/Application Support/CursorUsage/config.json`，**chmod 600**，路径在仓库外 | ✅ 兜底（钥匙串不可用时） |
| Cursor 本地状态库自动读取 | `SQLITE_OPEN_READONLY` 只读打开 + `busy_timeout`，**只读不回写**，避免破坏 Cursor 自身状态 | ✅ 默认模式 |
| 写进仓库 / 打印日志 | 绝对禁止 | ❌ |

安全原则：**accessToken 绝不写入仓库**（`.gitignore` 已排除 `token.txt`、`*.token`；配置/钥匙串都在仓库外路径）；代码里不打印 token 本身；HTTP 仅走 HTTPS。

---

## 4. 不确定点（明确列出）

1. **接口无官方公开文档**，字段可能随时变化（已做防御性解析：字段缺失/非数值时优雅降级）。
2. **per-pool 美元拆分无直给字段**，由 `GetAggregatedUsageEvents` 按模型归属求和得到（本机已验证合计与 `totalSpend` 一致）；归属以服务端 **`tier` 字段为准**（tier=2 auto 池 / tier=1 API 池），`autoBucketModels` 与名称前缀仅作兜底。
3. **池额度（$2000/$500）为反推推断**，非接口直给；UI 不将其当作硬数据展示。**面板 Included 行改用 `includedSpend/limit` 口径**（与官方 displayMessage 一致），`totalPercentUsed`（含 bonus 总池口径）仅作参考、不与买断额度金额并排展示。
4. **刷新端点未 live 验证**（怕轮换 token 影响用户 Cursor 会话）；实现中作为 401 时的可选兜底，默认不启用。
5. `displayThreshold`/`enabled` 的确切语义是推断（阈值告警），未影响主功能。
6. Pro 旧版 request-based 账户的响应可能不带 `planUsage` 金额字段（本实现按百分比 + 缺失降级处理）。
