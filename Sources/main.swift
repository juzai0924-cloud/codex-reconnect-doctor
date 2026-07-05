import AppKit
import Foundation

if CommandLine.arguments.contains("--diagnose") {
    let report = DiagnosticEngine(settings: SettingsStore.load()).run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(report.level == .healthy ? 0 : 1)
}

if CommandLine.arguments.contains("--self-test") {
    var failures: [String] = []
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for scenario in DiagnosticScenario.allCases {
        let report = DiagnosticEngine.previewReport(for: scenario)
        if report.level != scenario.expectedLevel {
            failures.append("\(scenario.title)：预期\(scenario.expectedLevel.rawValue)，实际\(report.level.rawValue)")
        }
        if report.summary.isEmpty || report.recommendation.isEmpty {
            failures.append("\(scenario.title)：缺少结论或建议")
        }
        if let data = try? encoder.encode(report), (try? decoder.decode(DiagnosticReport.self, from: data)) == nil {
            failures.append("\(scenario.title)：诊断记录无法编码或解码")
        }
    }

    for host in ["127.0.0.1", "localhost", "::1", "[::1]"] {
        if (try? ProxyValidator.validate(host: host, port: 8890)) == nil {
            failures.append("合法本机地址被拒绝：\(host)")
        }
    }
    for host in ["example.com", "192.168.1.2", "127.0.0.1; touch /tmp/pwned", "$(id)", "`id`"] {
        if (try? ProxyValidator.validate(host: host, port: 8890)) != nil {
            failures.append("危险或远程地址未被拒绝：\(host)")
        }
    }
    for port in [-1, 0, 65536, 99999] {
        if (try? ProxyValidator.validate(host: "127.0.0.1", port: port)) != nil {
            failures.append("非法端口未被拒绝：\(port)")
        }
    }

    let logNow = ISO8601DateFormatter().date(from: "2026-07-05T12:42:00Z")!
    let logSample = """
    2026-07-05T12:38:59.000Z warning errorMessage=net::ERR_CONNECTION_TIMED_OUT
    2026-07-05T12:41:42.000Z warning errorMessage=net::ERR_CONNECTION_TIMED_OUT
    2026-07-05T12:41:51.000Z warning errorMessage=net::ERR_PROXY_CONNECTION_FAILED
    2026-07-05T12:41:53.000Z info conversation text without a technical error marker
    """
    let recentErrors = CodexNetworkLogScanner.countNetworkErrors(in: logSample, now: logNow, windowSeconds: 180)
    if recentErrors != 2 {
        failures.append("Codex日志时间窗口计数错误：预期2，实际\(recentErrors)")
    }
    let healthyReport = DiagnosticEngine.previewReport(for: .healthy)
    let recentFailureDiagnosis = DiagnosticEngine(settings: StoredSettings()).classify(
        proxy: healthyReport.proxy,
        clientRunning: true,
        portListening: true,
        codexRunning: true,
        codexUsesProxy: true,
        recentCodexNetworkErrorCount: 2,
        endpoints: healthyReport.endpoints
    )
    if recentFailureDiagnosis.level != .critical || recentFailureDiagnosis.summary != "Codex近期网络连接异常" {
        failures.append("Codex连续网络错误未覆盖短请求正常结果")
    }
    let challengeReport = DiagnosticEngine.previewReport(for: .webChallengeButReachable)
    let incorrectlyNormalizedHistory = DiagnosticReport(
        checkedAt: challengeReport.checkedAt,
        level: .healthy,
        summary: "Codex网络链路可达",
        recommendation: "当前连接正常，无需处理。",
        proxy: challengeReport.proxy,
        proxyClientRunning: challengeReport.proxyClientRunning,
        proxyPortListening: challengeReport.proxyPortListening,
        codexRunning: challengeReport.codexRunning,
        codexUsesProxy: challengeReport.codexUsesProxy,
        launchEnvironmentConfigured: challengeReport.launchEnvironmentConfigured,
        persistentProxyConfigured: challengeReport.persistentProxyConfigured,
        recentCodexNetworkErrorCount: 3,
        codexLogWindowSeconds: 180,
        endpoints: challengeReport.endpoints
    )
    if HistoryStore.normalizeForDisplay(incorrectlyNormalizedHistory).level != .critical {
        failures.append("Codex近期网络异常被Cloudflare历史兼容逻辑覆盖")
    }
    if let currentData = try? encoder.encode(healthyReport),
       var legacyObject = (try? JSONSerialization.jsonObject(with: currentData)) as? [String: Any] {
        legacyObject.removeValue(forKey: "recentCodexNetworkErrorCount")
        legacyObject.removeValue(forKey: "codexLogWindowSeconds")
        if let legacyData = try? JSONSerialization.data(withJSONObject: legacyObject),
           (try? decoder.decode(DiagnosticReport.self, from: legacyData)) == nil {
            failures.append("旧版诊断记录无法兼容解码")
        }
    }

    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexProxyEnvironmentHelper")
    if !FileManager.default.isExecutableFile(atPath: helper.path) {
        failures.append("登录级代理Helper缺失或不可执行")
    }

    if failures.isEmpty {
        print("PASS: \(DiagnosticScenario.allCases.count) diagnostic scenarios and proxy safety checks")
        exit(0)
    }
    failures.forEach { fputs("FAIL: \($0)\n", stderr) }
    exit(1)
}

if let bundleIdentifier = Bundle.main.bundleIdentifier {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first(where: { $0.processIdentifier != currentPID && !$0.isTerminated }) {
        existing.activate(options: [.activateIgnoringOtherApps])
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
