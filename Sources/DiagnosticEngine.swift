import Foundation

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
            endpoints: endpoints
        )
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
        return ProxyConfiguration(host: settings.proxyHost, port: settings.proxyPort, source: "手动设置")
    }

    private func detectSystemHTTPProxy() -> ProxyConfiguration? {
        let result = Shell.run("/usr/sbin/scutil", ["--proxy"])
        guard result.exitCode == 0 else { return nil }
        let host = capture(#"HTTPProxy\s*:\s*([^\s]+)"#, in: result.output)
        let portText = capture(#"HTTPPort\s*:\s*(\d+)"#, in: result.output)
        let enabled = capture(#"HTTPEnable\s*:\s*(\d+)"#, in: result.output)
        guard enabled == "1", let host, let portText, let port = Int(portText) else { return nil }
        return ProxyConfiguration(host: host, port: port, source: "macOS系统代理")
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
              let port = components.port else { return nil }
        return (host, port)
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
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"] {
            let value = Shell.run("/bin/launchctl", ["getenv", key]).output
            if value.contains(expected) { return true }
        }
        return false
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
        let proxyURL = "http://\(proxy.host):\(proxy.port)"
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

    private func classify(
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
        if endpoints.contains(where: { $0.cloudflareChallenge }) {
            return (.critical, "ChatGPT/Auth链路受到Cloudflare挑战", "本地代理正常，但当前出口不适合Codex会话。请更换节点后重测。")
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
