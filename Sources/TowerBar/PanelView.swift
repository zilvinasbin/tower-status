import AppKit
import SwiftUI
import TowerCore

/// Colour carries meaning only: amber = needs you, teal = working,
/// red = blocked or over a limit, grey = idle.
enum Palette {
    static let attention = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.98, green: 0.71, blue: 0.27, alpha: 1) : NSColor(srgbRed: 0.80, green: 0.50, blue: 0.05, alpha: 1) })
    static let working = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(srgbRed: 0.35, green: 0.78, blue: 0.80, alpha: 1) : NSColor(srgbRed: 0.05, green: 0.52, blue: 0.56, alpha: 1) })
    static let danger = Color(nsColor: .systemRed)
    static let idle = Color.secondary

    static func tone(_ t: Panel.AgentTone) -> Color {
        switch t {
        case .working: working
        case .waiting: attention
        case .blocked: danger
        case .idle: idle
        }
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// Which face of the popover is showing.
@MainActor @Observable
final class PanelState {
    var showingSettings = false
    var showAllNeedsYou = false
}

struct PanelView: View {
    let store: TowerStore
    let ui: PanelState
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Group {
            if ui.showingSettings {
                SettingsPane(store: store, launchAtLogin: launchAtLogin) { ui.showingSettings = false }
            } else {
                StatusPane(store: store, ui: ui)
            }
        }
        .frame(width: 348)
    }
}

// MARK: - Status

private struct StatusPane: View {
    let store: TowerStore
    let ui: PanelState

    var body: some View {
        let p = store.presentation
        VStack(alignment: .leading, spacing: 0) {
            Header(store: store, presentation: p) { ui.showingSettings = true }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            if !p.messages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(p.messages, id: \.self) { message in
                        Label(Self.sentence(message), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Palette.attention)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Palette.attention.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12).padding(.bottom, 10)
            }

            if let snapshot = store.state.lastGood {
                let panel = Panel(snapshot, now: store.now)
                VStack(alignment: .leading, spacing: 0) {
                    NeedsYouSection(items: panel.needsYou, ui: ui)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                    Divider().padding(.horizontal, 16)
                    CapacityRow(slots: panel.slots, queue: panel.queue)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().padding(.horizontal, 16)
                    AgentsSection(agents: panel.agents)
                        .padding(.vertical, 12)
                    Divider().padding(.horizontal, 16)
                    HStack(spacing: 14) {
                        ForEach(panel.meters) { MeterView(meter: $0) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    if !panel.warnings.isEmpty {
                        Divider().padding(.horizontal, 16)
                        WarningsSection(warnings: panel.warnings)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
                .opacity(p.dataDimmed ? 0.45 : 1)
                .saturation(p.dataDimmed ? 0 : 1)
            } else {
                EmptyState(hasAddress: store.settings.address != nil) { ui.showingSettings = true }
                    .padding(.horizontal, 16).padding(.vertical, 18)
            }

            Divider()
            Footer(store: store)
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    /// "offline since 14:02" → "Offline since 14:02".
    static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

private struct Header: View {
    let store: TowerStore
    let presentation: Presentation
    let openSettings: () -> Void

    private var status: (String, Color) {
        if store.settings.address == nil { return ("Not set up", .secondary) }
        if presentation.titleDimmed { return (store.state.lastOutcome == .offline ? "Offline" : "Not live", Palette.attention) }
        return ("Live", Palette.working)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .semibold))
            Text("Tower").font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(status.1).frame(width: 7, height: 7)
                Text(status.0)
                if let at = store.state.lastGood?.generatedAt {
                    Text(at, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }
}

private struct NeedsYouSection: View {
    let items: [Panel.NeedsYouItem]
    let ui: PanelState
    private let collapsedCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.working)
                    Text("Nothing needs you").font(.title3.weight(.semibold))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(items.count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.attention)
                    Text(items.count == 1 ? "item needs you" : "items need you")
                        .font(.title3.weight(.medium))
                }
                let shown = ui.showAllNeedsYou ? items : Array(items.prefix(collapsedCount))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shown) { NeedsYouRow(item: $0) }
                }
                if items.count > collapsedCount {
                    Button(ui.showAllNeedsYou ? "Show fewer" : "Show \(items.count - collapsedCount) more") {
                        withAnimation(.easeOut(duration: 0.15)) { ui.showAllNeedsYou.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
    }
}

private struct NeedsYouRow: View {
    let item: Panel.NeedsYouItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ProjectTag(slug: item.project)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label).font(.callout.weight(.medium))
                if !item.reason.isEmpty {
                    Text(item.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(item.age).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

private struct ProjectTag: View {
    let slug: String

    var body: some View {
        Text(slug.isEmpty ? "—" : slug)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct CapacityRow: View {
    let slots: Panel.Slots
    let queue: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("Slots").foregroundStyle(.secondary)
            SlotCells(slots: slots)
            Text("\(slots.occupied.map(String.init) ?? "–") of \(slots.allocated.map(String.init) ?? "–") busy")
                .monospacedDigit()
                .foregroundStyle(slots.overbooked ? Palette.danger : .primary)
            Spacer()
            Text("Queue").foregroundStyle(.secondary)
            Text("\(queue)").monospacedDigit().fontWeight(.semibold)
        }
        .font(.callout)
        .help(slots.overbooked ? "More leases held than slots allocated" : "")
    }
}

/// One cell per slot: filled when busy, red when beyond the allocation.
private struct SlotCells: View {
    let slots: Panel.Slots

    var body: some View {
        let allocated = slots.allocated ?? 0
        let occupied = slots.occupied ?? 0
        let count = min(max(allocated, occupied), 12)
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                let over = i >= allocated
                let busy = i < occupied
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(busy ? (over ? Palette.danger : Palette.working) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 2.5)
                        .strokeBorder(over ? Palette.danger : Color.secondary.opacity(0.5), lineWidth: busy ? 0 : 1))
                    .frame(width: 9, height: 14)
            }
        }
        .accessibilityLabel("\(occupied) of \(allocated) slots busy")
    }
}

private struct AgentsSection: View {
    let agents: [Panel.AgentItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Running agents").font(.callout.weight(.semibold))
                Spacer()
                Text("\(agents.count)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            if agents.isEmpty {
                Text("No agents running.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 2) {
                    ForEach(agents) { AgentStrip(agent: $0) }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

/// A flight strip: state colour on the left edge; click opens the ticket.
private struct AgentStrip: View {
    let agent: Panel.AgentItem
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = agent.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.tone(agent.tone))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(agent.project).font(.callout.weight(.semibold))
                        Text(kindText).font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Text(agent.age).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(agent.stateLabel)
                            .foregroundStyle(agent.tone == .idle ? .secondary : Palette.tone(agent.tone))
                            .fontWeight(.medium)
                        if !agent.progress.isEmpty {
                            Text(agent.progress).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && agent.url != nil ? Color.primary.opacity(0.07) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(agent.url == nil)
        .onHover { hovering = $0 }
        .help(agent.title.isEmpty ? (agent.url?.absoluteString ?? "") : agent.title)
    }

    private var kindText: String {
        let kind = agent.kind.isEmpty ? "agent" : agent.kind
        return agent.attempt.map { "\(kind), attempt \($0)" } ?? kind
    }
}

/// A thin bar with a tick at the warning limit.
private struct MeterView: View {
    let meter: Panel.Meter
    private let limit = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(meter.name).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(meter.text)
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .foregroundStyle(meter.warn ? Palette.danger : .primary)
            }
            .font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(meter.warn ? Palette.danger : Color.primary.opacity(0.55))
                        .frame(width: geo.size.width * min(max(meter.fraction ?? 0, 0), 1))
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: 8)
                        .offset(x: geo.size.width * limit)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WarningsSection: View {
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tower reports").font(.callout.weight(.semibold))
            ForEach(warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.attention)
                    .lineLimit(2)
            }
        }
    }
}

private struct EmptyState: View {
    let hasAddress: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasAddress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Tower…").foregroundStyle(.secondary)
                }
            } else {
                Text("Connect to Tower").font(.title3.weight(.semibold))
                Text("Enter Tower's Tailscale IP address to see slots, agents and what needs you.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add address", action: openSettings)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct Footer: View {
    let store: TowerStore

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if let url = store.settings.address?.dashboardURL { NSWorkspace.shared.open(url) }
            } label: {
                Label("Open dashboard", systemImage: "safari")
            }
            .disabled(store.settings.address == nil)
            Button {
                store.restart()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.settings.address == nil)
            .help("Refresh now")
            .keyboardShortcut("r")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

// MARK: - Settings

/// Label on the left, switch aligned on the right.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden()
        }
    }
}

private struct SettingsPane: View {
    let store: TowerStore
    let launchAtLogin: LaunchAtLogin
    let done: () -> Void

    @State private var address = ""
    @State private var interval = Settings.defaultInterval
    @State private var notify = false
    @FocusState private var addressFocused: Bool

    private var parsed: TowerAddress? { TowerAddress(address) }
    private var addressInvalid: Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty && parsed == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Button(action: done) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .help("Back")
                Text("Settings").font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tower address").font(.callout.weight(.medium))
                TextField("", text: $address, prompt: Text("100.x.y.z"))
                    .textFieldStyle(.roundedBorder)
                    .focused($addressFocused)
                    .onSubmit(save)
                Group {
                    if addressInvalid {
                        Text("Enter an IP address, with an optional port such as :8090.")
                            .foregroundStyle(Palette.danger)
                    } else if let parsed {
                        Text("Reads \(parsed.feedURL.absoluteString)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Use the IP address, not a host name. Port 8090 is used if you leave it out.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Refresh every")
                    Spacer()
                    Stepper(value: $interval, in: Settings.intervalRange) {
                        Text("\(interval) s").monospacedDigit()
                    }
                }
                SwitchRow(title: "Notify me when something new needs me", isOn: $notify)
                SwitchRow(title: "Open Tower at login",
                          isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                if launchAtLogin.needsApproval {
                    Button("Allow in System Settings…") { launchAtLogin.openSystemSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                } else if let error = launchAtLogin.error {
                    Text(error).font(.caption).foregroundStyle(Palette.danger)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)

            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(addressInvalid)
            }
        }
        .padding(16)
        .onAppear {
            address = store.settings.addressText
            interval = store.settings.pollInterval
            notify = store.settings.notifyNeedsYou
            launchAtLogin.refresh()
            addressFocused = store.settings.address == nil
        }
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
        done()
    }
}
