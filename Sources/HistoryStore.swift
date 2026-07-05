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
        return reports
    }

    func append(_ report: DiagnosticReport) {
        var reports = load()
        reports.insert(report, at: 0)
        reports = Array(reports.prefix(30))
        if let data = try? JSONEncoder().encode(reports) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

