import AppKit
import Carbon.HIToolbox
import JitCLI

// MARK: - Setup status (single source of truth for banners, badges, menu bar, palette)

struct SetupStatus {
    var connectionConfigured: Bool
    var connectionProblem: String = "Set up an AI connection to start running actions."
    var accessibility: Bool
    var inputMonitoring: Bool
    var postEvents: Bool
    var hotkeyRegistered: Bool
    var hotkeyProblem: String?
    var shortcutText: String

    var permissionsGranted: Bool { accessibility && inputMonitoring && postEvents }
    var isReady: Bool { connectionConfigured && permissionsGranted && hotkeyRegistered }
    var missingPermissionCount: Int { [accessibility, inputMonitoring, postEvents].filter { !$0 }.count }

    /// One-line problem statement for the Settings banner and the menu bar. `nil` when everything is ready.
    var headline: String? {
        if !permissionsGranted {
            return "Jit needs system permissions to read and replace selected text."
        }
        if !connectionConfigured {
            return connectionProblem
        }
        if !hotkeyRegistered {
            return hotkeyProblem ?? "The global shortcut \(shortcutText) is not registered."
        }
        return nil
    }

    /// Shorter variant shown inside the action palette.
    var paletteNotice: String? {
        if !permissionsGranted {
            return "Missing system permissions — reading and replacing text may fail."
        }
        if !connectionConfigured {
            return connectionProblem
        }
        return nil
    }
}

// MARK: - Shortcut draft

struct ShortcutDraft: Equatable {
    var key: String
    var option: Bool
    var command: Bool
    var control: Bool
    var shift: Bool

    init(feature: FeatureConfig) {
        key = feature.hotkeyKey.uppercased()
        option = feature.hotkeyOption
        command = feature.hotkeyCommand
        control = feature.hotkeyControl
        shift = feature.hotkeyShift
    }

    init(key: String, option: Bool, command: Bool, control: Bool, shift: Bool) {
        self.key = key.uppercased()
        self.option = option
        self.command = command
        self.control = control
        self.shift = shift
    }

    var hasModifier: Bool { option || command || control || shift }

    /// Modifier glyphs then the key, e.g. ["⌥", "A"].
    var parts: [String] {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(key.uppercased())
        return parts
    }

    var display: String { parts.joined() }

    func apply(to feature: inout FeatureConfig) {
        feature.hotkeyKey = key
        feature.hotkeyOption = option
        feature.hotkeyCommand = command
        feature.hotkeyControl = control
        feature.hotkeyShift = shift
    }
}

// MARK: - Settings building blocks

/// Sidebar navigation row: icon, title, optional warning badge.
@MainActor
final class SidebarItemButton: NSButton {
    let titleText: String
    let symbolName: String
    var isSelectedItem = false { didSet { needsDisplay = true } }
    var badge: String? { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    init(title: String, symbol: String) {
        titleText = title
        symbolName = symbol
        super.init(frame: .zero)
        super.title = title
        isBordered = false
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        action = #selector(clicked)
        focusRingType = .none
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func clicked() { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        if isSelectedItem {
            Lantor.selectedFill.setFill()
            path.fill()
            Lantor.selectedBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if hovering {
            Lantor.hover.setFill()
            path.fill()
        }
        if let icon = Lantor.symbol(symbolName, size: 14, weight: .medium, color: isSelectedItem ? Lantor.accent : Lantor.muted) {
            let size = icon.size
            icon.draw(in: NSRect(x: 10 + (20 - size.width) / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: Lantor.font(14, isSelectedItem ? .semibold : .medium), .foregroundColor: Lantor.ink]
        let size = (titleText as NSString).size(withAttributes: attrs)
        (titleText as NSString).draw(at: NSPoint(x: 40, y: bounds.midY - size.height / 2), withAttributes: attrs)
        if let badge {
            let badgeAttrs: [NSAttributedString.Key: Any] = [.font: Lantor.font(11, .bold), .foregroundColor: Lantor.warning]
            let badgeSize = (badge as NSString).size(withAttributes: badgeAttrs)
            let width = max(22, badgeSize.width + 12)
            let rect = NSRect(x: bounds.maxX - 10 - width, y: bounds.midY - 9, width: width, height: 18)
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
            Lantor.warningSoft.setFill()
            pill.fill()
            Lantor.warningBorder.setStroke()
            pill.stroke()
            (badge as NSString).draw(at: NSPoint(x: rect.midX - badgeSize.width / 2, y: rect.midY - badgeSize.height / 2), withAttributes: badgeAttrs)
        }
    }
}

/// Selectable card (connection type): icon tile, title and a short description.
@MainActor
final class ChoiceCard: NSView {
    var isSelected = false { didSet { tile.selected = isSelected; titleLabel.textColor = isSelected ? Lantor.accent : Lantor.ink; needsDisplay = true } }
    var onClick: (() -> Void)?
    private let tile: LantorIconTile
    private let titleLabel: NSTextField
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    init(symbol: String, title: String, detail: String) {
        tile = LantorIconTile(symbol)
        titleLabel = Lantor.label(title, Lantor.font(14, .semibold), Lantor.ink)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let detailLabel = Lantor.label(detail, Lantor.font(12), Lantor.muted, lines: 2)
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [tile, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13)
        Lantor.panelStrong.setFill()
        path.fill()
        if isSelected {
            Lantor.selectedFill.setFill()
            path.fill()
            let halo = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), xRadius: 14.5, yRadius: 14.5)
            halo.lineWidth = 3
            Lantor.focusRing.setStroke()
            halo.stroke()
            Lantor.accent.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        } else {
            (hovering ? Lantor.lineStrong : Lantor.line).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// Flipped vertical stack so scrolled pages start at the top.
@MainActor
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SettingsSidebarView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Lantor.sidebar.setFill()
        bounds.fill()
        Lantor.line.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}

@MainActor
final class SettingsHeaderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Lantor.panel.withAlphaComponent(0.92).setFill()
        bounds.fill()
        Lantor.line.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

@MainActor
final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Lantor.appBackground.setFill()
        bounds.fill()
    }
}

// MARK: - Settings window

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    enum Section: String, CaseIterable {
        case general
        case model
        case actions
        case permissions

        var title: String {
            switch self {
            case .general: return "General"
            case .model: return "AI Model"
            case .actions: return "Actions"
            case .permissions: return "Permissions"
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "Shortcut, startup, translation and voice."
            case .model: return "Use your local Codex or Claude Code login, or an OpenAI-compatible API."
            case .actions: return "The prompts behind Translate, Polish, Custom and Words."
            case .permissions: return "System access Jit needs to read and replace selected text."
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .model: return "cpu"
            case .actions: return "text.bubble"
            case .permissions: return "checkmark.shield"
            }
        }
    }

    private enum Theme {
        static let sidebarWidth: CGFloat = 236
        static let contentPadding: CGFloat = 30
        static let titlebarInset: CGFloat = 50
        static let labelColumn: CGFloat = 132
    }

    private enum FeedbackKind {
        case neutral
        case success
        case error
    }

    // MARK: Callbacks (wired by AppDelegate)

    var statusProvider: (() -> SetupStatus)?
    /// Called on every change; the receiver persists and re-registers hotkeys.
    var onCommit: ((AppConfig) -> Void)?
    /// `true` while the shortcut recorder is listening; global hotkeys must be suspended.
    var onHotkeyCaptureChanged: ((Bool) -> Void)?
    var onTest: ((AppConfig, FeatureConfig, @escaping @MainActor (Result<String, Error>) -> Void) -> Void)?
    var onDiagnosePermissions: (() -> String)?
    var onRequestPermissions: (() -> String)?
    var onResetPermissions: (() -> String)?
    var loginItemInfo: (() -> (enabled: Bool, text: String))?
    /// Returns an error message when toggling failed.
    var onToggleLoginItem: (() -> String?)?
    var voiceInfo: (() -> (description: String, highQuality: Bool))?
    /// Installed English voices (best first) and the saved choice (nil = automatic).
    var voiceOptions: (() -> [(id: String, name: String)])?
    var selectedVoiceID: (() -> String?)?
    var onSelectVoice: ((String?) -> Void)?
    var onOpenVoiceSettings: (() -> Void)?
    var onClose: (() -> Void)?

    // MARK: Draft state

    private let baseURLField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let codexPathField = NSTextField(string: "")
    private let codexModelField = NSTextField(string: "")
    private let claudePathField = NSTextField(string: "")
    private let claudeModelField = NSTextField(string: "")
    private var backend: AIBackend
    private var targetLanguage: String
    private var featureConfigs: [FeatureConfig]
    private var shortcut: ShortcutDraft
    private var status: SetupStatus?

    // MARK: Views

    private var sectionButtons: [Section: SidebarItemButton] = [:]
    private var sectionPages: [Section: NSView] = [:]
    private var currentSection: Section = .general
    private let detailTitleLabel = Lantor.label("", Lantor.font(21, .bold), Lantor.ink)
    private let detailSubtitleLabel = Lantor.label("", Lantor.font(13), Lantor.muted)
    private let savedIcon = NSImageView()
    private let savedLabel = Lantor.label("Saved automatically", Lantor.font(12), Lantor.muted)
    private let pageStack = FlippedStackView()
    private let banner = LantorSurface(fill: Lantor.warningSoft, stroke: Lantor.warningBorder, radius: 13)
    private let bannerLabel = Lantor.label("", Lantor.font(13, .medium), Lantor.warning, lines: 2)
    private let bannerButton = LantorButton("Fix", kind: .secondary)
    private var bannerTarget: Section = .permissions
    private let statusTitle = Lantor.label("", Lantor.font(13, .semibold), Lantor.ink)
    private let statusDetail = Lantor.label("", Lantor.font(12.5), Lantor.muted, lines: 3)
    private var toastWorkItem: DispatchWorkItem?

    private var shortcutKeys: NSStackView?
    private weak var shortcutChip: LantorChip?
    private weak var shortcutDetail: NSTextField?
    private weak var shortcutButton: LantorButton?
    private weak var testButton: LantorButton?
    private weak var testSpinner: NSProgressIndicator?
    private weak var testChip: LantorChip?
    private weak var testErrorLabel: NSTextField?
    private weak var cliLocationIcon: NSImageView?
    private weak var cliLocationLabel: NSTextField?
    private var connectionTestGeneration = 0
    private weak var loginSwitch: NSSwitch?
    private weak var loginDetail: NSTextField?
    private weak var permissionsFeedbackLabel: NSTextField?

    private var hotkeyCaptureMonitor: Any?
    private var escapeMonitor: Any?
    private var promptEditor: PromptEditorWindowController?

    private static let frameAutosaveName = "JitSettingsWindow"

    // MARK: Init

    init(config: AppConfig) {
        backend = config.backend
        targetLanguage = config.targetLanguage
        featureConfigs = config.features
        let entry = config.features.first(where: { $0.id == "custom" }) ?? AppConfig.defaults.features[0]
        shortcut = ShortcutDraft(feature: entry)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Jit Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 820, height: 560)
        window.isReleasedWhenClosed = false
        window.backgroundColor = Lantor.appBackground
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        baseURLField.stringValue = config.baseURL
        apiKeyField.stringValue = config.apiKey
        modelField.stringValue = config.model
        codexPathField.stringValue = config.codexPath
        codexModelField.stringValue = config.codexModel
        claudePathField.stringValue = config.claudePath
        claudeModelField.stringValue = config.claudeModel

        configureInputFields()
        buildUI()
        installEscapeMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Window lifecycle

    func windowWillClose(_ notification: Notification) {
        stopHotkeyCapture()
        window?.makeFirstResponder(nil)
        commit()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        onClose?()
    }

    func show(section: Section? = nil) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refreshStatus()
        if let section {
            showSection(section, animated: false)
        } else if let status, !status.isReady {
            showSection(bannerTarget, animated: false)
        }
    }

    func focusPrimaryField() {
        showSection(.model, animated: false)
        window?.makeFirstResponder(primaryConnectionField)
    }

    /// Re-reads permissions/hotkey state and updates every status surface in the window.
    func refreshStatus() {
        status = statusProvider?()
        updateBanner()
        updateBadges()
        updateSidebarStatus()
        updateShortcutStatus()
        sectionPages[.permissions] = nil
        if currentSection == .permissions {
            showSection(.permissions, animated: false, force: true)
        }
    }

    // MARK: Draft → config

    private func draftConfig() -> AppConfig {
        var features = featureConfigs
        for index in features.indices {
            features[index].enabled = true
            if features[index].id == "custom" {
                shortcut.apply(to: &features[index])
            }
        }
        return AppConfig(
            backend: backend,
            codexPath: codexPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            codexModel: codexModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            claudePath: claudePathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            claudeModel: claudeModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            targetLanguage: targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines),
            features: features
        )
    }

    /// Persists the current draft immediately. Every control calls this on change; there is no Save button.
    private func commit(toast message: String? = nil) {
        onCommit?(draftConfig())
        refreshStatus()
        if let message {
            showToast(message, kind: .success)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField,
           [baseURLField, apiKeyField, modelField, codexPathField, codexModelField, claudePathField, claudeModelField].contains(where: { $0 === field }) {
            invalidateConnectionTest()
            updateCLILocation()
        }
        commit()
    }

    private func invalidateConnectionTest() {
        connectionTestGeneration += 1
        testButton?.isEnabled = true
        testSpinner?.stopAnimation(nil)
        testChip?.isHidden = true
        testErrorLabel?.isHidden = true
    }

    /// Path and model fields for the selected local CLI.
    private var cliFields: (tool: LocalCLITool, path: NSTextField, model: NSTextField)? {
        switch backend {
        case .codexCLI: return (.codex, codexPathField, codexModelField)
        case .claudeCLI: return (.claude, claudePathField, claudeModelField)
        case .chatAPI: return nil
        }
    }

    private var primaryConnectionField: NSTextField { cliFields?.model ?? apiKeyField }

    private func updateCLILocation() {
        guard let cli = cliFields else { return }
        let found = LocalCLI.executable(for: cli.tool, path: cli.path.stringValue)
        let text = NSMutableAttributedString()
        if let found {
            text.append(NSAttributedString(string: "Detected  ", attributes: [.font: Lantor.font(12, .medium), .foregroundColor: Lantor.success]))
            text.append(NSAttributedString(string: found.path, attributes: [.font: Lantor.mono(11.5), .foregroundColor: Lantor.success]))
        } else {
            text.append(NSAttributedString(
                string: "Not found. Install \(cli.tool.displayName), then run \(cli.tool.loginCommand) in Terminal.",
                attributes: [.font: Lantor.font(12, .medium), .foregroundColor: Lantor.warning]
            ))
        }
        cliLocationLabel?.attributedStringValue = text
        cliLocationIcon?.image = found == nil
            ? Lantor.symbol("exclamationmark.triangle.fill", size: 11, weight: .semibold, color: Lantor.warning)
            : Lantor.symbol("checkmark", size: 11, weight: .bold, color: Lantor.success)
    }

    // MARK: Escape closes the window (unless a text field or the recorder owns the key)

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  event.window === window,
                  event.keyCode == 53,
                  self.hotkeyCaptureMonitor == nil,
                  window.attachedSheet == nil else { return event }
            if window.firstResponder is NSTextView {
                window.makeFirstResponder(nil)
                return nil
            }
            window.close()
            return nil
        }
    }

    // MARK: UI construction

    private func configureInputFields() {
        [baseURLField, apiKeyField, modelField, codexPathField, codexModelField, claudePathField, claudeModelField].forEach { field in
            field.font = Lantor.font(13)
            field.textColor = Lantor.ink
            field.focusRingType = .none
            field.drawsBackground = false
            field.isBordered = false
            field.delegate = self
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.lineBreakMode = .byTruncatingTail
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        func placeholder(_ field: NSTextField, _ text: String) {
            field.placeholderAttributedString = NSAttributedString(string: text, attributes: [.foregroundColor: Lantor.placeholder, .font: Lantor.font(13)])
        }
        placeholder(baseURLField, "https://api.openai.com/v1")
        placeholder(apiKeyField, "sk-…")
        placeholder(modelField, "gpt-4o-mini")
        placeholder(codexPathField, "Auto-detect")
        placeholder(codexModelField, "Codex default")
        placeholder(claudePathField, "Auto-detect")
        placeholder(claudeModelField, "Claude default, or sonnet / haiku / opus")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        sectionButtons.removeAll()
        sectionPages.removeAll()

        let background = SettingsBackgroundView()
        background.translatesAutoresizingMaskIntoConstraints = false
        let sidebar = sidebarView()
        let detail = detailView()
        contentView.addSubview(background)
        contentView.addSubview(sidebar)
        contentView.addSubview(detail)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth),
            detail.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            detail.topAnchor.constraint(equalTo: contentView.topAnchor),
            detail.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        showSection(.general, animated: false)
    }

    private func sidebarView() -> NSView {
        let sidebar = SettingsSidebarView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let appTitle = Lantor.label("Jit", Lantor.font(18, .bold), Lantor.ink)
        let appSubtitle = Lantor.label("Settings", Lantor.font(12), Lantor.muted)
        let identity = NSStackView(views: [appTitle, appSubtitle])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 0
        let workspace = NSStackView(views: [LantorAppIcon(size: 30), identity])
        workspace.orientation = .horizontal
        workspace.alignment = .centerY
        workspace.spacing = 10
        workspace.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)

        let navLabel = Lantor.legend("Preferences")
        let navLabelRow = NSStackView(views: [navLabel])
        navLabelRow.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)

        let nav = NSStackView()
        nav.orientation = .vertical
        nav.alignment = .leading
        nav.spacing = 2
        nav.translatesAutoresizingMaskIntoConstraints = false
        for section in Section.allCases {
            let item = SidebarItemButton(title: section.title, symbol: section.symbol)
            item.onClick = { [weak self] in self?.showSection(section, animated: true) }
            sectionButtons[section] = item
            nav.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true
        }

        let top = NSStackView(views: [workspace, navLabelRow, nav])
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 6
        top.setCustomSpacing(18, after: workspace)
        top.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(top)

        // Readiness card pinned to the bottom of the sidebar.
        let statusCard = LantorSurface(fill: Lantor.panelStrong, stroke: Lantor.line, radius: 13)
        let dotView = StatusDotView()
        statusDotView = dotView
        let titleRow = NSStackView(views: [dotView, statusTitle])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        let statusStack = NSStackView(views: [titleRow, statusDetail])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 4
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusStack)
        sidebar.addSubview(statusCard)

        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            top.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            top.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: Theme.titlebarInset),
            nav.widthAnchor.constraint(equalTo: top.widthAnchor),
            statusCard.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            statusCard.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -15),
            statusCard.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),
            statusStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 12),
            statusStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -12),
            statusStack.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 10),
            statusStack.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -11),
            statusDetail.widthAnchor.constraint(equalTo: statusStack.widthAnchor),
        ])
        statusDetail.preferredMaxLayoutWidth = Theme.sidebarWidth - 29 - 24
        return sidebar
    }

    private var statusDotView: StatusDotView?

    private func detailView() -> NSView {
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false

        let header = SettingsHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let titles = NSStackView(views: [detailTitleLabel, detailSubtitleLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 3
        titles.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailSubtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        savedIcon.image = Lantor.symbol("checkmark", size: 11, weight: .bold, color: Lantor.success)
        savedIcon.setContentHuggingPriority(.required, for: .horizontal)
        savedLabel.setContentHuggingPriority(.required, for: .horizontal)
        let saved = NSStackView(views: [savedIcon, savedLabel])
        saved.orientation = .horizontal
        saved.alignment = .centerY
        saved.spacing = 5
        saved.setContentHuggingPriority(.required, for: .horizontal)
        saved.translatesAutoresizingMaskIntoConstraints = false
        titles.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titles)
        header.addSubview(saved)

        // Banner (setup problems) sits above the page inside the scroll content.
        let bannerIcon = NSImageView()
        bannerIcon.image = Lantor.symbol("exclamationmark.triangle.fill", size: 14, weight: .semibold, color: Lantor.warning)
        bannerIcon.setContentHuggingPriority(.required, for: .horizontal)
        bannerButton.height = 26
        bannerButton.fontSize = 12
        bannerButton.onClick = { [weak self] in self?.bannerActionTapped() }
        let bannerSpacer = NSView()
        bannerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        bannerLabel.preferredMaxLayoutWidth = 440
        let bannerRow = NSStackView(views: [bannerIcon, bannerLabel, bannerSpacer, bannerButton])
        bannerRow.orientation = .horizontal
        bannerRow.alignment = .centerY
        bannerRow.spacing = 10
        bannerRow.translatesAutoresizingMaskIntoConstraints = false
        bannerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        banner.addSubview(bannerRow)
        NSLayoutConstraint.activate([
            bannerRow.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            bannerRow.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -10),
            bannerRow.topAnchor.constraint(equalTo: banner.topAnchor, constant: 9),
            bannerRow.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -9),
        ])
        banner.isHidden = true
        banner.draggable = false

        let pageScroll = NSScrollView()
        pageScroll.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.hasVerticalScroller = true
        pageScroll.autohidesScrollers = true
        pageScroll.borderType = .noBorder
        pageScroll.drawsBackground = false
        pageScroll.automaticallyAdjustsContentInsets = false
        pageScroll.contentInsets = NSEdgeInsets(top: 20, left: Theme.contentPadding, bottom: 28, right: Theme.contentPadding)
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = 20
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.documentView = pageStack
        pageStack.addArrangedSubview(banner)
        banner.widthAnchor.constraint(equalTo: pageStack.widthAnchor).isActive = true

        detail.addSubview(header)
        detail.addSubview(pageScroll)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            header.topAnchor.constraint(equalTo: detail.topAnchor),
            titles.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Theme.contentPadding),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: saved.leadingAnchor, constant: -16),
            titles.topAnchor.constraint(equalTo: header.topAnchor, constant: 26),
            titles.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -16),
            saved.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Theme.contentPadding),
            saved.bottomAnchor.constraint(equalTo: titles.bottomAnchor, constant: -1),

            pageScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            pageScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            pageScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            pageScroll.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
            pageStack.widthAnchor.constraint(equalTo: pageScroll.widthAnchor, constant: -(Theme.contentPadding * 2)),
        ])
        return detail
    }

    private func bannerActionTapped() {
        showSection(bannerTarget, animated: true)
        if bannerTarget == .model {
            window?.makeFirstResponder(primaryConnectionField)
        }
    }

    // MARK: Section switching

    func showSection(_ section: Section, animated: Bool, force: Bool = false) {
        stopHotkeyCapture()
        currentSection = section
        for (item, button) in sectionButtons {
            button.isSelectedItem = item == section
        }
        updateBanner()
        detailTitleLabel.stringValue = section.title
        detailSubtitleLabel.stringValue = section.subtitle

        let nextPage = pageView(for: section)
        let previous = pageStack.arrangedSubviews.count > 1 ? pageStack.arrangedSubviews[1] : nil
        if previous === nextPage, !force { return }
        if let previous {
            pageStack.removeArrangedSubview(previous)
            previous.removeFromSuperview()
        }
        if animated {
            nextPage.alphaValue = 0
        }
        pageStack.addArrangedSubview(nextPage)
        nextPage.widthAnchor.constraint(equalTo: pageStack.widthAnchor).isActive = true
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                nextPage.animator().alphaValue = 1
            }
        }
    }

    private func pageView(for section: Section) -> NSView {
        if let page = sectionPages[section] { return page }
        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 20
        page.translatesAutoresizingMaskIntoConstraints = false
        let groups: [NSView]
        switch section {
        case .general:
            groups = [
                group("Palette shortcut", card([shortcutRow()])),
                group("Behavior", card([loginRow(), languageRow(), voiceRow()])),
            ]
        case .model:
            groups = modelGroups()
        case .actions:
            groups = [actionsGroup()]
        case .permissions:
            groups = permissionsGroups()
        }
        for item in groups {
            page.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        }
        sectionPages[section] = page
        return page
    }

    // MARK: Status surfaces

    private func updateBanner() {
        guard let status, let headline = status.headline else {
            banner.isHidden = true
            return
        }
        banner.isHidden = false
        bannerLabel.stringValue = headline
        if !status.permissionsGranted {
            bannerTarget = .permissions
            bannerButton.text = "Fix in Permissions"
        } else if !status.connectionConfigured {
            bannerTarget = .model
            bannerButton.text = "Set Up AI Model"
        } else {
            bannerTarget = .general
            bannerButton.text = "Change Shortcut"
        }
        bannerButton.isHidden = currentSection == bannerTarget
    }

    private func updateBadges() {
        guard let status else { return }
        sectionButtons[.general]?.badge = status.hotkeyRegistered ? nil : "!"
        sectionButtons[.model]?.badge = status.connectionConfigured ? nil : "!"
        sectionButtons[.permissions]?.badge = status.permissionsGranted ? nil : "\(status.missingPermissionCount)"
        sectionButtons[.actions]?.badge = nil
    }

    private func updateSidebarStatus() {
        guard let status else { return }
        if status.isReady {
            statusDotView?.color = Lantor.success
            statusDotView?.halo = Lantor.successSoft
            statusTitle.stringValue = "Ready"
            statusDetail.stringValue = "Press \(shortcut.display) in any app to open the palette."
        } else {
            statusDotView?.color = Lantor.warning
            statusDotView?.halo = Lantor.warningSoft
            statusTitle.stringValue = "Setup incomplete"
            if !status.permissionsGranted, !status.accessibility {
                statusDetail.stringValue = "Accessibility access is off — Jit can't read or replace the selection."
            } else {
                statusDetail.stringValue = status.headline ?? ""
            }
        }
    }

    private func updateShortcutStatus() {
        guard let shortcutChip, let shortcutDetail else { return }
        rebuildShortcutKeys()
        if hotkeyCaptureMonitor != nil {
            shortcutButton?.text = "Cancel"
            let fallback = ShortcutDraft(feature: AppConfig.defaults.features.first(where: { $0.id == "custom" }) ?? AppConfig.defaults.features[0])
            shortcutChip.text = "Listening"
            shortcutChip.tone = .thinking
            shortcutChip.pulse = true
            shortcutDetail.stringValue = "Press the new shortcut. Esc cancels, ⌫ restores \(fallback.display)."
            shortcutDetail.textColor = Lantor.muted
            return
        }
        shortcutButton?.text = "Record new…"
        shortcutChip.pulse = false
        guard let status else {
            shortcutChip.isHidden = true
            return
        }
        shortcutChip.isHidden = false
        if status.hotkeyRegistered {
            shortcutChip.text = "Active"
            shortcutChip.tone = .success
            shortcutDetail.stringValue = "Translate, Polish, Custom and Words share this one shortcut."
            shortcutDetail.textColor = Lantor.muted
        } else {
            shortcutChip.text = "Not registered"
            shortcutChip.tone = .danger
            shortcutDetail.stringValue = status.hotkeyProblem ?? "Not registered."
            shortcutDetail.textColor = Lantor.danger
        }
    }

    private func rebuildShortcutKeys() {
        guard let shortcutKeys else { return }
        shortcutKeys.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let listening = hotkeyCaptureMonitor != nil
        for part in listening ? ["…"] : shortcut.parts {
            let key = LantorKey(part, large: true)
            key.highlighted = listening
            shortcutKeys.addArrangedSubview(key)
        }
    }

    private func showToast(_ message: String, kind: FeedbackKind = .neutral) {
        toastWorkItem?.cancel()
        savedLabel.stringValue = message
        switch kind {
        case .neutral:
            savedLabel.textColor = Lantor.muted
            savedIcon.image = Lantor.symbol("info.circle", size: 11, weight: .semibold, color: Lantor.muted)
        case .success:
            savedLabel.textColor = Lantor.success
            savedIcon.image = Lantor.symbol("checkmark", size: 11, weight: .bold, color: Lantor.success)
        case .error:
            savedLabel.textColor = Lantor.danger
            savedIcon.image = Lantor.symbol("exclamationmark.circle", size: 11, weight: .semibold, color: Lantor.danger)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.savedLabel.stringValue = "Saved automatically"
            self.savedLabel.textColor = Lantor.muted
            self.savedIcon.image = Lantor.symbol("checkmark", size: 11, weight: .bold, color: Lantor.success)
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: General

    private func shortcutRow() -> NSView {
        let keys = NSStackView()
        keys.orientation = .horizontal
        keys.spacing = 6
        keys.alignment = .centerY
        shortcutKeys = keys

        let title = Lantor.label("Opens the palette in any app", Lantor.font(14, .semibold), Lantor.ink)
        let chip = LantorChip("Active", tone: .success, dot: true)
        shortcutChip = chip
        let titleRow = NSStackView(views: [title, chip])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        let detail = Lantor.label("", Lantor.font(12), Lantor.muted, lines: 2)
        shortcutDetail = detail
        let copy = NSStackView(views: [titleRow, detail])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = LantorButton("Record new…", kind: .secondary)
        button.toolTip = "Click, then press the new shortcut"
        button.onClick = { [weak self] in self?.recordShortcutTapped() }
        shortcutButton = button

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [keys, copy, spacer, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        updateShortcutStatus()
        return row
    }

    private func loginRow() -> NSView {
        let info = loginItemInfo?() ?? (enabled: false, text: "")
        let toggle = NSSwitch()
        toggle.state = info.enabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleLoginItemTapped)
        loginSwitch = toggle
        let (row, subtitle) = toggleRow(symbol: "power", title: "Launch at login", subtitle: loginSubtitle(info.text), accessory: toggle)
        loginDetail = subtitle
        return row
    }

    private func loginSubtitle(_ status: String) -> String {
        status.localizedCaseInsensitiveContains("approval")
            ? "Waiting for approval in System Settings → General → Login Items."
            : "Jit lives in the menu bar and has no Dock icon."
    }

    private func languageRow() -> NSView {
        let popup = NSPopUpButton()
        popup.target = self
        popup.action = #selector(languageChanged(_:))
        var names = TranslationLanguage.all.map(\.name)
        let current = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            names.append(current)
        }
        for name in names {
            popup.addItem(withTitle: TranslationLanguage.nativeName(for: name))
            popup.lastItem?.representedObject = name
        }
        if let index = names.firstIndex(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            popup.selectItem(at: index)
        }
        return toggleRow(
            symbol: "character.bubble", title: "Translate into",
            subtitle: "Text already in this language is translated to English.", accessory: popup
        ).row
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let name = sender.selectedItem?.representedObject as? String else { return }
        targetLanguage = name
        commit(toast: "Translate into \(TranslationLanguage.nativeName(for: name)).")
    }

    private func voiceRow() -> NSView {
        let popup = NSPopUpButton()
        popup.target = self
        popup.action = #selector(voiceChanged(_:))
        popup.addItem(withTitle: "Automatic (best installed)")
        popup.lastItem?.representedObject = nil
        let selected = selectedVoiceID?()
        for option in voiceOptions?() ?? [] {
            popup.addItem(withTitle: option.name)
            popup.lastItem?.representedObject = option.id
            if option.id == selected { popup.select(popup.lastItem) }
        }
        let info = voiceInfo?() ?? (description: "System default", highQuality: true)
        let subtitle = NSMutableAttributedString(string: "Used by Words. ", attributes: [.font: Lantor.font(12), .foregroundColor: Lantor.muted])
        if !info.highQuality {
            subtitle.append(NSAttributedString(string: "Only a compact voice is installed. ", attributes: [.font: Lantor.font(12), .foregroundColor: Lantor.warning]))
        }
        let link = LantorLinkButton("Download better voices…") { [weak self] in self?.onOpenVoiceSettings?() }
        let (row, subtitleLabel) = toggleRow(symbol: "speaker.wave.2", title: "Pronunciation voice", subtitle: "", accessory: popup, subtitleAccessory: link)
        subtitleLabel.attributedStringValue = subtitle
        return row
    }

    @objc private func voiceChanged(_ sender: NSPopUpButton) {
        let id = sender.selectedItem?.representedObject as? String
        onSelectVoice?(id)
        showToast(id == nil ? "Voice: automatic." : "Voice: \(sender.titleOfSelectedItem ?? "")", kind: .success)
    }

    @objc private func toggleLoginItemTapped() {
        if let error = onToggleLoginItem?() {
            showToast(error, kind: .error)
        }
        let info = loginItemInfo?() ?? (enabled: false, text: "")
        loginSwitch?.state = info.enabled ? .on : .off
        loginDetail?.stringValue = loginSubtitle(info.text)
    }

    // MARK: Shortcut recording

    private func recordShortcutTapped() {
        if hotkeyCaptureMonitor != nil {
            stopHotkeyCapture()
            return
        }
        onHotkeyCaptureChanged?(true)
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleHotkeyCapture(event)
        }
        updateShortcutStatus()
    }

    private func stopHotkeyCapture() {
        guard let monitor = hotkeyCaptureMonitor else { return }
        NSEvent.removeMonitor(monitor)
        hotkeyCaptureMonitor = nil
        onHotkeyCaptureChanged?(false)
        updateShortcutStatus()
    }

    private func captureError(_ message: String) {
        shortcutDetail?.stringValue = message
        shortcutDetail?.textColor = Lantor.danger
        NSSound.beep()
    }

    private func handleHotkeyCapture(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // Esc
            stopHotkeyCapture()
            return nil
        case 51: // Delete → restore default
            let fallback = AppConfig.defaults.features.first(where: { $0.id == "custom" }) ?? AppConfig.defaults.features[0]
            shortcut = ShortcutDraft(feature: fallback)
            stopHotkeyCapture()
            commit(toast: "Shortcut reset to \(shortcut.display).")
            return nil
        default:
            break
        }
        guard let key = KeyCodeMapper.shared.key(for: UInt32(event.keyCode)) else {
            captureError("Use a letter or number key.")
            return nil
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let candidate = ShortcutDraft(
            key: key,
            option: flags.contains(.option),
            command: flags.contains(.command),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
        guard candidate.hasModifier else {
            captureError("Add at least one modifier (⌘ ⌥ ⌃ ⇧).")
            return nil
        }
        if flags == [.shift] {
            captureError("Shift alone would block typing capital letters; add ⌘, ⌥, or ⌃.")
            return nil
        }
        let changed = candidate != shortcut
        shortcut = candidate
        stopHotkeyCapture()
        if changed {
            commit(toast: "Shortcut changed to \(shortcut.display).")
        }
        return nil
    }

    // MARK: AI Model

    private static let backendChoices: [(backend: AIBackend, symbol: String, title: String, detail: String)] = [
        (.codexCLI, "terminal", "Codex CLI", "Uses your saved Codex login. No API key."),
        (.claudeCLI, "asterisk", "Claude Code", "Uses your saved Claude Code login."),
        (.chatAPI, "link", "OpenAI-compatible", "Base URL, API key and model."),
    ]

    private func modelGroups() -> [NSView] {
        let choices = NSStackView()
        choices.orientation = .horizontal
        choices.distribution = .fillEqually
        choices.spacing = 8
        for choice in Self.backendChoices {
            let card = ChoiceCard(symbol: choice.symbol, title: choice.title, detail: choice.detail)
            card.isSelected = choice.backend == backend
            card.onClick = { [weak self] in self?.selectBackend(choice.backend) }
            choices.addArrangedSubview(card)
        }

        var rows: [NSView] = []
        let title: String
        if let cli = cliFields {
            title = cli.tool == .codex ? "Codex CLI" : "Claude Code"
            let icon = NSImageView()
            icon.setContentHuggingPriority(.required, for: .horizontal)
            cliLocationIcon = icon
            let location = Lantor.label("", Lantor.font(12, .medium), Lantor.success)
            location.lineBreakMode = .byTruncatingMiddle
            location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cliLocationLabel = location
            let locationRow = NSStackView(views: [icon, location])
            locationRow.orientation = .horizontal
            locationRow.alignment = .firstBaseline
            locationRow.spacing = 5
            updateCLILocation()
            rows.append(formRow("Executable", control: LantorFieldBox(cli.path), help: locationRow))
            let modelHelp = Lantor.label("Optional. Leave blank to use \(cli.tool.displayName)'s default model.", Lantor.font(12), Lantor.muted)
            rows.append(formRow("Model", control: LantorFieldBox(cli.model), help: modelHelp))
        } else {
            title = "OpenAI-compatible API"
            rows.append(formRow("Base URL", control: LantorFieldBox(baseURLField)))
            let paste = LantorButton("Paste", kind: .secondary)
            paste.onClick = { [weak self] in self?.pasteAPIKey() }
            let keyRow = NSStackView(views: [LantorFieldBox(apiKeyField), paste])
            keyRow.orientation = .horizontal
            keyRow.alignment = .centerY
            keyRow.spacing = 8
            rows.append(formRow("API key", control: keyRow))
            rows.append(formRow("Model", control: LantorFieldBox(modelField)))
        }

        // Check
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        testSpinner = spinner
        let chip = LantorChip("", tone: .success, dot: true)
        chip.maxTextWidth = 260
        chip.isHidden = true
        testChip = chip
        let button = LantorButton("Run test", kind: .secondary)
        button.onClick = { [weak self] in self?.testTapped() }
        testButton = button
        let accessory = NSStackView(views: [spinner, chip, button])
        accessory.orientation = .horizontal
        accessory.alignment = .centerY
        accessory.spacing = 8
        let (testRow, _) = toggleRow(symbol: "bolt", title: "Test connection", subtitle: "Sends one short Translate request.", accessory: accessory)
        let error = Lantor.label("", Lantor.font(12), Lantor.danger, lines: 4)
        error.isHidden = true
        testErrorLabel = error
        let errorRow = NSStackView(views: [error])
        errorRow.edgeInsets = NSEdgeInsets(top: 0, left: 56, bottom: 12, right: 16)
        let checkStack = NSStackView(views: [testRow, errorRow])
        checkStack.orientation = .vertical
        checkStack.alignment = .leading
        checkStack.spacing = 0
        testRow.widthAnchor.constraint(equalTo: checkStack.widthAnchor).isActive = true
        errorRow.widthAnchor.constraint(equalTo: checkStack.widthAnchor).isActive = true
        error.preferredMaxLayoutWidth = 520

        return [
            group("Connection", choices),
            group(title, card(rows)),
            group("Check", card([checkStack])),
        ]
    }

    private func selectBackend(_ newBackend: AIBackend) {
        guard newBackend != backend else { return }
        window?.makeFirstResponder(nil)
        invalidateConnectionTest()
        backend = newBackend
        commit(toast: "AI connection changed.")
        sectionPages[.model] = nil
        showSection(.model, animated: false, force: true)
    }

    private func pasteAPIKey() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            showToast("Clipboard has no text to paste.", kind: .error)
            return
        }
        apiKeyField.stringValue = text
        invalidateConnectionTest()
        commit(toast: "API key pasted and saved.")
    }

    private func testTapped() {
        window?.makeFirstResponder(nil)
        let config = draftConfig()
        guard config.hasRequiredConnectionSettings else {
            setTestResult(chip: "Not set up", tone: .warning, error: config.connectionSetupMessage)
            return
        }
        guard let feature = config.features.first(where: { $0.id == "translate" }) else { return }
        commit()
        connectionTestGeneration += 1
        let generation = connectionTestGeneration
        testButton?.isEnabled = false
        testSpinner?.startAnimation(nil)
        setTestResult(chip: "Sending…", tone: .thinking, error: nil)
        let started = Date()
        onTest?(config, feature) { [weak self] result in
            guard let self, self.connectionTestGeneration == generation else { return }
            self.testButton?.isEnabled = true
            self.testSpinner?.stopAnimation(nil)
            let elapsed = CommandInputWindowController.formatElapsed(Date().timeIntervalSince(started))
            switch result {
            case .success:
                self.setTestResult(chip: "Connected · \(config.connectionModelName) · \(elapsed)", tone: .success, error: nil)
            case .failure(let error):
                self.setTestResult(chip: "Failed", tone: .danger, error: FriendlyError.describe(error).message)
            }
        }
    }

    private func setTestResult(chip text: String, tone: LantorChip.Tone, error: String?) {
        testChip?.isHidden = false
        testChip?.text = text
        testChip?.tone = tone
        testChip?.pulse = tone == .thinking
        testErrorLabel?.stringValue = error ?? ""
        testErrorLabel?.isHidden = error == nil
    }

    // MARK: Actions

    private func actionsGroup() -> NSView {
        let order = ["translate", "refine", "custom", "vocabulary"]
        let features = featureConfigs.sorted { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        var rows: [NSView] = []
        for feature in features {
            let isDefault = feature.promptTemplate == AppConfig.defaultPromptTemplate(for: feature.id)
            let chip = LantorChip(isDefault ? "Default" : "Customized", tone: isDefault ? .neutral : .accent)
            let edit = LantorButton("Edit…", kind: .secondary)
            edit.height = 28
            edit.onClick = { [weak self] in self?.editFeaturePrompt(feature.id) }
            let accessory = NSStackView(views: [chip, edit])
            accessory.orientation = .horizontal
            accessory.alignment = .centerY
            accessory.spacing = 8
            let symbol = CommandInputWindowController.symbol(for: .init(id: feature.id, title: feature.displayName, requiresInstruction: false, supportsReplace: false, promptPreview: ""))
            let (row, _) = toggleRow(symbol: symbol, title: feature.displayName, subtitle: "\(promptSubtitle(for: feature.id)) · \(promptPreview(for: feature))", accessory: accessory)
            rows.append(row)
        }
        let help = helpLabel("Placeholders: {{text}} selected text · {{instruction}} your input · {{targetLanguage}} target language.")
        let stack = NSStackView(views: [help, card(rows)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return group("Prompts", stack)
    }

    private func editFeaturePrompt(_ id: String) {
        guard let feature = featureConfigs.first(where: { $0.id == id }), let window else { return }
        let editor = PromptEditorWindowController(
            currentTemplate: feature.promptTemplate,
            defaultTemplate: AppConfig.defaultPromptTemplate(for: feature.id)
        )
        editor.onSave = { [weak self] newTemplate in
            guard let self, let index = self.featureConfigs.firstIndex(where: { $0.id == feature.id }) else { return }
            self.featureConfigs[index].promptTemplate = newTemplate
            self.sectionPages[.actions] = nil
            self.showSection(.actions, animated: false, force: true)
            self.commit(toast: "\(feature.displayName) prompt saved.")
        }
        promptEditor = editor
        guard let sheet = editor.window else { return }
        window.beginSheet(sheet) { [weak self] _ in
            self?.promptEditor = nil
        }
    }

    private func promptSubtitle(for featureID: String) -> String {
        switch featureID {
        case "translate": return "Direct translation"
        case "refine": return "Rewrite and polish"
        case "custom": return "Runs your typed instruction"
        case "vocabulary": return "Word card with pronunciation"
        default: return "Custom prompt template"
        }
    }

    private func promptPreview(for feature: FeatureConfig) -> String {
        let firstLine = feature.promptTemplate
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        return firstLine.isEmpty ? "Empty prompt — the built-in default is used." : firstLine
    }

    // MARK: Permissions

    private func permissionsGroups() -> [NSView] {
        let current = status ?? statusProvider?()
        let rows: [(String, String, Bool, String, Selector)] = [
            ("Accessibility", "accessibility", current?.accessibility ?? AXIsProcessTrusted(),
             "Reads the selected text and positions the palette next to it.", #selector(openAccessibilitySettingsTapped)),
            ("Input Monitoring", "keyboard", current?.inputMonitoring ?? CGPreflightListenEventAccess(),
             "Lets the global shortcut work while other apps are focused.", #selector(openInputMonitoringSettingsTapped)),
            ("Post Events", "cursorarrow.click", current?.postEvents ?? CGPreflightPostEventAccess(),
             "Pastes results back with Replace and copies selections as a fallback.", #selector(openPrivacySecuritySettingsTapped)),
        ]
        var cardRows: [NSView] = []
        for (title, symbol, allowed, detail, selector) in rows {
            let chip = LantorChip(allowed ? "Allowed" : "Not allowed", tone: allowed ? .success : .warning, dot: true)
            var views: [NSView] = [chip]
            if !allowed {
                let open = LantorButton("Open Settings", kind: .secondary)
                open.height = 28
                open.onClick = { [weak self] in _ = self?.perform(selector) }
                views.append(open)
            }
            let accessory = NSStackView(views: views)
            accessory.orientation = .horizontal
            accessory.alignment = .centerY
            accessory.spacing = 8
            cardRows.append(toggleRow(symbol: symbol, title: title, subtitle: detail, accessory: accessory).row)
        }

        let allGranted = rows.allSatisfy { $0.2 }
        let request = LantorButton("Grant Access", kind: allGranted ? .secondary : .primary)
        request.onClick = { [weak self] in self?.requestPermissionsTapped() }
        let diagnose = LantorButton("Copy Diagnostics", kind: .secondary)
        diagnose.onClick = { [weak self] in self?.diagnosePermissionsTapped() }
        let reset = LantorButton("Reset Permissions…", kind: .danger)
        reset.onClick = { [weak self] in self?.resetPermissionsTapped() }
        let buttons = NSStackView(views: [request, diagnose, reset])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        let guide = helpLabel(allGranted
            ? "All set. If a permission stops working after an update, use Reset and grant it again."
            : "Click Grant Access to trigger the system prompts, enable Jit in System Settings, then come back here.")
        let feedback = helpLabel("")
        permissionsFeedbackLabel = feedback
        let actions = NSStackView(views: [guide, buttons, feedback])
        actions.orientation = .vertical
        actions.alignment = .leading
        actions.spacing = 10
        return [group("System access", card(cardRows)), group("Actions", actions)]
    }

    private func setPermissionsFeedback(_ message: String, kind: FeedbackKind) {
        permissionsFeedbackLabel?.stringValue = message
        switch kind {
        case .neutral: permissionsFeedbackLabel?.textColor = Lantor.muted
        case .success: permissionsFeedbackLabel?.textColor = Lantor.success
        case .error: permissionsFeedbackLabel?.textColor = Lantor.danger
        }
        showToast(message, kind: kind)
    }

    private func requestPermissionsTapped() {
        let report = onRequestPermissions?() ?? ""
        refreshStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatus()
        }
        if report.contains("Not Allowed") {
            setPermissionsFeedback("System prompts requested. Enable Jit in System Settings, then return here.", kind: .neutral)
        } else {
            setPermissionsFeedback("All permissions are already granted.", kind: .success)
        }
    }

    private func diagnosePermissionsTapped() {
        let report = onDiagnosePermissions?() ?? "No diagnostics available."
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        setPermissionsFeedback("Diagnostics copied to the clipboard.", kind: .success)
    }

    private func resetPermissionsTapped() {
        guard let window else { return }
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Reset Permissions?"
        confirm.informativeText = "Jit's Accessibility, Input Monitoring, and Post Events records are cleared. You will need to grant them again, then restart Jit."
        confirm.addButton(withTitle: "Reset")
        confirm.addButton(withTitle: "Cancel")
        confirm.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let report = self.onResetPermissions?() ?? "Permission reset is unavailable."
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            self.refreshStatus()
            self.setPermissionsFeedback("Permissions reset. Grant access again, then restart Jit. Details copied to the clipboard.", kind: .neutral)
        }
    }

    @objc private func openPrivacySecuritySettingsTapped() {
        openSystemSettings(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
            "x-apple.systempreferences:com.apple.preference.security",
        ])
    }

    @objc private func openAccessibilitySettingsTapped() {
        openSystemSettings(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ])
    }

    @objc private func openInputMonitoringSettingsTapped() {
        openSystemSettings(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ])
    }

    private func openSystemSettings(candidates: [String]) {
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                setPermissionsFeedback("Opened System Settings — enable Jit there and come back.", kind: .neutral)
                return
            }
        }
        let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if NSWorkspace.shared.open(appURL) {
            setPermissionsFeedback("Opened System Settings. Go to Privacy & Security.", kind: .neutral)
        } else {
            setPermissionsFeedback("Could not open System Settings.", kind: .error)
        }
    }

    // MARK: Shared building blocks

    /// Uppercase legend above a card or content block.
    private func group(_ title: String, _ content: NSView) -> NSView {
        let legend = Lantor.legend(title)
        let stack = NSStackView(views: [legend, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// Rounded card with hairlines between rows.
    private func card(_ rows: [NSView]) -> NSView {
        let surface = LantorSurface(fill: Lantor.panelStrong, stroke: Lantor.line, radius: 14)
        surface.draggable = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = LantorSeparator()
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 1),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -1),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 1),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -1),
        ])
        return surface
    }

    /// Label column + control (+ help line under the control), laid out with explicit constraints.
    private func formRow(_ title: String, control: NSView, help: NSView? = nil) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let label = Lantor.label(title, Lantor.font(13, .semibold), Lantor.inkSecondary)
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(control)
        var constraints = [
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.widthAnchor.constraint(equalToConstant: Theme.labelColumn),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 14),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -13),
            control.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
        ]
        if let help {
            help.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(help)
            constraints += [
                help.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 3),
                help.trailingAnchor.constraint(lessThanOrEqualTo: control.trailingAnchor),
                help.topAnchor.constraint(equalTo: control.bottomAnchor, constant: 2),
                help.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            ]
        } else {
            constraints.append(control.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -9))
        }
        NSLayoutConstraint.activate(constraints)
        return row
    }

    /// Icon tile + title/subtitle on the left, accessory control on the right.
    private func toggleRow(symbol: String, title: String, subtitle: String, accessory: NSView, subtitleAccessory: NSView? = nil) -> (row: NSView, subtitle: NSTextField) {
        let titleLabel = Lantor.label(title, Lantor.font(14, .semibold), Lantor.ink)
        // Single line: wrapping labels without a fixed width under-report their height in stack views.
        let subtitleLabel = Lantor.label(subtitle, Lantor.font(12), Lantor.muted)
        subtitleLabel.toolTip = subtitle.isEmpty ? nil : subtitle
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var subtitleView: NSView = subtitleLabel
        if let subtitleAccessory {
            let line = NSStackView(views: [subtitleLabel, subtitleAccessory])
            line.orientation = .horizontal
            line.alignment = .firstBaseline
            line.spacing = 0
            subtitleView = line
        }
        let text = NSStackView(views: [titleLabel, subtitleView])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        accessory.setContentHuggingPriority(.required, for: .horizontal)
        accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [LantorIconTile(symbol), text, spacer, accessory])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.setCustomSpacing(14, after: spacer)
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        return (row, subtitleLabel)
    }

    private func helpLabel(_ text: String, width: CGFloat = 560) -> NSTextField {
        let label = Lantor.label(text, Lantor.font(12), Lantor.muted, lines: 3)
        label.preferredMaxLayoutWidth = width
        return label
    }
}

/// Status dot with a soft halo, as in Lantor's readiness indicators.
@MainActor
final class StatusDotView: NSView {
    var color: NSColor = Lantor.success { didSet { needsDisplay = true } }
    var halo: NSColor = Lantor.successSoft { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 14).isActive = true
        heightAnchor.constraint(equalToConstant: 14).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        halo.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3)).fill()
    }
}

/// Accent text link ("Download better voices…").
@MainActor
final class LantorLinkButton: NSButton {
    private let action_: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        action_ = action
        super.init(frame: .zero)
        isBordered = false
        translatesAutoresizingMaskIntoConstraints = false
        attributedTitle = NSAttributedString(string: title, attributes: [.font: Lantor.font(12, .medium), .foregroundColor: Lantor.accent])
        target = self
        self.action = #selector(clicked)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func clicked() { action_() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
