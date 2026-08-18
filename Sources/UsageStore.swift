import Foundation
import Combine

/// 全局用量状态:负责拉取、缓存、错误、刷新时机与两个池的美元拆分。
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published var usage: CurrentPeriodUsageResponse?
    @Published var planInfo: PlanInfoResponse.PlanInfo?
    @Published var aggregations: AggregatedUsageEventsResponse?
    /// (cursor, other) —— 两个池当前周期花费(分),由 aggregations 按 autoBucketModels 归属求和
    @Published var poolSpendCents: (cursor: Double, other: Double)?
    /// 按花费降序的 Top 模型(名称, 分)
    @Published var topModels: [(name: String, cents: Double)] = []
    @Published var error: String?
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    /// 数据更新后的回调(AppDelegate 用它更新状态栏标题)
    var onUpdate: (() -> Void)?

    private var lastFetch: Date?
    private var timer: Timer?

    private init() {}

    /// 当前可用 token:Keychain → 兜底文件 → Cursor 本地状态库
    var token: String? {
        TokenStore.load(allowCursor: true)
    }

    /// 手动刷新(设置保存后 / 打开面板按需 / 定时)
    func refresh() async {
        guard !isLoading else { return }
        guard let token = token else {
            error = "未配置 accessToken,请在设置中粘贴或从 Cursor 自动读取。"
            usage = nil
            onUpdate?()
            return
        }
        isLoading = true
        error = nil
        defer {
            isLoading = false
            onUpdate?()
        }
        do {
            let usage: CurrentPeriodUsageResponse = try await UsageClient.fetchCurrentPeriodUsage(token: token)
            self.usage = usage
            lastUpdated = Date()
            lastFetch = Date()
            if planInfo == nil {
                if let info: PlanInfoResponse = try? await UsageClient.fetchPlanInfo(token: token) {
                    planInfo = info.planInfo
                }
            }
            // 拉取聚合用量以计算两个池的美元拆分;失败不阻塞主数据
            if let agg: AggregatedUsageEventsResponse = try? await UsageClient.fetchAggregatedUsageEvents(token: token) {
                aggregations = agg
                computePools(usage: usage, agg: agg)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 两个池的美元拆分

    /// 模型归属:Cursor models 池 = 服务端 autoBucketModels 精确命中;
    /// 未命中时按名称前缀启发式归属(cursor- / composer / vega / grok),与实测数据一致。
    /// 注:服务端对 Cursor 第一方模型的命名均带上述前缀;第三方(claude-*/gpt-*)不在其中。
    private func isCursorPoolModel(_ name: String, auto: Set<String>) -> Bool {
        if auto.contains(name) { return true }
        let lower = name.lowercased()
        let prefixes = ["cursor-", "composer", "vega", "grok"]
        return prefixes.contains { lower.hasPrefix($0) }
    }

    private func computePools(usage: CurrentPeriodUsageResponse, agg: AggregatedUsageEventsResponse) {
        guard let rows = agg.aggregations, !rows.isEmpty else {
            poolSpendCents = nil
            topModels = []
            return
        }
        let auto = Set(usage.autoBucketModels ?? [])
        var cursor = 0.0
        var other = 0.0
        var top: [(name: String, cents: Double)] = []
        for row in rows {
            let name = row.modelLabel
            let cents = row.totalCents ?? 0
            if isCursorPoolModel(name, auto: auto) { cursor += cents } else { other += cents }
            top.append((name, cents))
        }
        top.sort { $0.cents > $1.cents }
        poolSpendCents = (cursor, other)
        topModels = Array(top.prefix(5))
    }

    // MARK: - 刷新时机

    /// 打开面板时调用:数据 60 秒内则不重复拉取
    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 60 { return }
        await refresh()
    }

    /// 每 5 分钟后台刷新,保持常驻数据新鲜
    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }
}
