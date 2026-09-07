import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig.load()
    private let captureService = SelectionCaptureService()
    private let translationService = TranslationService()
    private let speechService = SpeechService()
    private let loginItemManager = LoginItemManager()
    private var settingsWindowController: SettingsWindowController?
    private var commandInputWindowController: CommandInputWindowController?
    private var statusItem: NSStatusItem!
    private var isQuitting = false
    private var lastFeatureTriggeredAt: [String: Date] = [:]
    /// Last global hotkey registration outcome; surfaced in Settings and the menu bar instead of alerts.
    private var hotkeyRegistered = false
    private var hotkeyProblem: String?
    private var hotkeysSuspended = false

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        registerHotkeys()
        rebuildStatusBarMenu()
        HistoryStore.shared.onChange = { [weak self] in
            self?.rebuildStatusBarMenu()
        }
        // First run / broken setup: the Settings window is the onboarding surface.
        if !setupStatus().isReady {
            presentSettings()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Coming back from System Settings: permissions may have changed.
        settingsWindowController?.refreshStatus()
        rebuildStatusBarMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Only reachable while Settings is open (the app has no Dock icon otherwise).
        if let controller = settingsWindowController {
            controller.window?.makeKeyAndOrderFront(nil)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    // MARK: Setup status

    private var hasRequiredPermissions: Bool {
        AXIsProcessTrusted() &&
            CGPreflightListenEventAccess() &&
            CGPreflightPostEventAccess()
    }

    private func setupStatus() -> SetupStatus {
        let entry = config.features.first(where: { $0.id == "custom" })
        return SetupStatus(
            connectionConfigured: config.hasRequiredConnectionSettings,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            postEvents: CGPreflightPostEventAccess(),
            hotkeyRegistered: hotkeyRegistered || hotkeysSuspended,
            hotkeyProblem: hotkeyProblem,
            shortcutText: entry.map(hotkeyDisplay(for:)) ?? "⌥A"
        )
    }

    // MARK: Menus

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Jit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Jit", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func rebuildStatusBarMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        let status = setupStatus()
        let symbol = status.isReady ? "character.book.closed" : "exclamationmark.triangle"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Jit") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.title = " Jit"
        statusItem.button?.toolTip = status.headline ?? "Jit — \(status.shortcutText) opens the action palette"

        let menu = NSMenu()
        menu.autoenablesItems = false
        if let headline = status.headline {
            let warn = NSMenuItem(title: "Setup incomplete", action: #selector(openSettings), keyEquivalent: "")
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            warn.toolTip = headline
            menu.addItem(warn)
            let detail = NSMenuItem(title: headline, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            detail.indentationLevel = 1
            menu.addItem(detail)
            menu.addItem(.separator())
        }
        if let entryFeature = config.features.first(where: { $0.id == "custom" && $0.enabled }) {
            let item = NSMenuItem(title: "Open Palette on Selection (\(hotkeyDisplay(for: entryFeature)))", action: #selector(runFeatureFromMenu(_:)), keyEquivalent: "")
            item.representedObject = entryFeature.id
            menu.addItem(item)
        }
        let recentItem = NSMenuItem(title: "Recent Results", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        recentMenu.autoenablesItems = false
        let recent = Array(HistoryStore.shared.entries.prefix(10))
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No results yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        }
        for entry in recent {
            let item = NSMenuItem(title: "\(entry.modeTitle): \(entry.selectedText.oneLinePreview(40))", action: #selector(showHistoryEntry(_:)), keyEquivalent: "")
            item.representedObject = entry.id.uuidString
            item.target = self
            item.toolTip = entry.output.oneLinePreview(200)
            recentMenu.addItem(item)
        }
        if !recent.isEmpty {
            recentMenu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear Recent", action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            recentMenu.addItem(clear)
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { if $0.target == nil && $0.action != nil { $0.target = self } }
        statusItem.menu = menu
    }

    private func hotkeyDisplay(for feature: FeatureConfig) -> String {
        ShortcutDraft(feature: feature).display
    }

    // MARK: Global hotkeys

    private func registerHotkeys() {
        var registrations: [HotKeyManager.Registration] = []
        var nextID: UInt32 = 1
        hotkeyProblem = nil
        for feature in config.features where feature.enabled && feature.id == "custom" {
            guard let keyCode = KeyCodeMapper.shared.keyCode(for: feature.hotkeyKey) else {
                hotkeyProblem = "\(feature.hotkeyKey) is not a valid shortcut key. Pick a letter or number."
                continue
            }
            let featureID = feature.id
            registrations.append(.init(id: nextID, keyCode: keyCode, modifiers: feature.modifierFlags) { [weak self] in
                self?.handleFeatureTriggered(featureID: featureID)
            })
            nextID += 1
        }
        let ok = HotKeyManager.shared.registerAll(registrations)
        hotkeyRegistered = ok && !registrations.isEmpty
        if !ok, !registrations.isEmpty, hotkeyProblem == nil {
            let shortcut = config.features.first(where: { $0.id == "custom" }).map(hotkeyDisplay(for:)) ?? "the shortcut"
            hotkeyProblem = "\(shortcut) could not be registered — another app probably owns it. Pick a different combination."
        }
    }

    /// While the Settings recorder listens, the global hotkey must not fire (it would open the palette on top of Settings).
    private func setHotkeysSuspended(_ suspended: Bool) {
        hotkeysSuspended = suspended
        if suspended {
            HotKeyManager.shared.unregister()
        } else {
            registerHotkeys()
        }
    }

    @objc private func runFeatureFromMenu(_ sender: NSMenuItem) {
        guard let featureID = sender.representedObject as? String else { return }
        executeFeature(featureID: featureID)
    }

    private func handleFeatureTriggered(featureID: String) {
        let now = Date()
        if let last = lastFeatureTriggeredAt[featureID], now.timeIntervalSince(last) < 0.45 {
            return
        }
        lastFeatureTriggeredAt[featureID] = now
        executeFeature(featureID: featureID)
    }

    // MARK: Palette

    private func executeFeature(featureID: String) {
        guard let feature = config.features.first(where: { $0.id == featureID && $0.enabled }) else { return }
        // A new trigger always replaces the current palette (and cancels its run).
        dismissPalette()
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let mouse = NSEvent.mouseLocation
        // Fast path: synchronous Accessibility read while the source app still owns focus.
        let axSelection = captureService.readSelectionViaAccessibility()
        let anchor = axSelection?.bounds ?? NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        let palette = makePalette(defaultModeID: feature.id, anchor: anchor, sourceApp: sourceApp)
        commandInputWindowController = palette
        if let axSelection {
            palette.setSelection(axSelection.text)
            presentPalette(palette)
            return
        }
        // Slow path: show the panel right away without stealing focus, then simulate ⌘C.
        palette.window?.orderFrontRegardless()
        captureService.captureSelectedTextViaCopy { [weak self, weak palette] text in
            guard let self, let palette, self.commandInputWindowController === palette else { return }
            palette.setSelection(text)
            self.presentPalette(palette)
        }
    }

    private func dismissPalette() {
        guard let existing = commandInputWindowController else { return }
        commandInputWindowController = nil
        existing.onClose = nil
        existing.window?.close()
    }

    private func makePalette(defaultModeID: String, anchor: NSRect, sourceApp: NSRunningApplication?) -> CommandInputWindowController {
        let modeIDs = ["custom", "refine", "translate", "vocabulary"]
        let modes = modeIDs.compactMap { id -> CommandInputWindowController.Mode? in
            guard let f = config.features.first(where: { $0.id == id && $0.enabled }) else { return nil }
            let promptPreview = f.promptTemplate
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "\(f.displayName) prompt"
            return .init(
                id: f.id,
                title: f.displayName,
                requiresInstruction: f.requiresInstruction,
                supportsReplace: f.supportsReplace,
                promptPreview: promptPreview
            )
        }
        let palette = CommandInputWindowController(anchor: anchor, modes: modes, defaultModeID: defaultModeID)
        palette.lastResult = HistoryStore.shared.entries.first
        palette.speechVoiceDescription = speechService.voiceDescription
        // Setup problems are shown inline; the hotkey never redirects to Settings.
        palette.setupNotice = setupStatus().paletteNotice
        palette.onSubmit = { [weak self] modeID, instruction, selectedText, onPartial, completion in
            guard let self, let selectedFeature = self.config.features.first(where: { $0.id == modeID && $0.enabled }) else {
                completion(.failure(NSError(domain: "JitAPP", code: 404, userInfo: [NSLocalizedDescriptionKey: "Selected mode is unavailable."])))
                return nil
            }
            return self.translationService.processStreaming(
                text: selectedText,
                config: self.config,
                feature: selectedFeature,
                instruction: selectedFeature.requiresInstruction ? instruction : nil,
                onPartial: onPartial,
                completion: completion
            )
        }
        palette.onResult = { entry in
            HistoryStore.shared.add(entry)
        }
        palette.onReplace = { [weak self] output in
            self?.captureService.replaceSelectedText(with: output, targetApp: sourceApp)
        }
        palette.onToggleSpeech = { [weak self] text, onStateChange in
            self?.speechService.toggle(text: text, onStateChange: onStateChange) ?? false
        }
        palette.onStopSpeech = { [weak self] in
            self?.speechService.stop()
        }
        palette.onOpenSettings = { [weak self] in
            self?.presentSettings()
        }
        palette.onClose = { [weak self, weak palette] in
            self?.speechService.stop()
            if let self, let palette, self.commandInputWindowController === palette {
                self.commandInputWindowController = nil
            }
        }
        return palette
    }

    private func presentPalette(_ palette: CommandInputWindowController) {
        NSApp.activate(ignoringOtherApps: true)
        palette.showWindow(nil)
        palette.window?.makeKeyAndOrderFront(nil)
        palette.window?.orderFrontRegardless()
        palette.focus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak palette] in
            NSApp.activate(ignoringOtherApps: true)
            palette?.focus()
        }
        palette.beginAutoDismiss()
    }

    @objc private func showHistoryEntry(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let entry = HistoryStore.shared.entry(withID: id) else { return }
        dismissPalette()
        let mouse = NSEvent.mouseLocation
        let palette = makePalette(defaultModeID: entry.modeID, anchor: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), sourceApp: nil)
        commandInputWindowController = palette
        palette.showHistoryEntry(entry)
        presentPalette(palette)
    }

    @objc private func clearHistory() {
        HistoryStore.shared.clear()
    }

    private func openSpokenContentSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: Settings

    @objc private func openSettings() {
        presentSettings()
    }

    private func presentSettings(section: SettingsWindowController.Section? = nil) {
        if isQuitting { return }
        // Settings is the only regular window: give the app a Dock presence while it is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let controller = settingsWindowController {
            controller.show(section: section)
            return
        }

        let controller = SettingsWindowController(config: config)
        controller.statusProvider = { [weak self] in
            self?.setupStatus() ?? SetupStatus(
                connectionConfigured: false, accessibility: false, inputMonitoring: false, postEvents: false,
                hotkeyRegistered: false, hotkeyProblem: nil, shortcutText: ""
            )
        }
        controller.onCommit = { [weak self] newConfig in
            guard let self else { return }
            self.config = newConfig
            self.config.save()
            if !self.hotkeysSuspended {
                self.registerHotkeys()
            }
            self.rebuildStatusBarMenu()
        }
        controller.onHotkeyCaptureChanged = { [weak self] capturing in
            self?.setHotkeysSuspended(capturing)
        }
        controller.onTest = { [weak self] draftConfig, feature, completion in
            guard let self else { return }
            self.translationService.process(text: "hello", config: draftConfig, feature: feature) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let translated):
                        completion(.success(translated))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
        controller.onDiagnosePermissions = { [weak self] in
            self?.permissionReport() ?? "Diagnostics failed."
        }
        controller.onRequestPermissions = { [weak self] in
            self?.requestPermissionAndReport() ?? "Permission request failed."
        }
        controller.onResetPermissions = { [weak self] in
            self?.resetPermissionsAndReport() ?? "Permission reset failed."
        }
        controller.loginItemInfo = { [weak self] in
            guard let self else { return (enabled: false, text: "") }
            return (enabled: self.loginItemManager.isEnabled(), text: self.loginItemManager.statusText())
        }
        controller.onToggleLoginItem = { [weak self] in
            guard let self else { return nil }
            do {
                try self.loginItemManager.toggle()
                if SMAppService.mainApp.status == .requiresApproval {
                    return "macOS needs your approval: System Settings → General → Login Items."
                }
                return nil
            } catch {
                return "Could not update Launch at Login: \(error.localizedDescription)"
            }
        }
        controller.voiceInfo = { [weak self] in
            guard let self else { return (description: "", highQuality: true) }
            return (description: self.speechService.voiceDescription, highQuality: self.speechService.hasHighQualityVoice)
        }
        controller.onOpenVoiceSettings = { [weak self] in
            self?.openSpokenContentSettings()
        }
        controller.onClose = { [weak self] in
            guard let self else { return }
            self.settingsWindowController = nil
            self.rebuildStatusBarMenu()
            if !self.isQuitting {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        settingsWindowController = controller
        controller.show(section: section)
    }

    @objc private func quit() {
        isQuitting = true
        settingsWindowController?.window?.close()
        settingsWindowController = nil
        HotKeyManager.shared.unregister()
        NSApp.terminate(nil)
    }

    // MARK: Permissions

    private func permissionReport() -> String {
        let ax = AXIsProcessTrusted()
        let listen = CGPreflightListenEventAccess()
        let post = CGPreflightPostEventAccess()
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dylan.jitapp"
        return [
            "Bundle ID: \(bundleID)",
            "Accessibility: \(ax ? "Allowed" : "Not Allowed")",
            "Input Monitoring (ListenEvent): \(listen ? "Allowed" : "Not Allowed")",
            "Event Posting (PostEvent): \(post ? "Allowed" : "Not Allowed")",
            "",
            "If any item is not allowed, enable it in System Settings -> Privacy & Security."
        ].joined(separator: "\n")
    }

    private func requestPermissionAndReport() -> String {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        _ = CGRequestPostEventAccess()

        return permissionReport() + "\n\nIf it still shows not allowed, enable permissions manually in System Settings and restart Jit."
    }

    private func resetPermissionsAndReport() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dylan.jitapp"
        let services = ["Accessibility", "ListenEvent", "PostEvent"]
        var lines: [String] = []

        for service in services {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
                let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let msg = !err.isEmpty ? err : out
                if process.terminationStatus == 0 {
                    lines.append("tccutil reset \(service): OK")
                } else {
                    lines.append("tccutil reset \(service): failed (\(process.terminationStatus))" + (msg.isEmpty ? "" : " - \(msg)"))
                }
            } catch {
                lines.append("tccutil reset \(service): failed - \(error.localizedDescription)")
            }
        }

        lines.append("")
        lines.append("Please re-open permission prompts, or manually enable permissions in System Settings -> Privacy & Security.")
        lines.append("Then restart Jit.")
        return lines.joined(separator: "\n")
    }
}
