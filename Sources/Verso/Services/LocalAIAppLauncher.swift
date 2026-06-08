import AppKit
import Foundation

struct LocalAIAppLaunchResult {
    let succeeded: Bool
    let message: String
}

enum LocalAIAppLauncher {
    static func buttonTitle(for backend: LocalAIBackend) -> String {
        switch backend {
        case .ollama:
            return "Start Ollama"
        case .openAICompatible:
            return "Open LM Studio"
        }
    }

    @MainActor
    static func openServerApp(for backend: LocalAIBackend) -> LocalAIAppLaunchResult {
        switch backend {
        case .ollama:
            if let appURL = appURL(for: .ollama) {
                return openApp(url: appURL, successMessage: "Ollamaを開きました。数秒後にRefresh Modelsを押してください。")
            }
            if let started = startOllamaServe() {
                return started
            }
            return LocalAIAppLaunchResult(
                succeeded: false,
                message: "Ollamaアプリ/CLIが見つかりません。Ollamaを入れるか、手動でollama serveを起動してください。"
            )
        case .openAICompatible:
            if let appURL = appURL(for: .lmStudio) {
                return openApp(url: appURL, successMessage: "LM Studioを開きました。Local Serverを起動してからRefresh Modelsを押してください。")
            }
            return LocalAIAppLaunchResult(
                succeeded: false,
                message: "LM Studioが見つかりません。/Applicationsに入れるか、OpenAI互換サーバーを手動で起動してください。"
            )
        }
    }

    private enum LocalServerApp {
        case ollama
        case lmStudio

        var bundleIdentifiers: [String] {
            switch self {
            case .ollama:
                return ["com.ollama.ollama", "com.electron.ollama"]
            case .lmStudio:
                return ["ai.elementlabs.lmstudio", "com.lmstudio.lmstudio", "com.elementlabs.lmstudio"]
            }
        }

        var fileNames: [String] {
            switch self {
            case .ollama:
                return ["Ollama.app"]
            case .lmStudio:
                return ["LM Studio.app", "LMStudio.app"]
            }
        }
    }

    @MainActor
    private static func openApp(url: URL, successMessage: String) -> LocalAIAppLaunchResult {
        if NSWorkspace.shared.open(url) {
            return LocalAIAppLaunchResult(succeeded: true, message: successMessage)
        }
        return LocalAIAppLaunchResult(succeeded: false, message: "アプリを開けませんでした: \(url.lastPathComponent)")
    }

    @MainActor
    private static func appURL(for app: LocalServerApp) -> URL? {
        for bundleIdentifier in app.bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        let searchRoots = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for root in searchRoots {
            for fileName in app.fileNames {
                let url = root.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    private static func startOllamaServe() -> LocalAIAppLaunchResult? {
        let candidates = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama"
        ]

        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["serve"]

        do {
            try process.run()
            return LocalAIAppLaunchResult(
                succeeded: true,
                message: "Ollamaサーバーを起動しました。数秒後にRefresh Modelsを押してください。"
            )
        } catch {
            return LocalAIAppLaunchResult(
                succeeded: false,
                message: "ollama serveを起動できませんでした: \(error.localizedDescription)"
            )
        }
    }
}
