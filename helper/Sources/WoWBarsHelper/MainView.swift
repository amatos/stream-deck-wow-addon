import StripKit
import SwiftUI

struct MainView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            permissions
            game
            slots
            settings
        }
        .padding(18)
        .frame(minWidth: 760)
    }

    // MARK: Sections

    private var permissions: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(
                    "Screen Recording", granted: model.screenRecording,
                    detail: "Needed to read the strip from the WoW window.",
                    action: Permissions.requestScreenRecording
                )
                permissionRow(
                    "Accessibility", granted: model.accessibility,
                    detail: "Needed to send key presses to WoW.",
                    action: Permissions.requestAccessibility
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func permissionRow(_ name: String, granted: Bool, detail: String, action: @escaping () -> Void) -> some View {
        HStack {
            StatusDot(ok: granted)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant…", action: action) }
        }
    }

    private var game: some View {
        GroupBox("World of Warcraft") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusDot(ok: isCapturing)
                    Text(sourceText)
                }
                HStack {
                    StatusDot(ok: model.snapshot.status == .connected, warn: model.snapshot.status == .stale)
                    Text(stripText)
                }
                if let frame = model.snapshot.frame {
                    Text(details(frame))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var slots: some View {
        GroupBox("Slots") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<3, id: \.self) { bar in
                    HStack(spacing: 4) {
                        Text("Bar \(bar + 1)").font(.caption).frame(width: 40, alignment: .leading)
                        ForEach(0..<12, id: \.self) { button in
                            SlotCell(slot: slot(bar * 12 + button))
                        }
                    }
                }
                Text("Green: usable · Grey: unusable · Blue: not enough mana · Gold border: proc glow · Red corner: out of range")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var settings: some View {
        GroupBox("Settings") {
            HStack {
                Text("Show in")
                Picker("Show in", selection: $model.presentation) {
                    ForEach(Presentation.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Spacer()
            }
            .padding(4)
        }
    }

    // MARK: Text

    private var isCapturing: Bool {
        if case .capturing = model.snapshot.source { return true }
        return false
    }

    private var sourceText: String {
        switch model.snapshot.source {
        case .noPermission: return "Waiting for Screen Recording permission"
        case .noWindow: return "WoW window not found"
        case let .capturing(title, w, h):
            return "Capturing “\(title)” at \(w)×\(h), \(Int(model.snapshot.framesPerSecond)) fps"
        case .failed(let message): return "Capture failed: \(message)"
        }
    }

    private var stripText: String {
        switch model.snapshot.status {
        case .searching: return "Strip not found yet (is the addon loaded and the strip shown?)"
        case .stale: return "Strip lost — no good frame for a few seconds"
        case .connected:
            guard let g = model.snapshot.geometry else { return "Strip connected" }
            return "Strip connected at (\(g.originX), \(g.originY)), block \(String(format: "%.1f", g.pitch)) px"
        }
    }

    private func details(_ f: StripFrame) -> String {
        var parts = ["sequence \(f.sequence)"]
        parts.append(f.flags.inCombat ? "in combat" : "out of combat")
        parts.append(f.flags.bindingsApplied ? "keybinds applied" : "keybinds not applied")
        if f.flags.bindingsPending { parts.append("keybinds pending") }
        if f.flags.countsSecret { parts.append("counts secret") }
        if let failure = model.snapshot.lastFailure { parts.append("last error: \(failure)") }
        return parts.joined(separator: " · ")
    }

    private func slot(_ i: Int) -> SlotState? {
        guard let f = model.snapshot.frame, i < f.slots.count else { return nil }
        return f.slots[i]
    }
}

struct StatusDot: View {
    var ok: Bool
    var warn = false

    var body: some View {
        Circle()
            .fill(ok ? Color.green : (warn ? Color.orange : Color.red))
            .frame(width: 9, height: 9)
    }
}

struct SlotCell: View {
    var slot: SlotState?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 5)
                .fill(fill)
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(slot?.glow == true ? Color.yellow : Color.secondary.opacity(0.3),
                              lineWidth: slot?.glow == true ? 3 : 1)
            if let slot, slot.hasAction {
                Text(String(slot.iconID))
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(3)
            }
            if let slot, slot.hasCount {
                Text(slot.count.map(String.init) ?? "?")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(3)
            }
            if let slot, slot.rangeApplies && !slot.inRange {
                Triangle().fill(Color.red)
                    .frame(width: 10, height: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(2)
            }
        }
        .frame(width: 52, height: 52)
        .help(tooltip)
    }

    private var fill: Color {
        guard let slot, slot.hasAction else { return Color.black.opacity(0.35) }
        if slot.noMana { return Color.blue.opacity(0.7) }
        return slot.usable ? Color.green.opacity(0.55) : Color.gray.opacity(0.6)
    }

    private var tooltip: String {
        guard let slot, slot.hasAction else { return "Empty" }
        var parts = ["Icon \(slot.iconID)", slot.usable ? "usable" : "unusable"]
        if slot.noMana { parts.append("not enough mana") }
        if slot.glow { parts.append("proc glow") }
        if slot.rangeApplies { parts.append(slot.inRange ? "in range" : "out of range") }
        if slot.hasCount { parts.append("count \(slot.count.map(String.init) ?? "unreadable")") }
        return parts.joined(separator: ", ")
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
        }
    }
}
