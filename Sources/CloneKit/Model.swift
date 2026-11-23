import Foundation

/// Stored inside each clone at Contents/Resources/clonebox.json. Read by the launcher.
public struct CloneConfig: Codable, Equatable {
    public var slug: String
    public var name: String            // profile name, e.g. "Work"
    public var appName: String         // original app name, e.g. "Claude"
    public var sourceApp: String       // path of the original .app
    public var sourceBundleID: String
    public var sourceVersion: String
    public var realExecutable: String  // original executable name inside Contents/MacOS
    public var bundleID: String
    public var dataDir: String
    public var env: [String: String]
    public var extraArgs: [String]
    public var schemes: [String]
    public var managerPath: String
    public var colorHex: String
}

public struct Clone: Identifiable, Equatable {
    public let url: URL
    public let config: CloneConfig
    public var id: String { config.slug }
    public var displayName: String { "\(config.appName) \(config.name)" }
}

public struct AppInfo: Equatable {
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let executable: String
    public let schemes: [String]
}

public struct CloneError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Paths {
    public static let configRelative = "Contents/Resources/clonebox.json"
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var clonesDir: URL { home.appendingPathComponent("Applications") }
    public static var dataRoot: URL { home.appendingPathComponent("Library/Application Support/CloneBox") }
}

public func slugify(_ text: String) -> String {
    let lowered = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
    return String(lowered).split(separator: "-").joined(separator: "-")
}

@discardableResult
func sh(_ tool: String, _ args: [String]) throws -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: tool)
    task.arguments = args
    let out = Pipe(), err = Pipe()
    task.standardOutput = out
    task.standardError = err
    try task.run()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let output = String(data: outData, encoding: .utf8) ?? ""
    if task.terminationStatus != 0 {
        let detail = String(data: errData, encoding: .utf8) ?? ""
        throw CloneError("\((tool as NSString).lastPathComponent) failed: \(detail.isEmpty ? output : detail)")
    }
    return output
}
