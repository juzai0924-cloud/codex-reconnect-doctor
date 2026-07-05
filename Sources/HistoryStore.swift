import Foundation

final class HistoryStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("CodexReconnectDoctor", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("history.json")
    }

    func load() -> [DiagnosticReport] {
        guard let data = try? Data(contentsOf: fileURL),
              let reports = try? JSONDecoder().decode([DiagnosticReport].self, from: data) else { return [] }
        return reports.map(Self.normalizeForDisplay)
    }

    func append(_ report: DiagnosticReport) {
        var reports = load()
        reports.insert(report, at: 0)
        reports = Array(reports.prefix(30))
        if let data = try? JSONEncoder().encode(reports) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func normalizeForDisplay(_ report: DiagnosticReport) -> DiagnosticReport {
        normalizeForcedProxyAdvisory(
            normalizeLegacyCloudflareResult(
                normalizeRecentCodexNetworkErrors(report)
            )
        )
    }

    private static func normalizeLegacyCloudflareResult(_ report: DiagnosticReport) -> DiagnosticReport {
        guard report.recentCodexNetworkErrorCount == nil,
              report.endpoints.contains(where: { $0.cloudflareChallenge }),
              report.endpoints.allSatisfy({ $0.reachable }) else { return report }

        let level: HealthLevel
        let summary: String
        let recommendation: String
        if report.endpoints.contains(where: { $0.duration >= 3 }) {
            level = .warning
            summary = "链路可用，但响应速度较慢"
            recommendation = "建议切换到延迟更低、更稳定的固定节点。"
        } else if report.codexRunning && !report.codexUsesProxy {
            level = .warning
            summary = "服务可达，但未确认Codex连接到代理"
            recommendation = "可以按代理方式重启Codex，再重新检测。"
        } else {
            level = .healthy
            summary = "Codex网络链路可达"
            recommendation = "当前连接正常，无需处理。"
        }
        return DiagnosticReport(
            checkedAt: report.checkedAt,
            level: level,
            summary: summary,
            recommendation: recommendation,
            proxy: report.proxy,
            proxyClientRunning: report.proxyClientRunning,
            proxyPortListening: report.proxyPortListening,
            codexRunning: report.codexRunning,
            codexUsesProxy: report.codexUsesProxy,
            launchEnvironmentConfigured: report.launchEnvironmentConfigured,
            persistentProxyConfigured: report.persistentProxyConfigured,
            recentCodexNetworkErrorCount: report.recentCodexNetworkErrorCount,
            codexLogWindowSeconds: report.codexLogWindowSeconds,
            endpoints: report.endpoints
        )
    }

    private static func normalizeRecentCodexNetworkErrors(_ report: DiagnosticReport) -> DiagnosticReport {
        guard (report.recentCodexNetworkErrorCount ?? 0) >= 2,
              report.level == .healthy else { return report }
        return DiagnosticReport(
            checkedAt: report.checkedAt,
            level: .critical,
            summary: "Codex近期网络连接异常",
            recommendation: "请先确认代理客户端已连接；如已连接，再检查或更换节点。",
            proxy: report.proxy,
            proxyClientRunning: report.proxyClientRunning,
            proxyPortListening: report.proxyPortListening,
            codexRunning: report.codexRunning,
            codexUsesProxy: report.codexUsesProxy,
            launchEnvironmentConfigured: report.launchEnvironmentConfigured,
            persistentProxyConfigured: report.persistentProxyConfigured,
            recentCodexNetworkErrorCount: report.recentCodexNetworkErrorCount,
            codexLogWindowSeconds: report.codexLogWindowSeconds,
            endpoints: report.endpoints
        )
    }

    private static func normalizeForcedProxyAdvisory(_ report: DiagnosticReport) -> DiagnosticReport {
        guard report.summary == "当前已走代理，但登录级强制代理未生效",
              report.codexUsesProxy,
              report.endpoints.allSatisfy({ $0.reachable }) else { return report }
        return DiagnosticReport(
            checkedAt: report.checkedAt,
            level: .healthy,
            summary: "Codex网络链路正常",
            recommendation: "当前无需处理。登录级代理保障未启用，不影响本次连接。",
            proxy: report.proxy,
            proxyClientRunning: report.proxyClientRunning,
            proxyPortListening: report.proxyPortListening,
            codexRunning: report.codexRunning,
            codexUsesProxy: report.codexUsesProxy,
            launchEnvironmentConfigured: report.launchEnvironmentConfigured,
            persistentProxyConfigured: report.persistentProxyConfigured,
            recentCodexNetworkErrorCount: report.recentCodexNetworkErrorCount,
            codexLogWindowSeconds: report.codexLogWindowSeconds,
            endpoints: report.endpoints
        )
    }
}
