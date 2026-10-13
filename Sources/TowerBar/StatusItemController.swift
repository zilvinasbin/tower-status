import AppKit
import Observation
import SwiftUI
import TowerCore

/// Owns the menu bar item and the panel it opens.
@MainActor
final class StatusItemController: NSObject {
    private let store: TowerStore
    private let ui = PanelState()
    private let launchAtLogin = LaunchAtLogin()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(store: TowerStore) {
        self.store = store
        super.init()
        // A fixed name lets macOS remember where the user ⌘-dragged the item.
        statusItem.autosaveName = "TowerStatusItem"

        let hosting = NSHostingController(rootView: PanelView(store: store, ui: ui, launchAtLogin: launchAtLogin))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
        }
        observeStore()
    }

    @objc private func toggle() {
        popover.isShown ? popover.performClose(nil) : show()
    }

    /// Opens the panel; `settings: true` opens it on the settings face.
    func show(settings: Bool = false) {
        guard let button = statusItem.button else { return }
        ui.showingSettings = settings
        store.touch()
        launchAtLogin.refresh()
        // The app is an accessory: activate it so the panel's text field takes typing.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Re-renders the button whenever the store changes.
    private func observeStore() {
        withObservationTracking {
            render(store.presentation)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func render(_ p: Presentation) {
        guard let button = statusItem.button else { return }
        button.image = Self.icon
        button.attributedTitle = Self.title(p)
        button.appearsDisabled = p.titleDimmed
        button.toolTip = (["Tower"] + p.messages).joined(separator: " — ")
    }

    private static let icon: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "Tower")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }()

    /// `1/3`, then an amber `⚠6` when items need you; `–` when not live.
    static func title(_ p: Presentation) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        guard !p.titleDimmed, let data = p.data, let slots = p.title.split(separator: " ").dropFirst().first else {
            return NSAttributedString(string: " –", attributes: [.font: font])
        }
        let title = NSMutableAttributedString(string: " \(slots)", attributes: [.font: font])
        if data.needsYouCount > 0 {
            title.append(NSAttributedString(string: "  ⚠\(data.needsYouCount)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .bold),
                .foregroundColor: NSColor.systemOrange,
            ]))
        }
        return title
    }
}
