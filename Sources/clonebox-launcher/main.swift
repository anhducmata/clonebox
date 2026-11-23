// Main executable of every clone. Starts the real app binary (same bundle) with the
// clone's own data folder. Rebuilds the clone first when the original app was updated.
import Foundation

let bundle = Bundle.main.bundleURL
let configURL = bundle.appendingPathComponent("Contents/Resources/clonebox.json")

func loadConfig() -> [String: Any]? {
    guard let data = try? Data(contentsOf: configURL) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func log(_ message: String) {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CloneBox")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("launcher.log")
    let line = "\(Date()) [\(bundle.lastPathComponent)] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: file) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.write(to: file, atomically: true, encoding: .utf8)
    }
}

func version(ofApp path: String) -> String? {
    let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
    guard let dict = NSDictionary(contentsOf: plist) else { return nil }
    let short = dict["CFBundleShortVersionString"] as? String ?? "?"
    let build = dict["CFBundleVersion"] as? String ?? "?"
    return "\(short) (\(build))"
}

guard var config = loadConfig(),
      let slug = config["slug"] as? String,
      let dataDir = config["dataDir"] as? String,
      let realName = config["realExecutable"] as? String
else {
    log("missing or broken clonebox.json")
    exit(1)
}

// Follow updates of the original app.
if let source = config["sourceApp"] as? String,
   let built = config["sourceVersion"] as? String,
   let current = version(ofApp: source), current != built,
   let manager = config["managerPath"] as? String,
   FileManager.default.isExecutableFile(atPath: manager) {
    log("original is \(current), clone is \(built): rebuilding")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: manager)
    task.arguments = ["rebuild", slug]
    do {
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus == 0 { config = loadConfig() ?? config } else { log("rebuild failed (\(task.terminationStatus)), starting old clone") }
    } catch {
        log("could not start rebuild: \(error)")
    }
}

try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
for (key, value) in (config["env"] as? [String: String]) ?? [:] { setenv(key, value, 1) }

let real = bundle.appendingPathComponent("Contents/MacOS/\(realName)").path
var args = [real, "--user-data-dir=\(dataDir)"]
args += (config["extraArgs"] as? [String]) ?? []
args += CommandLine.arguments.dropFirst()

var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
cArgs.append(nil)
execv(real, &cArgs)
log("execv failed for \(real): \(String(cString: strerror(errno)))")
exit(1)
