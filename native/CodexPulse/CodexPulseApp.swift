import AppKit
import SwiftUI
import WidgetKit

private func tr(_ en: String, _ zh: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
}

#if !SETUP_PREVIEW
@main
struct CodexPulseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 570, height: 510)
                .onAppear { WidgetCenter.shared.reloadAllTimelines() }
                .onOpenURL { _ in WidgetCenter.shared.reloadAllTimelines() }
        }
        .windowResizability(.contentSize)
    }
}
#endif

struct ContentView: View {
    @State private var status = tr("Checking local bridge…", "正在检查本机服务…")
    @State private var result = ""
    @State private var busy = false
    @State private var connected = false
    @State private var socialEnabled = false
    @State private var confirmRemoval = false
    @State private var confirmRadar = false
    @AppStorage("customCodexBinary") private var customCodexBinary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Codex Pulse", systemImage: "gauge.with.dots.needle.33percent")
                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.cyan)
            Text(tr("Your Codex quota. A glance away.", "Codex 额度，抬眼即见。"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 7) {
                Text(tr("1. Sign into Codex with your ChatGPT account", "1. 在 Codex 中使用 ChatGPT 账号登录"))
                Text(tr("2. Enable the local bridge below (starts at login)", "2. 点击下方按钮启用本机服务（登录时启动）"))
                Text(tr("3. Right-click desktop → Edit Widgets → Codex Pulse", "3. 右键桌面 → 编辑小组件 → Codex Pulse"))
            }.font(.system(size: 13))
            HStack {
                Button(tr("Enable/repair bridge", "启用／修复本机服务")) {
                    perform(["install-prebuilt", "--app", Bundle.main.bundlePath])
                }.buttonStyle(.borderedProminent)
                Button(tr("Refresh widgets", "刷新组件")) {
                    WidgetCenter.shared.reloadAllTimelines()
                    Task { await checkBridge() }
                }.buttonStyle(.bordered)
                if busy { ProgressView().controlSize(.small) }
            }.disabled(busy)
            Text(status).font(.caption).foregroundStyle(connected ? .green : .secondary)
            if !result.isEmpty {
                ScrollView { Text(result).font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(height: 56)
            }
            Divider()
            HStack {
                Button(tr(socialEnabled ? "Disable reset radar" : "Enable reset radar", socialEnabled ? "关闭重置雷达" : "开启重置雷达")) {
                    if socialEnabled { perform(["social", "off"]) } else { confirmRadar = true }
                }.disabled(busy || !connected)
                Button(tr("Remove local bridge", "移除本机服务")) { confirmRemoval = true }.disabled(busy)
            }
            HStack {
                Button(tr("Choose Codex…", "选择 Codex 程序…")) { chooseCodex() }.disabled(busy)
                Button(tr("Setup & help", "安装与帮助")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/18637168668a-cpu/codex-pulse/blob/main/docs/INSTALL.md")!)
                }
            }
            Text(tr("Both percentages show USED quota. Read-only · no telemetry. macOS schedules widget refreshes. You can close this app after setup.", "百分比均为已用额度。只读、无遥测；刷新由 macOS 调度。设置后可关闭主应用。"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.04, green: 0.05, blue: 0.075)).preferredColorScheme(.dark)
        .task { await checkBridge() }
        .alert(tr("Enable third-party reset radar?", "开启第三方重置雷达？"), isPresented: $confirmRadar) {
            Button(tr("Enable", "开启")) { perform(["social", "on"]) }
            Button(tr("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(tr("codex-reset.com receives normal HTTPS metadata, including your IP. Codex credentials and quota data are never sent. Posts are heuristic signals, not official reset confirmation.", "codex-reset.com 会收到 IP 等普通 HTTPS 请求信息，不会收到 Codex 凭证或用量。动态判断仅供参考，不是官方重置确认。"))
        }
        .alert(tr("Remove local bridge?", "移除本机服务？"), isPresented: $confirmRemoval) {
            Button(tr("Remove", "移除"), role: .destructive) { perform(["remove-bridge"]) }
            Button(tr("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(tr("Stops the login service and moves its files to Trash. The app and Codex login remain untouched. Remove the desktop widget separately.", "停止登录服务并将其文件移到废纸篓，保留应用和 Codex 登录资料。桌面小组件需另行移除。"))
        }
    }

    @MainActor private func chooseCodex() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose the Codex executable (not the .app)", "选择 Codex 可执行文件（不是 .app）")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customCodexBinary = url.path
            result = tr("Codex path selected. Click Enable/repair bridge to apply.", "已选择 Codex 路径，点击启用／修复本机服务后生效。")
        }
    }

    @MainActor private func perform(_ arguments: [String]) {
        guard !busy, let resources = Bundle.main.resourceURL else { return }
        busy = true
        result = tr("Working…", "正在处理…")
        let selectedCodex = customCodexBinary
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                SetupRunner.run(resources: resources, arguments: arguments, codex: selectedCodex)
            }.value
            result = outcome
            busy = false
            WidgetCenter.shared.reloadAllTimelines()
            await checkBridge()
        }
    }

    @MainActor private func checkBridge() async {
        do {
            var health = URLRequest(url: URL(string: "http://127.0.0.1:43187/health")!)
            health.timeoutInterval = 3
            let (data, response) = try await URLSession.shared.data(for: health)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (response as? HTTPURLResponse)?.statusCode == 200, json?["app"] as? String == "codex-pulse" else { throw URLError(.badServerResponse) }
            connected = true
            socialEnabled = json?["socialEnabled"] as? Bool ?? false
            status = tr("Local bridge connected. Checking Codex login…", "本机服务已连接，正在检查 Codex 登录…")
            var usage = URLRequest(url: URL(string: "http://127.0.0.1:43187/api/local/usage")!)
            usage.timeoutInterval = 20
            let (payload, usageResponse) = try await URLSession.shared.data(for: usage)
            let value = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
            if (usageResponse as? HTTPURLResponse)?.statusCode == 200 {
                status = value?["stale"] as? Bool == true
                    ? tr("Bridge connected. Showing cached quota; check Codex login/network.", "服务已连接，当前为缓存额度；请检查 Codex 登录和网络。")
                    : tr("Bridge connected. Quota data is available.", "服务已连接，额度数据可用。")
            } else {
                status = tr("Bridge connected. Open Codex and check your ChatGPT login.", "服务已连接，请打开 Codex 检查 ChatGPT 登录。")
            }
        } catch {
            connected = false
            status = tr("Bridge offline. Use Enable/repair bridge to set up.", "服务离线，请点击启用／修复本机服务。")
        }
    }
}

private enum SetupRunner {
    static func run(resources: URL, arguments: [String], codex: String) -> String {
        let candidates = [resources.appendingPathComponent("runtime/node").path, "/opt/homebrew/bin/node", "/usr/local/bin/node"]
        guard let node = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return tr("Node runtime missing. Download the complete release or install Node.js 22+ for a source build.", "未找到 Node 运行时。请下载完整发行版；源码版需安装 Node.js 22+。")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [resources.appendingPathComponent("scripts/manage.mjs").path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        // Avoid user-injected Node options in the bundled installer/runtime.
        environment.removeValue(forKey: "NODE_OPTIONS")
        environment.removeValue(forKey: "NODE_PATH")
        if !codex.isEmpty { environment["CODEX_BIN"] = codex }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? tr("Setup finished. Check the bridge status above.", "操作结束，请查看上方服务状态。") : String(text.prefix(1800))
        } catch {
            return tr("Could not start setup. Re-download the app and check the installation guide.", "无法启动设置。请重新下载应用并查看安装说明。")
        }
    }
}
