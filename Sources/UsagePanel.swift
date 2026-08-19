import SwiftUI

// MARK: - 主面板

struct UsagePanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 10)
            content
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.rays")
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor 用量")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if case .loading = model.phase {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let m = model.membership, !m.isEmpty { parts.append(m.capitalized) }
        if let p = model.planName, !p.isEmpty { parts.append(p) }
        if let e = model.email, !e.isEmpty { parts.append(e) }
        if parts.isEmpty { parts.append(model.tokenSource) }
        return parts.joined(separator: " · ")
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            HStack { Spacer(); ProgressView("正在拉取用量…"); Spacer() }.padding(.vertical, 24)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 8) {
                Label("加载失败", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("重试") { model.refresh() }.controlSize(.small)
                    Button("去设置 token") { model.openSettings() }.controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        case .loaded, .idle:
            if let usage = model.usage {
                meters(usage)
                cycleRow(usage)
                if let onDemand = usage.spendLimitUsage {
                    onDemandRow(onDemand)
                }
                if let msg = usage.displayMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.showSettings {
                    settingsSection
                }
            } else {
                Text("暂无数据，点击刷新")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: 用量条

    private func meters(_ usage: PeriodUsage) -> some View {
        let pools = model.poolSpendCents
        return VStack(alignment: .leading, spacing: 10) {
            MeterRow(title: "Cursor Models",
                     percent: usage.planUsage?.autoPercentUsed ?? 0,
                     detail: poolDetail(cents: pools?.cursor, percent: usage.planUsage?.autoPercentUsed))
            MeterRow(title: "Other Models",
                     percent: usage.planUsage?.apiPercentUsed ?? 0,
                     detail: poolDetail(cents: pools?.other, percent: usage.planUsage?.apiPercentUsed))
            MeterRow(title: "Included total",
                     percent: usage.planUsage?.totalPercentUsed ?? 0,
                     detail: totalDetail(usage.planUsage))
            if !model.topModels.isEmpty {
                topModelsSection
            }
        }
    }

    private func poolDetail(cents: Double?, percent: Double?) -> String {
        var parts: [String] = []
        if let c = cents {
            parts.append("已用 \(Self.cents(c))")
        }
        if let p = percent {
            parts.append(String(format: "%.1f%%", p))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var topModelsSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Top 模型（按花费）")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(Array(model.topModels.prefix(3)), id: \.name) { m in
                HStack {
                    Text(m.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(Self.cents(m.cents))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func totalDetail(_ pu: PlanUsage?) -> String {
        guard let pu else { return "—" }
        var parts: [String] = []
        if let t = pu.totalSpend { parts.append("已用 $\(Self.cents(t))") }
        if let l = pu.limit { parts.append("限额 $\(Self.cents(l))") }
        if let r = pu.remaining { parts.append("剩余 $\(Self.cents(r))") }
        return parts.joined(separator: " · ")
    }

    static func cents(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v / 100.0)) ?? String(format: "$%.2f", v / 100.0)
    }

    // MARK: 周期

    private func cycleRow(_ usage: PeriodUsage) -> some View {
        let start = Self.msDate(usage.billingCycleStart)
        let end = Self.msDate(usage.billingCycleEnd)
        let days = Self.daysUntil(usage.billingCycleEnd)
        return HStack {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(start) → \(end)")
                .font(.caption)
                .monospacedDigit()
            Spacer()
            if let d = days {
                Text("\(d) 天后重置")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 2)
    }

    static func msDate(_ s: String?) -> String {
        guard let s, let ms = Double(s), ms > 0 else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    static func daysUntil(_ s: String?) -> Int? {
        guard let s, let ms = Double(s), ms > 0 else { return nil }
        let days = (ms / 1000 - Date().timeIntervalSince1970) / 86400
        return max(0, Int(days.rounded()))
    }

    // MARK: 按量付费

    private func onDemandRow(_ sl: SpendLimitUsage) -> some View {
        var lines: [String] = []
        if let p = sl.pooledLimit, p > 0 {
            lines.append("团队池：$\(Self.cents(sl.pooledUsed ?? 0)) / $\(Self.cents(p))")
        }
        if let i = sl.individualLimit, i > 0 {
            lines.append("个人：$\(Self.cents(sl.individualUsed ?? 0)) / $\(Self.cents(i))")
        }
        if lines.isEmpty { return EmptyView().any }
        return VStack(alignment: .leading, spacing: 2) {
            Text("按量付费")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(lines, id: \.self) { Text($0).font(.caption).foregroundColor(.secondary) }
        }
        .padding(.top, 4).any
    }

    // MARK: 设置区

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token 设置").font(.headline)
                Spacer()
                Button { model.showSettings = false } label: { Image(systemName: "chevron.down") }
                    .controlSize(.small)
                    .help("收起设置")
            }
            SecureField("粘贴 Cursor accessToken", text: $model.settingsToken)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            HStack(spacing: 8) {
                Button("保存到钥匙串") { model.saveManualToken() }
                    .controlSize(.small)
                Button("自动读取 Cursor 本地") { model.clearManualToken() }
                    .controlSize(.small)
                Button("清除手动 token") { model.clearManualToken() }
                    .controlSize(.small)
            }
            Text("当前来源：\(model.tokenSource)")
                .font(.caption)
                .foregroundColor(.secondary)
            if !model.settingsMessage.isEmpty {
                Text(model.settingsMessage)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("token 只保存在 macOS 钥匙串（或本机 600 权限的本地文件，位于仓库外），不会写入代码仓库。也可登录 Cursor 桌面端后直接点“自动读取 Cursor 本地”，无需手动维护。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .padding(.top, 6)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: { model.refresh() }) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            Spacer()
            Text(model.lastUpdated.map { "更新于 " + Self.timeText($0) } ?? "未更新")
                .font(.caption2)
                .foregroundColor(.secondary)
            Button(action: { model.openSettings() }) {
                Image(systemName: "gearshape")
            }
            .controlSize(.small)
            .help("Token 设置")
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
            }
            .controlSize(.small)
            .help("退出")
        }
    }

    static func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}

// MARK: - 单条用量条

private struct MeterRow: View {
    let title: String
    let percent: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(detail)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            MeterBar(percent: percent, tint: tint)
        }
    }

    private var tint: Color {
        if percent >= 85 { return .red }
        if percent >= 60 { return .orange }
        return .green
    }
}

private struct MeterBar: View {
    let percent: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: max(6, geo.size.width * min(max(percent, 0), 100) / 100))
            }
        }
        .frame(height: 8)
    }
}

extension View {
    var any: AnyView { AnyView(self) }
}
