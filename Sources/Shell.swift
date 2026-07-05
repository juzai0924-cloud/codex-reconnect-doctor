import Foundation

struct CommandResult {
    let output: String
    let error: String
    let exitCode: Int32
}

enum Shell {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return CommandResult(output: "", error: error.localizedDescription, exitCode: -1)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            output: String(data: outData, encoding: .utf8) ?? "",
            error: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

