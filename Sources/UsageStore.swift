import Foundation
import Combine

/// 全局用量状态:负责拉取、缓存、错误与刷新时机。
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published var usage: CurrentPeriodUsageResponse?
    @Published var planInfo: PlanInfoResponse.PlanInfo?
    @Published var error: String?
    @Published var isLoading = false
    @Published var lastUpdated: Date?

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
            return
        }
        isLoading = true
        error = nil
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
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

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
