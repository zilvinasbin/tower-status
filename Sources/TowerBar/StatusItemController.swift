import AppKit
import Observation
import TowerCore

/// Owns the menu bar item and rebuilds its menu from the store's `Presentation`.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: TowerStore
    private let settingsWindow: SettingsWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(store: TowerStore, settingsWindow: SettingsWindowController) {
        self.store = store
        self.settingsWindow = settingsWindow
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        observeStore()
    }

    /// Re-renders whenever the store changes.
    private func observeStore() {
        withObservationTracking {
            render(store.presentation)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        render(store.presentation)  // fresh ages
    }

    private func render(_ p: Presentation) {
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: p.title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
            button.appearsDisabled = p.titleDimmed
            button.toolTip = (["Tower"] + p.messages).joined(separator: " · ")
        }
        menu.removeAllItems()
        Self.build(p, into: menu, target: self)
    }

    static func build(_ p: Presentation, into menu: NSMenu, target: StatusItemController?) {
        for message in p.messages {
            menu.addItem(info(message, color: .systemOrange))
        }
        if !p.messages.isEmpty { menu.addItem(.separator()) }

        if let d = p.data {
            let dim = p.dataDimmed
            menu.addItem(line(d.slots, dimmed: dim))

            let needs = line(d.needsYou, dimmed: dim)
            if !d.needsYouRows.isEmpty {
                let sub = NSMenu()
                sub.autoenablesItems = false
                d.needsYouRows.forEach { sub.addItem(line($0, dimmed: dim)) }
                needs.submenu = sub
                needs.isEnabled = true
            }
            menu.addItem(needs)
            menu.addItem(line(d.queue, dimmed: dim))
            menu.addItem(line(d.host, dimmed: dim))

            menu.addItem(info(d.agents.isEmpty ? "Running agents: none" : "Running agents:", dimmed: dim))
            for agent in d.agents {
                let item = line(agent, dimmed: dim, indent: 1)
                if let url = agent.url, let target {
                    item.representedObject = url
                    item.target = target
                    item.action = #selector(openURL(_:))
                    item.isEnabled = true
                    item.toolTip = url.absoluteString
                }
                menu.addItem(item)
            }

            if !d.warnings.isEmpty {
                menu.addItem(.separator())
                menu.addItem(NSMenuItem.sectionHeader(title: "Warnings"))
                d.warnings.forEach { menu.addItem(info($0, color: .systemOrange, dimmed: dim)) }
            }
            menu.addItem(.separator())
        }

        let actions: [(String, Selector, String, Bool)] = [
            ("Open dashboard", #selector(openDashboard), "d", target?.store.settings.address != nil),
            ("Refresh now", #selector(refresh), "r", target?.store.settings.address != nil),
            ("Settings…", #selector(openSettings), ",", true),
        ]
        for (title, action, key, enabled) in actions {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// A read-only row. Disabled items keep the colour of their attributed title,
    /// so normal rows read as normal text and dimmed rows as secondary text.
    private static func info(_ text: String, color: NSColor = .labelColor, dimmed: Bool = false, indent: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: dimmed ? NSColor.tertiaryLabelColor : color,
            .font: NSFont.menuFont(ofSize: 0),
        ])
        item.indentationLevel = indent
        item.isEnabled = false
        return item
    }

    private static func line(_ line: Presentation.Line, dimmed: Bool, indent: Int = 0) -> NSMenuItem {
        info(line.text, color: line.tone == .warning ? .systemOrange : .labelColor, dimmed: dimmed, indent: indent)
    }

    // MARK: - Actions

    @objc private func openURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func openDashboard() {
        if let url = store.settings.address?.dashboardURL { NSWorkspace.shared.open(url) }
    }

    @objc private func refresh() {
        store.restart()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
