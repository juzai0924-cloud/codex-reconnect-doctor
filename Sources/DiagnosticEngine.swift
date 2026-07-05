import Foundation

enum DiagnosticScenario: CaseIterable {
    case noProxy
    case proxyClientStopped
    case proxyPortClosed
    case nodeOffline
    case partialServiceFailure
    case highLatency
    case codexNotUsingProxy
    case forcedProxyInactive
    case webChallengeButReachable
    case healthy

    var title: String {
        switch self {
        case .noProxy: return "未发现代理配置"
        case .proxyClientStopped: return "代理客户端未启动"
        case .proxyPortClosed: return "HTTP代理端口未监听"
        case .nodeOffline: return "代理节点无法联网"
        case .partialServiceFailure: return "部分OpenAI服务不可达"
        case .highLatency: return "连接延迟过高"
        case .codexNotUsingProxy: return "Codex未连接代理"
        case .forcedProxyInactive: return "登录级强制代理未生效"
        case .webChallengeButReachable: return "网页返回403但网络可达"
        case .healthy: return "全部正常"
        }
    }

    var expectedLevel: HealthLevel {
        switch self {
        case .noProxy: return .unknown
        case .proxyClientStopped, .proxyPortClosed, .nodeOffline, .partialServiceFailure: return .critical
        case .highLatency, .codexNotUsingProxy: return .warning
        case .forcedProxyInactive, .webChallengeButReachable, .healthy: return .healthy
        }
    }
}

final class DiagnosticEngine {
    private let settings: StoredSettings

    init(settings: StoredSettings) {
        self.settings = settings
    }

    func run() -> DiagnosticReport {
        let proxy = detectProxy()
        let clientRunning = isProxyClientRunning()
        let portListening = proxy.map { isPortListening(host: $0.host, port: $0.port) } ?? false
        let codexUsesProxy = proxy.map { codexConnectedToProxy(port: $0.port) } ?? false
        let codexRunning = isCodexRunning() || codexUsesProxy
        let launchEnvironmentConfigured = proxy.map { proxyEnvironmentMatches($0) } ?? false
        let persistentProxyConfigured = proxy.map { persistentProxyMatches($0) } ?? false
        let endpoints = proxy.map { checkEndpoints(proxy: $0) } ?? []

        let diagnosis = classify(
            proxy: proxy,
            clientRunning: clientRunning,
            portListening: portListening,
            codexRunning: codexRunning,
            codexUsesProxy: codexUsesProxy,
            endpoints: endpoints
        )

        return DiagnosticReport(
            checkedAt: Date(),
            level: diagnosis.level,
            summary: diagnosis.summary,
            recommendation: diagnosis.recommendation,
            proxy: proxy,
            proxyClientRunning: clientRunning,
            proxyPortListening: portListening,
            codexRunning: codexRunning,
            codexUsesProxy: codexUsesProxy,
            launchEnvironmentConfigured: launchEnvironmentConfigured,
            persistentProxyConfigured: persistentProxyConfigured,
            endpoints: endpoints
        )
    }

    static func previewReport(for scenario: DiagnosticScenario) -> DiagnosticReport {
        let proxy = ProxyConfiguration(host: "127.0.0.1", port: 8890, source: "测试数据")
        let reachable = [
            EndpointResult(name: "OpenAI API", url: "https://api.openai.com/v1/models", statusCode: 401, duration: 0.42, cloudflareChallenge: false, error: nil),
            EndpointResult(name: "ChatGPT", url: "https://chatgpt.com", statusCode: 200, duration: 0.36, cloudflareChallenge: false, error: nil),
            EndpointResult(name: "OpenAI Auth", url: "https://auth.openai.com", statusCode: 200, duration: 0.31, cloudflareChallenge: false, error: nil)
        ]

        var selectedProxy: ProxyConfiguration? = proxy
        var clientRunning = true
        var portListening = true
        let codexRunning = true
        var codexUsesProxy = true
        var launchEnvironmentConfigured = true
        var persistentProxyConfigured = true
        var endpoints = reachable

        switch scenario {
        case .noProxy:
            selectedProxy = nil
            clientRunning = false
            portListening = false
            codexUsesProxy = false
            endpoints = []
        case .proxyClientStopped:
            clientRunning = false
            portListening = false
            codexUsesProxy = false
            endpoints = []
        case .proxyPortClosed:
            portListening = false
            codexUsesProxy = false
            endpoints = []
        case .nodeOffline:
            codexUsesProxy = false
            endpoints = unreachableEndpoints()
        case .partialServiceFailure:
            endpoints[2] = EndpointResult(name: "OpenAI Auth", url: "https://auth.openai.com", statusCode: 0, duration: 4, cloudflareChallenge: false, error: "模拟连接超时")
        case .highLatency:
            endpoints = reachable.map {
                EndpointResult(name: $0.name, url: $0.url, statusCode: $0.statusCode, duration: 4.2, cloudflareChallenge: false, error: nil)
            }
        case .codexNotUsingProxy:
            codexUsesProxy = false
        case .forcedProxyInactive:
            launchEnvironmentConfigured = false
            persistentProxyConfigured = false
        case .webChallengeButReachable:
            endpoints[1] = EndpointResult(name: "ChatGPT", url: "https://chatgpt.com", statusCode: 403, duration: 0.36, cloudflareChallenge: true, error: nil)
            endpoints[2] = EndpointResult(name: "OpenAI Auth", url: "https://auth.openai.com", statusCode: 403, duration: 0.31, cloudflareChallenge: true, error: nil)
        case .healthy:
            break
        }

        let engine = DiagnosticEngine(settings: StoredSettings())
        let diagnosis = engine.classify(
            proxy: selectedProxy,
            clientRunning: clientRunning,
            portListening: portListening,
            codexRunning: codexRunning,
            codexUsesProxy: codexUsesProxy,
            endpoints: endpoints
        )
        return DiagnosticReport(
            checkedAt: Date(),
            level: diagnosis.level,
            summary: diagnosis.summary,
            recommendation: diagnosis.recommendation,
            proxy: selectedProxy,
            proxyClientRunning: clientRunning,
            proxyPortListening: portListening,
            codexRunning: codexRunning,
            codexUsesProxy: codexUsesProxy,
            launchEnvironmentConfigured: launchEnvironmentConfigured,
            persistentProxyConfigured: persistentProxyConfigured,
            endpoints: endpoints
        )
    }

    private static func unreachableEndpoints() -> [EndpointResult] {
        [
            EndpointResult(name: "OpenAI API", url: "https://api.openai.com/v1/models", statusCode: 0, duration: 4, cloudflareChallenge: false, error: "模拟连接超时"),
            EndpointResult(name: "ChatGPT", url: "https://chatgpt.com", statusCode: 0, duration: 4, cloudflareChallenge: false, error: "模拟连接超时"),
            EndpointResult(name: "OpenAI Auth", url: "https://auth.openai.com", statusCode: 0, duration: 4, cloudflareChallenge: false, error: "模拟连接超时")
        ]
    }

    private func detectProxy() -> ProxyConfiguration? {
        if settings.autoDetectProxy {
            if let systemProxy = detectSystemHTTPProxy() { return systemProxy }
            if let environmentProxy = detectLaunchEnvironmentProxy() { return environmentProxy }
            if isPortListening(host: settings.proxyHost, port: settings.proxyPort) {
                return ProxyConfiguration(host: settings.proxyHost, port: settings.proxyPort, source: "默认端口")
            }
            for port in [7890, 8890, 8080, 1080, 1087] where port != settings.proxyPort {
                if isPortListening(host: "127.0.0.1", port: port) {
                    return ProxyConfiguration(host: "127.0.0.1", port: port, source: "自动发现")
                }
            }
        }
        return ProxyConfiguration(
            host: settings.proxyHost,
            port: settings.proxyPort,
            source: settings.autoDetectProxy ? "备用设置" : "手动设置"
        )
    }

    private func detectSystemHTTPProxy() -> ProxyConfiguration? {
        let result = Shell.run("/usr/sbin/scutil", ["--proxy"])
        guard result.exitCode == 0 else { return nil }
        let host = capture(#"HTTPProxy\s*:\s*([^\s]+)"#, in: result.output)
        let portText = capture(#"HTTPPort\s*:\s*(\d+)"#, in: result.output)
        let enabled = capture(#"HTTPEnable\s*:\s*(\d+)"#, in: result.output)
        guard enabled == "1", let host, let portText, let port = Int(portText),
              let validated = try? ProxyValidator.validate(host: host, port: port) else { return nil }
        return ProxyConfiguration(host: validated.host, port: validated.port, source: "macOS系统代理")
    }

    private func detectLaunchEnvironmentProxy() -> ProxyConfiguration? {
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"] {
            let result = Shell.run("/bin/launchctl", ["getenv", key])
            let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = parseProxyURL(value) {
                return ProxyConfiguration(host: parsed.host, port: parsed.port, source: "登录环境变量")
            }
        }
        return nil
    }

    private func parseProxyURL(_ value: String) -> (host: String, port: Int)? {
        guard !value.isEmpty else { return nil }
        let normalized = value.contains("://") ? value : "http://\(value)"
        guard let components = URLComponents(string: normalized),
              let host = components.host,
              let port = components.port,
              let validated = try? ProxyValidator.validate(host: host, port: port) else { return nil }
        return validated
    }

    private func isProxyClientRunning() -> Bool {
        let result = Shell.run("/usr/bin/pgrep", ["-ifl", "libcyber|shadowrocket|clash|mihomo|surge"])
        return result.exitCode == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isPortListening(host: String, port: Int) -> Bool {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP@\(host):\(port)", "-sTCP:LISTEN"])
        if result.exitCode == 0 && !result.output.isEmpty { return true }
        let fallback = Shell.run("/usr/bin/nc", ["-z", "-G", "1", host, String(port)], timeout: 2)
        return fallback.exitCode == 0
    }

    private func isCodexRunning() -> Bool {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-c", "Codex"])
        return result.output.split(separator: "\n").dropFirst().contains { line in
            line.hasPrefix("Codex ") || line.hasPrefix("Codex\\x20")
        }
    }

    private func codexConnectedToProxy(port: Int) -> Bool {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-a", "-c", "Codex", "-iTCP@127.0.0.1:\(port)"])
        return result.exitCode == 0 && result.output.contains("ESTABLISHED")
    }

    private func proxyEnvironmentMatches(_ proxy: ProxyConfiguration) -> Bool {
        let expected = "\(proxy.host):\(proxy.port)"
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            let value = Shell.run("/bin/launchctl", ["getenv", key]).output
            if !value.contains(expected) { return false }
        }
        return true
    }

    private func persistentProxyMatches(_ proxy: ProxyConfiguration) -> Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.codex-proxy-env.plist")
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any],
              dictionary["Label"] as? String == "com.local.codex-proxy-env",
              dictionary["RunAtLoad"] as? Bool == true,
              let arguments = dictionary["ProgramArguments"] as? [String],
              arguments.count == 3,
              arguments[0].hasSuffix("/Contents/Helpers/CodexProxyEnvironmentHelper"),
              let port = Int(arguments[2]),
              let configured = try? ProxyValidator.validate(host: arguments[1], port: port),
              let expected = try? ProxyValidator.validate(host: proxy.host, port: proxy.port) else { return false }
        return configured.host == expected.host && configured.port == expected.port
    }

    private func checkEndpoints(proxy: ProxyConfiguration) -> [EndpointResult] {
        let targets = [
            ("OpenAI API", "https://api.openai.com/v1/models"),
            ("ChatGPT", "https://chatgpt.com"),
            ("OpenAI Auth", "https://auth.openai.com")
        ]
        let lock = NSLock()
        let group = DispatchGroup()
        var results: [EndpointResult] = []

        for target in targets {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let value = self.checkEndpoint(name: target.0, url: target.1, proxy: proxy)
                lock.lock()
                results.append(value)
                lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 12)
        return targets.compactMap { target in results.first(where: { $0.name == target.0 }) }
    }

    private func checkEndpoint(name: String, url: String, proxy: ProxyConfiguration) -> EndpointResult {
        guard let proxyURL = try? ProxyValidator.proxyURL(host: proxy.host, port: proxy.port) else {
            return EndpointResult(name: name, url: url, statusCode: 0, duration: 0, cloudflareChallenge: false, error: "无效的本地代理配置")
        }
        let result = Shell.run("/usr/bin/curl", [
            "--silent", "--show-error", "--location", "--max-redirs", "2",
            "--connect-timeout", "4", "--max-time", "9",
            "--proxy", proxyURL, "--dump-header", "-", "--output", "/dev/null",
            "--write-out", "\n__DOCTOR__%{http_code}|%{time_total}", url
        ], timeout: 11)

        let marker = result.output.components(separatedBy: "__DOCTOR__").last ?? ""
        let values = marker.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        let code = values.first.flatMap { Int($0) } ?? 0
        let duration = values.count > 1 ? Double(values[1]) ?? 0 : 0
        let headers = result.output.lowercased()
        let challenge = code == 403 && (headers.contains("cf-mitigated: challenge") || headers.contains("server: cloudflare"))
        let error = result.exitCode == 0 ? nil : result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        return EndpointResult(name: name, url: url, statusCode: code, duration: duration, cloudflareChallenge: challenge, error: error?.isEmpty == true ? nil : error)
    }

    func classify(
        proxy: ProxyConfiguration?,
        clientRunning: Bool,
        portListening: Bool,
        codexRunning: Bool,
        codexUsesProxy: Bool,
        endpoints: [EndpointResult]
    ) -> (level: HealthLevel, summary: String, recommendation: String) {
        guard let proxy else {
            return (.unknown, "未发现本地代理配置", "请启动代理客户端，或在设置中填写本地HTTP代理端口。")
        }
        guard clientRunning || portListening else {
            return (.critical, "代理客户端可能未启动", "请启动代理客户端，然后重新检测。")
        }
        guard portListening else {
            return (.critical, "代理端口 \(proxy.host):\(proxy.port) 未监听", "请检查代理客户端显示的HTTP端口，或重新自动检测。")
        }
        if endpoints.isEmpty || endpoints.allSatisfy({ !$0.reachable }) {
            return (.critical, "代理节点无法完成外部连接", "请在代理客户端中更换节点后重新检测。")
        }
        if endpoints.contains(where: { !$0.reachable }) {
            return (.critical, "部分OpenAI服务不可达", "请检查当前节点和代理规则，确保OpenAI相关域名均走代理。")
        }
        if endpoints.contains(where: { $0.duration >= 3 }) {
            return (.warning, "链路可用，但响应速度较慢", "建议切换到延迟更低、更稳定的固定节点。")
        }
        if codexRunning && !codexUsesProxy {
            return (.warning, "服务可达，但未确认Codex连接到代理", "可以按代理方式重启Codex，再重新检测。")
        }
        if endpoints.contains(where: { $0.cloudflareChallenge }) {
            return (.healthy, "Codex网络链路可达", "当前连接正常，无需处理。")
        }
        return (.healthy, "Codex网络链路正常", "当前无需处理。")
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
