import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private var statusItem: NSStatusItem?
    private var hotkeyMonitor: HotkeyMonitor?
    private var popupController: PopupController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
        popupController = PopupController(settings: settings)
        setupHotkey()

        // Prompt for Accessibility on first run (needed for global ⌘C×2 detection)
        if !AccessibilityService.isTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = AccessibilityService.checkAndPromptIfNeeded()
            }
        }

        // Open Settings if no API key yet (first-launch UX)
        if settings.apiKey.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.openSettings()
            }
        }
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "character.bubble",
                accessibilityDescription: "Translator"
            )
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Check Accessibility Permission",
            action: #selector(recheckAccessibility),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Translator",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item
    }

    private func setupHotkey() {
        hotkeyMonitor = HotkeyMonitor { [weak self] in
            self?.handleDoubleCmdC()
        }
        hotkeyMonitor?.start()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func recheckAccessibility() {
        if AccessibilityService.isTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility OK"
            alert.informativeText = "⌘C×2 で翻訳が起動できる状態です。"
            alert.runModal()
        } else {
            _ = AccessibilityService.checkAndPromptIfNeeded()
        }
    }

    private func handleDoubleCmdC() {
        // Wait briefly for clipboard to settle after the second ⌘C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            guard let text = NSPasteboard.general.string(forType: .string),
                  !text.isEmpty else {
                return
            }
            self.popupController?.show(originalText: text)
        }
    }
}
