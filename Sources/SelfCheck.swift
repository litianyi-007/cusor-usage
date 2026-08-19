import Foundation

/// 无头自测：真实解析 token → 真实调用 API → 验证钥匙串/文件存取。
/// 不打印 token 本身。任何 [FAIL] 以非零退出码结束。
enum SelfCheck {

    static func run() -> Int32 {
        var lines: [String] = []
        var failed = false
        let store = TokenStore()

        // 1) token 解析
        let resolved = store.resolveToken()
        switch resolved.source {
        case .manual:
            lines.append("[ok] token 来源：手动保存")
        case .auto:
            let email = resolved.email.map { " (email: \($0))" } ?? ""
            let plan = resolved.plan.map { " (plan: \($0))" } ?? ""
            lines.append("[ok] token 来源：Cursor 本地自动读取\(email)\(plan)")
        case .none:
            lines.append("[FAIL] 未找到 accessToken（无手动 token，也读不到 Cursor 本地登录态）")
            failed = true
        }

        // 2) 真实 API
        if let token = resolved.token {
            let result = runAsync(timeout: 45) {
                do {
                    let usage = try await CursorAPI().fetchPeriodUsage(token: token)
                    var out = "[ok] GetCurrentPeriodUsage HTTP 200\n"
                    if let pu = usage.planUsage {
                        out += String(format: "[ok] Cursor Models (autoPercentUsed): %.2f%%\n", pu.autoPercentUsed ?? -1)
                        out += String(format: "[ok] Other Models (apiPercentUsed): %.2f%%\n", pu.apiPercentUsed ?? -1)
                        out += String(format: "[ok] Included total (totalPercentUsed): %.2f%%\n", pu.totalPercentUsed ?? -1)
                        out += String(format: "[ok] 金额: 已用 $%.2f / 限额 $%.2f / 剩余 $%.2f\n",
                                      (pu.totalSpend ?? 0) / 100, (pu.limit ?? 0) / 100, (pu.remaining ?? 0) / 100)
                    } else {
                        out += "[warn] 响应中没有 planUsage（账户形态可能与 Ultra 不同）\n"
                    }
                    if let s = usage.billingCycleStart, let e = usage.billingCycleEnd {
                        out += "[ok] 周期: \(msDate(s)) → \(msDate(e))\n"
                    }
                    out += "[ok] displayMessage: \(usage.displayMessage ?? "(无)")"
                    return (out, false)
                } catch {
                    return ("[FAIL] 请求失败: \(error.localizedDescription)", true)
                }
            }
            if result.failed { failed = true }
            lines.append(result.output)
        }

        // 3) 钥匙串读写
        let probe = "selfcheck-\(UUID().uuidString)"
        let kcOK = store.saveTokenToKeychain(probe) && store.loadTokenFromKeychain() == probe
        _ = store.clearTokenFromKeychain()
        lines.append(kcOK
            ? "[ok] 钥匙串 写入/读取/清除 正常"
            : "[warn] 钥匙串不可用（受限沙箱/权限环境属预期；本机直接运行时正常）")

        // 4) 兜底文件读写（用环境变量隔离目录，不污染真实配置）
        let fileOK = store.saveTokenToFile(probe) && store.loadTokenFromFile() == probe
        _ = store.clearTokenFromFile()
        lines.append(fileOK
            ? "[ok] 本地 600 配置文件 写入/读取/清除 正常"
            : "[warn] 本地配置文件不可用")

        // 5) GetPlanInfo
        if let token = resolved.token {
            let result = runAsync(timeout: 30) {
                do {
                    let plan = try await CursorAPI().fetchPlanInfo(token: token)
                    if let info = plan?.planInfo {
                        let amount = (info.includedAmountCents ?? 0) / 100
                        return ("[ok] GetPlanInfo: \(info.planName ?? "?") \(info.price ?? "") (included $\(String(format: "%.2f", amount)))", false)
                    }
                    return ("[warn] GetPlanInfo 无 planInfo 字段", false)
                } catch {
                    return ("[warn] GetPlanInfo 失败: \(error.localizedDescription)", false)
                }
            }
            if result.failed { failed = true }
            lines.append(result.output)
        }

        // 6) GetAggregatedUsageEvents + 两个池美元拆分
        if let token = resolved.token {
            let result = runAsync(timeout: 30) {
                do {
                    let usage = try await CursorAPI().fetchPeriodUsage(token: token)
                    let agg = try await CursorAPI().fetchAggregatedUsageEvents(token: token)
                    guard let rows = agg.aggregations, !rows.isEmpty else {
                        return ("[warn] GetAggregatedUsageEvents 无 aggregations", false)
                    }
                    let auto = Set(usage.autoBucketModels ?? [])
                    let prefixes = ["cursor-", "composer", "vega", "grok"]
                    var cursor = 0.0
                    var other = 0.0
                    var sum = 0.0
                    for row in rows {
                        let cents = row.totalCents ?? 0
                        sum += cents
                        let name = row.modelLabel.lowercased()
                        if auto.contains(row.modelLabel) || prefixes.contains(where: { name.hasPrefix($0) }) {
                            cursor += cents
                        } else {
                            other += cents
                        }
                    }
                    let spend = usage.planUsage?.totalSpend ?? -1
                    let diff = abs(sum - spend)
                    var out = String(format: "[ok] GetAggregatedUsageEvents: %d 个模型, totalCents 合计 $%.2f (planUsage.totalSpend $%.2f, 误差 $%.2f)\n", rows.count, sum / 100, spend / 100, diff / 100)
                    out += String(format: "[ok] 池拆分: Cursor Models $%.2f (%.1f%%) / Other Models $%.2f (%.1f%%)\n",
                                  cursor / 100, cursor / (cursor + other) * 100, other / 100, other / (cursor + other) * 100)
                    if let top = rows.max(by: { ($0.totalCents ?? 0) < ($1.totalCents ?? 0) }) {
                        out += String(format: "[ok] 花费最高模型: %@ $%.2f", top.modelLabel, (top.totalCents ?? 0) / 100)
                    }
                    return (out, false)
                } catch {
                    return ("[warn] GetAggregatedUsageEvents 失败: \(error.localizedDescription)", false)
                }
            }
            if result.failed { failed = true }
            lines.append(result.output)
        }

        print(lines.joined(separator: "\n"))
        return failed ? 1 : 0
    }

    // MARK: - 工具

    private static func runAsync(timeout: TimeInterval, _ body: @escaping () async -> (output: String, failed: Bool)) -> (output: String, failed: Bool) {
        let sem = DispatchSemaphore(value: 0)
        var result: (output: String, failed: Bool) = ("[FAIL] 超时", true)
        Task {
            result = await body()
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
        return result
    }

    static func msDate(_ s: String) -> String {
        guard let ms = Double(s), ms > 0 else { return s }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}
