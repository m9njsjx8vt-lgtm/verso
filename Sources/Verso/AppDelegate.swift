import AppKit
import Combine
import SwiftUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let glossary = Glossary()
    let history = HistoryStore()
    let writingMistakes = WritingMistakeStore()
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
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var workspaceWindowController: WorkspaceWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()

        let popup = PopupController(
            settings: settings, glossary: glossary, history: history,
            writingMistakes: writingMistakes,
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
        settingsWindowController = SettingsWindowController(
            settings: settings,
            glossary: glossary,
            history: history,
            writingMistakes: writingMistakes,
            usage: usage
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
        NotificationCenter.default.addObserver(
            forName: .versoOpenSettingsRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
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
        menu.addItem(appMenuItem(title: "\(L10n.menuTranslateClipboard)  ⌘⇧V",
                                 action: #selector(translateClipboard)))
        menu.addItem(appMenuItem(title: "\(L10n.menuTranslateRegion)  ⌥⇧C",
                                 action: #selector(translateRegion)))
        menu.addItem(appMenuItem(title: L10n.menuTranslateWindow,
                                 action: #selector(translateWindow)))
        menu.addItem(appMenuItem(title: "\(L10n.menuOpenWorkspace)  ⌘⇧T",
                                 action: #selector(openWorkspace)))
        menu.addItem(appMenuItem(title: "\(L10n.menuHistory)  ⌘⇧H",
                                 action: #selector(showHistory)))
        menu.addItem(.separator())
        let engineItem = NSMenuItem(title: aiEngineMenuTitle, action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)
        let pauseItem = appMenuItem(
            title: settings.paused ? L10n.menuResume : L10n.menuPause,
            action: #selector(togglePause)
        )
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
        menu.addItem(appMenuItem(title: L10n.menuSettings,
                                 action: #selector(openSettings),
                                 keyEquivalent: ","))
        menu.addItem(appMenuItem(title: L10n.menuShowWelcome,
                                 action: #selector(showOnboarding)))
        menu.addItem(appMenuItem(title: L10n.menuCheckAccessibility,
                                 action: #selector(recheckAccessibility)))
        menu.addItem(.separator())
        menu.addItem(.init(title: L10n.menuQuit,
                           action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    private func appMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.target = self
        return menuItem
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
                    if !ScreenCapturePermissionService.isTrusted() {
                        _ = ScreenCapturePermissionService.requestIfNeeded()
                    }
                }
            )
        }
        onboardingWindowController?.show()
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    @objc private func recheckAccessibility() {
        let accessibilityOK = AccessibilityService.isTrusted()
        let screenRecordingOK = ScreenCapturePermissionService.isTrusted()

        if accessibilityOK && screenRecordingOK {
            let alert = NSAlert()
            alert.messageText = L10n.t("Permissions OK", "権限 OK")
            alert.informativeText = L10n.t(
                "Hotkeys and OCR screen capture are available.",
                "ホットキーとOCR用の画面キャプチャが使えます。"
            )
            alert.runModal()
        } else {
            if !accessibilityOK {
                _ = AccessibilityService.checkAndPromptIfNeeded()
            }
            if !screenRecordingOK {
                _ = ScreenCapturePermissionService.requestIfNeeded()
            }
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
        case "settings":
            openSettings()
            if let tab = comps.queryItems?.first(where: { $0.name == "tab" })?.value, !tab.isEmpty {
                // Give the settings window a beat to materialize before switching tabs.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .versoSelectSettingsTab, object: tab)
                }
            }
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

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let glossary: Glossary
    private let history: HistoryStore
    private let writingMistakes: WritingMistakeStore
    private let usage: UsageTracker
    private var window: NSWindow?

    init(
        settings: AppSettings,
        glossary: Glossary,
        history: HistoryStore,
        writingMistakes: WritingMistakeStore,
        usage: UsageTracker
    ) {
        self.settings = settings
        self.glossary = glossary
        self.history = history
        self.writingMistakes = writingMistakes
        self.usage = usage
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView()
            .environmentObject(settings)
            .environmentObject(glossary)
            .environmentObject(history)
            .environmentObject(writingMistakes)
            .environmentObject(usage)

        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Verso — Settings"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 700, height: 600))
        win.minSize = NSSize(width: 660, height: 560)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

extension Notification.Name {
    static let versoOpenSettingsRequested = Notification.Name("versoOpenSettingsRequested")
}
