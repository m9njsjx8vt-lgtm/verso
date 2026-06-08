import AppKit
import Combine
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
    private var workspaceWindowController: WorkspaceWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()

        let popup = PopupController(
            settings: settings, glossary: glossary, history: history,
            usage: usage, cache: cache, network: network
        )
        popupController = popup
        ocrCoordinator = OCRCoordinator(popupController: popup)
        workspaceWindowController = WorkspaceWindowController(
            popupController: popup,
            settings: settings,
            glossary: glossary,
            history: history,
            usage: usage,
            cache: cache,
            network: network
        )
        historyWindowController = HistoryWindowController(
            history: history,
            workspaceController: workspaceWindowController
        )

        setupCmdCHotkey()
        setupAuxHotkeys()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // Rebuild menu when UI language toggles
        NotificationCenter.default.addObserver(
            forName: .versoLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildStatusBarMenu() }
        }
        network.$isOnline
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildStatusBarMenu()
                }
            }
            .store(in: &cancellables)

        if !settings.hasCompletedOnboarding {
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
                self?.rebuildStatusBarMenu()
            }
        }
    }

    // MARK: - Menu bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshStatusBarIcon()
        rebuildStatusBarMenu()
    }

    private func rebuildStatusBarMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(.init(title: "\(L10n.menuTranslateClipboard)  ⌘⇧V",
                           action: #selector(translateClipboard), keyEquivalent: ""))
        menu.addItem(.init(title: "\(L10n.menuTranslateRegion)  ⌥⇧C",
                           action: #selector(translateRegion), keyEquivalent: ""))
        menu.addItem(.init(title: L10n.menuTranslateWindow,
                           action: #selector(translateWindow), keyEquivalent: ""))
        menu.addItem(.init(title: "\(L10n.menuOpenWorkspace)  ⌘⇧T",
                           action: #selector(openWorkspace), keyEquivalent: ""))
        menu.addItem(.init(title: "\(L10n.menuHistory)  ⌘⇧H",
                           action: #selector(showHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        let engineItem = NSMenuItem(title: aiEngineMenuTitle, action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)
        let pauseItem = NSMenuItem(title: settings.paused ? L10n.menuResume : L10n.menuPause,
                                   action: #selector(togglePause), keyEquivalent: "")
        pauseItem.tag = 999
        menu.addItem(pauseItem)
        if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           !feed.contains("REPLACE_ME") {
            let updateItem = NSMenuItem(title: L10n.menuCheckForUpdates,
                                        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                        keyEquivalent: "")
            updateItem.target = updaterController
            menu.addItem(updateItem)
        }
        menu.addItem(.init(title: L10n.menuSettings,
                           action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.init(title: L10n.menuShowWelcome,
                           action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(.init(title: L10n.menuCheckAccessibility,
                           action: #selector(recheckAccessibility), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: L10n.menuQuit,
                           action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    private var aiEngineMenuTitle: String {
        let useLocalAI = settings.shouldRouteToLocalAI(isOnline: network.isOnline)
        let model = useLocalAI ? settings.localAIModel : settings.model
        let provider: String
        if useLocalAI, !settings.usesLocalAI {
            provider = network.isOnline ? "Local AI fallback" : "Local AI offline"
        } else {
            provider = settings.providerTitle(useLocalAI: useLocalAI)
        }
        return cappedMenuTitle("AI: \(provider) · \(compactModelName(model))")
    }

    private func compactModelName(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = value.lastIndex(of: "/") {
            value = String(value[value.index(after: slash)...])
        }
        for removable in ["gemini-", "-abliterated", "-thinking", "-q4_K_M", "_q4_K_M"] {
            value = value.replacingOccurrences(of: removable, with: "")
        }
        value = value
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("Not set", "未設定") : value
    }

    private func cappedMenuTitle(_ title: String) -> String {
        guard title.count > 30 else { return title }
        return String(title.prefix(29)) + "…"
    }

    private func refreshStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName = settings.paused ? "character.bubble.slash" : "character.bubble"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Verso")
        if let pauseItem = statusItem?.menu?.item(withTag: 999) {
            pauseItem.title = settings.paused ? L10n.menuResume : L10n.menuPause
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
            // ⌥⇧C → OCR
            if event.keyCode == 8, flags == [.option, .shift] {
                Task { @MainActor in self.ocrCoordinator?.startRegionTranslation() }
            }
            // ⌘⇧H → History
            if event.keyCode == 4, flags == [.command, .shift] {
                Task { @MainActor in self.showHistory() }
            }
            // ⌘⇧V → Translate clipboard
            if event.keyCode == 9, flags == [.command, .shift] {
                Task { @MainActor in self.translateClipboard() }
            }
            // ⌘⇧T → Open workspace
            if event.keyCode == 17, flags == [.command, .shift] {
                Task { @MainActor in self.openWorkspace() }
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

    @objc private func openWorkspace() { workspaceWindowController?.show() }

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
            alert.messageText = L10n.t("Accessibility OK", "アクセシビリティ OK")
            alert.informativeText = L10n.t(
                "⌘C×2, ⌥⇧C, ⌘⇧H, ⌘⇧V, ⌘⇧T are all working.",
                "⌘C×2、⌥⇧C、⌘⇧H、⌘⇧V、⌘⇧T が動作します。"
            )
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
                let mode = comps.queryItems?.first(where: { $0.name == "mode" })?.value
                if mode == "workspace" {
                    workspaceWindowController?.show(text: text, forceTarget: target, translateImmediately: true)
                } else {
                    popupController?.show(originalText: text, forceTarget: target)
                }
            }
        case "history": showHistory()
        case "settings": openSettings()
        case "welcome", "onboarding": showOnboarding()
        case "workspace":
            let text = comps.queryItems?.first(where: { $0.name == "text" })?.value
            let target = comps.queryItems?.first(where: { $0.name == "target" })?.value
            let translate = comps.queryItems?.first(where: { $0.name == "translate" })?.value == "1"
            workspaceWindowController?.show(
                text: text,
                forceTarget: target,
                translateImmediately: translate
            )
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
