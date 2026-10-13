import AppKit
import SwiftUI
import TowerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TowerStore(settings: Settings())
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(store: store)
        self.controller = controller
        store.start()
        if store.settings.address == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { controller.show(settings: true) }
        }
    }

    /// Opening the app again (Spotlight, Finder) opens the panel, so it stays
    /// reachable when a menu bar manager hides the status item.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return false
    }
}

/// `TowerBar --print <address>` polls once and prints the title and menu lines,
/// then exits. Handy for checking a Tower without clicking.
func printOnce(_ raw: String) async -> Int32 {
    guard let address = TowerAddress(raw) else {
        print("not an IP address:", raw)
        return 2
    }
    let outcome = await TowerClient().fetch(address)
    let state = PollState(hasAddress: true).applying(outcome, at: Date())
    let p = Presentation(state: state, now: Date())
    print("GET", address.feedURL.absoluteString, "→", outcome.summary)
    print("title:", p.title, p.titleDimmed ? "(dimmed)" : "")
    p.messages.forEach { print("!", $0) }
    if let d = p.data {
        let mark = { (l: Presentation.Line) in l.tone == .warning ? " [amber]" : "" }
        for l in [d.slots, d.needsYou] { print(l.text + mark(l)) }
        d.needsYouRows.forEach { print("    " + $0.text) }
        for l in [d.queue, d.host] { print(l.text + mark(l)) }
        print(d.agents.isEmpty ? "Running agents: none" : "Running agents:")
        d.agents.forEach { print("  " + $0.text + mark($0)) }
        if !d.warnings.isEmpty {
            print("Warnings")
            d.warnings.forEach { print("  " + $0) }
        }
    }
    return outcome == .offline ? 1 : 0
}

extension FetchOutcome {
    var summary: String {
        switch self {
        case .snapshot(let s): "200 schema \(s.schema.map(String.init) ?? "?")"
        case .unavailable: "503"
        case .misdirected: "421"
        case .httpStatus(let c): "\(c)"
        case .unreadable: "200 unreadable"
        case .offline: "offline"
        }
    }
}

/// `TowerBar --snapshot out.png <address> [settings]` polls once and renders the
/// panel to a PNG, for checking the design without clicking.
@MainActor
func snapshot(to path: String, address raw: String, settings: Bool) async -> Int32 {
    let defaults = UserDefaults(suiteName: "towerbar.snapshot")!
    defaults.set(raw, forKey: "towerAddress")
    let store = TowerStore(settings: Settings(defaults: defaults))
    await store.pollOnce()
    let ui = PanelState()
    ui.showingSettings = settings
    let view = PanelView(store: store, ui: ui, launchAtLogin: LaunchAtLogin())
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, ProcessInfo.processInfo.environment["DARK"] == nil ? .light : .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed")
        return 1
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote", path)
    return 0
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
    let path = args[i + 1], raw = args[i + 2]
    let settings = args.contains("settings")
    Task { @MainActor in
        exit(await snapshot(to: path, address: raw, settings: settings))
    }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--print"), i + 1 < args.count {
    let raw = args[i + 1]
    Task {
        exit(await printOnce(raw))
    }
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
