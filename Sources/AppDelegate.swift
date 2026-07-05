import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let testModeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let summaryItem = NSMenuItem(title: "尚未检查", action: nil, keyEquivalent: "")
    private let recommendationItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let detailsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let forcedProxyItem = NSMenuItem(title: "强制代理：等待检查", action: nil, keyEquivalent: "")
    private let apiItem = NSMenuItem(title: "API：等待检查", action: nil, keyEquivalent: "")
    private let chatGPTItem = NSMenuItem(title: "ChatGPT：等待检查", action: nil, keyEquivalent: "")
    private let authItem = NSMenuItem(title: "Auth：等待检查", action: nil, keyEquivalent: "")
    private let checkedAtItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let recoverySeparator = NSMenuItem.separator()
    private let recoveryTitle = NSMenuItem(title: "建议操作", action: nil, keyEquivalent: "")
    private let openProxyItem = NSMenuItem(title: "打开代理客户端", action: #selector(openProxyClient), keyEquivalent: "")
    private let restartCodexItem = NSMenuItem(title: "让 Codex 通过当前代理重新启动…", action: #selector(restartCodex), keyEquivalent: "")
    private let enableForcedProxyItem = NSMenuItem(title: "启用登录级强制代理…", action: #selector(enableForcedProxy), keyEquivalent: "")
    private let advancedForcedProxyItem = NSMenuItem(title: "可选：启用登录级代理保障…", action: #selector(enableForcedProxy), keyEquivalent: "")
    private let disableForcedProxyItem = NSMenuItem(title: "关闭登录级代理保障…", action: #selector(disableForcedProxy), keyEquivalent: "")
    private let historyMenu = NSMenu()
    private let historyStore = HistoryStore()
    private var settings = SettingsStore.load()
    private var timer: Timer?
    private var currentReport: DiagnosticReport?
    private var checking = false
    private var previewingScenario = false

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
        testModeItem.isEnabled = false
        testModeItem.isHidden = true
        menu.addItem(testModeItem)
        menu.addItem(summaryItem)
        menu.addItem(recommendationItem)
        menu.addItem(detailsItem)
        forcedProxyItem.toolTip = "检查登录级LaunchAgent和当前用户会话中的6个代理环境变量，确保从Dock或访达启动Codex时仍继承本地代理。"
        menu.addItem(forcedProxyItem)
        menu.addItem(apiItem)
        menu.addItem(chatGPTItem)
        menu.addItem(authItem)
        menu.addItem(checkedAtItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "立即检查", action: #selector(runCheck), keyEquivalent: "r"))
        recoveryTitle.isEnabled = false
        menu.addItem(recoverySeparator)
        menu.addItem(recoveryTitle)
        menu.addItem(openProxyItem)
        menu.addItem(restartCodexItem)
        menu.addItem(enableForcedProxyItem)

        let advancedMenu = NSMenu()
        advancedMenu.addItem(advancedForcedProxyItem)
        advancedMenu.addItem(disableForcedProxyItem)
        advancedMenu.addItem(.separator())
        let commandItem = NSMenuItem(title: "备用：复制终端启动命令", action: #selector(copyLaunchCommand), keyEquivalent: "")
        commandItem.toolTip = "正常情况下不需要使用。只有诊断显示“Codex未连接代理”时，主菜单才会出现“让Codex通过当前代理重新启动”。如果该操作失败，再使用本命令：① 点击复制；② 打开“终端”；③ 按Command+V粘贴；④ 按回车运行。"
        advancedMenu.addItem(commandItem)
        advancedMenu.addItem(.separator())
        let scenarioMenu = NSMenu()
        for (index, scenario) in DiagnosticScenario.allCases.enumerated() {
            let item = NSMenuItem(title: scenario.title, action: #selector(previewScenario(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            scenarioMenu.addItem(item)
        }
        scenarioMenu.addItem(.separator())
        scenarioMenu.addItem(NSMenuItem(title: "退出测试并立即真实检测", action: #selector(exitScenarioPreview), keyEquivalent: ""))
        let scenarioItem = NSMenuItem(title: "测试诊断场景", action: nil, keyEquivalent: "")
        scenarioItem.submenu = scenarioMenu
        advancedMenu.addItem(scenarioItem)
        let advancedItem = NSMenuItem(title: "高级工具", action: nil, keyEquivalent: "")
        advancedItem.submenu = advancedMenu
        menu.addItem(advancedItem)

        let historyItem = NSMenuItem(title: "最近检查", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        updateRecoveryActions(nil)
        refreshHistoryMenu()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(settings.checkIntervalMinutes, 1) * 60), repeats: true) { [weak self] _ in
            guard self?.previewingScenario == false else { return }
            self?.runCheck()
        }
    }

    @objc private func runCheck() {
        guard !checking else { return }
        previewingScenario = false
        testModeItem.isHidden = true
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
        forcedProxyItem.title = forcedProxyStatus(report)
        if report.persistentProxyConfigured == true && report.launchEnvironmentConfigured {
            advancedForcedProxyItem.title = "重新应用登录级代理保障…"
        } else {
            advancedForcedProxyItem.title = "可选：启用登录级代理保障…"
        }
        advancedForcedProxyItem.isEnabled = !previewingScenario
        advancedForcedProxyItem.toolTip = previewingScenario ? "测试模式不会写入登录配置。" : nil
        disableForcedProxyItem.isHidden = !FileManager.default.fileExists(atPath: launchAgentURL.path)
        disableForcedProxyItem.isEnabled = !previewingScenario
        disableForcedProxyItem.toolTip = previewingScenario ? "测试模式不会删除登录配置。" : nil
        checkedAtItem.title = "检查时间：\(DateFormatter.doctor.string(from: report.checkedAt))"
        apiItem.title = endpointLine(named: "OpenAI API", label: "API", in: report)
        chatGPTItem.title = endpointLine(named: "ChatGPT", label: "ChatGPT", in: report)
        authItem.title = endpointLine(named: "OpenAI Auth", label: "Auth", in: report)
        updateRecoveryActions(report)
        switch report.level {
        case .healthy: setStatusColor(.systemGreen)
        case .warning: setStatusColor(.systemOrange)
        case .critical: setStatusColor(.systemRed)
        case .unknown: setStatusColor(.systemGray)
        }
        statusItem.button?.toolTip = report.summary
    }

    @objc private func previewScenario(_ sender: NSMenuItem) {
        let scenarios = DiagnosticScenario.allCases
        guard scenarios.indices.contains(sender.tag) else { return }
        let scenario = scenarios[sender.tag]
        previewingScenario = true
        let report = DiagnosticEngine.previewReport(for: scenario)
        currentReport = report
        testModeItem.title = "🧪 测试模式：\(scenario.title)（不会执行操作或写入历史）"
        testModeItem.isHidden = false
        render(report)
        checkedAtItem.title = "模拟场景：\(scenario.title)"
    }

    @objc private func exitScenarioPreview() {
        runCheck()
    }

    private func refreshHistoryMenu() {
        historyMenu.removeAllItems()
        let reports = historyStore.load()
        if reports.isEmpty {
            historyMenu.addItem(withTitle: "暂无记录", action: nil, keyEquivalent: "")
            return
        }
        for (index, report) in reports.prefix(10).enumerated() {
            let status: String
            let color: NSColor
            switch report.level {
            case .healthy: status = "正常"; color = .systemGreen
            case .warning: status = "待确认"; color = .systemOrange
            case .critical: status = "需处理"; color = .systemRed
            case .unknown: status = "未完成"; color = .systemGray
            }
            let title = "● \(DateFormatter.shortDoctor.string(from: report.checkedAt)) · \(status) · \(report.summary)"
            let item = NSMenuItem(
                title: title,
                action: #selector(showHistoryDetails(_:)),
                keyEquivalent: ""
            )
            let attributedTitle = NSMutableAttributedString(string: title)
            attributedTitle.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: 1))
            attributedTitle.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: NSRange(location: 0, length: 1))
            item.attributedTitle = attributedTitle
            item.target = self
            item.tag = index
            historyMenu.addItem(item)
        }
    }

    @objc private func showHistoryDetails(_ sender: NSMenuItem) {
        let reports = historyStore.load()
        guard reports.indices.contains(sender.tag) else { return }
        let report = reports[sender.tag]
        let proxyText = report.proxy.map { "\($0.host):\($0.port)（\($0.source)）" } ?? "未发现"
        let codexText = report.codexRunning
            ? (report.codexUsesProxy ? "已运行，并检测到连接本地代理" : "已运行，但未检测到连接本地代理")
            : "未运行"
        let forcedProxyText = forcedProxyStatus(report).replacingOccurrences(of: "登录级代理保障：", with: "")
        let endpointText = report.endpoints.map { endpointDetail($0) }.joined(separator: "\n")
        let presentation = historyPresentation(report.level)
        let alert = NSAlert()
        alert.alertStyle = presentation.style
        alert.messageText = presentation.title
        alert.informativeText = "检查时间：\(DateFormatter.doctor.string(from: report.checkedAt))\n\n结论：\(report.summary)\n建议：\(report.recommendation)\n\n代理：\(proxyText)\n登录级代理保障：\(forcedProxyText)\nCodex：\(codexText)\n\n网络检测：\n\(endpointText)"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
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
        guard let command = launchCommand(proxy: proxy) else {
            showTransientAlert(title: "无法生成命令", message: "代理地址或端口无效，请先检查设置。")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        showTransientAlert(title: "备用命令已复制", message: "只有菜单中的“让Codex通过当前代理重新启动”无效时，才需要把这个命令粘贴到“终端”运行。")
    }

    @objc private func restartCodex() {
        let alert = NSAlert()
        alert.messageText = "让 Codex 通过当前代理重新启动？"
        alert.informativeText = "仅在诊断提示“未检测到Codex连接代理”时使用。Codex会立即退出并重新启动，正在生成的任务可能会中断。"
        alert.addButton(withTitle: "退出并重启")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let proxy = currentReport?.proxy ?? ProxyConfiguration(host: settings.proxyHost, port: settings.proxyPort, source: "设置")
        guard let validated = try? ProxyValidator.validate(host: proxy.host, port: proxy.port),
              let value = try? ProxyValidator.proxyURL(host: validated.host, port: validated.port) else {
            showTransientAlert(title: "无法重启", message: "代理地址或端口无效，请先检查设置。")
            return
        }
        _ = Shell.run("/usr/bin/osascript", ["-e", "quit app \"Codex\""])
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/MacOS/Codex")
            process.arguments = ["--proxy-server=\(value)"]
            var environment = ProcessInfo.processInfo.environment
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
                environment[key] = value
            }
            process.environment = environment
            try? process.run()
        }
    }

    @objc private func enableForcedProxy() {
        guard !previewingScenario else { return }
        let proxy = currentReport?.proxy ?? ProxyConfiguration(host: settings.proxyHost, port: settings.proxyPort, source: "设置")
        let alert = NSAlert()
        alert.messageText = "启用登录级强制代理？"
        alert.informativeText = "将创建或修复 ~/Library/LaunchAgents/com.local.codex-proxy-env.plist，并把当前用户会话的代理变量设置为 http://\(proxy.host):\(proxy.port)。以后从Dock或访达启动Codex时也会继承该代理。不会修改代理订阅或节点。"
        alert.addButton(withTitle: "启用")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try installPersistentProxy(proxy)
            showTransientAlert(title: "登录级强制代理已启用", message: "配置已写入并在当前用户会话中生效。下次启动Codex时会继承该代理；可以立即重新检测确认状态。")
            runCheck()
        } catch {
            showTransientAlert(title: "启用失败", message: error.localizedDescription)
        }
    }

    private func installPersistentProxy(_ proxy: ProxyConfiguration) throws {
        let validated = try ProxyValidator.validate(host: proxy.host, port: proxy.port)
        let value = try ProxyValidator.proxyURL(host: validated.host, port: validated.port)
        let keys = ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexProxyEnvironmentHelper")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw NSError(domain: "CodexReconnectDoctor", code: 2, userInfo: [NSLocalizedDescriptionKey: "应用内的代理环境Helper缺失或不可执行。"])
        }
        let plist: [String: Any] = [
            "Label": "com.local.codex-proxy-env",
            "ProgramArguments": [helper.path, validated.host, String(validated.port)],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let folder = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = launchAgentURL
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        for key in keys {
            _ = Shell.run("/bin/launchctl", ["setenv", key, value])
        }
        _ = Shell.run("/bin/launchctl", ["setenv", "NO_PROXY", "localhost,127.0.0.1,::1"])
        _ = Shell.run("/bin/launchctl", ["setenv", "no_proxy", "localhost,127.0.0.1,::1"])
        let domain = "gui/\(getuid())"
        _ = Shell.run("/bin/launchctl", ["bootout", domain, file.path])
        let loaded = Shell.run("/bin/launchctl", ["bootstrap", domain, file.path])
        if loaded.exitCode != 0 && !loaded.error.contains("already bootstrapped") {
            throw NSError(domain: "CodexReconnectDoctor", code: Int(loaded.exitCode), userInfo: [NSLocalizedDescriptionKey: loaded.error.isEmpty ? "无法加载登录级配置。" : loaded.error])
        }
    }

    @objc private func disableForcedProxy() {
        guard !previewingScenario else { return }
        let alert = NSAlert()
        alert.messageText = "关闭登录级代理保障？"
        alert.informativeText = "将卸载并删除本工具管理的登录配置，同时清除与当前本地代理匹配的用户会话代理变量。不会关闭系统代理或代理客户端。"
        alert.addButton(withTitle: "关闭并删除配置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let domain = "gui/\(getuid())"
        _ = Shell.run("/bin/launchctl", ["bootout", domain, launchAgentURL.path])
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            do {
                try FileManager.default.removeItem(at: launchAgentURL)
            } catch {
                showTransientAlert(title: "关闭失败", message: error.localizedDescription)
                return
            }
        }
        if let proxy = currentReport?.proxy,
           let expected = try? ProxyValidator.proxyURL(host: proxy.host, port: proxy.port) {
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
                let current = Shell.run("/bin/launchctl", ["getenv", key]).output.trimmingCharacters(in: .whitespacesAndNewlines)
                if current == expected { _ = Shell.run("/bin/launchctl", ["unsetenv", key]) }
            }
        }
        showTransientAlert(title: "登录级代理保障已关闭", message: "配置已卸载并删除。系统代理和代理客户端未被修改。")
        runCheck()
    }

    @objc private func showSettings() {
        let alert = NSAlert()
        alert.messageText = "诊断设置"
        alert.informativeText = "自动发现会读取macOS系统代理、登录环境变量和常见本地端口。发现失败时才使用备用地址。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        let auto = NSButton(checkboxWithTitle: "自动发现本机HTTP代理（推荐）", target: nil, action: nil)
        auto.state = settings.autoDetectProxy ? .on : .off
        let host = NSTextField(string: settings.proxyHost)
        let port = NSTextField(string: String(settings.proxyPort))
        let interval = NSTextField(string: String(settings.checkIntervalMinutes))
        stack.addArrangedSubview(auto)
        stack.addArrangedSubview(settingsRow(label: "备用代理地址", field: host))
        stack.addArrangedSubview(settingsRow(label: "备用HTTP端口", field: port))
        stack.addArrangedSubview(settingsRow(label: "自动检查间隔（分钟）", field: interval))
        let note = NSTextField(wrappingLabelWithString: "例如：Libcyber Desktop的HTTP代理为127.0.0.1:8890。关闭自动发现后，将始终使用上述备用配置。")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(note)
        stack.frame = NSRect(x: 0, y: 0, width: 390, height: 168)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let candidateHost = host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "127.0.0.1" : host.stringValue
        guard let candidatePort = Int(port.stringValue),
              let validated = try? ProxyValidator.validate(host: candidateHost, port: candidatePort) else {
            showTransientAlert(title: "设置无效", message: "代理地址只能是本机地址，端口必须是1到65535之间的整数。")
            return
        }
        settings.autoDetectProxy = auto.state == .on
        settings.proxyHost = validated.host
        settings.proxyPort = validated.port
        settings.checkIntervalMinutes = max(Int(interval.stringValue) ?? 15, 1)
        SettingsStore.save(settings)
        scheduleTimer()
        runCheck()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.codex-proxy-env.plist")
    }

    private func launchCommand(proxy: ProxyConfiguration) -> String? {
        guard let value = try? ProxyValidator.proxyURL(host: proxy.host, port: proxy.port) else { return nil }
        return "osascript -e 'quit app \"Codex\"'; sleep 2; HTTP_PROXY=\(value) HTTPS_PROXY=\(value) ALL_PROXY=\(value) http_proxy=\(value) https_proxy=\(value) all_proxy=\(value) \"/Applications/Codex.app/Contents/MacOS/Codex\" --proxy-server=\"\(value)\""
    }

    private func endpointLine(named name: String, label: String, in report: DiagnosticReport) -> String {
        guard let endpoint = report.endpoints.first(where: { $0.name == name }) else { return "\(label)：无结果" }
        if let error = endpoint.error, !error.isEmpty { return "\(label)：连接失败" }
        return String(format: "%@：网络可达 · %.2fs", label, endpoint.duration)
    }

    private func endpointDetail(_ endpoint: EndpointResult) -> String {
        if let error = endpoint.error, !error.isEmpty {
            return "• \(endpoint.name)：连接失败"
        }
        let note = endpoint.cloudflareChallenge ? "，网络已连通；HTTP 403仅代表网页不接受命令行访问，不能据此判断Codex会重连" : ""
        return String(format: "• %@：HTTP %d，%.2f秒%@", endpoint.name, endpoint.statusCode, endpoint.duration, note)
    }

    private func updateRecoveryActions(_ report: DiagnosticReport?) {
        recoverySeparator.isHidden = true
        recoveryTitle.isHidden = true
        openProxyItem.isHidden = true
        restartCodexItem.isHidden = true
        enableForcedProxyItem.isHidden = true
        guard let report, report.level != .healthy else { return }

        recoverySeparator.isHidden = false
        recoveryTitle.isHidden = false
        if report.level == .warning && (!report.launchEnvironmentConfigured || report.persistentProxyConfigured != true) {
            enableForcedProxyItem.isHidden = false
            enableForcedProxyItem.isEnabled = !previewingScenario
            enableForcedProxyItem.title = report.persistentProxyConfigured == true
                ? "建议操作：重新启用登录级强制代理…"
                : "建议操作：启用登录级强制代理…"
            enableForcedProxyItem.toolTip = previewingScenario ? "测试模式只预览建议，不会写入登录配置。" : nil
        }
        if report.codexRunning && !report.codexUsesProxy && report.proxyPortListening {
            restartCodexItem.isHidden = false
            restartCodexItem.isEnabled = !previewingScenario
            restartCodexItem.toolTip = previewingScenario ? "测试模式只预览建议，不会退出或重启Codex。" : nil
            return
        }

        if !enableForcedProxyItem.isHidden { return }

        openProxyItem.isHidden = false
        openProxyItem.isEnabled = !previewingScenario
        openProxyItem.toolTip = previewingScenario ? "测试模式只预览建议，不会打开或修改代理客户端。" : nil
        if !report.proxyClientRunning {
            openProxyItem.title = "建议操作：打开代理客户端"
        } else if !report.proxyPortListening {
            openProxyItem.title = "建议操作：打开代理客户端检查HTTP端口"
        } else {
            openProxyItem.title = "建议操作：打开代理客户端并切换节点"
        }
    }

    private func historyStatus(_ level: HealthLevel) -> String {
        switch level {
        case .healthy: return "正常"
        case .warning: return "待确认"
        case .critical: return "需处理"
        case .unknown: return "未完成"
        }
    }

    private func forcedProxyStatus(_ report: DiagnosticReport) -> String {
        if report.persistentProxyConfigured == nil {
            return "登录级代理保障：旧版记录未检测"
        }
        if report.persistentProxyConfigured == true && report.launchEnvironmentConfigured {
            return "登录级代理保障：已启用"
        }
        if report.persistentProxyConfigured == true {
            return report.codexUsesProxy
                ? "登录级代理保障：配置存在但未加载（当前不影响连接）"
                : "登录级代理保障：配置存在但未加载"
        }
        if report.launchEnvironmentConfigured {
            return "登录级代理保障：本次会话已设置，登录后不会自动恢复"
        }
        return report.codexUsesProxy
            ? "登录级代理保障：未启用（当前不影响连接）"
            : "登录级代理保障：未启用"
    }

    private func historyPresentation(_ level: HealthLevel) -> (title: String, style: NSAlert.Style) {
        switch level {
        case .healthy: return ("✅ 检查正常", .informational)
        case .warning: return ("⚠️ 需要确认", .warning)
        case .critical: return ("❌ 发现连接问题", .critical)
        case .unknown: return ("❓ 检查未完成", .warning)
        }
    }

    private func settingsRow(label: String, field: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.widthAnchor.constraint(equalToConstant: 150).isActive = true
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        row.addArrangedSubview(title)
        row.addArrangedSubview(field)
        return row
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
              var value = try? JSONDecoder().decode(StoredSettings.self, from: data),
              let validated = try? ProxyValidator.validate(host: value.proxyHost, port: value.proxyPort) else { return StoredSettings() }
        value.proxyHost = validated.host
        value.proxyPort = validated.port
        value.checkIntervalMinutes = max(value.checkIntervalMinutes, 1)
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
