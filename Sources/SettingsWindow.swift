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

    /// One-line problem statement for the Settings banner and the menu bar. `nil` when everything is ready.
    var headline: String? {
        if !permissionsGranted {
            return "Grant system permissions so Jit can read and replace selected text."
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

    var display: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(key.uppercased())
        return parts.joined()
    }

    func apply(to feature: inout FeatureConfig) {
        feature.hotkeyKey = key
        feature.hotkeyOption = option
        feature.hotkeyCommand = command
        feature.hotkeyControl = control
        feature.hotkeyShift = shift
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
            case .general: return "Shortcut, startup, translation, and voice"
            case .model: return "Local Codex, Claude Code, or an API connection"
            case .actions: return "Prompts behind Translate, Refine, Vocabulary, and Custom"
            case .permissions: return "System access Jit needs to read and replace text"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .model: return "network"
            case .actions: return "text.bubble"
            case .permissions: return "lock.shield"
            }
        }
    }

    @MainActor
    private enum Theme {
        static let sidebarWidth: CGFloat = 220
        static let contentPadding: CGFloat = 24
        static let sectionSpacing: CGFloat = 16
        static let cardPadding: CGFloat = 18
        static let cardCornerRadius: CGFloat = 12
        static let fieldCornerRadius: CGFloat = 8
        static let titlebarInset: CGFloat = 52

        static let sidebarSelection = NSColor.controlAccentColor.withAlphaComponent(0.16)
        static let cardStroke = NSColor.separatorColor.withAlphaComponent(0.42)
        static let fieldBackground = NSColor.controlBackgroundColor.withAlphaComponent(0.82)
        static let okColor = NSColor.systemGreen
        static let warnColor = NSColor.systemOrange
        static let errorColor = NSColor.systemRed

        static let sectionTitleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        static let bodyFont = NSFont.systemFont(ofSize: 13)
        static let captionFont = NSFont.systemFont(ofSize: 12)
        static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    }

    @MainActor
    private enum FeedbackKind {
        case neutral
        case success
        case error

        var color: NSColor {
            switch self {
            case .neutral: return .secondaryLabelColor
            case .success: return Theme.okColor
            case .error: return Theme.errorColor
            }
        }
    }

    @MainActor
    final class FlippedStackView: NSStackView {
        override var isFlipped: Bool { true }
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
    private let backendPicker = NSPopUpButton()
    private var backend: AIBackend
    private let targetLanguageField = NSTextField(string: "")
    private var featureConfigs: [FeatureConfig]
    private var shortcut: ShortcutDraft
    private var status: SetupStatus?

    // MARK: Views

    private var sectionButtons: [Section: NSButton] = [:]
    private var sectionBadges: [Section: NSView] = [:]
    private var sectionPages: [Section: NSView] = [:]
    private var currentSection: Section = .general
    private weak var detailTitleLabel: NSTextField?
    private weak var detailSubtitleLabel: NSTextField?
    private weak var detailPageStack: NSStackView?
    private weak var bannerView: NSView?
    private weak var bannerLabel: NSTextField?
    private weak var bannerButton: NSButton?
    private var bannerTarget: Section = .permissions
    private weak var toastLabel: NSTextField?
    private var toastWorkItem: DispatchWorkItem?

    private weak var shortcutButton: NSButton?
    private weak var shortcutStatusLabel: NSTextField?
    private weak var testButton: NSButton?
    private weak var testSpinner: NSProgressIndicator?
    private weak var testResultLabel: NSTextField?
    private weak var cliLocationLabel: NSTextField?
    private var connectionTestGeneration = 0
    private weak var loginItemCheckbox: NSButton?
    private weak var loginItemStatusLabel: NSTextField?
    private weak var permissionsFeedbackLabel: NSTextField?

    private var hotkeyCaptureMonitor: Any?
    private var escapeMonitor: Any?
    private var promptEditor: PromptEditorWindowController?

    private static let frameAutosaveName = "JitSettingsWindow"

    // MARK: Init

    init(config: AppConfig) {
        backend = config.backend
        featureConfigs = config.features
        let entry = config.features.first(where: { $0.id == "custom" }) ?? AppConfig.defaults.features[0]
        shortcut = ShortcutDraft(feature: entry)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Jit Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 780, height: 520)
        window.isReleasedWhenClosed = false
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
        targetLanguageField.stringValue = config.targetLanguage

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
        updateShortcutStatus()
        sectionPages[.permissions] = nil
        if currentSection == .permissions {
            showSection(.permissions, animated: false)
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
            targetLanguage: targetLanguageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
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
        testResultLabel?.stringValue = ""
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
        cliLocationLabel?.stringValue = found.map { "Found: " + $0.path } ?? "Install \(cli.tool.displayName), then run \(cli.tool.loginCommand) in Terminal."
        cliLocationLabel?.textColor = found == nil ? Theme.warnColor : .secondaryLabelColor
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
        [baseURLField, apiKeyField, modelField, codexPathField, codexModelField, claudePathField, claudeModelField, targetLanguageField].forEach { field in
            field.font = NSFont.systemFont(ofSize: 14)
            field.focusRingType = .default
            field.drawsBackground = false
            field.isBordered = false
            field.delegate = self
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        baseURLField.placeholderString = "https://api.openai.com/v1"
        apiKeyField.placeholderString = "sk-…"
        modelField.placeholderString = "gpt-4o-mini"
        codexPathField.placeholderString = "Automatic detection"
        codexModelField.placeholderString = "Default Codex model"
        claudePathField.placeholderString = "Automatic detection"
        claudeModelField.placeholderString = "Default Claude model, or sonnet / haiku / opus"
        targetLanguageField.placeholderString = "Chinese"
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        sectionButtons.removeAll()
        sectionBadges.removeAll()
        sectionPages.removeAll()

        let sidebar = sidebarView()
        let detail = detailView()
        contentView.addSubview(sidebar)
        contentView.addSubview(detail)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth),
            detail.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            detail.topAnchor.constraint(equalTo: contentView.topAnchor),
            detail.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        showSection(.general, animated: false)
    }

    private func sidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.state = .followsWindowActiveState
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "Jit") {
            iconView.image = image
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
            iconView.contentTintColor = .controlAccentColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let appTitle = label("Jit", font: NSFont.systemFont(ofSize: 16, weight: .semibold), color: .labelColor)
        let appSubtitle = label("Settings", font: Theme.captionFont, color: .secondaryLabelColor)
        let identityStack = NSStackView(views: [appTitle, appSubtitle])
        identityStack.orientation = .vertical
        identityStack.spacing = 1
        identityStack.alignment = .leading

        let topRow = NSStackView(views: [iconView, identityStack])
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        let navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.spacing = 4
        navStack.alignment = .leading
        for section in Section.allCases {
            navStack.addArrangedSubview(sidebarItem(for: section))
        }

        let container = NSStackView(views: [topRow, navStack])
        container.orientation = .vertical
        container.spacing = 18
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(container)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(divider)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: Theme.titlebarInset),
            divider.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: sidebar.topAnchor),
            divider.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1)
        ])
        return sidebar
    }

    private func sidebarItem(for section: Section) -> NSView {
        let button = NSButton(title: section.title, target: self, action: #selector(sidebarSectionTapped(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(section.rawValue)
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        if let image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title) {
            button.image = image
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        }
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        sectionButtons[section] = button

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = Theme.warnColor.cgColor
        badge.layer?.cornerRadius = 4
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        badge.toolTip = "Needs attention"
        sectionBadges[section] = badge

        let item = NSView()
        item.translatesAutoresizingMaskIntoConstraints = false
        item.addSubview(button)
        item.addSubview(badge)
        NSLayoutConstraint.activate([
            item.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth - 28),
            item.heightAnchor.constraint(equalToConstant: 30),
            button.leadingAnchor.constraint(equalTo: item.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: item.trailingAnchor),
            button.topAnchor.constraint(equalTo: item.topAnchor),
            button.bottomAnchor.constraint(equalTo: item.bottomAnchor),
            badge.widthAnchor.constraint(equalToConstant: 8),
            badge.heightAnchor.constraint(equalToConstant: 8),
            badge.trailingAnchor.constraint(equalTo: item.trailingAnchor, constant: -10),
            badge.centerYAnchor.constraint(equalTo: item.centerYAnchor)
        ])
        return item
    }

    @objc private func sidebarSectionTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let section = Section(rawValue: raw) else { return }
        showSection(section, animated: true)
    }

    private func detailView() -> NSView {
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .windowBackground
        background.state = .followsWindowActiveState
        background.blendingMode = .behindWindow
        background.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(background)

        let titleLabel = label("", font: NSFont.systemFont(ofSize: 24, weight: .semibold), color: .labelColor)
        let subtitleLabel = label("", font: Theme.bodyFont, color: .secondaryLabelColor)
        subtitleLabel.maximumNumberOfLines = 2
        detailTitleLabel = titleLabel
        detailSubtitleLabel = subtitleLabel

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.spacing = 3
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let banner = setupBannerView()

        let pageScroll = NSScrollView()
        pageScroll.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.hasVerticalScroller = true
        pageScroll.borderType = .noBorder
        pageScroll.drawsBackground = false
        pageScroll.contentInsets = NSEdgeInsets(top: 4, left: Theme.contentPadding, bottom: Theme.contentPadding, right: Theme.contentPadding)
        let pageStack = FlippedStackView()
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = 0
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.documentView = pageStack
        detailPageStack = pageStack

        let toast = label("", font: Theme.captionFont, color: .secondaryLabelColor)
        toast.maximumNumberOfLines = 1
        toast.lineBreakMode = .byTruncatingTail
        toast.translatesAutoresizingMaskIntoConstraints = false
        toastLabel = toast

        detail.addSubview(headerStack)
        detail.addSubview(banner)
        detail.addSubview(pageScroll)
        detail.addSubview(toast)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            background.topAnchor.constraint(equalTo: detail.topAnchor),
            background.bottomAnchor.constraint(equalTo: detail.bottomAnchor),

            headerStack.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: Theme.contentPadding),
            headerStack.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -Theme.contentPadding),
            headerStack.topAnchor.constraint(equalTo: detail.topAnchor, constant: 30),

            banner.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: Theme.contentPadding),
            banner.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -Theme.contentPadding),
            banner.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),

            pageScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            pageScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            pageScroll.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 8),
            pageScroll.bottomAnchor.constraint(equalTo: toast.topAnchor, constant: -6),

            pageStack.widthAnchor.constraint(equalTo: pageScroll.widthAnchor, constant: -(Theme.contentPadding * 2)),

            toast.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: Theme.contentPadding),
            toast.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -Theme.contentPadding),
            toast.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -12),
            toast.heightAnchor.constraint(equalToConstant: 16)
        ])
        return detail
    }

    private func setupBannerView() -> NSView {
        let banner = NSView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 10
        banner.layer?.backgroundColor = Theme.warnColor.withAlphaComponent(0.13).cgColor
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = Theme.warnColor.withAlphaComponent(0.35).cgColor

        let icon = NSImageView()
        if let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Setup incomplete") {
            icon.image = image
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            icon.contentTintColor = Theme.warnColor
        }
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let text = label("", font: Theme.bodyFont, color: .labelColor)
        text.maximumNumberOfLines = 2
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bannerLabel = text

        let button = NSButton(title: "Fix", target: self, action: #selector(bannerActionTapped))
        styleInlineButton(button)
        button.setContentHuggingPriority(.required, for: .horizontal)
        bannerButton = button

        let row = NSStackView(views: [icon, text, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: banner.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -9)
        ])
        banner.isHidden = true
        bannerView = banner
        return banner
    }

    @objc private func bannerActionTapped() {
        showSection(bannerTarget, animated: true)
        if bannerTarget == .model {
            window?.makeFirstResponder(primaryConnectionField)
        }
    }

    // MARK: Section switching

    func showSection(_ section: Section, animated: Bool) {
        stopHotkeyCapture()
        currentSection = section
        updateSidebarSelection(section)
        updateBanner()
        detailTitleLabel?.stringValue = section.title
        detailSubtitleLabel?.stringValue = section.subtitle

        guard let pageStack = detailPageStack else { return }
        let nextPage = pageView(for: section)
        let previous = pageStack.arrangedSubviews.first
        if previous === nextPage { return }

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
        page.spacing = Theme.sectionSpacing
        switch section {
        case .general:
            page.addArrangedSubview(contentCard(shortcutCard()))
            page.addArrangedSubview(contentCard(startupCard()))
            page.addArrangedSubview(contentCard(translationCard()))
            page.addArrangedSubview(contentCard(voiceCard()))
        case .model:
            page.addArrangedSubview(contentCard(modelCard()))
        case .actions:
            page.addArrangedSubview(actionsSectionView())
        case .permissions:
            page.addArrangedSubview(contentCard(permissionsSectionView()))
        }
        for card in page.arrangedSubviews {
            card.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        }
        sectionPages[section] = page
        return page
    }

    private func updateSidebarSelection(_ section: Section) {
        for (item, button) in sectionButtons {
            let selected = (item == section)
            button.layer?.backgroundColor = selected ? Theme.sidebarSelection.cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium),
                .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
            button.attributedTitle = NSAttributedString(string: item.title, attributes: attrs)
        }
    }

    // MARK: Status surfaces

    private func updateBanner() {
        guard let bannerView, let bannerLabel, let bannerButton else { return }
        guard let status, let headline = status.headline else {
            bannerView.isHidden = true
            return
        }
        bannerView.isHidden = false
        bannerLabel.stringValue = headline
        if !status.permissionsGranted {
            bannerTarget = .permissions
            bannerButton.title = "Open Permissions"
        } else if !status.connectionConfigured {
            bannerTarget = .model
            bannerButton.title = "Set Up AI Model"
        } else {
            bannerTarget = .general
            bannerButton.title = "Change Shortcut"
        }
        bannerButton.isHidden = currentSection == bannerTarget
    }

    private func updateBadges() {
        guard let status else { return }
        sectionBadges[.general]?.isHidden = status.hotkeyRegistered
        sectionBadges[.model]?.isHidden = status.connectionConfigured
        sectionBadges[.permissions]?.isHidden = status.permissionsGranted
        sectionBadges[.actions]?.isHidden = true
    }

    private func updateShortcutStatus() {
        guard let shortcutButton, let shortcutStatusLabel else { return }
        if hotkeyCaptureMonitor != nil {
            shortcutButton.title = "Type new shortcut…"
            shortcutButton.contentTintColor = .controlAccentColor
            let fallback = ShortcutDraft(feature: AppConfig.defaults.features.first(where: { $0.id == "custom" }) ?? AppConfig.defaults.features[0])
            shortcutStatusLabel.stringValue = "Listening — Esc cancels, ⌫ restores \(fallback.display)"
            shortcutStatusLabel.textColor = .secondaryLabelColor
            return
        }
        shortcutButton.title = shortcut.display
        shortcutButton.contentTintColor = nil
        guard let status else {
            shortcutStatusLabel.stringValue = ""
            return
        }
        if status.hotkeyRegistered {
            shortcutStatusLabel.stringValue = "Active — press it in any app to open the palette."
            shortcutStatusLabel.textColor = Theme.okColor
        } else {
            shortcutStatusLabel.stringValue = status.hotkeyProblem ?? "Not registered."
            shortcutStatusLabel.textColor = Theme.errorColor
        }
    }

    private func showToast(_ message: String, kind: FeedbackKind = .neutral) {
        guard let toastLabel else { return }
        toastWorkItem?.cancel()
        toastLabel.stringValue = message
        toastLabel.textColor = kind.color
        let work = DispatchWorkItem { [weak toastLabel] in
            toastLabel?.stringValue = ""
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: General

    private func shortcutCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.addArrangedSubview(sectionHeader(
            title: "Action Palette Shortcut",
            subtitle: "One global shortcut opens the palette for Translate, Refine, Vocabulary, or Custom."
        ))

        let button = NSButton(title: shortcut.display, target: self, action: #selector(recordShortcutTapped))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = Theme.monoFont
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        button.toolTip = "Click, then press the new shortcut"
        shortcutButton = button

        let statusLabel = label("", font: Theme.captionFont, color: .secondaryLabelColor)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        shortcutStatusLabel = statusLabel

        let row = NSStackView(views: [button, statusLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        stack.addArrangedSubview(formRow("Shortcut", control: row))
        updateShortcutStatus()
        return stack
    }

    private func startupCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.addArrangedSubview(sectionHeader(title: "Startup", subtitle: "Jit lives in the menu bar; it has no Dock icon."))

        let info = loginItemInfo?() ?? (enabled: false, text: "")
        let checkbox = NSButton(checkboxWithTitle: "Launch Jit at login", target: self, action: #selector(toggleLoginItemTapped))
        checkbox.state = info.enabled ? .on : .off
        checkbox.font = Theme.bodyFont
        loginItemCheckbox = checkbox
        let statusLabel = label(info.text, font: Theme.captionFont, color: .secondaryLabelColor)
        loginItemStatusLabel = statusLabel
        stack.addArrangedSubview(checkbox)
        stack.addArrangedSubview(statusLabel)
        return stack
    }

    private func translationCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.addArrangedSubview(sectionHeader(
            title: "Translation",
            subtitle: "Text already in the target language is translated to English instead."
        ))
        stack.addArrangedSubview(formRow("Target Language", control: fieldContainer(for: targetLanguageField, minWidth: 260)))
        return stack
    }

    private func voiceCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        let info = voiceInfo?() ?? (description: "System default", highQuality: true)
        stack.addArrangedSubview(sectionHeader(title: "Pronunciation Voice", subtitle: "Used by Vocabulary to read words aloud."))
        let voiceLabel = label(info.description, font: Theme.bodyFont, color: .labelColor)
        if info.highQuality {
            stack.addArrangedSubview(formRow("Voice", control: voiceLabel))
        } else {
            let download = NSButton(title: "Download Better Voices…", target: self, action: #selector(openVoiceSettingsTapped))
            styleInlineButton(download)
            let hint = label("Only a compact voice is installed. Enhanced voices sound much better.", font: Theme.captionFont, color: Theme.warnColor)
            let row = NSStackView(views: [voiceLabel, download])
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY
            stack.addArrangedSubview(formRow("Voice", control: row))
            stack.addArrangedSubview(hint)
        }
        return stack
    }

    @objc private func toggleLoginItemTapped() {
        if let error = onToggleLoginItem?() {
            showToast(error, kind: .error)
        }
        let info = loginItemInfo?() ?? (enabled: false, text: "")
        loginItemCheckbox?.state = info.enabled ? .on : .off
        loginItemStatusLabel?.stringValue = info.text
    }

    @objc private func openVoiceSettingsTapped() {
        onOpenVoiceSettings?()
    }

    // MARK: Shortcut recording

    @objc private func recordShortcutTapped() {
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

    private func handleHotkeyCapture(_ event: NSEvent) -> NSEvent? {
        guard let shortcutStatusLabel else { return event }
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
            shortcutStatusLabel.stringValue = "Use a letter or number key."
            shortcutStatusLabel.textColor = Theme.errorColor
            NSSound.beep()
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
            shortcutStatusLabel.stringValue = "Add at least one modifier (⌘ ⌥ ⌃ ⇧)."
            shortcutStatusLabel.textColor = Theme.errorColor
            NSSound.beep()
            return nil
        }
        if flags == [.shift] {
            shortcutStatusLabel.stringValue = "Shift alone would block typing capital letters; add ⌘, ⌥, or ⌃."
            shortcutStatusLabel.textColor = Theme.errorColor
            NSSound.beep()
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

    private func modelCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.addArrangedSubview(sectionHeader(
            title: "Connection",
            subtitle: "Use your local Codex or Claude Code login, or an API connection. Changes are saved as you go."
        ))
        backendPicker.removeAllItems()
        backendPicker.addItems(withTitles: Self.backendChoices.map(\.title))
        backendPicker.selectItem(at: Self.backendChoices.firstIndex(where: { $0.backend == backend }) ?? 0)
        backendPicker.target = self
        backendPicker.action = #selector(backendChanged)
        stack.addArrangedSubview(formRow("Use", control: backendPicker))
        if let cli = cliFields {
            let name = cli.tool.displayName
            stack.addArrangedSubview(formRow("", control: label(
                "Uses your saved \(name) login. No API key is needed in Jit.",
                font: Theme.captionFont, color: .secondaryLabelColor
            )))
            stack.addArrangedSubview(formRow("\(cli.tool.executableName.capitalized) path", control: fieldContainer(for: cli.path, minWidth: 420)))
            let location = label("", font: Theme.captionFont, color: .secondaryLabelColor)
            cliLocationLabel = location
            updateCLILocation()
            stack.addArrangedSubview(formRow("", control: location))
            stack.addArrangedSubview(formRow("Model", control: fieldContainer(for: cli.model, minWidth: 300)))
            stack.addArrangedSubview(formRow("", control: label(
                "Optional. Leave blank to use \(name)'s default model.",
                font: Theme.captionFont, color: .secondaryLabelColor
            )))
        } else {
            stack.addArrangedSubview(formRow("Base URL", control: fieldContainer(for: baseURLField, minWidth: 460)))
            stack.addArrangedSubview(apiKeyRow())
            stack.addArrangedSubview(formRow("Model", control: fieldContainer(for: modelField, minWidth: 300)))
        }

        let button = NSButton(title: "Test Connection", target: self, action: #selector(testTapped))
        styleSecondaryButton(button)
        button.setContentHuggingPriority(.required, for: .horizontal)
        testButton = button

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true
        testSpinner = spinner

        let result = label("", font: Theme.captionFont, color: .secondaryLabelColor)
        result.maximumNumberOfLines = 3
        result.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        testResultLabel = result

        let row = NSStackView(views: [button, spinner, result])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        stack.addArrangedSubview(formRow("", control: row))
        return stack
    }

    private static let backendChoices: [(backend: AIBackend, title: String)] = [
        (.codexCLI, "Local Codex CLI"),
        (.claudeCLI, "Local Claude Code CLI"),
        (.chatAPI, "OpenAI-compatible API"),
    ]

    @objc private func backendChanged() {
        window?.makeFirstResponder(nil)
        invalidateConnectionTest()
        let index = backendPicker.indexOfSelectedItem
        backend = Self.backendChoices.indices.contains(index) ? Self.backendChoices[index].backend : .chatAPI
        commit(toast: "AI connection changed.")
        sectionPages[.model] = nil
        showSection(.model, animated: false)
    }

    private func apiKeyRow() -> NSView {
        let pasteButton = NSButton(title: "Paste", target: self, action: #selector(pasteAPIKey))
        styleInlineButton(pasteButton)
        pasteButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let row = NSStackView(views: [fieldContainer(for: apiKeyField, minWidth: 380), pasteButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return formRow("API Key", control: row)
    }

    @objc private func pasteAPIKey() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            showToast("Clipboard has no text to paste.", kind: .error)
            return
        }
        apiKeyField.stringValue = text
        invalidateConnectionTest()
        commit(toast: "API key pasted and saved.")
    }

    @objc private func testTapped() {
        window?.makeFirstResponder(nil)
        let config = draftConfig()
        guard config.hasRequiredConnectionSettings else {
            setTestResult(config.connectionSetupMessage, kind: .error)
            return
        }
        guard let feature = config.features.first(where: { $0.id == "translate" }) else { return }
        commit()
        connectionTestGeneration += 1
        let generation = connectionTestGeneration
        testButton?.isEnabled = false
        testSpinner?.startAnimation(nil)
        setTestResult("Sending a test request…", kind: .neutral)
        let started = Date()
        onTest?(config, feature) { [weak self] result in
            guard let self, self.connectionTestGeneration == generation else { return }
            self.testButton?.isEnabled = true
            self.testSpinner?.stopAnimation(nil)
            let elapsed = String(format: "%.1fs", Date().timeIntervalSince(started))
            switch result {
            case .success:
                self.setTestResult("Connected · \(config.connectionModelName) · \(elapsed)", kind: .success)
            case .failure(let error):
                self.setTestResult("Failed: \(FriendlyError.describe(error).message)", kind: .error)
            }
        }
    }

    private func setTestResult(_ message: String, kind: FeedbackKind) {
        testResultLabel?.stringValue = message
        testResultLabel?.textColor = kind.color
    }

    // MARK: Actions

    private func actionsSectionView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 10
        container.alignment = .leading
        container.addArrangedSubview(sectionHeader(
            title: "Prompts",
            subtitle: "Placeholders: {{text}} selected text · {{instruction}} your input · {{targetLanguage}}"
        ))

        for feature in featureConfigs {
            let title = label(feature.displayName, font: NSFont.systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
            let subtitle = label(promptSubtitle(for: feature.id), font: Theme.captionFont, color: .secondaryLabelColor)
            let preview = label(promptPreview(for: feature), font: Theme.captionFont, color: .tertiaryLabelColor)
            preview.maximumNumberOfLines = 1
            preview.lineBreakMode = .byTruncatingTail
            preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let titleStack = NSStackView(views: [title, subtitle, preview])
            titleStack.orientation = .vertical
            titleStack.spacing = 3
            titleStack.alignment = .leading
            titleStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let isDefault = feature.promptTemplate == AppConfig.defaultPromptTemplate(for: feature.id)
            let chip = statusChip(text: isDefault ? "Default" : "Customized", tone: isDefault ? .neutral : .accent)

            let editPrompt = NSButton(title: "Edit…", target: self, action: #selector(editFeaturePromptTapped(_:)))
            editPrompt.identifier = NSUserInterfaceItemIdentifier(feature.id)
            styleInlineButton(editPrompt)
            editPrompt.setContentHuggingPriority(.required, for: .horizontal)

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [titleStack, spacer, chip, editPrompt])
            row.orientation = .horizontal
            row.distribution = .fill
            row.alignment = .centerY
            row.spacing = 10
            let styled = styledRow(row)
            container.addArrangedSubview(styled)
            styled.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            row.widthAnchor.constraint(equalTo: styled.widthAnchor, constant: -22).isActive = true
        }
        return container
    }

    @objc private func editFeaturePromptTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let feature = featureConfigs.first(where: { $0.id == id }),
              let window else { return }
        let editor = PromptEditorWindowController(
            currentTemplate: feature.promptTemplate,
            defaultTemplate: AppConfig.defaultPromptTemplate(for: feature.id)
        )
        editor.onSave = { [weak self] newTemplate in
            guard let self, let index = self.featureConfigs.firstIndex(where: { $0.id == feature.id }) else { return }
            self.featureConfigs[index].promptTemplate = newTemplate
            self.sectionPages[.actions] = nil
            self.showSection(.actions, animated: false)
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
        case "custom": return "Runs your typed instruction on the selection"
        case "vocabulary": return "English word study with pronunciation"
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

    private func permissionsSectionView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 10
        container.alignment = .leading
        container.addArrangedSubview(sectionHeader(
            title: "System Permissions",
            subtitle: "Status refreshes automatically when you come back from System Settings."
        ))

        let current = status ?? statusProvider?()
        let rows: [(String, Bool, String, Selector)] = [
            ("Accessibility", current?.accessibility ?? AXIsProcessTrusted(),
             "Reads the selected text and positions the palette next to it.", #selector(openAccessibilitySettingsTapped)),
            ("Input Monitoring", current?.inputMonitoring ?? CGPreflightListenEventAccess(),
             "Lets the global shortcut work while other apps are focused.", #selector(openInputMonitoringSettingsTapped)),
            ("Post Events", current?.postEvents ?? CGPreflightPostEventAccess(),
             "Pastes results back with Replace and copies selections as a fallback.", #selector(openPrivacySecuritySettingsTapped))
        ]
        for (title, allowed, detail, selector) in rows {
            let row = permissionStatusRow(title: title, allowed: allowed, detail: detail, actionSelector: selector)
            container.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }

        let allGranted = rows.allSatisfy { $0.1 }
        let guide = label(
            allGranted
                ? "All set. If a permission stops working after an update, use Reset and grant it again."
                : "Click Grant Access to trigger the system prompts, enable Jit in System Settings, then come back here.",
            font: Theme.captionFont,
            color: .secondaryLabelColor
        )
        guide.maximumNumberOfLines = 2
        container.addArrangedSubview(guide)

        let requestButton = NSButton(title: "Grant Access", target: self, action: #selector(requestPermissionsTapped))
        if allGranted {
            styleSecondaryButton(requestButton)
        } else {
            stylePrimaryButton(requestButton)
        }
        let diagnoseButton = NSButton(title: "Copy Diagnostics", target: self, action: #selector(diagnosePermissionsTapped))
        styleSecondaryButton(diagnoseButton)
        let resetButton = NSButton(title: "Reset Permissions…", target: self, action: #selector(resetPermissionsTapped))
        styleDestructiveButton(resetButton)
        [requestButton, diagnoseButton, resetButton].forEach {
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }
        let actions = NSStackView(views: [requestButton, diagnoseButton, resetButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.alignment = .centerY
        container.addArrangedSubview(actions)

        let feedback = label("", font: Theme.captionFont, color: .secondaryLabelColor)
        feedback.maximumNumberOfLines = 2
        permissionsFeedbackLabel = feedback
        container.addArrangedSubview(feedback)
        return container
    }

    private func permissionStatusRow(title: String, allowed: Bool, detail: String, actionSelector: Selector) -> NSView {
        let icon = NSImageView()
        if let image = NSImage(systemSymbolName: allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", accessibilityDescription: title) {
            icon.image = image
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            icon.contentTintColor = allowed ? Theme.okColor : Theme.warnColor
        }
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = label(title, font: NSFont.systemFont(ofSize: 13, weight: .medium), color: .labelColor)
        let detailLabel = label(detail, font: Theme.captionFont, color: .secondaryLabelColor)
        detailLabel.maximumNumberOfLines = 2
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let chip = statusChip(text: allowed ? "Allowed" : "Not allowed", tone: allowed ? .ok : .warn)
        var views: [NSView] = [icon, textStack, spacer, chip]
        if !allowed {
            let openButton = NSButton(title: "Open System Settings", target: self, action: actionSelector)
            styleInlineButton(openButton)
            openButton.setContentHuggingPriority(.required, for: .horizontal)
            views.append(openButton)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 10
        let styled = styledRow(row)
        row.widthAnchor.constraint(equalTo: styled.widthAnchor, constant: -22).isActive = true
        return styled
    }

    private func setPermissionsFeedback(_ message: String, kind: FeedbackKind) {
        permissionsFeedbackLabel?.stringValue = message
        permissionsFeedbackLabel?.textColor = kind.color
        showToast(message, kind: kind)
    }

    @objc private func requestPermissionsTapped() {
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

    @objc private func diagnosePermissionsTapped() {
        let report = onDiagnosePermissions?() ?? "No diagnostics available."
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        setPermissionsFeedback("Diagnostics copied to the clipboard.", kind: .success)
    }

    @objc private func resetPermissionsTapped() {
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
            "x-apple.systempreferences:com.apple.preference.security"
        ])
    }

    @objc private func openAccessibilitySettingsTapped() {
        openSystemSettings(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ])
    }

    @objc private func openInputMonitoringSettingsTapped() {
        openSystemSettings(candidates: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
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

    @MainActor
    private enum ChipTone {
        case ok
        case warn
        case neutral
        case accent

        var color: NSColor {
            switch self {
            case .ok: return Theme.okColor
            case .warn: return Theme.warnColor
            case .neutral: return .secondaryLabelColor
            case .accent: return .controlAccentColor
            }
        }
    }

    private func statusChip(text: String, tone: ChipTone) -> NSView {
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.masksToBounds = true
        chip.layer?.backgroundColor = tone.color.withAlphaComponent(0.15).cgColor
        chip.setContentHuggingPriority(.required, for: .horizontal)

        let labelView = label(text, font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: tone.color)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
            labelView.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8),
            labelView.topAnchor.constraint(equalTo: chip.topAnchor, constant: 3),
            labelView.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -3)
        ])
        return chip
    }

    private func contentCard(_ content: NSView) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = Theme.cardCornerRadius
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Theme.cardStroke.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.cardPadding),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.cardPadding),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.cardPadding),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.cardPadding)
        ])
        return card
    }

    private func sectionHeader(title: String, subtitle: String) -> NSView {
        let titleLabel = label(title, font: Theme.sectionTitleFont, color: .labelColor)
        let subtitleLabel = label(subtitle, font: Theme.captionFont, color: .secondaryLabelColor)
        subtitleLabel.maximumNumberOfLines = 2
        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        return stack
    }

    private func styledRow(_ content: NSView) -> NSView {
        let row = NSStackView(views: [content])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 0
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        row.layer?.masksToBounds = true
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        row.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)
        return row
    }

    private func formRow(_ title: String, control: NSView) -> NSView {
        let labelView = label(title, font: Theme.bodyFont, color: .secondaryLabelColor)
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func fieldContainer(for field: NSTextField, minWidth: CGFloat, height: CGFloat = 32) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Theme.fieldCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = Theme.fieldBackground.cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
        container.heightAnchor.constraint(equalToConstant: height).isActive = true

        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let textField = NSTextField(labelWithString: text)
        textField.font = font
        textField.textColor = color
        return textField
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.bezelColor = .controlAccentColor
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    }

    private func styleSecondaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 13, weight: .regular)
    }

    private func styleInlineButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    }

    private func styleDestructiveButton(_ button: NSButton) {
        styleSecondaryButton(button)
        button.contentTintColor = .systemRed
    }
}
