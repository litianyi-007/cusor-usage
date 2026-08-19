import Foundation
import AppKit

@MainActor
final class PanelModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var usage: PeriodUsage?
    @Published var planName: String?
    @Published var tokenSource: String = "未配置"
    @Published var email: String?
    @Published var membership: String?
    @Published var lastUpdated: Date?
    @Published var statusTitle: String = ""
    @Published var showSettings: Bool = false
    @Published var settingsToken: String = ""
    @Published var settingsMessage: String = ""

    /// 按模型聚合用量（GetAggregatedUsageEvents）
    @Published var aggregations: AggregatedUsageEventsResponse?
    /// 两个池当前周期美元花费（分）：(cursor 池, other 池)，由 aggregations 按 autoBucketModels 归属求和
    @Published var poolSpendCents: (cursor: Double, other: Double)?
    /// 按花费降序的 Top 模型（名称, 分）
    @Published var topModels: [(name: String, cents: Double)] = []

    private let api = CursorAPI()
    private let store = TokenStore()

    var totalPercent: Double? { usage?.planUsage?.totalPercentUsed }
    var autoPercent: Double? { usage?.planUsage?.autoPercentUsed }
    var apiPercent: Double? { usage?.planUsage?.apiPercentUsed }

    // MARK: - 拉取

    func refresh() {
        if phase != .loading { phase = .loading }
        Task { await fetch() }
    }

    /// 供截图/自测模式直接拉取（refresh 的可等待版本）
    func loadData() async {
        await fetch()
    }

    private func fetch() async {
        let resolved = store.resolveToken()
        guard let token = resolved.token, !token.isEmpty else {
            phase = .failed("未找到 accessToken：点击底部 ⚙️ 设置粘贴 token，或先登录 Cursor 桌面端后点“自动读取 Cursor 本地”。")
            statusTitle = ""
            return
        }
        switch resolved.source {
        case .manual: tokenSource = "手动保存"
        case .auto:   tokenSource = "Cursor 本地自动读取"
        case .none:   tokenSource = "未配置"
        }
        email = resolved.email
        membership = resolved.plan

        do {
            let u = try await api.fetchPeriodUsage(token: token)
            usage = u
            if planName == nil {
                planName = try? await api.fetchPlanInfo(token: token)?.planInfo?.planName
            }
            // 拉取聚合用量以计算两个池的美元拆分；失败不阻塞主数据
            if let agg = try? await api.fetchAggregatedUsageEvents(token: token) {
                aggregations = agg
                computePools(usage: u, agg: agg)
            }
            lastUpdated = Date()
            phase = .loaded
            if let total = u.planUsage?.totalPercentUsed {
                statusTitle = String(format: "%.0f%%", total)
            }
        } catch {
            phase = .failed("请求失败：\(error.localizedDescription)")
            statusTitle = ""
        }
    }

    // MARK: - 两个池的美元拆分

    /// 模型归属：Cursor models 池 = 服务端 autoBucketModels 精确命中；
    /// 未命中时按名称前缀启发式归属（cursor- / composer / vega / grok），与实测数据一致。
    private func isCursorPoolModel(_ name: String, auto: Set<String>) -> Bool {
        if auto.contains(name) { return true }
        let lower = name.lowercased()
        let prefixes = ["cursor-", "composer", "vega", "grok"]
        return prefixes.contains { lower.hasPrefix($0) }
    }

    private func computePools(usage: PeriodUsage, agg: AggregatedUsageEventsResponse) {
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

    // MARK: - 设置

    func openSettings() {
        settingsToken = ""
        settingsMessage = ""
        showSettings = true
    }

    func saveManualToken() {
        let t = settingsToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            settingsMessage = "token 为空，请粘贴后再保存"
            return
        }
        if store.saveTokenToKeychain(t) {
            settingsMessage = "已保存到 macOS 钥匙串 ✓（加密存储）"
            settingsToken = ""
            refresh()
        } else if store.saveTokenToFile(t) {
            settingsMessage = "钥匙串不可用，已写入本地 600 权限配置文件（仓库外）"
            settingsToken = ""
            refresh()
        } else {
            settingsMessage = "保存失败：钥匙串与本地文件都不可用"
        }
    }

    func clearManualToken() {
        let kc = store.clearTokenFromKeychain()
        let file = store.clearTokenFromFile()
        settingsMessage = (kc || file) ? "已清除手动 token，将回退到“Cursor 本地自动读取”" : "当前没有手动 token 可清除"
        refresh()
    }
}
