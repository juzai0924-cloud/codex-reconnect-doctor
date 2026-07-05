import Foundation

struct CodexNetworkLogScan {
    let errorCount: Int
    let windowSeconds: Int
}

enum CodexNetworkLogScanner {
    private static let errorMarkers = [
        "errorMessage=net::ERR_CONNECTION_TIMED_OUT",
        "errorMessage=net::ERR_PROXY_CONNECTION_FAILED",
        "errorMessage=net::ERR_TUNNEL_CONNECTION_FAILED",
        "errorMessage=net::ERR_INTERNET_DISCONNECTED"
    ]

    static func scan(now: Date = Date(), windowSeconds: Int = 180) -> CodexNetworkLogScan {
        guard let logURL = newestLogFile(),
              let text = readTail(of: logURL, maximumBytes: 1_500_000) else {
            return CodexNetworkLogScan(errorCount: 0, windowSeconds: windowSeconds)
        }
        return CodexNetworkLogScan(
            errorCount: countNetworkErrors(in: text, now: now, windowSeconds: windowSeconds),
            windowSeconds: windowSeconds
        )
    }

    static func countNetworkErrors(in text: String, now: Date, windowSeconds: Int) -> Int {
        let lowerBound = now.addingTimeInterval(-TimeInterval(windowSeconds))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return text.split(separator: "\n", omittingEmptySubsequences: true).reduce(into: 0) { count, rawLine in
            guard errorMarkers.contains(where: { rawLine.contains($0) }),
                  let timestamp = rawLine.split(separator: " ", maxSplits: 1).first,
                  let date = formatter.date(from: String(timestamp)),
                  date >= lowerBound,
                  date <= now.addingTimeInterval(5) else { return }
            count += 1
        }
    }

    private static func newestLogFile() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/com.openai.codex", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "log" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if newest == nil || date > newest!.date { newest = (url, date) }
        }
        return newest?.url
    }

    private static func readTail(of url: URL, maximumBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > maximumBytes ? end - maximumBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
