import Foundation

enum ProxyValidationError: LocalizedError {
    case nonLocalHost
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .nonLocalHost:
            return "代理地址只能填写本机地址：127.0.0.1、localhost或::1。"
        case .invalidPort:
            return "代理端口必须是1到65535之间的整数。"
        }
    }
}

enum ProxyValidator {
    static func normalizedLocalHost(_ value: String) -> String? {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch host {
        case "127.0.0.1", "localhost": return "127.0.0.1"
        case "::1", "[::1]": return "::1"
        default: return nil
        }
    }

    static func validate(host: String, port: Int) throws -> (host: String, port: Int) {
        guard let normalizedHost = normalizedLocalHost(host) else {
            throw ProxyValidationError.nonLocalHost
        }
        guard (1...65535).contains(port) else {
            throw ProxyValidationError.invalidPort
        }
        return (normalizedHost, port)
    }

    static func proxyURL(host: String, port: Int) throws -> String {
        let validated = try validate(host: host, port: port)
        let formattedHost = validated.host == "::1" ? "[::1]" : validated.host
        return "http://\(formattedHost):\(validated.port)"
    }
}
