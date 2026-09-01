import AppKit
import SwiftUI
import WidgetKit

private func tr(_ en: String, _ zh: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
}

#if !SETUP_PREVIEW
@main
struct CodexPulseApp: App {
    @NSApplicationDelegateAdaptor(PulseMenuDelegate.self) private var menuDelegate
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
                    NSWorkspace.shared.open(URL(string: "https://github.com/matyang-dev/codex-pulse/blob/main/docs/INSTALL.md")!)
                }
            }
            Text(tr("Both percentages show USED quota. Read-only · no telemetry. macOS schedules widget refreshes. You may close this setup window; keep the app running to show the CP menu meter.", "百分比均为已用额度。只读、无遥测；刷新由 macOS 调度。可关闭设置窗口；保持 App 运行即可显示 CP 菜单栏用量。"))
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


struct QuotaMeterState {
    var fiveHour: Double?
    var weekly: Double?
    var stale = false

    static func decode(_ data: Data) throws -> QuotaMeterState {
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let byID = response["rateLimitsByLimitId"] as? [String: [String: Any]]
        let bucket = byID?["codex"] ?? response["rateLimits"] as? [String: Any] ?? [:]
        let windows = [bucket["primary"], bucket["secondary"]].compactMap { $0 as? [String: Any] }
        func used(_ duration: Int) -> Double? {
            guard let window = windows.first(where: { ($0["windowDurationMins"] as? Int) == duration }),
                  let value = window["usedPercent"] as? Double, value.isFinite,
                  (0...100).contains(value) else { return nil }
            return value
        }
        let updatedAt = (response["updatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        let stale = response["stale"] as? Bool == true || updatedAt.map { Date().timeIntervalSince($0) > 900 } == true
        return QuotaMeterState(fiveHour: used(300), weekly: used(10080), stale: stale)
    }
}

enum QuotaMeterColor {
    // Green at 0%, yellow at 50%, red at 100%. Missing data has no usage color.
    static func components(_ used: Double?) -> [Double]? {
        guard let used, used.isFinite else { return nil }
        let value = max(0, min(100, used))
        let green = [0.12, 0.75, 0.32], yellow = [1.0, 0.80, 0.10], red = [0.95, 0.18, 0.18]
        let start = value <= 50 ? green : yellow
        let end = value <= 50 ? yellow : red
        let progress = value <= 50 ? value / 50 : (value - 50) / 50
        return zip(start, end).map { $0 + ($1 - $0) * progress }
    }

    static func color(_ used: Double?) -> NSColor {
        guard let rgb = components(used) else { return .secondaryLabelColor }
        return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }

    @MainActor static func image(_ state: QuotaMeterState) -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 20))
        image.lockFocus()
        for (letter, value, x) in [("C", state.fiveHour, 1.0), ("P", state.weekly, 15.0)] {
            (letter as NSString).draw(at: NSPoint(x: x, y: 2), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: color(state.stale ? nil : value)
            ])
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

@MainActor final class PulseMenuDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    private var fetching = false
    private var fiveHourItem: NSMenuItem?
    private var weeklyItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: 32)
        let menu = NSMenu()
        fiveHourItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        weeklyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(fiveHourItem!)
        menu.addItem(weeklyItem!)
        menu.addItem(.separator())
        for entry in [
            NSMenuItem(title: tr("Refresh usage", "刷新用量"), action: #selector(refreshFromMenu), keyEquivalent: ""),
            NSMenuItem(title: tr("Setup & help", "安装与帮助"), action: #selector(openHelp), keyEquivalent: ""),
            NSMenuItem(title: tr("Quit Codex Pulse", "退出 Codex Pulse"), action: #selector(quit), keyEquivalent: "q")
        ] { entry.target = self; menu.addItem(entry) }
        item?.menu = menu
        update(QuotaMeterState())
        Task { await refreshUsage() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func update(_ state: QuotaMeterState) {
        func value(_ used: Double?) -> String { used.map { String(format: "%.0f%%", $0) } ?? "—" }
        let suffix = state.stale ? tr(" (cached)", "（缓存）") : ""
        let short = tr("C · 5h used: ", "C · 5 小时已用：") + value(state.fiveHour) + suffix
        let week = tr("P · Week used: ", "P · 本周已用：") + value(state.weekly) + suffix
        item?.button?.image = QuotaMeterColor.image(state)
        item?.button?.toolTip = "Codex Pulse\n" + short + "\n" + week
        item?.button?.setAccessibilityLabel("Codex Pulse. " + short + ". " + week)
        fiveHourItem?.title = short
        weeklyItem?.title = week
    }

    private func refreshUsage() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:43187/api/local/usage")!)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            update(try QuotaMeterState.decode(data))
        } catch { update(QuotaMeterState()) }
    }

    @objc private func refreshFromMenu() { Task { await refreshUsage() } }
    @objc private func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/matyang-dev/codex-pulse/blob/main/docs/INSTALL.md")!)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
