import AppKit
import SwiftUI

@main
struct LayoutPreview {
    @MainActor
    static func main() throws {
        let now = Date()
        for (seconds, en, zh) in [
            (6 * 86_400 + 23 * 3_600 + 59 * 60, "6d 23h 59m", "6天 23时 59分"),
            (86_400, "1d 0h 0m", "1天 0时 0分"),
            (86_399, "23h 59m", "23时 59分"),
            (3_600, "1h 0m", "1时 0分"), (59, "<1m", "不到1分"),
            (0, "Updating…", "等待更新"), (-60, "Updating…", "等待更新")
        ] {
            precondition(ResetDuration.text(until: now.addingTimeInterval(Double(seconds)), from: now) == PulseText.t(en, zh))
        }
        precondition(ResetDuration.text(until: nil, from: now) == PulseText.t("No data", "暂无数据"))
        print("Passed countdown boundary tests")
        var payload = WidgetPayload.placeholder
        payload.fiveHourReset = now.addingTimeInterval(4 * 3_600 + 59 * 60)
        payload.weeklyReset = now.addingTimeInterval(6 * 86_400 + 23 * 3_600 + 59 * 60)
        payload.fiveHourUsed = 100
        payload.weeklyUsed = 100
        payload.updatedAt = now
        payload.isLive = true
        payload.signalText = PulseText.t("Demo post: a possible reset is being discussed for tomorrow.", "演示动态：讨论明天可能发生的重置。")
        payload.signalReason = PulseText.t("Synthetic example · not an announcement.", "示例内容，不是真实公告。")
        var demo = payload
        demo.fiveHourUsed = 38
        demo.weeklyUsed = 64
        let hero = VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text("CODEX PULSE").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                Spacer()
                Text("macOS 14+  /  SwiftUI  /  Open source").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Text("Your Codex quota.\nA glance away.").font(.system(size: 52, weight: .bold, design: .rounded))
            HStack(alignment: .center, spacing: 28) {
                MediumWidgetView(payload: demo, referenceDate: now)
                    .frame(width: 360, height: 170)
                    .background(Color(red: 0.06, green: 0.07, blue: 0.10), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 14) {
                    Text("5-hour + weekly usage").font(.system(size: 20, weight: .semibold))
                    Text("Reset countdowns — days included").font(.system(size: 16))
                    Text("Read-only. Local bridge. No extra API key.").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            Text("Native widget rendering · synthetic demo data · optional third-party radar")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(44)
        let cases: [(String, AnyView, CGFloat, CGFloat)] = [
            ("small", AnyView(SmallWidgetView(payload: payload, referenceDate: now)), 170, 170),
            ("medium", AnyView(MediumWidgetView(payload: payload, referenceDate: now)), 360, 170),
            ("empty", AnyView(SmallWidgetView(payload: .unavailable, referenceDate: now)), 170, 170),
            ("hero", AnyView(hero), 900, 520),
        ]
        for (name, view, width, height) in cases {
            let renderer = ImageRenderer(content: view
                .frame(width: width, height: height)
                .background(Color(red: 0.035, green: 0.045, blue: 0.065))
                .environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let cgImage = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                fatalError("Could not render \(name)")
            }
            let output = ProcessInfo.processInfo.environment["PULSE_PREVIEW_DIR"] ?? NSTemporaryDirectory()
            try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name)-\(PulseText.chinese ? "zh" : "en").png"))
            print("Rendered \(name): \(width)x\(height)")
        }
    }
}
