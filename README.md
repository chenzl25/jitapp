# Jit APP (macOS)

A menu bar app for running AI actions on selected text globally on macOS, using an OpenAI-compatible Chat API (you can use a DeepSeek API key directly).

## Features

- Global action palette hotkey (default: `Option + A`)
- Translate, Refine, and Custom Prompt actions from one floating panel
- Streaming AI output with in-panel Stop, Copy, and Replace controls
- Copy returns only the generated output; Replace pastes the output back into the source app
- Configurable options: `Base URL / API Key / Model / Target Language`
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
2. If Settings opens, use the `Get Started` checklist.
3. Paste your API key, save/test the AI connection, and grant the requested system permissions.
4. After setup is complete, Jit stays in the menu bar and no longer opens Settings on every launch.
5. Select text in any app.
6. Press the action palette hotkey (default: `Option + A`), choose an action, then run it.

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
