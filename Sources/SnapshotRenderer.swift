#if DEBUG
import AppKit

/// Debug-only: `JIT_SNAPSHOT_DIR=/tmp/jit swift run` renders the palette and Settings
/// in representative states (light + dark) to PNGs offscreen and exits. No screen
/// recording permission is needed because views draw themselves into a bitmap.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["JIT_SNAPSHOT_DIR"], !path.isEmpty else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        if let icon = NSImage(contentsOf: root.appendingPathComponent("Assets/AppIcon-1024.png")) {
            NSApp.applicationIconImage = icon
        }
        renderPalettes(into: directory)
        renderSettings(into: directory)
        UserDefaults.standard.removeObject(forKey: "paletteExpandedSize")
        return true
    }

    // MARK: Palette

    private static let modes: [CommandInputWindowController.Mode] = [
        .init(id: "translate", title: "Translate", requiresInstruction: false, supportsReplace: false, promptPreview: ""),
        .init(id: "refine", title: "Polish", requiresInstruction: false, supportsReplace: true, promptPreview: ""),
        .init(id: "custom", title: "Custom", requiresInstruction: true, supportsReplace: true, promptPreview: ""),
        .init(id: "vocabulary", title: "Words", requiresInstruction: false, supportsReplace: false, promptPreview: ""),
    ]

    private static let words = """
    Headword: ephemeral
    Part of speech: adj.
    IPA: /ɪˈfem(ə)rəl/
    Meaning: 短暂的，转瞬即逝的 — lasting for a very short time
    Usage:
    - ephemeral storage
    - ephemeral nature of
    - largely ephemeral
    Examples:
    - Fame on social media is often ephemeral. | 社交媒体上的名气往往转瞬即逝。
    - The container writes logs to ephemeral storage. | 容器把日志写入临时存储。
    Notes: Formal register; everyday synonym: short-lived.
    """

    private static func palette(
        _ name: String, dark: Bool, mode: String, selection: String?, output: String? = nil, running: Bool = false,
        error: String? = nil, elapsed: TimeInterval? = nil, instruction: String? = nil, model: String = "Codex · gpt-5.1",
        recent: [String] = [], notice: String? = nil, size: NSSize? = nil, into directory: URL
    ) {
        if let size {
            UserDefaults.standard.set(NSStringFromSize(size), forKey: "paletteExpandedSize")
        } else {
            UserDefaults.standard.removeObject(forKey: "paletteExpandedSize")
        }
        let controller = CommandInputWindowController(anchor: NSRect(x: 200, y: 700, width: 1, height: 1), modes: modes, defaultModeID: mode)
        controller.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.modelLabel = model
        controller.recentInstructions = recent
        controller.directionLabel = { _ in "English → 简体中文" }
        controller.setupNotice = notice
        controller.debugShow(modeID: mode, selection: selection, output: output, running: running, error: error, elapsed: elapsed, instruction: instruction)
        if let window = controller.window {
            write(window: window, dark: dark, to: directory.appendingPathComponent("\(name).png"))
        }
        controller.onClose = nil
        controller.window?.close()
    }

    private static func renderPalettes(into directory: URL) {
        let selection = "The streaming job keeps the backfill snapshot consistent across barriers, so no row is emitted twice even when the upstream is under heavy write load."
        palette("palette-translate-light", dark: false, mode: "translate", selection: selection,
                output: "1) Translation: 流式作业会在各个 barrier 之间保持回填快照的一致性，因此即使上游处于高写入负载下，也不会有任何一行被重复输出。\n2) Useful English words/phrases:\n- backfill — fill in historical data; backfill a table; We backfill the index overnight.\n- under heavy load — while very busy; The API slows down under heavy load.",
                elapsed: 1.4, size: NSSize(width: 620, height: 470), into: directory)
        palette("palette-translate-dark", dark: true, mode: "translate", selection: selection,
                output: "1) Translation: 流式作业会在各个 barrier 之间保持回填快照的一致性，因此即使上游处于高写入负载下，也不会有任何一行被重复输出。",
                elapsed: 1.4, size: NSSize(width: 620, height: 360), into: directory)
        palette("palette-custom-light", dark: false, mode: "custom",
                selection: "hi team, the deploy is gonna slip to thursday because the migration script still breaks on the old partitions, sorry about that, will update once its fixed",
                instruction: "改写成给客户的正式邮件，语气诚恳，保留周四这个时间",
                recent: ["更简洁", "Summarize in 3 bullets", "Explain this code"], into: directory)
        palette("palette-words-dark", dark: true, mode: "vocabulary", selection: "ephemeral",
                output: String(words.prefix(through: words.range(of: "ephemeral storage.")!.lowerBound).dropLast()), running: true,
                model: "Claude Code · sonnet", size: NSSize(width: 620, height: 520), into: directory)
        palette("palette-words-light", dark: false, mode: "vocabulary", selection: "ephemeral", output: words, elapsed: 3.2,
                model: "Claude Code · sonnet", size: NSSize(width: 620, height: 560), into: directory)
        palette("palette-polish-idle-light", dark: false, mode: "refine", selection: "the deploy is gonna slip to thursday because the migration script still breaks", into: directory)
        palette("palette-noselection-dark", dark: true, mode: "custom", selection: nil,
                recent: ["更简洁", "Summarize in 3 bullets"],
                notice: "Missing system permissions — reading and replacing text may fail.", into: directory)
        palette("palette-error-light", dark: false, mode: "translate", selection: "hello world",
                error: "Sign in to Codex by running codex login in Terminal, then try again. No API key is needed in Jit.",
                size: NSSize(width: 620, height: 380), into: directory)
    }

    // MARK: Settings

    private static func renderSettings(into directory: URL) {
        let sections: [(SettingsWindowController.Section, String)] = [(.general, "general"), (.model, "model"), (.actions, "actions"), (.permissions, "permissions")]
        for dark in [false, true] {
            for (section, name) in sections {
                for broken in [false, true] where !(broken && section != .general) {
                    let controller = SettingsWindowController(config: AppConfig.defaults)
                    controller.statusProvider = {
                        SetupStatus(
                            connectionConfigured: true, connectionProblem: "", accessibility: !broken, inputMonitoring: true,
                            postEvents: true, hotkeyRegistered: true, hotkeyProblem: nil, shortcutText: "⌥A"
                        )
                    }
                    controller.loginItemInfo = { (enabled: true, text: "Launch at Login: Enabled") }
                    controller.voiceInfo = { (description: "Ava · Premium · en-US", highQuality: true) }
                    controller.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    controller.window?.setContentSize(NSSize(width: 940, height: 660))
                    controller.refreshStatus()
                    controller.showSection(section, animated: false)
                    if let window = controller.window {
                        let suffix = broken ? "-setup" : ""
                        write(window: window, dark: dark, to: directory.appendingPathComponent("settings-\(name)\(suffix)-\(dark ? "dark" : "light").png"))
                    }
                    controller.onClose = nil
                    controller.window?.delegate = nil
                    controller.window?.close()
                }
            }
        }
    }

    // MARK: Rendering

    private static func write(window: NSWindow, dark: Bool, to url: URL) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        let panel = NSImage(size: bounds.size)
        panel.addRepresentation(rep)

        // Compose on a desktop-like backdrop with a soft shadow so corners and borders are visible.
        let margin: CGFloat = 36
        let canvasSize = NSSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2)
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width * scale), pixelsHigh: Int(canvasSize.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        canvas.size = canvasSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        (dark ? NSColor(srgbHex: 0x1b2129) : NSColor(srgbHex: 0xd9dde3)).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.45 : 0.18)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        panel.draw(in: NSRect(x: margin, y: margin, width: bounds.width, height: bounds.height))
        NSGraphicsContext.restoreGraphicsState()
        if let data = canvas.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
#endif
