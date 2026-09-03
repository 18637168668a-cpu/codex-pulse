import SwiftUI
import WidgetKit

private let widgetKind = "CodexPulseUsageWidget"

enum PulseText {
    static var chinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") == true }
    static func t(_ english: String, _ chinese: String) -> String { self.chinese ? chinese : english }
}

struct RateWindow: Codable {
    let usedPercent: Int
    let resetsAt: Int?
    let windowDurationMins: Int?
}

struct RateBucket: Codable {
    let primary: RateWindow?
    let secondary: RateWindow?
}

struct UsageResponse: Codable {
    let rateLimits: RateBucket
    let rateLimitsByLimitId: [String: RateBucket]?
    let updatedAt: Double
    let stale: Bool
}

struct ResetAnalysis: Codable {
    let level: String
    let label: String
    let strength: String
    let reason: String
}

struct ResetSignal: Codable {
    let text: String
    let at: String
    let url: String
    let resetAnalysis: ResetAnalysis
}

struct FeedResponse: Codable {
    let signals: [ResetSignal]?
    let enabled: Bool
    let stale: Bool
}

struct WidgetPayload: Codable {
    var fiveHourUsed: Int?
    var weeklyUsed: Int?
    var fiveHourReset: Date?
    var weeklyReset: Date?
    var signalLabel: String
    var signalText: String
    var signalReason: String
    var signalURL: URL?
    var isLive: Bool
    var updatedAt: Date? = nil

    static var unavailable: WidgetPayload {
        WidgetPayload(fiveHourUsed: nil, weeklyUsed: nil, fiveHourReset: nil, weeklyReset: nil,
                      signalLabel: PulseText.t("Radar unavailable", "雷达暂无数据"),
                      signalText: PulseText.t("Start the local bridge to connect.", "请启动本机后台服务。"),
                      signalReason: "", signalURL: nil, isLive: false)
    }

    static let placeholder = WidgetPayload(
        fiveHourUsed: 68,
        weeklyUsed: 41,
        fiveHourReset: Date().addingTimeInterval(7_200),
        weeklyReset: Date().addingTimeInterval(3 * 86_400),
        signalLabel: PulseText.t("Demo · possible reset", "演示 · 可能重置"),
        signalText: PulseText.t("Demo post: a possible reset is being discussed.", "演示动态：出现可能重置的讨论。"),
        signalReason: PulseText.t("Synthetic example, not a real announcement.", "示例内容，不是真实公告。"),
        signalURL: nil,
        isLive: false
    )
}

enum PulseLoader {
    private static let usageURL = URL(string: "http://localhost:43187/api/local/usage")!
    private static let feedURL = URL(string: "http://localhost:43187/api/local/tibo")!
    private static let cacheKey = "CodexPulseWidgetPayloadV2"

    static func load() async -> WidgetPayload {
        var payload = cached() ?? .unavailable
        payload.isLive = false
        async let usageResult: UsageResponse? = try? fetch(usageURL)
        async let feedResult: FeedResponse? = try? fetch(feedURL)

        if let usage = await usageResult {
            let bucket = usage.rateLimitsByLimitId?["codex"] ?? usage.rateLimits
            let windows = [bucket.primary, bucket.secondary].compactMap { $0 }
            let short = windows.first { $0.windowDurationMins == 300 }
            let weekly = windows.first { $0.windowDurationMins == 10080 }
            payload.fiveHourUsed = short?.usedPercent
            payload.weeklyUsed = weekly?.usedPercent
            payload.fiveHourReset = short?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            payload.weeklyReset = weekly?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            payload.updatedAt = Date(timeIntervalSince1970: usage.updatedAt / 1000)
            payload.isLive = !usage.stale
        }

        if let feed = await feedResult {
            payload.signalURL = nil
            if !feed.enabled {
                payload.signalLabel = PulseText.t("Radar off", "雷达已关闭")
                payload.signalText = PulseText.t("Optional reset radar. Your quota monitor works without it.", "可选重置信号雷达。不影响额度监控。")
                payload.signalReason = PulseText.t("Enable reset radar in the Codex Pulse app.", "在 Codex Pulse 应用中开启重置雷达。")
            } else if let signal = feed.signals?.first {
                payload.signalLabel = feed.stale ? PulseText.t("Radar cached", "雷达缓存") : (signal.resetAnalysis.level == "reported" ? PulseText.t("Reset reported", "动态称已重置") : PulseText.t("Possible reset", "可能涉及重置"))
                payload.signalText = signal.text
                payload.signalReason = String(signal.at.prefix(10)) + " · " + PulseText.t("Text heuristic, not account confirmation.", "文本规则判断，不代表你的账户已重置。")
                if let url = URL(string: signal.url), url.scheme == "https", ["x.com", "twitter.com"].contains(url.host ?? "") { payload.signalURL = url }
            } else {
                payload.signalLabel = PulseText.t("No recent signal", "暂无近期信号")
                payload.signalText = PulseText.t("No matching reset posts in the last seven days.", "最近七天未发现匹配的重置动态。")
                payload.signalReason = PulseText.t("Public third-party feed · may lag or omit posts.", "公开第三方源，可能延迟或遗漏。")
            }
        } else {
            payload.signalLabel = PulseText.t("Radar unavailable", "雷达暂无数据")
            payload.signalText = PulseText.t("The optional feed could not be reached.", "暂时无法连接可选信号源。")
            payload.signalReason = ""
            payload.signalURL = nil
        }

        save(payload)
        return payload
    }

    private static func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func cached() -> WidgetPayload? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(WidgetPayload.self, from: data)
    }

    private static func save(_ payload: WidgetPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let payload: WidgetPayload
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), payload: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(PulseEntry(date: Date(), payload: .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        Task {
            let payload = await PulseLoader.load()
            let now = Date()
            // Keep the day/hour/minute display advancing even if the next fetch is delayed.
            let entries = (0..<60).map {
                PulseEntry(date: now.addingTimeInterval(Double($0) * 60), payload: payload)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
        }
    }
}

struct UsageBar: View {
    let value: Int
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(max(0, min(100, value))) / 100)
                    .shadow(color: tint.opacity(0.55), radius: 5)
            }
        }
        .frame(height: 5)
    }
}

private enum WidgetPalette {
    // The widget background is always dark, so avoid system primary/secondary
    // colors that can resolve to near-black when macOS is in light mode.
    static let primary = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.54)
    static let body = Color.white.opacity(0.88)
    static let track = Color.white.opacity(0.14)
    static let divider = Color.white.opacity(0.18)
}

enum ResetDuration {
    static func text(until reset: Date?, from now: Date) -> String {
        guard let reset else { return PulseText.t("No data", "暂无数据") }
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return PulseText.t("Updating…", "等待更新") }
        let minutes = Int(seconds / 60)
        if minutes == 0 { return PulseText.t("<1m", "不到1分") }
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let remainder = minutes % 60
        if days > 0 { return PulseText.t("\(days)d \(hours)h \(remainder)m", "\(days)天 \(hours)时 \(remainder)分") }
        return PulseText.t("\(hours)h \(remainder)m", "\(hours)时 \(remainder)分")
    }
}

struct UsageMetric: View {
    let title: String
    let value: Int?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WidgetPalette.secondary)
            Text("\(Text(value.map(String.init) ?? "—").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(WidgetPalette.primary))\(Text(value == nil ? "" : "%").font(.system(size: 12, weight: .bold)).foregroundStyle(tint))")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            UsageBar(value: value ?? 0, tint: value == nil ? .gray : tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UsageSummary: View {
    let payload: WidgetPayload
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("CODEX")
                Spacer()
                Text(payload.updatedAt == nil ? PulseText.t("No data", "暂无数据") : (payload.isLive && referenceDate.timeIntervalSince(payload.updatedAt!) < 900 ? PulseText.t("Updated", "已更新") : PulseText.t("Cached", "缓存")))
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(WidgetPalette.secondary)
            HStack(alignment: .top, spacing: 10) {
                UsageMetric(title: PulseText.t("5h used", "5 小时已用"), value: payload.fiveHourUsed, tint: .cyan)
                UsageMetric(title: PulseText.t("Week used", "本周已用"), value: payload.weeklyUsed, tint: .purple)
            }
            VStack(spacing: 6) {
                resetRow(PulseText.t("5h reset", "5 小时重置"), reset: payload.fiveHourReset, tint: .cyan)
                resetRow(PulseText.t("Week reset", "本周重置"), reset: payload.weeklyReset, tint: .purple)
            }
        }
    }

    private func resetRow(_ title: String, reset: Date?, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(WidgetPalette.secondary)
                .fixedSize()
            Spacer(minLength: 0)
            Text(ResetDuration.text(until: reset, from: referenceDate))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct SmallWidgetView: View {
    let payload: WidgetPayload
    var referenceDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageSummary(payload: payload, referenceDate: referenceDate)
            Spacer(minLength: 5)
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text(payload.signalLabel).lineLimit(1)
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.purple.opacity(0.98))
        }
        .padding(12)
    }
}

struct MediumWidgetView: View {
    let payload: WidgetPayload
    var referenceDate: Date = Date()

    var body: some View {
        HStack(spacing: 14) {
            UsageSummary(payload: payload, referenceDate: referenceDate)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider().overlay(WidgetPalette.divider)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("TIBO RESET RADAR")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(WidgetPalette.secondary)
                    Spacer()
                    Circle()
                        .fill(payload.isLive ? Color.cyan : Color.gray)
                        .frame(width: 5, height: 5)
                }

                Text(payload.signalLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.purple.opacity(0.22), in: Capsule())

                Text(payload.signalText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.body)
                    .lineLimit(4)

                Text(payload.signalReason)
                    .font(.system(size: 8))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(3)

                Spacer()
                Text(PulseText.t("Third-party feed · not official", "第三方信号源 · 非官方"))
                    .font(.system(size: 7))
                    .foregroundStyle(WidgetPalette.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

struct CodexPulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                MediumWidgetView(payload: entry.payload, referenceDate: entry.date)
            } else {
                SmallWidgetView(payload: entry.payload, referenceDate: entry.date)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.045, blue: 0.065), Color(red: 0.075, green: 0.055, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(entry.payload.signalURL ?? URL(string: "codexpulse://refresh"))
    }
}

#if !LAYOUT_PREVIEW
@main
struct CodexPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: PulseProvider()) { entry in
            CodexPulseWidgetView(entry: entry)
        }
        .configurationDisplayName(PulseText.t("Codex Usage", "Codex 已用量"))
        .description(PulseText.t("5-hour and weekly usage, reset countdowns, optional reset radar.", "查看 5 小时、本周已用量和可选重置信号。"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
#endif
