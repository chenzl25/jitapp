# Jit APP (macOS)

A menu bar app for running AI actions on selected text globally on macOS, using your local Codex CLI or Claude Code login, or an OpenAI-compatible Chat API.

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
- Local Codex CLI and Claude Code CLI modes reuse your saved login; no API key is required in Jit
- Choose a local Codex or Claude model, or an API `Base URL / API Key / Model`; settings are saved separately
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
2. Open Settings → AI Model. New users default to **Local Codex CLI** (or **Local Claude Code CLI** when only Claude Code is installed). Existing API configurations stay on **OpenAI-compatible API**.
3. For Codex, install the CLI and sign in once in Terminal:

   ```bash
   npm install -g @openai/codex
   codex login
   ```

   For Claude Code, install it and sign in once:

   ```bash
   curl -fsSL https://claude.ai/install.sh | bash   # or: npm install -g @anthropic-ai/claude-code
   claude auth login
   ```

   Jit automatically detects common installations, including Homebrew and `~/.local/bin`. Use **Codex path** / **Claude path** for another install location. Leave **Model** blank for the CLI's default, or enter a model your account supports (for Claude: `sonnet`, `haiku`, `opus`, or a full model name). Click **Test Connection** to verify a real request.

   For API mode, enter your Base URL, API Key and Model. Grant the requested macOS permissions in either mode.
4. After setup is complete, Jit stays in the menu bar and no longer opens Settings on every launch.
5. Select text in any app.
6. Press the action palette hotkey (default: `Option + A`), choose an action, then run it.

Both CLIs use their saved authentication; Jit never reads or copies tokens. Each request runs in a temporary directory, non-interactively, without session history, and with tools disabled:

- Codex: `codex exec` in read-only, ephemeral mode with user config ignored. Its events arrive as whole messages rather than tokens.
- Claude Code: `claude -p --safe-mode --tools ""` with a replacement system prompt, so CLAUDE.md, hooks, plugins, skills and MCP servers are not loaded. Text streams token by token. A prompt that starts with `/` is sent as text, not as a slash command.

Stop cancels the child process, and the final response replaces streamed output. Apps opened from Finder do not inherit your shell's `https_proxy`; when it is missing, Jit passes the macOS system proxy (System Settings → Network) to the CLI. Without it, Codex can spend about two minutes retrying, and Claude can fail with `403 Request not allowed` on networks that need a proxy. Tested with Codex CLI 0.159.3 and Claude Code 2.1.286; update an older CLI if Jit reports unsupported options. See the [Codex non-interactive documentation](https://developers.openai.com/codex/noninteractive).

## Verification

```bash
swift test
JIT_LIVE_CLI=1 swift test --filter Live   # real Codex and Claude calls, Finder-like environment
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
