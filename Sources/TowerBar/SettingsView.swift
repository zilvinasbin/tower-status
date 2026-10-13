import AppKit
import SwiftUI
import TowerCore

@MainActor
final class SettingsWindowController {
    private let store: TowerStore
    private let launchAtLogin = LaunchAtLogin()
    private var window: NSWindow?

    init(store: TowerStore) {
        self.store = store
    }

    func show() {
        launchAtLogin.refresh()
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store, launchAtLogin: launchAtLogin) { [weak self] in
                self?.window?.close()
            })
            let w = NSWindow(contentViewController: hosting)
            w.title = "Tower Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let store: TowerStore
    let launchAtLogin: LaunchAtLogin
    let close: () -> Void

    @State private var address = ""
    @State private var interval = Settings.defaultInterval
    @State private var notify = false

    private var parsed: TowerAddress? { TowerAddress(address) }
    private var addressInvalid: Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty && parsed == nil }

    var body: some View {
        Form {
            Section {
                TextField("Tower address", text: $address, prompt: Text("100.x.y.z or 100.x.y.z:8090"))
                    .onSubmit(save)
                if addressInvalid {
                    Text("Enter an IP address, optionally with :port.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text(parsed.map { "Polls \($0.feedURL.absoluteString)" }
                         ?? "Use Tower's Tailscale IP (100.x), not a host name.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: $interval, in: Settings.intervalRange) {
                    Text("Poll every \(interval) s")
                }
            }
            Section {
                Toggle("Notify when needs-you goes up", isOn: $notify)
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.needsApproval {
                    Button("Approve in System Settings…") { launchAtLogin.openSystemSettings() }
                } else if let error = launchAtLogin.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(addressInvalid)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear(perform: load)
    }

    private func load() {
        address = store.settings.addressText
        interval = store.settings.pollInterval
        notify = store.settings.notifyNeedsYou
    }

    private func save() {
        guard !addressInvalid else { return }
        let settings = store.settings
        let newAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressChanged = TowerAddress(newAddress) != settings.address
        let intervalChanged = interval != settings.pollInterval
        if notify && !settings.notifyNeedsYou { TowerStore.requestNotificationPermission() }

        settings.addressText = newAddress
        settings.pollInterval = Settings.clamp(interval)
        settings.notifyNeedsYou = notify
        if addressChanged {
            store.addressChanged()
        } else if intervalChanged {
            store.restart()
        }
        close()
    }
}
