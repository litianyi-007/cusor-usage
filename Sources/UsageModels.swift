import Foundation

// MARK: - GetCurrentPeriodUsage 响应模型
//
// 协议:Connect RPC v1(JSON over HTTP)。JSON 字段名 = proto 字段的 lowerCamelCase。
// 字段清单取自 Cursor 桌面应用内嵌的 proto 定义(workbench.desktop.main.js 中
// makeMessageType("aiserver.v1.GetCurrentPeriodUsageResponse", ...)),
// 并与 2026-08-19 本机实机请求(HTTP 200)逐字段核对一致。金额单位「分」(cents),÷100 = 美元。
//
// 「Cursor models vs Other models」映射(权威依据 = Cursor 应用内代码 + 服务端返回):
//   firstPartyPercentUsed = planUsage.autoPercentUsed  → Cursor models(Auto 桶)
//   thirdPartyPercentUsed = planUsage.apiPercentUsed   → Other models(API/指定模型)
//   Other Models 池金额   = planUsage.limit / includedSpend / remaining
//   usedPercentage        = min(includedSpend / limit * 100, 100) —— 与服务端 displayMessage 口径一致
//
// 两个池的美元拆分:接口不直接给 autoSpend/apiSpend(本机实测为 null/缺失),
// 由 GetAggregatedUsageEvents 的 totalCents 按 autoBucketModels 归属求和得到
// (实测:aggregations.totalCents 之和 == planUsage.totalSpend,精确一致)。

struct CurrentPeriodUsageResponse: Codable {
    var billingCycleStart: String?        // unix 毫秒(JSON 中为字符串)
    var billingCycleEnd: String?
    var planUsage: PlanUsage?
    var spendLimitUsage: SpendLimitUsage?
    var displayThreshold: Int?            // 告警阈值(基点,200 = 2%)
    var enabled: Bool?
    var displayMessage: String?
    var autoModelSelectedDisplayMessage: String?
    var namedModelSelectedDisplayMessage: String?
    var autoBucketModels: [String]?       // Auto 桶(= Cursor models 池)包含的模型列表

    struct PlanUsage: Codable {
        var totalSpend: Int?              // 总花费(分)
        var includedSpend: Int?           // 计入套餐额度的花费(分)
        var bonusSpend: Int?              // 模型厂商赠送额度(分)
        var remaining: Int?               // 剩余(分)
        var limit: Int?                   // 套餐额度 = Other Models 池金额(分)
        var remainingBonus: Bool?
        var bonusTooltip: String?
        var autoSpend: Int?               // Auto 桶花费(分;可选,本机实测未填充 → nil)
        var apiSpend: Int?                // API/指定模型花费(分;可选)
        var autoLimit: Int?               // Auto 桶额度(分;可选)
        var apiLimit: Int?                // API 桶额度(分;可选)
        var autoPercentUsed: Double?      // Cursor models(Auto 桶)用量 %
        var apiPercentUsed: Double?       // Other models(API 桶)用量 %
        var totalPercentUsed: Double?     // 综合用量 %
    }

    struct SpendLimitUsage: Codable {
        var totalSpend: Int?
        var pooledLimit: Int?
        var pooledUsed: Int?
        var pooledRemaining: Int?
        var individualLimit: Int?
        var individualUsed: Int?
        var individualRemaining: Int?
        var limitType: String?            // "user" | "team"
        var overallLimit: Int?
        var overallUsed: Int?
        var overallRemaining: Int?
    }
}

// GetPlanInfo —— 面板头部展示套餐名 / 价格(次要数据)
struct PlanInfoResponse: Decodable {
    var planInfo: PlanInfo?
    struct PlanInfo: Decodable {
        var planName: String?
        var includedAmountCents: Int?
        var price: String?
        var billingCycleEnd: String?
        var planOwner: String?
    }
}

// GetAggregatedUsageEvents —— 按模型的聚合用量(用于两个池的美元拆分 + Top 模型费用)
// 实机响应:{"aggregations":[{"modelIntent":"claude-fable-5-thinking-max","inputTokens":"618279",
//   "outputTokens":"560792","cacheWriteTokens":"3351642","cacheReadTokens":"53863200",
//   "totalCents":12094.52587,"tier":1}, ...],"totalInputTokens":"5978789","totalOutputTokens":"1190452",...}
struct AggregatedUsageEventsResponse: Decodable {
    var aggregations: [AggregationRow]?
    var totalInputTokens: String?
    var totalOutputTokens: String?
    var totalCents: Double?

    struct AggregationRow: Decodable {
        var modelIntent: String?
        var model: String?
        var inputTokens: String?
        var outputTokens: String?
        var cacheWriteTokens: String?
        var cacheReadTokens: String?
        var totalCents: Double?           // 该模型当前周期花费(分)
        var tier: Int?

        var modelLabel: String {
            (modelIntent ?? model ?? "unknown")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? "unknown" : (modelIntent ?? model ?? "unknown")
        }
    }
}

// Connect 错误响应(非 2xx 时返回,例如 401 时 {"code":"unauthenticated","message":"Error",...})
struct ConnectErrorEnvelope: Decodable {
    var code: String?
    var message: String?
}
