import SwiftUI

@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.glossary)
                .environmentObject(appDelegate.history)
                .environmentObject(appDelegate.writingMistakes)
                .environmentObject(appDelegate.usage)
        }
    }
}
