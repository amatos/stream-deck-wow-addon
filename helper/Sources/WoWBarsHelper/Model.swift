import AppKit
import ApplicationServices
import Combine
import StripKit

/// Where the app shows itself. Stored in user defaults.
enum Presentation: String, CaseIterable, Identifiable {
    case dock
    case menuBar

    var id: String { rawValue }
    var label: String { self == .dock ? "Dock" : "Menu bar" }

    static let defaultsKey = "presentation"

    static var stored: Presentation {
        get { Presentation(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .dock }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

enum Permissions {
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() { open("Privacy_ScreenCapture") }
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { open("Privacy_Accessibility") }
    }

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// State shown in the window. Main thread only.
final class Model: ObservableObject {
    @Published var snapshot = CaptureSnapshot() {
        didSet { requestIcons(); deckFeed.update(snapshot: snapshot, icons: icons) }
    }
    @Published var icons: [Int: NSImage] = [:] {
        didSet { deckFeed.update(snapshot: snapshot, icons: icons) }
    }
    @Published var deckClients = 0
    let deckServer = DeckServer()
    lazy var deckFeed = DeckFeed(server: deckServer)
    let iconLoader = IconLoader()
    @Published var screenRecording = Permissions.screenRecording
    @Published var accessibility = Permissions.accessibility
    @Published var presentation = Presentation.stored {
        didSet {
            Presentation.stored = presentation
            onPresentationChange?(presentation)
        }
    }

    @Published var lastKeyMessage = "Click a slot to press its key in WoW."

    var onPresentationChange: ((Presentation) -> Void)?
    let keySender = KeySender()
    private var timer: Timer?

    /// Starts the Stream Deck server; plugin key presses go to WoW without activating it.
    func startDeck() {
        deckServer.onPress = { [weak self] slot in self?.keySender.press(slot: slot, activate: false) }
        deckServer.onClientsChanged = { [weak self] in self?.deckClients = $0 }
        deckServer.start()
        deckFeed.update(snapshot: snapshot, icons: icons)
    }

    func startIcons() {
        iconLoader.onLoad = { [weak self] id, image in self?.icons[id] = image }
        requestIcons()
    }

    private func requestIcons() {
        guard let frame = snapshot.frame else { return }
        if iconLoader.store == nil { iconLoader.prepare(appBundle: KeySender.wowApp()?.bundleURL) }
        iconLoader.request(frame.slots.map(\.iconID).filter { icons[$0] == nil })
    }

    /// Debug: presses a slot's key in WoW, bringing WoW to the front first.
    func press(slot: Int) {
        switch keySender.press(slot: slot, activate: true) {
        case .sent(let name):
            let (bar, button) = Spec.barButton(slot: slot) ?? (0, 0)
            lastKeyMessage = "Sent \(name) to WoW (bar \(bar), button \(button))."
        case .noAccessibility:
            lastKeyMessage = "Grant Accessibility permission first."
        case .noWoW:
            lastKeyMessage = "WoW is not running."
        case .badSlot:
            lastKeyMessage = "No key for that slot."
        }
    }

    func startPolling(onScreenRecordingGranted: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = Permissions.screenRecording
            if granted && !self.screenRecording { onScreenRecordingGranted() }
            if granted != self.screenRecording { self.screenRecording = granted }
            let ax = Permissions.accessibility
            if ax != self.accessibility { self.accessibility = ax }
        }
    }
}
