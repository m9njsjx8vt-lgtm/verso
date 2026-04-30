import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let glossary = Glossary()

    private var statusItem: NSStatusItem?
    private var hotkeyMonitor: HotkeyMonitor?
    private var ocrHotkeyMonitor: Any?
    private var popupController: PopupController?
    private var ocrCoordinator: OCRCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()

        let popup = PopupController(settings: settings, glossary: glossary)
        popupController = popup
        ocrCoordinator = OCRCoordinator(popupController: popup)

        setupCmdCHotkey()
        setupOCRHotkey()

        // Prompt for Accessibility on first run (needed for global hotkey detection)
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

    // MARK: - Menu bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "character.bubble",
                accessibilityDescription: "Verso"
            )
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Translate Region…  ⌥⇧C",
            action: #selector(translateRegion),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem(
            title: "Check Accessibility Permission",
            action: #selector(recheckAccessibility),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Verso",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item
    }

    // MARK: - Hotkeys

    private func setupCmdCHotkey() {
        hotkeyMonitor = HotkeyMonitor { [weak self] in
            self?.handleDoubleCmdC()
        }
        hotkeyMonitor?.start()
    }

    /// Single-press ⌥⇧C → start screen-region OCR translation.
    private func setupOCRHotkey() {
        ocrHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 8 else { return }  // C
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.option, .shift] {
                Task { @MainActor in
                    self?.ocrCoordinator?.startRegionTranslation()
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func translateRegion() {
        ocrCoordinator?.startRegionTranslation()
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
            alert.informativeText = "⌘C×2 と ⌥⇧C が動作します。"
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
