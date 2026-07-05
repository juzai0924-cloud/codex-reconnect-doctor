import Foundation

func normalizedLocalHost(_ value: String) -> String? {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "127.0.0.1", "localhost": return "127.0.0.1"
    case "::1", "[::1]": return "::1"
    default: return nil
    }
}

guard CommandLine.arguments.count == 3,
      let host = normalizedLocalHost(CommandLine.arguments[1]),
      let port = Int(CommandLine.arguments[2]),
      (1...65535).contains(port) else {
    fputs("Invalid local proxy configuration.\n", stderr)
    exit(2)
}

let formattedHost = host == "::1" ? "[::1]" : host
let value = "http://\(formattedHost):\(port)"
let environment = [
    "HTTP_PROXY": value,
    "HTTPS_PROXY": value,
    "ALL_PROXY": value,
    "http_proxy": value,
    "https_proxy": value,
    "all_proxy": value,
    "NO_PROXY": "localhost,127.0.0.1,::1",
    "no_proxy": "localhost,127.0.0.1,::1"
]

for (key, value) in environment {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["setenv", key, value]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
}
