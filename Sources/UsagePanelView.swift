import SwiftUI

// MARK: - 格式化工具

enum UsageFormat {
    /// 分 → 美元字符串,如 16729 → "$167.29";nil → "—"
    static func cents(_ v: Int?) -> String {
        guard let v else { return "—" }
        return String(format: "$%.2f", Double(v) / 100.0)
    }

    /// 分(Double)→ 美元字符串
    static func centsD(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "$%.2f", v / 100.0)
    }

    /// 百分比,如 26.68 → "26.7%"
    static func percent(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f%%", v)
    }

    /// unix 毫秒字符串 → "MM-dd"
    static func date(_ ms: String?) -> String {
        guard let ms, let t = Double(ms) else { return "—" }
        let d = Date(timeIntervalSince1970: t / 1000.0)
        return Self.dayFormatter.string(from: d)
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return "—" }
        return Self.timeFormatter.string(from: d)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - 用量面板

struct UsagePanelView: View {
    @ObservedObject var store: UsageStore
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if let error = store.error {
                errorBanner(error)
            }
            if let usage = store.usage {
                usageBody(usage)
            } else if store.isLoading {
                HStack { Spacer(); ProgressView("正在拉取…"); Spacer() }
                    .padding(.vertical, 24)
            } else {
                Text("暂无数据 — 点击「刷新」或先设置 Token")
                    .font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("计费周期:\(UsageFormat.date(store.usage?.billingCycleStart)) → \(UsageFormat.date(store.usage?.billingCycleEnd))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var title: String {
        if let p = store.planInfo, let name = p.planName {
            return "\(name)\(p.price.map { " · \($0)" } ?? "")"
        }
        return "Cursor 用量"
    }

    // MARK: 主内容

    @ViewBuilder
    private func usageBody(_ usage: CurrentPeriodUsageResponse) -> some View {
        if let pu = usage.planUsage {
            totalUsageSection(pu)
            modelSections(pu)
            if !store.topModels.isEmpty {
                topModelsSection
            }
            onDemandSection(usage.spendLimitUsage)
            serverMessages(usage)
            autoBucketFooter(usage.autoBucketModels)
        } else {
            Text("接口返回异常:无 planUsage 字段")
                .font(.callout).foregroundColor(.orange)
        }
    }

    /// 综合用量:usedPercentage = min(includedSpend/limit*100,100),与服务端 displayMessage 一致
    private func totalUsageSection(_ pu: CurrentPeriodUsageResponse.PlanUsage) -> some View {
        let usedPct = (pu.limit ?? 0) > 0
            ? min(Double(pu.includedSpend ?? 0) / Double(pu.limit!) * 100.0, 100.0)
            : (pu.totalPercentUsed ?? 0)
        let threshold = Double(store.usage?.displayThreshold ?? 50)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Other Models 池(套餐额度)")
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", usedPct))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(usedPct >= threshold ? .orange : .primary)
            }
            ProgressView(value: usedPct / 100.0)
                .tint(usedPct >= threshold ? .orange : .accentColor)
            HStack {
                Text("已用 \(UsageFormat.cents(pu.includedSpend)) / \(UsageFormat.cents(pu.limit))")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("剩余 \(UsageFormat.cents(pu.remaining))")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    /// Cursor models(Auto 桶)与 Other models(API 桶)用量 —— 面板核心展示
    private func modelSections(_ pu: CurrentPeriodUsageResponse.PlanUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            modelRow(title: "Cursor models(Auto)",
                     percent: UsageFormat.percent(pu.autoPercentUsed),
                     spend: poolSpend(for: true) ?? pu.autoSpend.map { UsageFormat.cents($0) })
            modelRow(title: "Other models(API)",
                     percent: UsageFormat.percent(pu.apiPercentUsed),
                     spend: poolSpend(for: false) ?? pu.apiSpend.map { UsageFormat.cents($0) })
            if let t = pu.totalPercentUsed {
                modelRow(title: "综合用量",
                         percent: UsageFormat.percent(t),
                         spend: nil)
            }
        }
    }

    /// 从聚合用量得到的某池花费(分 → "$xx.xx");无数据时 nil
    private func poolSpend(for cursor: Bool) -> String? {
        guard let pool = store.poolSpendCents else { return nil }
        return cursor ? UsageFormat.centsD(pool.cursor) : UsageFormat.centsD(pool.other)
    }

    private func modelRow(title: String, percent: String, spend: String?) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            if let spend {
                Text(spend).font(.caption).foregroundColor(.secondary)
            }
            Text(percent)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    /// 按花费 Top 5 模型(来自 GetAggregatedUsageEvents)
    private var topModelsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("按模型花费 Top \(store.topModels.count)")
                .font(.caption).foregroundColor(.secondary)
            ForEach(store.topModels, id: \.name) { item in
                HStack {
                    Text(item.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(UsageFormat.centsD(item.cents))
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func onDemandSection(_ sl: CurrentPeriodUsageResponse.SpendLimitUsage?) -> some View {
        if let sl, (sl.individualLimit ?? 0) > 0 || (sl.pooledLimit ?? 0) > 0 || (sl.overallLimit ?? 0) > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("按需额度(On-demand)")
                    .font(.subheadline)
                if let p = sl.pooledLimit, p > 0 {
                    Text("团队池:已用 \(UsageFormat.cents(sl.pooledUsed)) / \(UsageFormat.cents(p))")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let i = sl.individualLimit, i > 0 {
                    Text("个人:已用 \(UsageFormat.cents(sl.individualUsed)) / \(UsageFormat.cents(i))")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let o = sl.overallLimit, o > 0 {
                    Text("总计:已用 \(UsageFormat.cents(sl.overallUsed)) / \(UsageFormat.cents(o))")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func serverMessages(_ usage: CurrentPeriodUsageResponse) -> some View {
        if let m = usage.displayMessage {
            Text(m).font(.caption).foregroundColor(.secondary)
        }
    }

    private func autoBucketFooter(_ models: [String]?) -> some View {
        Group {
            if let models, !models.isEmpty {
                Text("Auto 桶模型(\(models.count) 个):\(models.prefix(6).joined(separator: ", "))\(models.count > 6 ? " …" : "")")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 错误

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 底部

    private var footer: some View {
        HStack {
            Text("更新于 \(UsageFormat.time(store.lastUpdated))")
                .font(.caption2).foregroundColor(.secondary)
            Spacer()
            Button("设置 Token…") { onOpenSettings() }
                .controlSize(.small)
            Button("刷新") {
                Task { await store.refresh() }
            }
            .controlSize(.small)
            .disabled(store.isLoading)
        }
    }
}
