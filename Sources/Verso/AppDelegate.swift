import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let glossary = Glossary()
    let history = HistoryStore()

    private var statusItem: NSStatusItem?
    private var hotkeyMonitor: HotkeyMonitor?
    private var auxHotkeyMonitor: Any?
    private var popupController: PopupController?
    private var ocrCoordinator: OCRCoordinator?
    private var historyWindowController: HistoryWindowController?
    private var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()

        let popup = PopupController(settings: settings, glossary: glossary, history: history)
        popupController = popup
        ocrCoordinator = OCRCoordinator(popupController: popup)
        historyWindowController = HistoryWindowController(history: history, popupController: popup)

        setupCmdCHotkey()
        setupAuxHotkeys()

        // First-launch flow
        if settings.apiKey.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboarding()
            }
        } else if !AccessibilityService.isTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = AccessibilityService.checkAndPromptIfNeeded()
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
        menu.addItem(.init(title: "History…  ⌘⇧H",
                           action: #selector(showHistory),
                           keyEquivalent: ""))
        menu.addItem(.init(title: "Translate Region…  ⌥⇧C",
                           action: #selector(translateRegion),
                           keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: "Settings…",
                           action: #selector(openSettings),
                           keyEquivalent: ","))
        menu.addItem(.init(title: "Show Welcome Tour…",
                           action: #selector(showOnboarding),
                           keyEquivalent: ""))
        menu.addItem(.init(title: "Check Accessibility Permission",
                           action: #selector(recheckAccessibility),
                           keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: "Quit Verso",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))
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

    /// One global monitor handles both ⌥⇧C (OCR) and ⌘⇧H (history).
    private func setupAuxHotkeys() {
        auxHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌥⇧C → OCR region translation
            if event.keyCode == 8, flags == [.option, .shift] {
                Task { @MainActor in self?.ocrCoordinator?.startRegionTranslation() }
            }
            // ⌘⇧H → History window
            if event.keyCode == 4, flags == [.command, .shift] {
                Task { @MainActor in self?.showHistory() }
            }
        }
    }

    // MARK: - Actions

    @objc private func translateRegion() {
        ocrCoordinator?.startRegionTranslation()
    }

    @objc private func showHistory() {
        historyWindowController?.show()
    }

    @objc private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(
                settings: settings,
                onComplete: { [weak self] in
                    self?.onboardingWindowController = nil
                    if !AccessibilityService.isTrusted() {
                        _ = AccessibilityService.checkAndPromptIfNeeded()
                    }
                }
            )
        }
        onboardingWindowController?.show()
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
            alert.informativeText = "⌘C×2、⌥⇧C、⌘⇧H が動作します。"
            alert.runModal()
        } else {
            _ = AccessibilityService.checkAndPromptIfNeeded()
        }
    }

    private func handleDoubleCmdC() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            guard let text = NSPasteboard.general.string(forType: .string),
                  !text.isEmpty else { return }
            self.popupController?.show(originalText: text)
        }
    }
}
