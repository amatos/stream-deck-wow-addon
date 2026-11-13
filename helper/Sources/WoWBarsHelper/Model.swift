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
    @Published var snapshot = CaptureSnapshot()
    @Published var screenRecording = Permissions.screenRecording
    @Published var accessibility = Permissions.accessibility
    @Published var presentation = Presentation.stored {
        didSet {
            Presentation.stored = presentation
            onPresentationChange?(presentation)
        }
    }

    var onPresentationChange: ((Presentation) -> Void)?
    private var timer: Timer?

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
