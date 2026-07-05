import Foundation

enum HealthLevel: String, Codable {
    case healthy
    case warning
    case critical
    case unknown
}

struct EndpointResult: Codable {
    let name: String
    let url: String
    let statusCode: Int
    let duration: Double
    let cloudflareChallenge: Bool
    let error: String?

    var reachable: Bool { statusCode > 0 && error == nil }
}

struct ProxyConfiguration: Codable {
    let host: String
    let port: Int
    let source: String
}

struct DiagnosticReport: Codable {
    let checkedAt: Date
    let level: HealthLevel
    let summary: String
    let recommendation: String
    let proxy: ProxyConfiguration?
    let proxyClientRunning: Bool
    let proxyPortListening: Bool
    let codexRunning: Bool
    let codexUsesProxy: Bool
    let launchEnvironmentConfigured: Bool
    let persistentProxyConfigured: Bool?
    let recentCodexNetworkErrorCount: Int?
    let codexLogWindowSeconds: Int?
    let endpoints: [EndpointResult]
}

struct StoredSettings: Codable {
    var proxyHost: String = "127.0.0.1"
    var proxyPort: Int = 8890
    var autoDetectProxy: Bool = true
    var checkIntervalMinutes: Int = 15
}
