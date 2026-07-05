import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let summaryItem = NSMenuItem(title: "尚未检查", action: nil, keyEquivalent: "")
    private let recommendationItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let detailsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let apiItem = NSMenuItem(title: "API：等待检查", action: nil, keyEquivalent: "")
    private let chatGPTItem = NSMenuItem(title: "ChatGPT：等待检查", action: nil, keyEquivalent: "")
    private let authItem = NSMenuItem(title: "Auth：等待检查", action: nil, keyEquivalent: "")
    private let checkedAtItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let historyMenu = NSMenu()
    private let historyStore = HistoryStore()
    private var settings = SettingsStore.load()
    private var timer: Timer?
    private var currentReport: DiagnosticReport?
    private var checking = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "●"
        statusItem.button?.toolTip = "Codex Reconnect Doctor"
        buildMenu()
        statusItem.menu = menu
        scheduleTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.runCheck() }
    }

    private func buildMenu() {
        let title = NSMenuItem(title: "Codex Reconnect Doctor", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(summaryItem)
        menu.addItem(recommendationItem)
        menu.addItem(detailsItem)
        menu.addItem(apiItem)
        menu.addItem(chatGPTItem)
        menu.addItem(authItem)
        menu.addItem(checkedAtItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "立即检查", action: #selector(runCheck), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "打开 Libcyber Desktop", action: #selector(openProxyClient), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "复制代理启动命令", action: #selector(copyLaunchCommand), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "按代理方式重启 Codex…", action: #selector(restartCodex), keyEquivalent: ""))

        let historyItem = NSMenuItem(title: "最近检查", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        refreshHistoryMenu()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(settings.checkIntervalMinutes, 1) * 60), repeats: true) { [weak self] _ in
            self?.runCheck()
        }
    }

    @objc private func runCheck() {
        guard !checking else { return }
        checking = true
        summaryItem.title = "正在检查…"
        setStatusColor(.systemGray)
        let snapshot = settings
        DispatchQueue.global(qos: .userInitiated).async {
            let report = DiagnosticEngine(settings: snapshot).run()
            DispatchQueue.main.async {
                self.checking = false
                self.currentReport = report
                self.historyStore.append(report)
                self.render(report)
                self.refreshHistoryMenu()
            }
        }
    }

    private func render(_ report: DiagnosticReport) {
        summaryItem.title = report.summary
        recommendationItem.title = "建议：\(report.recommendation)"
        if let proxy = report.proxy {
            detailsItem.title = "代理：\(proxy.host):\(proxy.port) · \(proxy.source)"
        } else {
            detailsItem.title = "代理：未发现"
        }
        checkedAtItem.title = "检查时间：\(DateFormatter.doctor.string(from: report.checkedAt))"
        apiItem.title = endpointLine(named: "OpenAI API", label: "API", in: report)
        chatGPTItem.title = endpointLine(named: "ChatGPT", label: "ChatGPT", in: report)
        authItem.title = endpointLine(named: "OpenAI Auth", label: "Auth", in: report)
        switch report.level {
        case .healthy: setStatusColor(.systemGreen)
        case .warning: setStatusColor(.systemOrange)
        case .critical: setStatusColor(.systemRed)
        case .unknown: setStatusColor(.systemGray)
        }
        statusItem.button?.toolTip = report.summary
    }

    private func refreshHistoryMenu() {
        historyMenu.removeAllItems()
        let reports = historyStore.load()
        if reports.isEmpty {
            historyMenu.addItem(withTitle: "暂无记录", action: nil, keyEquivalent: "")
            return
        }
        for report in reports.prefix(10) {
            let symbol: String
            switch report.level {
            case .healthy: symbol = "●"
            case .warning: symbol = "▲"
            case .critical: symbol = "✕"
            case .unknown: symbol = "?"
            }
            historyMenu.addItem(withTitle: "\(symbol) \(DateFormatter.shortDoctor.string(from: report.checkedAt))  \(report.summary)", action: nil, keyEquivalent: "")
        }
    }

    @objc private func openProxyClient() {
        let candidates = ["Libcyber Desktop", "Libcyber", "Shadowrocket", "Clash Verge", "Mihomo Party"]
        let folders = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for folder in folders {
            for name in candidates {
                let url = folder.appendingPathComponent("\(name).app")
                if FileManager.default.fileExists(atPath: url.path) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    return
                }
            }
        }
        let alert = NSAlert()
        alert.messageText = "未找到代理客户端"
        alert.informativeText = "请先手动打开代理客户端，或在设置中确认代理端口。"
        alert.runModal()
    }

    @objc private func copyLaunchCommand() {
        let proxy = currentReport?.proxy ?? ProxyConfiguration(host: settings.proxyHost, port: settings.proxyPort, source: "设置")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(launchCommand(proxy: proxy), forType: .string)
        showTransientAlert(title: "已复制", message: "Codex代理启动命令已复制到剪贴板。")
    }

    @objc private func restartCodex() {
        let alert = NSAlert()
        alert.messageText = "按代理方式重启 Codex？"
        alert.informativeText = "这会退出当前Codex进程，并使用检测到的本地HTTP代理重新启动。请先确认当前任务已经保存。"
        alert.addButton(withTitle: "重启")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let proxy = currentReport?.proxy ?? ProxyConfiguration(host: settings.proxyHost, port: settings.proxyPort, source: "设置")
        _ = Shell.run("/usr/bin/osascript", ["-e", "quit app \"Codex\""])
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/MacOS/Codex")
            process.arguments = ["--proxy-server=http://\(proxy.host):\(proxy.port)"]
            var environment = ProcessInfo.processInfo.environment
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
                environment[key] = "http://\(proxy.host):\(proxy.port)"
            }
            process.environment = environment
            try? process.run()
        }
    }

    @objc private func showSettings() {
        let alert = NSAlert()
        alert.messageText = "诊断设置"
        alert.informativeText = "默认自动发现代理；检测失败时使用下方地址。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        let auto = NSButton(checkboxWithTitle: "自动发现代理", target: nil, action: nil)
        auto.state = settings.autoDetectProxy ? .on : .off
        let host = NSTextField(string: settings.proxyHost)
        host.placeholderString = "代理地址"
        let port = NSTextField(string: String(settings.proxyPort))
        port.placeholderString = "HTTP代理端口"
        let interval = NSTextField(string: String(settings.checkIntervalMinutes))
        interval.placeholderString = "自动检查间隔（分钟）"
        [auto, host, port, interval].forEach { stack.addArrangedSubview($0) }
        stack.frame = NSRect(x: 0, y: 0, width: 310, height: 112)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        settings.autoDetectProxy = auto.state == .on
        settings.proxyHost = host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "127.0.0.1" : host.stringValue
        settings.proxyPort = Int(port.stringValue) ?? 8890
        settings.checkIntervalMinutes = max(Int(interval.stringValue) ?? 15, 1)
        SettingsStore.save(settings)
        scheduleTimer()
        runCheck()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func launchCommand(proxy: ProxyConfiguration) -> String {
        let value = "http://\(proxy.host):\(proxy.port)"
        return "osascript -e 'quit app \"Codex\"'; sleep 2; HTTP_PROXY=\(value) HTTPS_PROXY=\(value) ALL_PROXY=\(value) http_proxy=\(value) https_proxy=\(value) all_proxy=\(value) \"/Applications/Codex.app/Contents/MacOS/Codex\" --proxy-server=\"\(value)\""
    }

    private func endpointLine(named name: String, label: String, in report: DiagnosticReport) -> String {
        guard let endpoint = report.endpoints.first(where: { $0.name == name }) else { return "\(label)：无结果" }
        if let error = endpoint.error, !error.isEmpty { return "\(label)：连接失败" }
        let challenge = endpoint.cloudflareChallenge ? " · Cloudflare challenge" : ""
        return String(format: "%@：HTTP %d · %.2fs%@", label, endpoint.statusCode, endpoint.duration, challenge)
    }

    private func setStatusColor(_ color: NSColor) {
        statusItem.button?.attributedTitle = NSAttributedString(
            string: "●",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 14, weight: .bold)]
        )
    }

    private func showTransientAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

enum SettingsStore {
    private static let key = "settings.v1"

    static func load() -> StoredSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(StoredSettings.self, from: data) else { return StoredSettings() }
        return value
    }

    static func save(_ settings: StoredSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension DateFormatter {
    static let doctor: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "MM-dd HH:mm:ss"
        return value
    }()

    static let shortDoctor: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "MM-dd HH:mm"
        return value
    }()
}
