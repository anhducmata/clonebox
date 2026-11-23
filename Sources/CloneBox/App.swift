import AppKit
import CloneKit
import SwiftUI
import UniformTypeIdentifiers

struct CloneBoxApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("CloneBox") {
            ContentView().environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var clones: [Clone] = []
    @Published var pending: AppInfo?
    @Published var message: String?
    @Published var isError = false
    @Published var busy: String?
    @Published var targeted = false
    @Published var confirmDelete: String?
    @Published var hovered: String?
    @Published var running: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        // Keep the "running" dots current.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunning() }
            })
        }
    }

    func refresh() {
        clones = Cloner.list()
        refreshRunning()
    }

    func refreshRunning() { running = Set(clones.filter(Cloner.isRunning).map(\.id)) }

    func say(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }

    func dropped(_ url: URL) {
        do {
            pending = try Cloner.inspect(url)
            message = nil
        } catch {
            say(error.localizedDescription, error: true)
        }
    }

    func run(_ label: String, done: String?, _ work: @escaping @Sendable () throws -> Void) {
        busy = label
        Task.detached {
            let result = Result { try work() }
            await MainActor.run {
                self.busy = nil
                self.refresh()
                switch result {
                case .success: if let done { self.say(done) }
                case .failure(let error): self.say(error.localizedDescription, error: true)
                }
            }
        }
    }

    func create(_ info: AppInfo, profile: String, colorHex: String, env: [String: String]) {
        pending = nil
        run("Cloning \(info.name)…", done: "\(info.name) \(profile) is ready. Close other \(info.name) windows before signing in.") {
            _ = try Cloner.create(from: info, profile: profile, colorHex: colorHex, env: env)
        }
    }
}


struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 12) {
            dropZone
            if let message = store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(store.isError ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.clones.isEmpty {
                VStack(spacing: 2) {
                    ForEach(store.clones) { CloneRow(clone: $0) }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .sheet(isPresented: Binding(get: { store.pending != nil }, set: { if !$0 { store.pending = nil } })) {
            if let info = store.pending { NewCloneSheet(info: info).environmentObject(store) }
        }
    }

    var dropZone: some View {
        HStack(spacing: 10) {
            if let busy = store.busy {
                ProgressView().controlSize(.small)
                Text(busy)
            } else {
                Image(systemName: "plus.square.on.square").font(.title2).foregroundStyle(.tint)
                Text("Drop an app to clone")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(store.targeted ? 0.15 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor.opacity(store.targeted ? 1 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: chooseApp)
        .help("Drop an app here, or click to choose one")
        .onDrop(of: [.fileURL], isTargeted: $store.targeted) { providers in
            guard store.busy == nil, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in store.dropped(url) } }
            }
            return true
        }
    }

    func chooseApp() {
        guard store.busy == nil else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url { store.dropped(url) }
    }
}

struct CloneRow: View {
    @EnvironmentObject var store: Store
    let clone: Clone

    var hovered: Bool { store.hovered == clone.id }
    var running: Bool { store.running.contains(clone.id) }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: clone.url.path)).resizable().frame(width: 24, height: 24)
            Text(clone.config.appName).foregroundColor(.secondary)
                + Text(" \(clone.config.name)").fontWeight(.medium)
            if running {
                Circle().fill(Color.green).frame(width: 6, height: 6).help("Running")
            }
            Spacer(minLength: 4)
            Menu { actions } label: {
                Image(systemName: "ellipsis").frame(width: 20, height: 20).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .opacity(hovered ? 1 : 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovered ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { Cloner.open(clone) }
        .onHover { inside in
            if inside { store.hovered = clone.id } else if store.hovered == clone.id { store.hovered = nil }
        }
        .contextMenu { actions }
        .help(running ? "Click to show \(clone.displayName)" : "Click to open \(clone.displayName)")
        .confirmationDialog("Move \(clone.displayName) to the Trash?",
                            isPresented: Binding(get: { store.confirmDelete == clone.id }, set: { if !$0 { store.confirmDelete = nil } })) {
            Button("Keep its login data") { delete(alsoData: false) }
            Button("Delete its login data too", role: .destructive) { delete(alsoData: true) }
        }
    }

    @ViewBuilder var actions: some View {
        Button(running ? "Show" : "Open") { Cloner.open(clone) }
        Divider()
        if !clone.config.schemes.isEmpty {
            Button("Send sign-in links here") { routeLinks(toClone: true) }
            Button("Send sign-in links to original") { routeLinks(toClone: false) }
            Divider()
        }
        Button("Rebuild") {
            store.run("Rebuilding…", done: "\(clone.displayName) rebuilt.") { [clone] in _ = try Cloner.rebuild(clone) }
        }
        Button("Show data folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: clone.config.dataDir) }
        Divider()
        Button("Move to Trash…", role: .destructive) { store.confirmDelete = clone.id }
    }

    func delete(alsoData: Bool) {
        let clone = clone
        store.run("Removing…", done: "\(clone.displayName) moved to the Trash.") {
            try Cloner.delete(clone, alsoData: alsoData)
        }
    }

    func routeLinks(toClone: Bool) {
        let target = toClone ? clone.url : URL(fileURLWithPath: clone.config.sourceApp)
        let name = toClone ? clone.displayName : clone.config.appName
        let schemes = clone.config.schemes
        store.run("Routing links…", done: "Sign-in links now open \(name).") {
            LinkRouter.route(schemes, to: target)
        }
    }
}

final class Draft: ObservableObject {
    @Published var profile = ""
    @Published var colorHex = "7C5CFF"
    @Published var separateClaudeCode = false
}

struct NewCloneSheet: View {
    @EnvironmentObject var store: Store
    let info: AppInfo
    @StateObject private var draft = Draft()
    static let colors = ["7C5CFF", "E5484D", "F5A524", "30A46C", "0091FF", "6F6E77"]

    var isClaude: Bool { info.bundleID == "com.anthropic.claudefordesktop" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: info.url.path)).resizable().frame(width: 28, height: 28)
                TextField("\(info.name) profile name", text: $draft.profile).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                ForEach(Self.colors, id: \.self) { hex in
                    Circle().fill(Color(nsColor: IconMaker.color(hex: hex))).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary, lineWidth: draft.colorHex == hex ? 1.5 : 0).padding(-3))
                        .onTapGesture { draft.colorHex = hex }
                }
                Spacer()
            }
            if isClaude {
                Toggle("Separate Claude Code login", isOn: $draft.separateClaudeCode)
                    .help("Uses ~/.claude-<profile> instead of ~/.claude")
            }
            HStack {
                Spacer()
                Button("Cancel") { store.pending = nil }.keyboardShortcut(.cancelAction)
                Button("Clone") {
                    let dir = "\(NSHomeDirectory())/.claude-\(slugify(draft.profile))"
                    let env = isClaude && draft.separateClaudeCode ? ["CLAUDE_CONFIG_DIR": dir] : [:]
                    store.create(info, profile: draft.profile, colorHex: draft.colorHex, env: env)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(slugify(draft.profile).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
