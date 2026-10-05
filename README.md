# Jit APP (macOS)

A menu bar app for running AI actions on selected text globally on macOS, using your local Codex CLI login or an OpenAI-compatible Chat API.

## Features

- Global action palette hotkey (default: `Option + A`)
- Translate, Refine, Vocabulary, and Custom Prompt actions from one floating panel
- Vocabulary mode explains English word meaning, pronunciation, usage, examples, and common notes
- Native macOS speech button in Vocabulary mode for fast selected-text pronunciation
- Streaming AI output with in-panel Stop, Copy, and Replace controls
- Copy returns only the generated output; Replace pastes the output back into the source app
- Palette keyboard: `↑/↓` or `⌘1–4` switch actions, `↩` runs, `⌘C` copies the result, `⌘↩` replaces, `⎋` stops/closes
- Translate detects the source language and flips direction automatically (e.g. Chinese → English)
- The palette opens instantly at the selection, works without a selection (Custom), and is resizable once output appears
- Recent Results in the menu bar reopen previous outputs; "Last Result" is one click away when nothing is selected
- Speech uses the best installed English voice (premium/enhanced when available) with a shortcut to download better voices
- Local Codex CLI mode reuses your saved login; no API key is required in Jit
- Choose a local Codex model or an API `Base URL / API Key / Model`; settings are saved separately
- Launch-at-login toggle from the menu bar

## Run Locally

```bash
swift run
```

## Build a Double-Clickable `.app` / `.dmg`

```bash
./scripts/release.sh
```

Output:

- `dist/Jit APP.app`
- `dist/Jit-APP.dmg`

You can also run the steps separately:

```bash
./scripts/build_app.sh
./scripts/package_dmg.sh
```

## Signing

By default, the app is signed with ad-hoc signing (works on the local machine).

If you have a Developer ID certificate, specify it at build time:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
```

## First-Time Setup

1. Double-click `dist/Jit APP.app` to open it.
2. Open Settings → AI Model. New users default to **Local Codex CLI**. Existing API configurations stay on **OpenAI-compatible API**.
3. For Codex, install the CLI and sign in once in Terminal:

   ```bash
   npm install -g @openai/codex
   codex login
   ```

   Jit automatically detects common installations, including Homebrew. Use **Codex path** for another install location. Leave **Model** blank for Codex's default, or enter a model supported by your Codex account. Click **Test Connection** to verify a real request.

   For API mode, enter your Base URL, API Key and Model. Grant the requested macOS permissions in either mode.
4. After setup is complete, Jit stays in the menu bar and no longer opens Settings on every launch.
5. Select text in any app.
6. Press the action palette hotkey (default: `Option + A`), choose an action, then run it.

Codex uses saved CLI authentication without reading or copying tokens into Jit. Each request runs in a temporary directory using read-only, ephemeral non-interactive mode with user-configured tools disabled. Stop cancels the child process. CLI events can arrive as complete messages rather than individual tokens; the final response replaces earlier output. Codex needs internet access and available account usage. This integration is tested with Codex CLI 0.159.3; update an older CLI if Jit reports unsupported options. See the [official non-interactive documentation](https://developers.openai.com/codex/noninteractive).

## Verification

```bash
swift test
swift build
./scripts/release.sh
```

## Permissions and System Settings

To read selected text globally, enable this macOS permission:

- `System Settings -> Privacy & Security -> Accessibility`

To enable launch at login, if the menu shows "Waiting for system approval", go to:

- `System Settings -> General -> Login Items`

## Scripts

- `scripts/generate_icon.swift`: Generate a 1024px PNG icon
- `scripts/make_icon.sh`: Generate `.icns`
- `scripts/build_app.sh`: Build and assemble the `.app`
- `scripts/sign_app.sh`: Sign and verify the app
- `scripts/package_dmg.sh`: Package a `.dmg`
- `scripts/release.sh`: One-command build + package
