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
