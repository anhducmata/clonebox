import AppKit

public enum Cloner {
    static let fm = FileManager.default
    static let chromiumFrameworks = ["Google Chrome Framework", "Chromium Framework", "Microsoft Edge Framework",
                                     "Brave Browser Framework", "Vivaldi Framework"]

    // MARK: Inspect

    /// Reads an app and decides whether it can be cloned. Throws a readable reason when it cannot.
    public static func inspect(_ url: URL) throws -> AppInfo {
        let url = url.resolvingSymlinksInPath()
        guard url.pathExtension == "app",
              let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              let executable = plist["CFBundleExecutable"] as? String
        else { throw CloneError("\(url.lastPathComponent) is not a macOS app.") }

        let name = url.deletingPathExtension().lastPathComponent
        if fm.fileExists(atPath: url.appendingPathComponent(Paths.configRelative).path) {
            throw CloneError("\(name) is already a clone. Drop the original app instead.")
        }
        let frameworks = (try? fm.contentsOfDirectory(atPath: url.appendingPathComponent("Contents/Frameworks").path)) ?? []
        let supported = frameworks.contains("Electron Framework.framework")
            || frameworks.contains { item in chromiumFrameworks.contains { item == "\($0).framework" } }
        guard supported else {
            throw CloneError("\(name) cannot be cloned. Only Electron and Chromium apps (Claude, Slack, Notion, Postman, Chrome…) "
                + "keep their login in a folder that can be switched. Native and App Store apps do not.")
        }
        let schemes = ((plist["CFBundleURLTypes"] as? [[String: Any]]) ?? [])
            .flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        let version = "\(plist["CFBundleShortVersionString"] as? String ?? "?") (\(plist["CFBundleVersion"] as? String ?? "?"))"
        return AppInfo(url: url, name: name, bundleID: bundleID, version: version, executable: executable, schemes: schemes)
    }

    // MARK: List

    public static func list() -> [Clone] {
        let items = (try? fm.contentsOfDirectory(at: Paths.clonesDir, includingPropertiesForKeys: nil)) ?? []
        return items.compactMap { url -> Clone? in
            guard url.pathExtension == "app", !url.lastPathComponent.hasPrefix("."),
                  let data = try? Data(contentsOf: url.appendingPathComponent(Paths.configRelative)),
                  let config = try? JSONDecoder().decode(CloneConfig.self, from: data) else { return nil }
            return Clone(url: url, config: config)
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public static func find(_ slug: String) throws -> Clone {
        guard let clone = list().first(where: { $0.config.slug == slug }) else { throw CloneError("No clone named \(slug).") }
        return clone
    }

    // MARK: Create / rebuild

    public static func create(from source: AppInfo, profile: String, colorHex: String = "7C5CFF",
                              env: [String: String] = [:]) throws -> Clone {
        let profile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = slugify("\(source.name)-\(profile)")
        guard !profile.isEmpty, !slugify(profile).isEmpty else { throw CloneError("Give the profile a name, for example Work.") }
        guard !profile.contains("/"), !profile.contains(":") else { throw CloneError("The profile name cannot contain / or :") }
        let dest = Paths.clonesDir.appendingPathComponent("\(source.name) \(profile).app")
        if fm.fileExists(atPath: dest.path) || list().contains(where: { $0.config.slug == slug }) {
            throw CloneError("\(source.name) \(profile) already exists.")
        }
        let config = CloneConfig(
            slug: slug, name: profile, appName: source.name, sourceApp: source.url.path,
            sourceBundleID: source.bundleID, sourceVersion: source.version, realExecutable: source.executable,
            bundleID: "local.clonebox.\(slug)", dataDir: Paths.dataRoot.appendingPathComponent("\(slug)/data").path,
            env: env, extraArgs: ["--use-mock-keychain"], schemes: source.schemes,
            managerPath: managerPath(), colorHex: colorHex)
        try build(source: source, config: config, dest: dest)
        return Clone(url: dest, config: config)
    }

    /// Rebuilds a clone from the current version of the original app. Data and login stay.
    public static func rebuild(_ clone: Clone) throws -> Clone {
        let source = try inspect(URL(fileURLWithPath: clone.config.sourceApp))
        var config = clone.config
        config.sourceVersion = source.version
        config.realExecutable = source.executable
        config.schemes = source.schemes
        config.managerPath = managerPath()
        try build(source: source, config: config, dest: clone.url)
        return Clone(url: clone.url, config: config)
    }

    static func managerPath() -> String {
        Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    }

    static func launcherBinary() throws -> URL {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("clonebox-launcher"),
            Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("clonebox-launcher"),
        ].compactMap { $0 }
        guard let found = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) else {
            throw CloneError("clonebox-launcher is missing from the CloneBox app.")
        }
        return found
    }

    static func build(source: AppInfo, config: CloneConfig, dest: URL) throws {
        let launcher = try launcherBinary()
        let parent = dest.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let tmp = parent.appendingPathComponent(".clonebox-\(config.slug).tmp.app")
        let old = parent.appendingPathComponent(".clonebox-\(config.slug).old.app")
        try? fm.removeItem(at: tmp)
        try? fm.removeItem(at: old)
        let previousHandlers = Dictionary(uniqueKeysWithValues: source.schemes.map { ($0, LinkRouter.handler(for: $0)) })

        do {
            // 1. Copy-on-write copy: shares disk blocks with the original on APFS.
            try sh("/bin/cp", ["-Rc", source.url.path, tmp.path])
            _ = try? sh("/usr/bin/xattr", ["-cr", tmp.path])

            // 2. New identity.
            let plistURL = tmp.appendingPathComponent("Contents/Info.plist")
            guard let plist = NSMutableDictionary(contentsOf: plistURL) else { throw CloneError("Cannot read Info.plist of the copy.") }
            let display = "\(config.appName) \(config.name)"
            plist["CFBundleIdentifier"] = config.bundleID
            // CFBundleName stays: Electron uses it to find "<name> Helper.app" and crashes if it changes.
            plist["CFBundleDisplayName"] = display
            plist["CFBundleExecutable"] = "clonebox-launcher"
            plist["CFBundleIconFile"] = "clonebox"
            plist.removeObject(forKey: "CFBundleIconName")
            try plist.write(to: plistURL)

            // Localised names would override the new name.
            let resources = tmp.appendingPathComponent("Contents/Resources")
            for item in (try? fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? [] where item.pathExtension == "lproj" {
                try? fm.removeItem(at: item.appendingPathComponent("InfoPlist.strings"))
            }

            // 3. Icon, launcher, config.
            try IconMaker.writeBadgedIcon(forApp: source.url, letter: String(config.name.prefix(1)).uppercased(),
                                          colorHex: config.colorHex, to: resources.appendingPathComponent("clonebox.icns"))
            try fm.copyItem(at: launcher, to: tmp.appendingPathComponent("Contents/MacOS/clonebox-launcher"))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: tmp.appendingPathComponent(Paths.configRelative))

            // 4. Ad-hoc sign, inside-out (never --deep: it breaks Electron helper apps).
            try sign(tmp, realExecutable: config.realExecutable)

            // 5. Swap into place.
            if fm.fileExists(atPath: dest.path) { try fm.moveItem(at: dest, to: old) }
            try fm.moveItem(at: tmp, to: dest)
            try? fm.removeItem(at: old)
        } catch {
            try? fm.removeItem(at: tmp)
            if !fm.fileExists(atPath: dest.path), fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: dest) }
            throw error
        }

        _ = try? sh("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", dest.path])
        // The clone declares the same link schemes; keep links going where they went before.
        for (scheme, handler) in previousHandlers {
            if let handler, handler.path != dest.path { LinkRouter.route([scheme], to: handler) }
        }
    }

    static func sign(_ app: URL, realExecutable: String) throws {
        let codesign = "/usr/bin/codesign"
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        for item in (try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [] where item.pathExtension == "app" {
            try sh(codesign, ["--force", "--sign", "-", item.path])
        }
        try sh(codesign, ["--force", "--sign", "-", app.appendingPathComponent("Contents/MacOS/\(realExecutable)").path])
        try sh(codesign, ["--force", "--sign", "-", app.path])
    }

    // MARK: Open / delete

    public static func open(_ clone: Clone) {
        NSWorkspace.shared.openApplication(at: clone.url, configuration: NSWorkspace.OpenConfiguration())
    }

    public static func isRunning(_ clone: Clone) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: clone.config.bundleID).isEmpty
    }

    /// Moves the clone to the Trash. The data folder (the login) goes too only when asked.
    public static func delete(_ clone: Clone, alsoData: Bool) throws {
        if isRunning(clone) { throw CloneError("Quit \(clone.displayName) first.") }
        if let original = try? inspect(URL(fileURLWithPath: clone.config.sourceApp)) {
            let mine = clone.config.schemes.filter { LinkRouter.handler(for: $0)?.path == clone.url.path }
            if !mine.isEmpty { LinkRouter.route(mine, to: original.url) }
        }
        try fm.trashItem(at: clone.url, resultingItemURL: nil)
        if alsoData {
            let dir = URL(fileURLWithPath: clone.config.dataDir).deletingLastPathComponent()
            if fm.fileExists(atPath: dir.path) { try fm.trashItem(at: dir, resultingItemURL: nil) }
        }
    }
}

/// Decides which app receives link callbacks such as claude:// (used by browser sign-in).
public enum LinkRouter {
    public static func handler(for scheme: String) -> URL? {
        guard let url = URL(string: "\(scheme)://clonebox") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    public static func route(_ schemes: [String], to app: URL) {
        for scheme in schemes {
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { _ in done.signal() }
            _ = done.wait(timeout: .now() + 5)
        }
    }

    public static func ownsLinks(_ clone: Clone) -> Bool {
        guard let first = clone.config.schemes.first else { return false }
        return handler(for: first)?.path == clone.url.path
    }
}
