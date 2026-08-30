import AppKit
import SwiftUI
import WidgetKit

private func tr(_ en: String, _ zh: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
}

@main
struct CodexPulseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 480, height: 340)
                .onAppear { WidgetCenter.shared.reloadAllTimelines() }
                .onOpenURL { _ in WidgetCenter.shared.reloadAllTimelines() }
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var status = tr("Checking local bridge…", "正在检查本机服务…")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Codex Pulse", systemImage: "gauge.with.dots.needle.33percent")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan)
            Text(tr("Your Codex quota. A glance away.", "Codex 额度，抬眼即见。"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("1. Right-click your desktop → Edit Widgets", "1. 右键桌面 → 编辑小组件"))
                Text(tr("2. Search Codex Pulse → add small or medium", "2. 搜索 Codex Pulse → 添加小号或中号"))
                Text(tr("3. Both percentages mean USED, not remaining", "3. 两组百分比都是已用量，不是剩余量"))
            }.font(.system(size: 13))
            Text(status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(tr("Refresh widgets", "刷新组件")) {
                    WidgetCenter.shared.reloadAllTimelines()
                    Task { await checkBridge() }
                }.buttonStyle(.borderedProminent)
                Button(tr("Setup & help", "安装与帮助")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/18637168668a-cpu/codex-pulse#quick-start")!)
                }.buttonStyle(.bordered)
            }
            Text(tr("Read-only · local bridge · macOS schedules widget refreshes", "只读 · 本机服务 · 小组件刷新由 macOS 调度"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.04, green: 0.05, blue: 0.075))
        .preferredColorScheme(.dark)
        .task { await checkBridge() }
    }

    private func checkBridge() async {
        do {
            var request = URLRequest(url: URL(string: "http://localhost:43187/api/local/usage")!)
            request.timeoutInterval = 20
            let (_, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode == 200
                ? tr("Bridge connected. Quota data is available.", "服务已连接，额度数据可用。")
                : tr("Bridge is running. Check your Codex ChatGPT login.", "服务运行中，请检查 Codex 的 ChatGPT 登录。")
        } catch {
            status = tr("Bridge offline. Run bash scripts/install.sh from the repository.", "服务离线，请在项目目录运行 bash scripts/install.sh。")
        }
    }
}
