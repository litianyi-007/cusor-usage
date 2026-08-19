import Foundation

// MARK: - 响应模型（字段名与接口一致，均为 camelCase）

struct PlanUsage: Codable {
    var totalSpend: Double?
    var includedSpend: Double?
    var bonusSpend: Double?
    var remaining: Double?
    var limit: Double?
    var remainingBonus: Bool?
    var bonusTooltip: String?
    /// Cursor Models 池用量（%）
    var autoPercentUsed: Double?
    /// Other Models 池用量（%）
    var apiPercentUsed: Double?
    /// 合计用量（%）
    var totalPercentUsed: Double?
}

struct SpendLimitUsage: Codable {
    var pooledLimit: Double?
    var pooledUsed: Double?
    var pooledRemaining: Double?
    var individualLimit: Double?
    var individualUsed: Double?
    var individualRemaining: Double?
    var limitType: String?
}

struct PeriodUsage: Codable {
    var billingCycleStart: String?
    var billingCycleEnd: String?
    var planUsage: PlanUsage?
    var spendLimitUsage: SpendLimitUsage?
    var displayMessage: String?
    var autoModelSelectedDisplayMessage: String?
    var namedModelSelectedDisplayMessage: String?
    var displayThreshold: Double?
    var enabled: Bool?
    var autoBucketModels: [String]?
}

struct PlanInfoResponse: Codable {
    struct PlanInfo: Codable {
        var planName: String?
        var includedAmountCents: Double?
        var price: String?
        var billingCycleEnd: String?
        var planOwner: String?
    }
    var planInfo: PlanInfo?
}

/// GetAggregatedUsageEvents —— 按模型的当前周期聚合用量。
/// 实测:aggregations[].totalCents 之和 == planUsage.totalSpend(精确一致)。
/// 两个池的美元拆分 = 按 autoBucketModels(或名称前缀)归属各模型 totalCents 求和。
struct AggregatedUsageEventsResponse: Codable {
    var aggregations: [AggregationRow]?
    var totalInputTokens: String?
    var totalOutputTokens: String?
    var totalCostCents: Double?

    struct AggregationRow: Codable {
        var modelIntent: String?
        var model: String?
        var inputTokens: String?
        var outputTokens: String?
        var cacheWriteTokens: String?
        var cacheReadTokens: String?
        var totalCents: Double?
        var tier: Int?

        var modelLabel: String {
            let raw = modelIntent ?? model ?? "unknown"
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : raw
        }
    }
}

/// Connect 错误响应(非 2xx 时返回,如 401 → {"code":"unauthenticated","message":...})
struct ConnectErrorEnvelope: Codable {
    var code: String?
    var message: String?
}

enum CursorAPIError: LocalizedError {
    case httpStatus(Int, String)
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body):
            if code == 401 {
                return "Token 无效或已过期(HTTP 401)。请在 ⚙️ 设置中更新 accessToken(或点“自动读取 Cursor 本地”)。"
            }
            let preview = String(body.prefix(120))
            return "HTTP \(code) \(preview)"
        case .invalidResponse:
            return "响应不是合法 JSON"
        case .timeout:
            return "请求超时(25s)"
        }
    }
}

// MARK: - Connect RPC v1 (JSON over HTTP) 客户端

struct CursorAPI {
    let baseURL = URL(string: "https://api2.cursor.sh")!

    /// 单例 session：ephemeral 不落盘缓存；必须长期持有——每次新建的 URLSession 若在
    /// 请求完成前被释放，async/await 的 continuation 可能永远不恢复(表现为面板一直转圈)。
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 25
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private func connectRequest(path: String, token: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("cursorusage-menubar/0.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 20
        return req
    }

    private func post<T: Decodable>(path: String, token: String, as type: T.Type) async throws -> T {
        let req = connectRequest(path: path, token: token)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let envelope = try? JSONDecoder().decode(ConnectErrorEnvelope.self, from: data)
            let detail = envelope?.message ?? String(data: data, encoding: .utf8) ?? ""
            throw CursorAPIError.httpStatus(http.statusCode, detail)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw CursorAPIError.invalidResponse
        }
        return decoded
    }

    /// POST /aiserver.v1.DashboardService/GetCurrentPeriodUsage
    func fetchPeriodUsage(token: String) async throws -> PeriodUsage {
        try await post(path: "aiserver.v1.DashboardService/GetCurrentPeriodUsage", token: token, as: PeriodUsage.self)
    }

    /// POST /aiserver.v1.DashboardService/GetPlanInfo
    func fetchPlanInfo(token: String) async throws -> PlanInfoResponse? {
        try? await post(path: "aiserver.v1.DashboardService/GetPlanInfo", token: token, as: PlanInfoResponse.self)
    }

    /// POST /aiserver.v1.DashboardService/GetAggregatedUsageEvents
    func fetchAggregatedUsageEvents(token: String) async throws -> AggregatedUsageEventsResponse {
        try await post(path: "aiserver.v1.DashboardService/GetAggregatedUsageEvents", token: token, as: AggregatedUsageEventsResponse.self)
    }
}
