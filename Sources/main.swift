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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

