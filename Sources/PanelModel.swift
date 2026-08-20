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

    /// 防止并发拉取（打开面板 + 定时器 + 启动可能同时触发）
    private var isFetching = false
    /// 日志文件（可用环境变量 CURSORUSAGE_LOG 覆盖）
    static var logFileURL: URL {
        if let env = ProcessInfo.processInfo.environment["CURSORUSAGE_LOG"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CursorUsage/app.log")
    }

    private func log(_ message: String) {
        let line = "[\(Self.nowText())] \(message)"
        NSLog("%@", line)
        // 日志失败不影响主流程
        try? FileManager.default.createDirectory(at: Self.logFileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: Self.logFileURL, options: .atomic)
        }
    }

    private static func nowText() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    var totalPercent: Double? { usage?.planUsage?.totalPercentUsed }
    var autoPercent: Double? { usage?.planUsage?.autoPercentUsed }
    var apiPercent: Double? { usage?.planUsage?.apiPercentUsed }

    /// 状态栏标题：两池百分比（官方语义只有两个用量池），如 "7%/45%"（Cursor Models / Other Models）
    var poolTitle: String? {
        guard let auto = autoPercent, let api = apiPercent else { return nil }
        return String(format: "%.0f%%/%.0f%%", auto, api)
    }

    // MARK: - 拉取

    /// 刷新：**有缓存数据时静默刷新**（保持 loaded 展示缓存，后台请求成功后更新）；
    /// 无缓存（首次/数据被清空）才进入 loading。
    func refresh() {
        if usage == nil && phase != .loading { phase = .loading }
        Task { await fetch() }
    }

    /// 供截图/自测模式直接拉取（refresh 的可等待版本）
    func loadData() async {
        await fetch()
    }

    private func fetch() async {
        PanelModel.diagnose("fetch: 进入")
        guard !isFetching else {
            log("fetch: 已有拉取在进行，跳过本次")
            return
        }
        isFetching = true
        defer { isFetching = false }

        let hasCache = usage != nil
        let t0 = Date()
        let resolved = store.resolveToken()
        PanelModel.diagnose("fetch: resolveToken 完成 (source=\(resolved.source.rawValue))")
        guard let token = resolved.token, !token.isEmpty else {
            log("fetch: 未找到 accessToken")
            // 有缓存时保留缓存展示，不打断；无缓存才报错
            if !hasCache {
                phase = .failed("未找到 accessToken：点击底部 ⚙️ 设置粘贴 token，或先登录 Cursor 桌面端后点“自动读取 Cursor 本地”。")
                statusTitle = ""
            }
            return
        }
        switch resolved.source {
        case .manual: tokenSource = "手动保存"
        case .auto:   tokenSource = "Cursor 本地自动读取"
        case .none:   tokenSource = "未配置"
        }
        email = resolved.email
        membership = resolved.plan
        log("fetch: 开始 (source=\(resolved.source.rawValue), email=\(resolved.email ?? "?"), hasCache=\(hasCache))")

        // 主数据：带硬超时（25s），确保绝不让面板永远停在 loading
        let u: PeriodUsage
        do {
            u = try await withThrowingTaskGroup(of: PeriodUsage.self) { group in
                group.addTask { try await self.api.fetchPeriodUsage(token: token) }
                group.addTask {
                    try await Task.sleep(nanoseconds: 25_000_000_000)
                    throw CursorAPIError.timeout
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch {
            log("fetch: 主请求失败 -> \(error.localizedDescription) (耗时 \(Int(-t0.timeIntervalSinceNow))s)")
            // 有缓存时保留缓存数据与 loaded 状态（静默失败），无缓存才进入 failed
            if !hasCache {
                phase = .failed("请求失败：\(error.localizedDescription)")
                statusTitle = ""
            }
            return
        }
        log("fetch: 主请求成功 (耗时 \(Int(-t0.timeIntervalSinceNow))s)")

        // 主数据落地，进入 loaded
        usage = u
        lastUpdated = Date()
        phase = .loaded
        // 状态栏标题：两池百分比（如 7%/45%）
        statusTitle = poolTitle ?? ""

        // 次要数据（planName / 聚合拆分）fire-and-forget：失败或超时绝不影响主流程
        if planName == nil {
            Task {
                if let info = try? await self.api.fetchPlanInfo(token: token)?.planInfo {
                    self.planName = info.planName
                }
            }
        }
        Task {
            if let agg = try? await self.api.fetchAggregatedUsageEvents(token: token) {
                self.aggregations = agg
                self.computePools(usage: u, agg: agg)
            }
        }
    }

    // MARK: - 两个池的美元拆分

    /// 模型归属（权威标准 = 服务端 `tier` 字段）：
    /// - `tier == 2` → **Cursor Models 池**（第一方：Grok 4.6/4.5、Composer 等）
    /// - `tier == 1` → **Other Models 池**（第三方：claude / gpt 等，按厂商价格计费）
    /// 官方文档（cursor.com/help/models-and-usage/usage-limits）：套餐只有这两个用量池，
    /// Ultra 含 $400 Other Models（API agent usage）+ generous Cursor Models 池。
    /// 实测验证：tier2 花费和 ÷ autoPercentUsed ≈ $2000（Cursor Models 池）、
    /// tier1 花费和 ÷ apiPercentUsed ≈ $500（$400 官方额度 + 模型厂商赠送 bonus）。
    /// 注：`autoBucketModels` 清单并不完整（实测不含 cursor-grok-4.6 系列，但其 tier=2），
    /// 因此仅作为 tier 缺失时的兜底，名称前缀启发式为最后兜底。
    private func isCursorPoolModel(_ name: String, tier: Int?, auto: Set<String>) -> Bool {
        if let tier { return tier == 2 }
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
            if isCursorPoolModel(name, tier: row.tier, auto: auto) { cursor += cents } else { other += cents }
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
        log("设置: 展开设置区")
    }

    /// 设置按钮 toggle：展开/收起（与设置区内的收起按钮构成两处收起入口）
    func toggleSettings() {
        if showSettings {
            showSettings = false
            log("设置: 收起设置区（gear 按钮）")
        } else {
            openSettings()
        }
    }

    func saveManualToken() {
        let t = settingsToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            settingsMessage = "token 为空，请粘贴后再保存"
            log("设置: 保存失败，token 为空")
            return
        }
        if store.saveTokenToKeychain(t) {
            settingsMessage = "已保存到 macOS 钥匙串 ✓（加密存储）"
            settingsToken = ""
            log("设置: 已保存到钥匙串")
            refresh()
        } else if store.saveTokenToFile(t) {
            settingsMessage = "钥匙串不可用，已写入本地 600 权限配置文件（仓库外）"
            settingsToken = ""
            log("设置: 钥匙串失败，已写入本地配置文件")
            refresh()
        } else {
            settingsMessage = "保存失败：钥匙串与本地文件都不可用"
            log("设置: 保存失败（钥匙串与文件都不可用）")
        }
    }

    func clearManualToken() {
        let kc = store.clearTokenFromKeychain()
        let file = store.clearTokenFromFile()
        settingsMessage = (kc || file) ? "已清除手动 token，将回退到“Cursor 本地自动读取”" : "当前没有手动 token 可清除"
        log("设置: 清除手动 token (keychain=\(kc), file=\(file))")
        refresh()
    }
}
