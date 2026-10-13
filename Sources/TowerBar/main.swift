import AppKit
import TowerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TowerStore(settings: Settings())
    private var controller: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsWindow = SettingsWindowController(store: store)
        self.settingsWindow = settingsWindow
        controller = StatusItemController(store: store, settingsWindow: settingsWindow)
        store.start()
        if store.settings.address == nil { settingsWindow.show() }
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

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--print"), i + 1 < args.count {
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
