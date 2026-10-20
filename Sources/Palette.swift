import AppKit
import JitText

// MARK: - Palette chrome

/// Solid Lantor panel: rounded body with a recessed footer strip.
@MainActor
final class PaletteRootView: NSView {
    weak var footer: NSView?
    var onAppearanceChange: (() -> Void)?
    static let radius: CGFloat = 18

    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
        Lantor.panelStrong.setFill()
        path.fill()
        if let footer, !footer.isHidden {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            Lantor.panel.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: footer.frame.maxY).fill()
            Lantor.line.setFill()
            NSRect(x: 0, y: footer.frame.maxY - 1, width: bounds.width, height: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        Lantor.floatingBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        onAppearanceChange?()
    }
}

/// One segment of the mode switcher: icon and title.
@MainActor
final class ModeTabButton: NSButton {
    let titleText: String
    let symbolName: String
    var isSelectedTab = false { didSet { needsDisplay = true } }
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
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func clicked() { onClick?() }

    override var mouseDownCanMoveWindow: Bool { false }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

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
        NSGraphicsContext.saveGraphicsState()
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        if isSelectedTab {
            Lantor.selectedFill.setFill()
            path.fill()
            Lantor.selectedBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if hovering && isEnabled {
            Lantor.hover.setFill()
            path.fill()
        }
        let ink = isSelectedTab ? Lantor.accent : Lantor.inkSecondary
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: Lantor.font(13, isSelectedTab ? .semibold : .medium), .foregroundColor: ink]
        let titleSize = (titleText as NSString).size(withAttributes: titleAttrs)
        let icon = Lantor.symbol(symbolName, size: 13, weight: .medium, color: ink)
        let iconWidth: CGFloat = icon == nil ? 0 : 16 + 7
        var x = (bounds.width - iconWidth - titleSize.width) / 2
        if let icon {
            let size = icon.size
            icon.draw(in: NSRect(x: x + (16 - size.width) / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            x += iconWidth
        }
        (titleText as NSString).draw(at: NSPoint(x: x, y: bounds.midY - titleSize.height / 2), withAttributes: titleAttrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Wrapping text field that reports Return so the palette can run it.
@MainActor
final class ComposerField: NSTextField {
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - Palette controller

@MainActor
final class CommandInputWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let width: CGFloat = 620
        static let defaultExpandedSize = NSSize(width: 620, height: 540)
        static let minExpandedSize = NSSize(width: 540, height: 380)
        static let maxSize = NSSize(width: 1280, height: 1100)
        static let sizeDefaultsKey = "paletteExpandedSize"
        static let footerHeight: CGFloat = 56
        static let composerIdleHeight: CGFloat = 74
        static let composerCompactHeight: CGFloat = 52
    }

    private enum Phase: Equatable {
        case readingSelection
        case noSelection
        case idle
        case running
        case done
        case error
    }

    struct Mode {
        let id: String
        let title: String
        let requiresInstruction: Bool
        let supportsReplace: Bool
        let promptPreview: String
    }

    // Callbacks
    var onSubmit: ((_ modeID: String, _ instruction: String?, _ selectedText: String, _ onPartial: @escaping @Sendable (String) -> Void, _ completion: @escaping @Sendable (Result<String, Error>) -> Void) -> TextProcessingRun?)?
    var onToggleSpeech: ((String, @escaping @MainActor (Bool) -> Void) -> Bool)?
    var onStopSpeech: (() -> Void)?
    var onReplace: ((String) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onResult: ((HistoryEntry) -> Void)?
    var onClose: (() -> Void)?
    var lastResult: HistoryEntry?
    /// Replace pastes into the source app; disabled when showing a stored result.
    var allowsReplace = true
    var speechVoiceDescription: String = ""
    /// Setup problem (missing permissions / connection) surfaced inline instead of redirecting to Settings.
    var setupNotice: String? { didSet { render() } }
    /// "Codex · gpt-5.1" shown in the header.
    var modelLabel: String = "" { didSet { modelChip.text = modelLabel; modelChip.isHidden = modelLabel.isEmpty } }
    /// Recent Custom instructions offered as one-click presets.
    var recentInstructions: [String] = [] { didSet { rebuildPresets(); render() } }
    /// "English → 简体中文" for the selection card in Translate.
    var directionLabel: ((String) -> String?)?

    // Views
    private let root = PaletteRootView()
    private let body = NSStackView()
    private let modeLabel = Lantor.label("", Lantor.font(15, .medium), Lantor.muted)
    private let modelChip = LantorChip("", tone: .neutral, symbol: "cpu")
    private let statusChip = LantorChip("", tone: .success, dot: true)
    private let closeButton = LantorButton("", kind: .ghost, symbol: "xmark")
    private let tabsTrack = LantorSurface(fill: Lantor.track, stroke: Lantor.line, radius: 13)
    private var modeButtons: [ModeTabButton] = []
    private let noticeBanner = LantorSurface(fill: Lantor.warningSoft, stroke: Lantor.warningBorder, radius: 12)
    private let noticeLabel = Lantor.label("", Lantor.font(12.5, .medium), Lantor.warning, lines: 2)
    private let noticeButton = LantorButton("Open Settings", kind: .secondary)
    private let refCard = LantorSurface(fill: Lantor.panel, stroke: Lantor.line, radius: 12)
    private let refMeta = Lantor.label("", Lantor.font(12, .medium), Lantor.muted)
    private let refText = Lantor.label("", Lantor.font(13), Lantor.inkSecondary, lines: 2)
    private let composer = LantorSurface(fill: Lantor.input, stroke: Lantor.controlBorder, radius: 18)
    private let commandField = ComposerField(string: "")
    private let sendButton = LantorButton("", kind: .primary, symbol: "arrow.up")
    private var composerHeight: NSLayoutConstraint?
    private let presetsRow = NSStackView()
    private let outputCard = LantorSurface(fill: Lantor.input, stroke: Lantor.controlBorder, radius: 13)
    private let outputScroll = NSScrollView()
    private let outputTextView = NSTextView(usingTextLayoutManager: false)
    private let cardSpeakButton = LantorButton("", kind: .accentSoft, symbol: "speaker.wave.2.fill")
    private let footer = NSView()
    private let hintsRow = NSStackView()
    private let speakButton = LantorButton("", kind: .secondary, symbol: "speaker.wave.2.fill")
    private let settingsButton = LantorButton("Open Settings", kind: .secondary)
    private let lastResultButton = LantorButton("Last Result", kind: .secondary, symbol: "clock.arrow.circlepath")
    private let runAgainButton = LantorButton("Run again", kind: .secondary, hint: "↩")
    private let copyButton = LantorButton("Copy", kind: .secondary, hint: "⌘C")
    private let replaceButton = LantorButton("Replace", kind: .primary, hint: "⌘↩")
    private let stopButton = LantorButton("Stop", kind: .warning, hint: "esc")
    private let runButton = LantorButton("Run", kind: .primary, hint: "↩")

    // State
    private let modes: [Mode]
    private var currentModeIndex = 0
    private var phase: Phase = .readingSelection
    private var selectedText = ""
    private var customInstructionDraft = ""
    private var rawOutput = ""
    private var outputDidStream = false
    private var errorMessage = ""
    private var errorNeedsSettings = false
    private var expanded = false
    private var showingStoredResult = false
    private var activeRun: TextProcessingRun?
    private var runStartedAt: Date?
    private var lastElapsed: TimeInterval?
    private var isSpeakingSelectedText = false
    private var hintsKey = ""
    private var outputPlaceholder = "(No content returned)"
    private var renderedCardVisible = false
    private var runGeneration = 0
    private var copyResetWork: DispatchWorkItem?
    private var localKeyMonitor: Any?
    private var windowUpdateObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(anchor: NSRect, modes: [Mode], defaultModeID: String = "custom") {
        self.modes = modes.isEmpty
            ? [Mode(id: "custom", title: "Custom", requiresInstruction: true, supportsReplace: true, promptPreview: "Custom instruction mode")]
            : modes
        let panel = BubblePanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Layout.width, height: 220)),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in
            self?.handlePanelKeyDown(event) ?? false
        }
        buildUI()
        if let index = self.modes.firstIndex(where: { $0.id == defaultModeID }) {
            currentModeIndex = index
        }
        applyMode()
        render()
        position(near: anchor)
        installKeyMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public state transitions

    /// Called once the selection is known. `nil`/empty switches to the no-selection state.
    func setSelection(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedText = trimmed
        if trimmed.isEmpty {
            phase = .noSelection
            if let index = modes.firstIndex(where: { $0.requiresInstruction }) {
                currentModeIndex = index
            }
        } else {
            phase = .idle
        }
        applyMode()
        render()
    }

    /// Reopens a previous result in the done state.
    func showHistoryEntry(_ entry: HistoryEntry) {
        selectedText = entry.selectedText
        if let index = modes.firstIndex(where: { $0.id == entry.modeID }) {
            currentModeIndex = index
        }
        customInstructionDraft = entry.instruction ?? ""
        allowsReplace = false
        showingStoredResult = true
        rawOutput = entry.output
        outputDidStream = false
        lastElapsed = nil
        phase = .done
        applyMode()
        expandForOutputIfNeeded()
        refreshOutput()
        render()
    }

    func focus() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        let mode = modes[currentModeIndex]
        if mode.requiresInstruction && phase != .running && phase != .readingSelection {
            window.makeFirstResponder(commandField)
            moveCaretToEnd()
        } else {
            window.makeFirstResponder(nil)
        }
    }

    /// Puts the caret back without re-activating the app (the user may have moved on while waiting).
    private func restoreFirstResponder() {
        guard let window, window.isKeyWindow else { return }
        window.makeFirstResponder(modes[currentModeIndex].requiresInstruction ? commandField : nil)
    }

    func beginAutoDismiss() {
        stopOutsideClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeIfClickOutside()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.closeIfClickOutside()
            return event
        }
    }

    // MARK: UI construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        root.frame = contentView.bounds
        root.autoresizingMask = [.width, .height]
        root.onAppearanceChange = { [weak self] in self?.refreshOutput() }
        contentView.addSubview(root)

        // Header: icon · Jit / Mode · model · status · close
        let jitLabel = Lantor.label("Jit", Lantor.font(15, .bold), Lantor.ink)
        let slash = Lantor.label("/", Lantor.font(15), Lantor.placeholder)
        modeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modelChip.maxTextWidth = 200
        modelChip.isHidden = true
        modelChip.toolTip = "AI connection — change it in Settings → AI Model"
        statusChip.isHidden = true
        closeButton.height = 26
        closeButton.symbolSize = 10
        closeButton.toolTip = "Close (esc)"
        closeButton.onClick = { [weak self] in self?.window?.close() }
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [LantorAppIcon(size: 22), jitLabel, slash, modeLabel, headerSpacer, modelChip, statusChip, closeButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.setCustomSpacing(10, after: header.views[0])
        header.setCustomSpacing(6, after: jitLabel)
        header.setCustomSpacing(6, after: slash)
        header.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 26).isActive = true

        // Mode tabs
        let tabs = NSStackView()
        tabs.orientation = .horizontal
        tabs.distribution = .fillEqually
        tabs.spacing = 4
        tabs.translatesAutoresizingMaskIntoConstraints = false
        modeButtons = modes.enumerated().map { index, mode in
            let button = ModeTabButton(title: Self.compactTitle(for: mode), symbol: Self.symbol(for: mode))
            button.toolTip = "\(Self.compactTitle(for: mode)) — tab or ← → to switch"
            button.onClick = { [weak self] in self?.selectMode(index) }
            tabs.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            return button
        }
        tabsTrack.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabsTrack.heightAnchor.constraint(equalToConstant: 40),
            tabs.leadingAnchor.constraint(equalTo: tabsTrack.leadingAnchor, constant: 4),
            tabs.trailingAnchor.constraint(equalTo: tabsTrack.trailingAnchor, constant: -4),
            tabs.topAnchor.constraint(equalTo: tabsTrack.topAnchor, constant: 4),
            tabs.bottomAnchor.constraint(equalTo: tabsTrack.bottomAnchor, constant: -4),
        ])

        // Setup notice
        let noticeIcon = NSImageView()
        noticeIcon.image = Lantor.symbol("exclamationmark.triangle.fill", size: 13, weight: .semibold, color: Lantor.warning)
        noticeIcon.setContentHuggingPriority(.required, for: .horizontal)
        noticeButton.height = 26
        noticeButton.fontSize = 12
        noticeButton.onClick = { [weak self] in self?.settingsTapped() }
        let noticeSpacer = NSView()
        noticeSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        noticeLabel.preferredMaxLayoutWidth = 400
        let noticeRow = NSStackView(views: [noticeIcon, noticeLabel, noticeSpacer, noticeButton])
        noticeRow.orientation = .horizontal
        noticeRow.alignment = .centerY
        noticeRow.spacing = 9
        noticeRow.translatesAutoresizingMaskIntoConstraints = false
        noticeBanner.addSubview(noticeRow)
        NSLayoutConstraint.activate([
            noticeRow.leadingAnchor.constraint(equalTo: noticeBanner.leadingAnchor, constant: 12),
            noticeRow.trailingAnchor.constraint(equalTo: noticeBanner.trailingAnchor, constant: -8),
            noticeRow.topAnchor.constraint(equalTo: noticeBanner.topAnchor, constant: 7),
            noticeRow.bottomAnchor.constraint(equalTo: noticeBanner.bottomAnchor, constant: -7),
        ])

        // Selection card
        refCard.accentBar = Lantor.accent
        refText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        refMeta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let refStack = NSStackView(views: [refMeta, refText])
        refStack.orientation = .vertical
        refStack.alignment = .leading
        refStack.spacing = 3
        refStack.translatesAutoresizingMaskIntoConstraints = false
        refCard.addSubview(refStack)
        NSLayoutConstraint.activate([
            refStack.leadingAnchor.constraint(equalTo: refCard.leadingAnchor, constant: 14),
            refStack.trailingAnchor.constraint(equalTo: refCard.trailingAnchor, constant: -12),
            refStack.topAnchor.constraint(equalTo: refCard.topAnchor, constant: 9),
            refStack.bottomAnchor.constraint(equalTo: refCard.bottomAnchor, constant: -10),
            refText.widthAnchor.constraint(equalTo: refStack.widthAnchor),
        ])

        // Composer
        composer.ringInset = 3
        composer.draggable = false
        commandField.font = Lantor.font(15)
        commandField.textColor = Lantor.ink
        commandField.isBordered = false
        commandField.drawsBackground = false
        commandField.focusRingType = .none
        commandField.usesSingleLineMode = false
        commandField.cell?.wraps = true
        commandField.cell?.isScrollable = false
        commandField.lineBreakMode = .byWordWrapping
        commandField.maximumNumberOfLines = 0
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        commandField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sendButton.height = 32
        sendButton.symbolSize = 13
        sendButton.toolTip = "Run (↩)"
        sendButton.onClick = { [weak self] in self?.runTapped() }
        composer.addSubview(commandField)
        composer.addSubview(sendButton)
        let composerHeight = composer.heightAnchor.constraint(equalToConstant: Layout.composerIdleHeight + 6)
        self.composerHeight = composerHeight
        NSLayoutConstraint.activate([
            composerHeight,
            commandField.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 3 + 15),
            commandField.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -(3 + 52)),
            commandField.topAnchor.constraint(equalTo: composer.topAnchor, constant: 3 + 13),
            commandField.bottomAnchor.constraint(lessThanOrEqualTo: composer.bottomAnchor, constant: -(3 + 10)),
            sendButton.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -(3 + 10)),
            sendButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -(3 + 10)),
        ])
        // Focus follows the field editor, so the halo shows as soon as the caret is in the composer.
        windowUpdateObserver = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let editing = self.window?.firstResponder === self.commandField.currentEditor()
                if self.composer.focused != editing { self.composer.focused = editing }
            }
        }

        presetsRow.orientation = .horizontal
        presetsRow.spacing = 6
        presetsRow.alignment = .centerY
        presetsRow.translatesAutoresizingMaskIntoConstraints = false
        presetsRow.edgeInsets = NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 0)

        // Output
        outputScroll.translatesAutoresizingMaskIntoConstraints = false
        outputScroll.hasVerticalScroller = true
        outputScroll.hasHorizontalScroller = false
        outputScroll.autohidesScrollers = true
        outputScroll.borderType = .noBorder
        outputScroll.drawsBackground = false
        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.drawsBackground = false
        outputTextView.isRichText = true
        outputTextView.importsGraphics = false
        outputTextView.font = Lantor.font(15)
        outputTextView.textContainerInset = NSSize(width: 12, height: 12)
        outputTextView.isVerticallyResizable = true
        outputTextView.isHorizontallyResizable = false
        outputTextView.autoresizingMask = [.width]
        outputTextView.minSize = .zero
        outputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.textContainer?.widthTracksTextView = true
        outputTextView.textContainer?.containerSize = NSSize(width: Layout.width, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.textContainer?.lineBreakMode = .byWordWrapping
        outputTextView.textContainer?.lineFragmentPadding = 4
        outputTextView.selectedTextAttributes = [.backgroundColor: Lantor.accentSoft]
        outputScroll.documentView = outputTextView
        outputCard.addSubview(outputScroll)
        cardSpeakButton.height = 28
        cardSpeakButton.symbolSize = 12
        cardSpeakButton.toolTip = "Speak (⌥S)"
        cardSpeakButton.onClick = { [weak self] in self?.speakTapped() }
        outputCard.addSubview(cardSpeakButton)
        outputCard.isHidden = true
        outputCard.setContentHuggingPriority(.init(1), for: .vertical)
        outputCard.setContentCompressionResistancePriority(.init(1), for: .vertical)
        NSLayoutConstraint.activate([
            outputScroll.leadingAnchor.constraint(equalTo: outputCard.leadingAnchor, constant: 2),
            outputScroll.trailingAnchor.constraint(equalTo: outputCard.trailingAnchor, constant: -2),
            outputScroll.topAnchor.constraint(equalTo: outputCard.topAnchor, constant: 2),
            outputScroll.bottomAnchor.constraint(equalTo: outputCard.bottomAnchor, constant: -2),
            outputCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            cardSpeakButton.topAnchor.constraint(equalTo: outputCard.topAnchor, constant: 12),
            cardSpeakButton.trailingAnchor.constraint(equalTo: outputCard.trailingAnchor, constant: -14),
        ])

        body.orientation = .vertical
        // Centered so the composer's 3pt focus-ring margin overhangs evenly on both sides.
        body.alignment = .centerX
        body.spacing = 10
        body.translatesAutoresizingMaskIntoConstraints = false
        for view in [header, tabsTrack, noticeBanner, refCard, composer, presetsRow, outputCard] {
            body.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: body.widthAnchor, constant: view === composer ? 6 : 0).isActive = true
        }
        body.setCustomSpacing(12, after: tabsTrack)
        body.setCustomSpacing(7, after: refCard)
        body.setCustomSpacing(7, after: composer)
        noticeBanner.isHidden = true

        // Footer
        hintsRow.orientation = .horizontal
        hintsRow.spacing = 12
        hintsRow.alignment = .centerY
        hintsRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        speakButton.toolTip = "Speak (⌥S)"
        speakButton.onClick = { [weak self] in self?.speakTapped() }
        settingsButton.onClick = { [weak self] in self?.settingsTapped() }
        lastResultButton.onClick = { [weak self] in self?.lastResultTapped() }
        runAgainButton.onClick = { [weak self] in self?.runTapped() }
        copyButton.onClick = { [weak self] in self?.copyTapped() }
        replaceButton.onClick = { [weak self] in self?.replaceTapped() }
        stopButton.onClick = { [weak self] in self?.cancelTapped() }
        runButton.onClick = { [weak self] in self?.runTapped() }
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let footerRow = NSStackView(views: [hintsRow, footerSpacer, speakButton, settingsButton, lastResultButton, runAgainButton, copyButton, replaceButton, stopButton, runButton])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 8
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(footerRow)
        root.footer = footer

        root.addSubview(body)
        root.addSubview(footer)
        let bodyBottom = body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12)
        bodyBottom.priority = .init(999)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 11),
            bodyBottom,
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: Layout.footerHeight),
            footerRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            footerRow.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            footerRow.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: -1),
        ])
    }

    private func rebuildPresets() {
        presetsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for instruction in recentInstructions.prefix(3) {
            let button = LantorButton(instruction.oneLinePreview(28), kind: .pill, symbol: "clock.arrow.circlepath")
            button.height = 26
            button.horizontalPadding = 10
            button.symbolSize = 11
            button.toolTip = instruction
            button.onClick = { [weak self] in self?.applyPreset(instruction) }
            presetsRow.addArrangedSubview(button)
        }
    }

    private func applyPreset(_ instruction: String) {
        guard modes[currentModeIndex].requiresInstruction, phase != .running else { return }
        commandField.stringValue = instruction
        customInstructionDraft = instruction
        window?.makeFirstResponder(commandField)
        moveCaretToEnd()
    }

    private func moveCaretToEnd() {
        guard let editor = commandField.currentEditor() else { return }
        editor.selectedRange = NSRange(location: (commandField.stringValue as NSString).length, length: 0)
    }

    // MARK: Rendering from state

    /// Derives every visible control from `phase`, the current mode and the selection.
    private func render() {
        guard !modeButtons.isEmpty else { return }
        let mode = modes[currentModeIndex]
        let hasSelection = !selectedText.isEmpty
        let busy = phase == .running || phase == .readingSelection
        let isWords = mode.id == "vocabulary"

        modeLabel.stringValue = phase == .readingSelection ? "Reading selection…" : Self.compactTitle(for: mode)
        for (index, button) in modeButtons.enumerated() {
            let candidate = modes[index]
            button.isEnabled = !busy && (hasSelection || candidate.requiresInstruction)
            button.isSelectedTab = index == currentModeIndex
        }

        // Status chip
        switch phase {
        case .readingSelection:
            setStatus("Reading", tone: .thinking, pulse: true)
        case .running:
            setStatus(outputDidStream ? "Streaming" : "Running", tone: .thinking, pulse: true)
        case .done:
            if showingStoredResult {
                setStatus("Saved result", tone: .neutral, pulse: false)
            } else if let lastElapsed {
                setStatus("Done · \(Self.formatElapsed(lastElapsed))", tone: .success, pulse: false)
            } else {
                setStatus("Done", tone: .success, pulse: false)
            }
        case .error:
            setStatus("Failed", tone: .danger, pulse: false)
        case .idle, .noSelection:
            statusChip.isHidden = true
        }

        // Setup notice
        let showNotice = setupNotice != nil && (phase == .idle || phase == .noSelection)
        noticeBanner.isHidden = !showNotice
        noticeLabel.stringValue = setupNotice ?? ""

        // Selection card (Words hides it once the card shows the headword).
        let wordsCardVisible = isWords && !rawOutput.isEmpty && phase != .error
        refCard.isHidden = wordsCardVisible
        renderSelectionCard(mode: mode)

        // Composer + presets
        composer.isHidden = !mode.requiresInstruction
        let editable = mode.requiresInstruction && !busy
        commandField.isEditable = editable
        commandField.isEnabled = editable
        commandField.placeholderAttributedString = NSAttributedString(
            string: hasSelection ? "Tell Jit what to do with the selection…" : "Ask anything — no text selected",
            attributes: [.foregroundColor: Lantor.placeholder, .font: Lantor.font(15)]
        )
        sendButton.isEnabled = editable
        let outputVisible = expanded
        composerHeight?.constant = (outputVisible ? Layout.composerCompactHeight : Layout.composerIdleHeight) + 6
        presetsRow.isHidden = !(mode.requiresInstruction && !recentInstructions.isEmpty && !outputVisible && phase != .readingSelection)

        outputCard.isHidden = !outputVisible
        renderedCardVisible = wordsCardVisible && hasSelection && currentCard != nil
        cardSpeakButton.isHidden = !renderedCardVisible
        cardSpeakButton.symbolName = isSpeakingSelectedText ? "speaker.slash.fill" : "speaker.wave.2.fill"

        // Footer hints (rebuilt only when they change)
        let showSpeakHint = isWords && hasSelection
        let escLabel = phase == .running ? "Stop" : "Close"
        let key = "\(showSpeakHint)|\(escLabel)"
        if key != hintsKey {
            hintsKey = key
            hintsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
            hintsRow.addArrangedSubview(lantorHint("tab", "Switch"))
            if showSpeakHint {
                hintsRow.addArrangedSubview(lantorHint("⌥S", "Speak"))
            }
            hintsRow.addArrangedSubview(lantorHint("esc", escLabel))
        }

        // Footer buttons
        let hasOutput = !rawOutput.isEmpty && !busy && phase != .error
        let canReplace = hasOutput && mode.supportsReplace && allowsReplace
        speakButton.isHidden = !(isWords && hasSelection && phase != .readingSelection)
        speakButton.kind = isSpeakingSelectedText ? .warning : .secondary
        speakButton.symbolName = isSpeakingSelectedText ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let voice = speechVoiceDescription.isEmpty ? "" : " · \(speechVoiceDescription)"
        speakButton.toolTip = isSpeakingSelectedText ? "Stop speaking" : "Speak selection (⌥S)\(voice)"
        settingsButton.isHidden = !(phase == .error && errorNeedsSettings)
        lastResultButton.isHidden = !(phase == .noSelection && lastResult != nil)
        runAgainButton.isHidden = !(phase == .done && (hasSelection || mode.requiresInstruction))
        copyButton.isHidden = !hasOutput
        copyButton.kind = canReplace ? .secondary : .primary
        replaceButton.isHidden = !canReplace
        stopButton.isHidden = phase != .running
        let canRun = !busy && (hasSelection || mode.requiresInstruction)
        runButton.isHidden = !(phase == .idle || phase == .noSelection || phase == .error)
        runButton.isEnabled = canRun
        runButton.text = phase == .error ? "Retry" : "Run"
        root.needsDisplay = true
        fitCompactHeight(anchorTop: true)
    }

    private func setStatus(_ text: String, tone: LantorChip.Tone, pulse: Bool) {
        statusChip.isHidden = false
        statusChip.text = text
        statusChip.tone = tone
        statusChip.pulse = pulse
    }

    private func renderSelectionCard(mode: Mode) {
        let meta = NSMutableAttributedString()
        let mutedAttrs: [NSAttributedString.Key: Any] = [.font: Lantor.font(12, .medium), .foregroundColor: Lantor.muted]
        func dot() { meta.append(NSAttributedString(string: "  ·  ", attributes: mutedAttrs)) }
        if phase == .readingSelection {
            meta.append(NSAttributedString(string: "Selection", attributes: [.font: Lantor.font(12, .semibold), .foregroundColor: Lantor.inkSecondary]))
            refText.stringValue = "Reading the selected text…"
            refText.textColor = Lantor.muted
        } else if selectedText.isEmpty {
            meta.append(NSAttributedString(string: "No selection", attributes: [.font: Lantor.font(12, .semibold), .foregroundColor: Lantor.inkSecondary]))
            refText.stringValue = "Custom works as a general prompt. Select text first to transform it."
            refText.textColor = Lantor.muted
        } else {
            meta.append(NSAttributedString(string: "Selection", attributes: [.font: Lantor.font(12, .semibold), .foregroundColor: Lantor.inkSecondary]))
            dot()
            meta.append(NSAttributedString(string: "\(selectedText.count) chars", attributes: mutedAttrs))
            if mode.id == "translate", let direction = directionLabel?(selectedText) {
                dot()
                meta.append(NSAttributedString(string: direction, attributes: mutedAttrs))
            }
            refText.stringValue = selectedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            refText.textColor = Lantor.inkSecondary
        }
        refMeta.attributedStringValue = meta
        refText.preferredMaxLayoutWidth = (window?.frame.width ?? Layout.width) - 28 - 26
    }

    /// Applies mode-specific field content (called on mode switches, not on every render).
    private func applyMode() {
        let mode = modes[currentModeIndex]
        if mode.id != "vocabulary", isSpeakingSelectedText {
            onStopSpeech?()
            isSpeakingSelectedText = false
        }
        commandField.stringValue = mode.requiresInstruction ? customInstructionDraft : ""
    }

    // MARK: Actions

    private func runTapped() {
        guard phase != .running, phase != .readingSelection else { return }
        let mode = modes[currentModeIndex]
        let rawInstruction = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode.requiresInstruction {
            customInstructionDraft = rawInstruction
            if rawInstruction.isEmpty {
                NSSound.beep()
                window?.makeFirstResponder(commandField)
                return
            }
        } else if selectedText.isEmpty {
            NSSound.beep()
            return
        }
        let instruction = mode.requiresInstruction ? rawInstruction : nil
        phase = .running
        showingStoredResult = false
        rawOutput = ""
        outputDidStream = false
        runStartedAt = Date()
        lastElapsed = nil
        expandForOutputIfNeeded()
        refreshOutput(placeholder: "Waiting for \(Self.compactTitle(for: mode))…")
        render()
        window?.makeFirstResponder(nil)

        runGeneration += 1
        let generation = runGeneration
        activeRun = onSubmit?(
            mode.id,
            instruction,
            selectedText,
            { [weak self] delta in
                Task { @MainActor in
                    self?.appendOutput(delta, generation: generation)
                }
            },
            { [weak self] result in
                Task { @MainActor in
                    self?.finishRunning(result: result, mode: mode, instruction: instruction, generation: generation)
                }
            }
        )
        if activeRun == nil {
            finishRunning(
                result: .failure(NSError(domain: "JitAPP", code: 500, userInfo: [NSLocalizedDescriptionKey: "No processing handler is configured."])),
                mode: mode,
                instruction: instruction,
                generation: generation
            )
        }
    }

    private func cancelTapped() {
        if phase == .running {
            runGeneration += 1
            activeRun?.cancel()
            activeRun = nil
            phase = rawOutput.isEmpty ? .idle : .done
            lastElapsed = runStartedAt.map { Date().timeIntervalSince($0) }
            refreshOutput(placeholder: "Stopped.")
            render()
            focus()
            return
        }
        window?.close()
    }

    private func speakTapped() {
        guard modes[currentModeIndex].id == "vocabulary", !selectedText.isEmpty else { return }
        let text = currentCard?.headword ?? selectedText
        let started = onToggleSpeech?(text) { [weak self] speaking in
            self?.setSpeechState(speaking)
        } ?? false
        setSpeechState(started)
    }

    private func replaceTapped() {
        let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, modes[currentModeIndex].supportsReplace, allowsReplace else { return }
        onReplace?(output)
    }

    private func copyTapped() {
        let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copyButton.text = "Copied"
        copyButton.hint = "✓"
        copyResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.copyButton.text = "Copy"
            self?.copyButton.hint = "⌘C"
        }
        copyResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func settingsTapped() {
        onOpenSettings?()
        window?.close()
    }

    private func lastResultTapped() {
        guard let lastResult else { return }
        showHistoryEntry(lastResult)
    }

    private func selectMode(_ index: Int) {
        guard index >= 0, index < modes.count, index != currentModeIndex else { return }
        guard phase != .running, phase != .readingSelection else { return }
        let target = modes[index]
        if selectedText.isEmpty && !target.requiresInstruction {
            NSSound.beep()
            return
        }
        if modes[currentModeIndex].requiresInstruction {
            customInstructionDraft = commandField.stringValue
        }
        currentModeIndex = index
        if phase == .done || phase == .error {
            phase = selectedText.isEmpty ? .noSelection : .idle
            rawOutput = ""
            showingStoredResult = false
            refreshOutput(placeholder: "Press ↩ to run \(Self.compactTitle(for: target)).")
        }
        applyMode()
        render()
        focus()
    }

    private func moveMode(delta: Int) {
        guard modes.count > 1 else { return }
        var index = currentModeIndex
        for _ in 0..<modes.count {
            index = (index + delta + modes.count) % modes.count
            if !selectedText.isEmpty || modes[index].requiresInstruction {
                selectMode(index)
                return
            }
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handlePanelKeyDown(event) ? nil : event
        }
    }

    private func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let busy = phase == .running || phase == .readingSelection
        // Let an input method finish composing (e.g. Pinyin) before Return/Esc act on the palette.
        if let editor = commandField.currentEditor() as? NSTextView, editor.hasMarkedText() {
            return false
        }
        if event.keyCode == 53 { // Esc
            cancelTapped()
            return true
        }
        if flags == .command, let chars = event.charactersIgnoringModifiers {
            if chars == "c" {
                let outputHasSelection = window?.firstResponder === outputTextView && outputTextView.selectedRange().length > 0
                if !rawOutput.isEmpty, !outputHasSelection, phase == .done {
                    copyTapped()
                    return true
                }
                return false
            }
            if event.keyCode == 36 || event.keyCode == 76 { // ⌘↩
                if !replaceButton.isHidden {
                    replaceTapped()
                }
                return true
            }
            return false
        }
        if flags == .option, event.keyCode == 1, modes[currentModeIndex].id == "vocabulary" { // ⌥S
            speakTapped()
            return true
        }
        if event.keyCode == 48, flags.isEmpty || flags == .shift { // Tab / ⇧Tab cycle modes
            if !busy { moveMode(delta: flags == .shift ? -1 : 1) }
            return true
        }
        guard flags.isEmpty else { return false }
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            if !busy {
                runTapped()
            }
            return true
        }
        // ← / → switch modes unless they are moving the caret in a non-empty instruction.
        let editingText = window?.firstResponder === commandField.currentEditor() && !commandField.stringValue.isEmpty
        if event.keyCode == 123, !editingText { // Left
            if !busy { moveMode(delta: -1) }
            return true
        }
        if event.keyCode == 124, !editingText { // Right
            if !busy { moveMode(delta: 1) }
            return true
        }
        return false
    }

    // MARK: Run lifecycle

    private func finishRunning(result: Result<String, Error>, mode: Mode, instruction: String?, generation: Int) {
        guard generation == runGeneration else { return }
        activeRun = nil
        lastElapsed = runStartedAt.map { Date().timeIntervalSince($0) }
        switch result {
        case .success(let output):
            // The completed response is authoritative if a CLI event revised
            // an earlier snapshot or emitted more than one agent message.
            rawOutput = output
            phase = .done
            refreshOutput()
            render()
            onResult?(HistoryEntry(
                id: UUID(),
                modeID: mode.id,
                modeTitle: Self.compactTitle(for: mode),
                selectedText: selectedText,
                instruction: instruction,
                output: rawOutput,
                date: Date()
            ))
            restoreFirstResponder()
        case .failure(let error):
            if error is CancellationError { return }
            let described = FriendlyError.describe(error)
            errorMessage = described.message
            errorNeedsSettings = described.needsSettings
            phase = .error
            refreshOutput()
            render()
            restoreFirstResponder()
        }
    }

    private func appendOutput(_ delta: String, generation: Int) {
        guard generation == runGeneration, phase == .running else { return }
        rawOutput += delta
        let first = !outputDidStream
        outputDidStream = true
        refreshOutput()
        // Chrome only changes on the first delta and when the Words card first parses.
        let cardVisible = modes[currentModeIndex].id == "vocabulary" && !selectedText.isEmpty && currentCard != nil
        if first || cardVisible != renderedCardVisible { render() }
        scrollOutputToEnd()
    }

    private func setSpeechState(_ speaking: Bool) {
        isSpeakingSelectedText = speaking
        render()
    }

    // MARK: Output view

    private var currentCard: VocabularyCard? {
        guard modes[currentModeIndex].id == "vocabulary" else { return nil }
        return VocabularyCard.parse(rawOutput)
    }

    /// Re-renders the output from state (also after appearance changes, since colors are baked in).
    private func refreshOutput(placeholder: String? = nil) {
        if let placeholder { outputPlaceholder = placeholder }
        let style = OutputFormatter.Style()
        let rendered = NSMutableAttributedString()
        if phase == .error {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            rendered.append(NSAttributedString(string: errorMessage, attributes: [
                .font: Lantor.font(14), .foregroundColor: Lantor.danger, .paragraphStyle: paragraph,
            ]))
        } else if rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rendered.append(NSAttributedString(string: phase == .running ? "Waiting for \(Self.compactTitle(for: modes[currentModeIndex]))…" : outputPlaceholder, attributes: [
                .font: Lantor.font(14), .foregroundColor: Lantor.placeholder,
            ]))
        } else if let card = currentCard {
            rendered.append(OutputFormatter.vocabularyCard(card, style: style))
        } else {
            rendered.append(OutputFormatter.attributedString(from: rawOutput.trimmingCharacters(in: .whitespacesAndNewlines), style: style))
        }
        if phase == .running, outputDidStream {
            rendered.append(NSAttributedString(string: " ", attributes: [.font: style.body]))
            rendered.append(OutputFormatter.caret())
        }
        outputTextView.textStorage?.setAttributedString(rendered)
    }

    private func scrollOutputToEnd() {
        let length = (outputTextView.string as NSString).length
        outputTextView.scrollRangeToVisible(NSRange(location: length, length: 0))
    }

    private var isFitting = false

    /// Without output the panel hugs its content; this keeps the top edge where it was.
    private func fitCompactHeight(anchorTop: Bool) {
        guard let window, !expanded, !isFitting else { return }
        isFitting = true
        defer { isFitting = false }
        body.layoutSubtreeIfNeeded()
        let measuring = body.widthAnchor.constraint(equalToConstant: window.frame.width - 28)
        measuring.isActive = true
        let height = ceil(11 + body.fittingSize.height + 12 + Layout.footerHeight)
        measuring.isActive = false
        guard abs(window.frame.height - height) > 0.5 else { return }
        var frame = window.frame
        if anchorTop { frame.origin.y = frame.maxY - height }
        frame.size.height = height
        if let visible = window.screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY + 8
        }
        window.minSize = NSSize(width: Layout.width, height: height)
        window.maxSize = NSSize(width: Layout.width, height: height)
        window.setFrame(frame, display: true)
        window.invalidateShadow()
    }

    private func expandForOutputIfNeeded() {
        guard let window, !expanded else { return }
        expanded = true
        render()
        var size = UserDefaults.standard.string(forKey: Layout.sizeDefaultsKey).map(NSSizeFromString) ?? Layout.defaultExpandedSize
        size.width = min(max(size.width, Layout.minExpandedSize.width), Layout.maxSize.width)
        size.height = min(max(size.height, Layout.minExpandedSize.height), Layout.maxSize.height)
        window.minSize = Layout.minExpandedSize
        window.maxSize = Layout.maxSize
        var frame = window.frame
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        if frame.minY < visible.minY { frame.origin.y = visible.minY + 8 }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height - 8 }
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width - 8 }
        if frame.minX < visible.minX { frame.origin.x = visible.minX + 8 }
        window.setFrame(frame, display: true, animate: window.isVisible)
        window.invalidateShadow()
    }

    func windowDidResize(_ notification: Notification) {
        refText.preferredMaxLayoutWidth = (window?.frame.width ?? Layout.width) - 28 - 26
        window?.invalidateShadow()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard expanded, let window else { return }
        UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: Layout.sizeDefaultsKey)
    }

    func windowWillClose(_ notification: Notification) {
        runGeneration += 1
        activeRun?.cancel()
        activeRun = nil
        onStopSpeech?()
        stopOutsideClickMonitor()
        if let windowUpdateObserver {
            NotificationCenter.default.removeObserver(windowUpdateObserver)
            self.windowUpdateObserver = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        onClose?()
    }

    private func stopOutsideClickMonitor() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func closeIfClickOutside() {
        guard let window, window.isVisible else { return }
        if !window.frame.contains(NSEvent.mouseLocation) {
            window.close()
        }
    }

    /// Places the panel just below the selection (or the mouse), flipping above when there is no room.
    private func position(near anchor: NSRect) {
        guard let window else { return }
        let frame = window.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.minX - 12
        var y = anchor.minY - frame.height - 10
        if y < visible.minY { y = anchor.maxY + 10 }
        if y + frame.height > visible.maxY { y = visible.maxY - frame.height - 8 }
        if x + frame.width > visible.maxX { x = visible.maxX - frame.width - 8 }
        if x < visible.minX { x = visible.minX + 8 }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    static func compactTitle(for mode: Mode) -> String {
        switch mode.id {
        case "custom": return "Custom"
        case "refine": return "Polish"
        case "translate": return "Translate"
        case "vocabulary": return "Words"
        default: return mode.title
        }
    }

    static func symbol(for mode: Mode) -> String {
        switch mode.id {
        case "translate": return "character.bubble"
        case "refine": return "pencil.line"
        case "custom": return "text.bubble"
        case "vocabulary": return "book.closed"
        default: return "sparkles"
        }
    }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 10 { return String(format: "%.1fs", seconds) }
        if seconds < 60 { return "\(Int(seconds.rounded()))s" }
        let total = Int(seconds.rounded())
        return String(format: "%dm %02ds", total / 60, total % 60)
    }

    #if DEBUG
    /// Drives the palette into a given state for offscreen snapshots (see SnapshotRenderer).
    func debugShow(modeID: String, selection: String?, output: String?, running: Bool = false, error: String? = nil, elapsed: TimeInterval? = nil, instruction: String? = nil) {
        if let index = modes.firstIndex(where: { $0.id == modeID }) { currentModeIndex = index }
        setSelection(selection)
        if let index = modes.firstIndex(where: { $0.id == modeID }) { currentModeIndex = index }
        if let instruction { customInstructionDraft = instruction }
        applyMode()
        if let output {
            rawOutput = output
            outputDidStream = running
            phase = running ? .running : .done
            lastElapsed = elapsed
            expandForOutputIfNeeded()
        } else if let error {
            errorMessage = error
            errorNeedsSettings = true
            phase = .error
            expandForOutputIfNeeded()
        }
        refreshOutput()
        render()
    }
    #endif
}
