import Foundation

enum UsageAPIError: LocalizedError {
    case noToken
    case httpStatus(Int, message: String?)
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "未配置 accessToken,请在设置中粘贴或从 Cursor 自动读取。"
        case .httpStatus(let code, let message):
            if code == 401 {
                return "Token 无效或已过期(HTTP 401)。请在设置中更新 accessToken(或从 Cursor 自动读取)。"
            }
            return "HTTP \(code)\(message.map { " — \($0)" } ?? "")"
        case .network(let msg):
            return "网络错误:\(msg)"
        case .invalidResponse:
            return "响应解析失败"
        }
    }
}

/// Connect RPC v1(JSON over HTTP)客户端。
/// 关键头:Authorization: Bearer <token>、Content-Type: application/json、Connect-Protocol-Version: 1
struct UsageClient {
    static let baseURL = URL(string: "https://api2.cursor.sh")!

    static func fetchCurrentPeriodUsage(token: String) async throws -> CurrentPeriodUsageResponse {
        try await post(path: "/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
                       token: token, body: [:])
    }

    static func fetchPlanInfo(token: String) async throws -> PlanInfoResponse {
        try await post(path: "/aiserver.v1.DashboardService/GetPlanInfo",
                       token: token, body: [:])
    }

    static func fetchAggregatedUsageEvents(token: String) async throws -> AggregatedUsageEventsResponse {
        try await post(path: "/aiserver.v1.DashboardService/GetAggregatedUsageEvents",
                       token: token, body: [:])
    }

    private static func post<T: Decodable>(path: String, token: String, body: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version") // Connect 协议必需
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            // ephemeral:不写磁盘缓存(菜单栏常驻程序避免在 ~/Library/Caches 落盘)
            let session = URLSession(configuration: .ephemeral)
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ConnectErrorEnvelope.self, from: data))?.message
            throw UsageAPIError.httpStatus(http.statusCode, message: msg)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw UsageAPIError.invalidResponse
        }
    }
}
