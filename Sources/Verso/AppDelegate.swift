import AppKit
import SwiftUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let glossary = Glossary()
    let history = HistoryStore()
    let usage = UsageTracker()
    let cache = TranslationCache()
    let network = NetworkMonitor()

    /// Sparkle updater. Pulls appcast from Info.plist SUFeedURL, checks daily,
    /// verifies new builds via SUPublicEDKey signature.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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

        let popup = PopupController(
            settings: settings, glossary: glossary, history: history,
            usage: usage, cache: cache, network: network
        )
        popupController = popup
        ocrCoordinator = OCRCoordinator(popupController: popup)
        historyWindowController = HistoryWindowController(history: history, popupController: popup)

        setupCmdCHotkey()
        setupAuxHotkeys()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        if settings.apiKey.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboarding()
            }
        } else if !AccessibilityService.isTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = AccessibilityService.checkAndPromptIfNeeded()
            }
        }

        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                self?.refreshStatusBarIcon()
            }
        }
    }

    // MARK: - Menu bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshStatusBarIcon()

        let menu = NSMenu()
        menu.addItem(.init(title: "Translate Clipboard  ⌘⇧V",
                           action: #selector(translateClipboard), keyEquivalent: ""))
        menu.addItem(.init(title: "Translate Region…  ⌥⇧C",
                           action: #selector(translateRegion), keyEquivalent: ""))
        menu.addItem(.init(title: "Translate Frontmost Window…",
                           action: #selector(translateWindow), keyEquivalent: ""))
        menu.addItem(.init(title: "History…  ⌘⇧H",
                           action: #selector(showHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        let pauseItem = NSMenuItem(title: settings.paused ? "Resume Verso" : "Pause Verso",
                                   action: #selector(togglePause), keyEquivalent: "")
        pauseItem.tag = 999
        menu.addItem(pauseItem)
        // Show 'Check for Updates' only if a real SUFeedURL is configured
        if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           !feed.contains("REPLACE_ME") {
            let updateItem = NSMenuItem(title: "Check for Updates…",
                                        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                        keyEquivalent: "")
            updateItem.target = updaterController
            menu.addItem(updateItem)
        }
        menu.addItem(.init(title: "Settings…",
                           action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.init(title: "Show Welcome Tour…",
                           action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(.init(title: "Check Accessibility Permission",
                           action: #selector(recheckAccessibility), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: "Quit Verso",
                           action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    private func refreshStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        if settings.paused { symbolName = "character.bubble.slash" }
        else if !network.isOnline { symbolName = "character.bubble" /* could indicate offline differently */ }
        else { symbolName = "character.bubble" }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Verso")
        if let pauseItem = statusItem?.menu?.item(withTag: 999) {
            pauseItem.title = settings.paused ? "Resume Verso" : "Pause Verso"
        }
    }

    // MARK: - Hotkeys

    private func setupCmdCHotkey() {
        hotkeyMonitor = HotkeyMonitor { [weak self] in
            guard let self = self, !self.settings.paused else { return }
            self.handleDoubleCmdC()
        }
        hotkeyMonitor?.start()
    }

    private func setupAuxHotkeys() {
        auxHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, !self.settings.paused else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 8, flags == [.option, .shift] {
                Task { @MainActor in self.ocrCoordinator?.startRegionTranslation() }
            }
            if event.keyCode == 4, flags == [.command, .shift] {
                Task { @MainActor in self.showHistory() }
            }
            if event.keyCode == 9, flags == [.command, .shift] {
                Task { @MainActor in self.translateClipboard() }
            }
        }
    }

    // MARK: - Actions

    @objc private func togglePause() {
        settings.paused.toggle()
        refreshStatusBarIcon()
    }

    @objc private func translateClipboard() {
        guard !settings.paused,
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else { NSSound.beep(); return }
        popupController?.show(originalText: text)
    }

    @objc private func translateRegion() {
        guard !settings.paused else { return }
        ocrCoordinator?.startRegionTranslation()
    }

    @objc private func translateWindow() {
        guard !settings.paused else { return }
        ocrCoordinator?.startWindowTranslation()
    }

    @objc private func showHistory() { historyWindowController?.show() }

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
            alert.informativeText = "⌘C×2、⌥⇧C、⌘⇧H、⌘⇧V が動作します。"
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

    // MARK: - URL scheme handler  (verso://translate?text=...)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url: url) }
    }

    private func handle(url: URL) {
        guard url.scheme == "verso" else { return }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        switch url.host {
        case "translate":
            if let text = comps.queryItems?.first(where: { $0.name == "text" })?.value, !text.isEmpty {
                let target = comps.queryItems?.first(where: { $0.name == "target" })?.value
                popupController?.show(originalText: text, forceTarget: target)
            }
        case "history": showHistory()
        case "settings": openSettings()
        default: break
        }
    }

    // MARK: - Services menu provider
    @objc func translateText(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard !settings.paused else { return }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            popupController?.show(originalText: text)
        }
    }
}
