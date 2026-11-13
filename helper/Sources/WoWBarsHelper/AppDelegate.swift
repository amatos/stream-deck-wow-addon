import AppKit
import DeckKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let appName = "WoW Bars Helper"

    let model = Model()
    let capture = WindowCapture()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        model.onPresentationChange = { [weak self] in self?.apply($0) }
        apply(model.presentation)

        model.startIcons()
        model.startDeck()
        capture.onUpdate = { [weak self] in self?.model.snapshot = $0 }
        capture.start()
        model.startPolling { [weak self] in self?.capture.refresh() }
        if !Permissions.screenRecording { Permissions.requestScreenRecording() }

        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon reopens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Presentation

    /// Shows the app in the Dock or the menu bar. Exactly one is always present.
    func apply(_ presentation: Presentation) {
        switch presentation {
        case .dock:
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            NSApp.setActivationPolicy(.regular)
        case .menuBar:
            if statusItem == nil { statusItem = makeStatusItem() }
            NSApp.setActivationPolicy(.accessory)
        }
        // Changing the policy can hide the window; bring it back if it was open.
        if window?.isVisible == true { showWindow() }
    }

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            w.title = Self.appName
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainView(model: model))
            w.center()
            w.setFrameAutosaveName("MainWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarImage()
        let menu = NSMenu()
        menu.addItem(withTitle: "Open \(Self.appName)", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(Self.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    /// The W-on-keys mark as a template image, so macOS tints it for light and dark menu bars.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            Emblem.drawMono(
                in: ctx, rect: rect.insetBy(dx: 1, dy: 0),
                colour: CGColor(gray: 0, alpha: 1), gap: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = appName
        return image
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About \(Self.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(Self.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit \(Self.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return main
    }
}
