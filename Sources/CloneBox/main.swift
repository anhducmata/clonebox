import CloneKit
import Foundation

// No arguments: the window. With arguments: a small command line (also used by the launcher to rebuild).
let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn") }
guard let command = args.first, !command.hasPrefix("-") else {
    CloneBoxApp.main()
    exit(0)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("clonebox: \(message)\n".data(using: .utf8)!)
    exit(1)
}

do {
    switch command {
    case "inspect":
        guard args.count == 2 else { fail("usage: inspect <App.app>") }
        let info = try Cloner.inspect(URL(fileURLWithPath: args[1]))
        print("\(info.name)  \(info.bundleID)  \(info.version)  links: \(info.schemes.joined(separator: ","))")
    case "create":
        guard args.count >= 3 else { fail("usage: create <App.app> <profile> [colorHex]") }
        let info = try Cloner.inspect(URL(fileURLWithPath: args[1]))
        let clone = try Cloner.create(from: info, profile: args[2], colorHex: args.count > 3 ? args[3] : "7C5CFF")
        print("created \(clone.url.path)")
    case "list":
        for clone in Cloner.list() {
            print("\(clone.config.slug)\t\(clone.url.path)\t\(clone.config.sourceVersion)")
        }
    case "rebuild":
        guard args.count == 2 else { fail("usage: rebuild <slug>") }
        let clone = try Cloner.rebuild(try Cloner.find(args[1]))
        print("rebuilt \(clone.url.path) from \(clone.config.sourceVersion)")
    case "delete":
        guard args.count >= 2 else { fail("usage: delete <slug> [--data]") }
        try Cloner.delete(try Cloner.find(args[1]), alsoData: args.contains("--data"))
        print("moved to Trash")
    case "make-app-icon":
        guard args.count == 2 else { fail("usage: make-app-icon <out.icns>") }
        try IconMaker.writeAppIcon(to: URL(fileURLWithPath: args[1]))
    default:
        fail("unknown command \(command). Commands: inspect, create, list, rebuild, delete")
    }
} catch {
    fail(error.localizedDescription)
}
