import AppKit
import SwiftUI

@main
struct KaiLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
                .frame(width: 460)
                .padding(24)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel()

    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.openSettingsHandler = { [weak self] in
            self?.showSetupWindow()
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let robotImage = NSImage(
            systemSymbolName: "robot",
            accessibilityDescription: "Kai"
        )
        statusItem.button?.image = robotImage
        if robotImage == nil {
            statusItem.button?.title = "K"
        }
        statusItem.button?.toolTip = "Kai Live"
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
        self.statusItem = statusItem

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.contentViewController = NSHostingController(rootView: ConversationView(model: model))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if model.hasAPIKey() {
                showPopover()
            } else {
                showSetupWindow()
            }
        }
    }

    @objc private func togglePopover() {
        guard statusItem?.button != nil else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        Task { await model.startConversation() }
    }

    private func showSetupWindow() {
        if let setupWindow {
            setupWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kai Live Setup"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsView(model: model)
                .frame(minWidth: 460, minHeight: 390)
                .padding(20)
        )
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if model.hasAPIKey() {
            showPopover()
        } else {
            showSetupWindow()
        }
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        Task { await model.endConversation() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopImmediately()
    }
}
