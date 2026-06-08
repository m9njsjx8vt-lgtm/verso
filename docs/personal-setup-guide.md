# Verso — Personal Setup Guide

Verso is a personal macOS translator. Select text anywhere, press Cmd+C twice, and get a translation popup.

This guide is for Tomoro's own setup first. A separate handoff guide can be written later when the app is ready for another user.

## 1. Install

1. Open `Verso-vX.Y.Z.dmg`.
2. Drag **Verso** to **Applications**.
3. Launch Verso from Applications.
4. If macOS shows an unidentified developer warning:
   - Close the warning.
   - Right-click Verso in Applications.
   - Choose **Open**.
   - Confirm **Open**.

## 2. First Run

Verso appears as a menu bar icon.

### Step 1: Choose AI Engine

Default: **Local AI**.

Use Local AI when you want offline/private translation on this Mac.

1. In the welcome tour, choose **Local AI**.
2. Use **Start Ollama** or **Open LM Studio**.
3. Verso auto-checks the saved endpoint when the setup/settings screen opens.
4. Use **Detect Local AI** to search common Ollama / LM Studio local endpoints, or **Refresh Models** to retry the current endpoint manually.
5. Press **Test Local AI**.

Gemini is optional. Use it when internet access is available and cloud translation quality is preferred. If Gemini is selected but its API key is blank, Verso automatically uses Local AI for translation.

### Step 2: DeepL API Key

DeepL is optional. Leave it blank unless instant cloud preview is useful.

### Step 3: Accessibility Permission

Required for global shortcuts.

1. Open macOS **System Settings**.
2. Go to **Privacy & Security → Accessibility**.
3. Enable **Verso**.
4. Quit and relaunch Verso.

## 3. Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+C twice | Translate selected text |
| Option+Shift+C | OCR a selected screen region |
| Cmd+Shift+V | Translate clipboard |
| Cmd+Shift+H | Open history |
| Cmd+Shift+T | Open translation workspace |

## 4. Personalization

Use **Settings → Personalization** for default tone and context.

Examples:

```text
- Japanese to English: concise, direct business English.
- English to Japanese: natural, short Japanese.
- Preserve project names and company names.
```

Use **Settings → Glossary** for terms that should always translate the same way.

## 5. Privacy

- Local AI requests go to the local endpoint on this Mac, such as Ollama or LM Studio.
- Gemini requests go to Google only when Gemini is selected, online, and has an API key.
- If Gemini is selected without an API key, or the Mac is offline, Verso uses Local AI for that request.
- DeepL requests go to DeepL only when a DeepL key is configured and online.
- Translation history stays on this Mac unless manually exported.
- Turn on **Settings → Behavior → Privacy mode** to avoid saving history.

## 6. If Something Fails

### Cmd+C twice does nothing

1. Menu bar icon → **Check Accessibility Permission**.
2. Re-enable Verso in macOS Accessibility settings.
3. Relaunch Verso.

### Local AI cannot connect

1. Settings → General → AI Engine → Local AI.
2. Press **Start Ollama** or **Open LM Studio**.
3. Press **Detect Local AI**. If you typed a custom endpoint, press **Refresh Models**.
4. Press **Test Local AI**.

### Translation quality is weak

1. Try another local model.
2. Add context in Settings → Personalization.
3. Add fixed terms in Settings → Glossary.
4. Edit a translation and use **Save & Learn**.
