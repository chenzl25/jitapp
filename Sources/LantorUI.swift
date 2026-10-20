import AppKit

// Lantor design tokens and the small custom-drawn controls the palette and
// Settings are built from. Values mirror lantor/src/styles.css (light + dark).
// Everything draws in draw(_:) with dynamic colors, so appearance switches
// repaint correctly and nothing depends on layer snapshots of cgColor.

extension NSColor {
    /// sRGB hex color; `alpha` matches CSS rgba().
    convenience init(srgbHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    static func lantor(_ light: UInt32, _ lightAlpha: CGFloat = 1, dark: UInt32, _ darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(srgbHex: dark, alpha: darkAlpha) : NSColor(srgbHex: light, alpha: lightAlpha)
        }
    }
}

@MainActor
enum Lantor {
    // Surfaces
    static let appBackground = NSColor.lantor(0xf0f3f7, dark: 0x242b35)
    static let sidebar = NSColor.lantor(0xf3f5f8, dark: 0x2b333f)
    static let panel = NSColor.lantor(0xf7f8fa, dark: 0x303844)
    static let panelStrong = NSColor.lantor(0xfbfcfd, dark: 0x374151)
    static let elevated = NSColor.lantor(0xf4f6f9, dark: 0x3d4858)
    static let recessed = NSColor.lantor(0xe8ecf2, dark: 0x1d232c)
    static let input = NSColor.lantor(0xfbfcfd, dark: 0x2a3340)
    static let control = NSColor.lantor(0xf4f6f9, dark: 0x3a4454)
    static let hover = NSColor.lantor(0xe6eefa, dark: 0x69aafc, 0.14)
    static let selectedFill = NSColor.lantor(0x0a84ff, 0.10, dark: 0x69aafc, 0.19)
    static let selectedBorder = NSColor.lantor(0x0a84ff, 0.24, dark: 0x69aafc, 0.72)
    static let track = NSColor.lantor(0xe8ecf2, 0.9, dark: 0x1d232c, 0.7)
    static let kbd = NSColor.lantor(0xffffff, dark: 0x2a3340)
    static let defaultFill = NSColor.lantor(0x8e8e93, 0.12, dark: 0xe2e8f0, 0.10)

    // Ink
    static let ink = NSColor.lantor(0x20242b, dark: 0xf4f6fa)
    static let inkSecondary = NSColor.lantor(0x4f5661, dark: 0xdde3ec)
    static let muted = NSColor.lantor(0x68717d, dark: 0xb3bdcc)
    static let placeholder = NSColor.lantor(0x68717d, 0.72, dark: 0x8f98a8, 0.72)

    // Lines
    static let line = NSColor.lantor(0x20242c, 0.10, dark: 0xe2e8f0, 0.18)
    static let lineStrong = NSColor.lantor(0x20242c, 0.16, dark: 0xe2e8f0, 0.30)
    static let controlBorder = NSColor.lantor(0x20242c, 0.14, dark: 0xe2e8f0, 0.24)
    static let floatingBorder = NSColor.lantor(0x20242c, 0.16, dark: 0xe2e8f0, 0.22)

    // Accent and states
    static let accent = NSColor.lantor(0x0a84ff, dark: 0x69aafc)
    static let accentPressed = NSColor.lantor(0x0070e0, dark: 0x5296ea)
    static let accentInk = NSColor.lantor(0xffffff, dark: 0x07111f)
    static let accentSoft = NSColor.lantor(0x0a84ff, 0.10, dark: 0x69aafc, 0.14)
    static let accentSoftBorder = NSColor.lantor(0x0a84ff, 0.22, dark: 0x69aafc, 0.28)
    static let accentSoftInk = NSColor.lantor(0x1262b3, dark: 0x69aafc)
    static let focusRing = NSColor.lantor(0x0a84ff, 0.16, dark: 0x69aafc, 0.22)
    static let success = NSColor.lantor(0x167d32, dark: 0x67d084)
    static let successSoft = NSColor.lantor(0x34c759, 0.14, dark: 0x34c759, 0.14)
    static let warning = NSColor.lantor(0xa25c00, dark: 0xffc166)
    static let warningSoft = NSColor.lantor(0xff9f0a, 0.10, dark: 0xffb142, 0.16)
    static let warningBorder = NSColor.lantor(0xff9f0a, 0.24, dark: 0xffb142, 0.28)
    static let danger = NSColor.lantor(0xb42318, dark: 0xffb4ab)
    static let dangerSoft = NSColor.lantor(0xb42318, 0.08, dark: 0xffb4ab, 0.14)
    static let thinkingSoft = NSColor.lantor(0x5ac8fa, 0.16, dark: 0x5ac8fa, 0.16)
    static let thinkingInk = NSColor.lantor(0x0071a8, dark: 0x7dd3fc)
    static let fileSoft = NSColor.lantor(0xbf5af2, 0.14, dark: 0xd8b4fe, 0.16)
    static let fileInk = NSColor.lantor(0x7b2cbf, dark: 0xd8b4fe)

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    @MainActor
    static func label(_ text: String, _ font: NSFont, _ color: NSColor, lines: Int = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.translatesAutoresizingMaskIntoConstraints = false
        if lines != 1 {
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return field
    }

    /// Uppercase section legend ("CONNECTION", "BEHAVIOR").
    @MainActor
    static func legend(_ text: String) -> NSTextField {
        let field = label("", font(12, .semibold), muted)
        field.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: font(12, .semibold), .foregroundColor: muted, .kern: 0.3,
        ])
        return field
    }

    /// SF Symbol drawn in a fixed color (palette rendering resolves dynamic colors at draw time).
    @MainActor
    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .medium, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return base.withSymbolConfiguration(config)
    }

    @MainActor
    static var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}

// MARK: - Surface

/// Rounded rectangle with fill, border, optional left accent bar and focus ring.
/// `ringInset` reserves space inside the bounds so the 3pt focus halo is never clipped.
@MainActor
class LantorSurface: NSView {
    var fill: NSColor? { didSet { needsDisplay = true } }
    var stroke: NSColor? { didSet { needsDisplay = true } }
    var radius: CGFloat = 12 { didSet { needsDisplay = true } }
    var accentBar: NSColor? { didSet { needsDisplay = true } }
    var ringInset: CGFloat = 0 { didSet { needsDisplay = true } }
    var focused = false { didSet { if focused != oldValue { needsDisplay = true } } }
    var draggable = true

    init(fill: NSColor? = nil, stroke: NSColor? = nil, radius: CGFloat = 12) {
        self.fill = fill
        self.stroke = stroke
        self.radius = radius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { draggable }
    override var isOpaque: Bool { false }

    var surfaceRect: NSRect { bounds.insetBy(dx: ringInset, dy: ringInset) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = surfaceRect
        if focused, ringInset > 0 {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -ringInset / 2, dy: -ringInset / 2), xRadius: radius + ringInset / 2, yRadius: radius + ringInset / 2)
            ring.lineWidth = ringInset
            Lantor.focusRing.setStroke()
            ring.stroke()
        }
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if let fill {
            fill.setFill()
            path.fill()
        }
        if let accentBar {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            accentBar.setFill()
            let bar = NSRect(x: rect.minX, y: rect.minY + 10, width: 3, height: max(0, rect.height - 20))
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        if let border = focused ? Lantor.accent : stroke {
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// A 1pt hairline in the Lantor line color.
@MainActor
final class LantorSeparator: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }

    override func draw(_ dirtyRect: NSRect) {
        Lantor.line.setFill()
        bounds.fill()
    }
}

// MARK: - Button

@MainActor
final class LantorButton: NSButton {
    enum Kind {
        case primary
        case secondary
        case warning
        case danger
        case ghost
        case pill
        case accentSoft
    }

    var kind: Kind { didSet { needsDisplay = true } }
    var text: String { didSet { super.title = text; invalidateIntrinsicContentSize(); needsDisplay = true } }
    var hint: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var symbolName: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var symbolSize: CGFloat = 13
    var height: CGFloat = 30 { didSet { invalidateIntrinsicContentSize() } }
    var radius: CGFloat? { didSet { needsDisplay = true } }
    var horizontalPadding: CGFloat = 12 { didSet { invalidateIntrinsicContentSize() } }
    var fontSize: CGFloat = 13 { didSet { invalidateIntrinsicContentSize() } }
    var maxTextWidth: CGFloat = 260
    var onClick: (() -> Void)?

    private var hovering = false
    private var trackingArea: NSTrackingArea?

    init(_ text: String, kind: Kind = .secondary, hint: String? = nil, symbol: String? = nil, onClick: (() -> Void)? = nil) {
        self.kind = kind
        self.text = text
        self.hint = hint
        self.symbolName = symbol
        self.onClick = onClick
        super.init(frame: .zero)
        super.title = text
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        action = #selector(clicked)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func clicked() {
        onClick?()
    }

    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var mouseDownCanMoveWindow: Bool { false }

    private var isIconOnly: Bool { text.isEmpty && symbolName != nil }

    private var labelFont: NSFont {
        switch kind {
        case .pill: return Lantor.font(fontSize - 0.5, .medium)
        case .ghost: return Lantor.font(fontSize, .medium)
        default: return Lantor.font(fontSize, .semibold)
        }
    }

    private var hintFont: NSFont { Lantor.font(fontSize - 1, .medium) }

    private var textWidth: CGFloat {
        min(ceil((text as NSString).size(withAttributes: [.font: labelFont]).width), maxTextWidth)
    }

    private var hintWidth: CGFloat {
        guard let hint, !hint.isEmpty else { return 0 }
        return ceil((hint as NSString).size(withAttributes: [.font: hintFont]).width)
    }

    override var intrinsicContentSize: NSSize {
        if isIconOnly { return NSSize(width: height, height: height) }
        var width = horizontalPadding * 2 + textWidth
        if symbolName != nil { width += symbolSize + 6 }
        if hintWidth > 0 { width += 7 + hintWidth }
        return NSSize(width: ceil(width), height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    private struct Palette {
        var fill: NSColor?
        var stroke: NSColor?
        var ink: NSColor
        var hintInk: NSColor
    }

    private var palette: Palette {
        let pressed = isHighlighted
        let hot = hovering && isEnabled
        switch kind {
        case .primary:
            return Palette(fill: pressed ? Lantor.accentPressed : Lantor.accent, stroke: nil, ink: Lantor.accentInk, hintInk: Lantor.accentInk.withAlphaComponent(0.72))
        case .secondary:
            return Palette(fill: pressed ? Lantor.recessed : (hot ? Lantor.hover : Lantor.control), stroke: Lantor.controlBorder, ink: Lantor.ink, hintInk: Lantor.muted)
        case .warning:
            return Palette(fill: Lantor.warningSoft, stroke: Lantor.warningBorder, ink: Lantor.warning, hintInk: Lantor.warning.withAlphaComponent(0.75))
        case .danger:
            return Palette(fill: pressed ? Lantor.recessed : (hot ? Lantor.dangerSoft : Lantor.control), stroke: Lantor.controlBorder, ink: Lantor.danger, hintInk: Lantor.muted)
        case .ghost:
            return Palette(fill: hot || pressed ? Lantor.lineStrong : Lantor.defaultFill, stroke: nil, ink: Lantor.muted, hintInk: Lantor.muted)
        case .pill:
            return Palette(fill: pressed ? Lantor.recessed : (hot ? Lantor.hover : Lantor.control), stroke: Lantor.controlBorder, ink: Lantor.inkSecondary, hintInk: Lantor.muted)
        case .accentSoft:
            return Palette(fill: hot || pressed ? Lantor.selectedFill : Lantor.accentSoft, stroke: Lantor.accentSoftBorder, ink: Lantor.accent, hintInk: Lantor.accent)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = palette
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let r = radius ?? (kind == .pill || isIconOnly && kind != .secondary ? rect.height / 2 : 10)
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        NSGraphicsContext.saveGraphicsState()
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
        if let fill = colors.fill {
            fill.setFill()
            path.fill()
        }
        if let stroke = colors.stroke {
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if isIconOnly, let symbolName, let image = Lantor.symbol(symbolName, size: symbolSize, weight: .semibold, color: colors.ink) {
            let size = image.size
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        var x = (bounds.width - intrinsicContentSize.width) / 2 + horizontalPadding
        if let symbolName, let image = Lantor.symbol(symbolName, size: symbolSize, weight: .semibold, color: kind == .pill ? Lantor.muted : colors.ink) {
            let size = image.size
            image.draw(in: NSRect(x: x + (symbolSize - size.width) / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            x += symbolSize + 6
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: colors.ink]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textRect = NSRect(x: x, y: bounds.midY - textSize.height / 2, width: textWidth, height: textSize.height)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs.merging([.paragraphStyle: paragraph]) { $1 })
        x += textWidth
        if let hint, !hint.isEmpty {
            let hintAttrs: [NSAttributedString.Key: Any] = [.font: hintFont, .foregroundColor: colors.hintInk]
            let hintSize = (hint as NSString).size(withAttributes: hintAttrs)
            (hint as NSString).draw(at: NSPoint(x: x + 7, y: bounds.midY - hintSize.height / 2), withAttributes: hintAttrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Chip

@MainActor
final class LantorChip: NSView {
    enum Tone {
        case success, thinking, neutral, warning, danger, accent
    }

    var tone: Tone { didSet { needsDisplay = true } }
    var text: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var showsDot: Bool { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var pulse = false { didSet { needsDisplay = true } }
    var symbolName: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var maxTextWidth: CGFloat = 220 { didSet { invalidateIntrinsicContentSize() } }
    var height: CGFloat = 22 { didSet { invalidateIntrinsicContentSize() } }

    init(_ text: String = "", tone: Tone = .neutral, dot: Bool = false, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.showsDot = dot
        self.symbolName = symbol
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var font: NSFont { Lantor.font(12, tone == .neutral ? .medium : .semibold) }

    private var colors: (fill: NSColor, ink: NSColor, stroke: NSColor?) {
        switch tone {
        case .success: return (Lantor.successSoft, Lantor.success, nil)
        case .thinking: return (Lantor.thinkingSoft, Lantor.thinkingInk, nil)
        case .neutral: return (Lantor.defaultFill, Lantor.muted, nil)
        case .warning: return (Lantor.warningSoft, Lantor.warning, Lantor.warningBorder)
        case .danger: return (Lantor.dangerSoft, Lantor.danger, nil)
        case .accent: return (Lantor.accentSoft, Lantor.accentSoftInk, Lantor.accentSoftBorder)
        }
    }

    private var textWidth: CGFloat {
        min(ceil((text as NSString).size(withAttributes: [.font: font]).width), maxTextWidth)
    }

    override var intrinsicContentSize: NSSize {
        var width = 18 + textWidth
        if showsDot { width += 12 }
        if symbolName != nil { width += 18 }
        return NSSize(width: ceil(width), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = colors
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        c.fill.setFill()
        path.fill()
        if let stroke = c.stroke {
            stroke.setStroke()
            path.stroke()
        }
        var x: CGFloat = 9
        if showsDot {
            if pulse {
                c.ink.withAlphaComponent(0.22).setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 3, y: bounds.midY - 6, width: 12, height: 12)).fill()
            }
            c.ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: bounds.midY - 3, width: 6, height: 6)).fill()
            x += 12
        }
        if let symbolName, let image = Lantor.symbol(symbolName, size: 11, weight: .semibold, color: c.ink) {
            let size = image.size
            image.draw(in: NSRect(x: x, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            x += 18
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c.ink]
        let size = (text as NSString).size(withAttributes: attrs)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            with: NSRect(x: x, y: bounds.midY - size.height / 2, width: textWidth, height: size.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attrs.merging([.paragraphStyle: paragraph]) { $1 }
        )
    }
}

// MARK: - Keycaps

/// Small inline key ("⌘C", "esc") or a large keycap for the shortcut card.
@MainActor
final class LantorKey: NSView {
    var text: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var large: Bool
    var highlighted = false { didSet { needsDisplay = true } }

    init(_ text: String, large: Bool = false) {
        self.text = text
        self.large = large
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var font: NSFont { large ? Lantor.font(18, .semibold) : Lantor.font(11, .semibold) }

    override var intrinsicContentSize: NSSize {
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return large
            ? NSSize(width: max(44, width + 20), height: 46)
            : NSSize(width: max(20, width + 10), height: 21)
    }

    override func draw(_ dirtyRect: NSRect) {
        let drop: CGFloat = large ? 2 : 1
        let radius: CGFloat = large ? 11 : 6
        let cap = NSRect(x: 0.5, y: drop + 0.5, width: bounds.width - 1, height: bounds.height - drop - 1)
        Lantor.lineStrong.setFill()
        NSBezierPath(roundedRect: cap.offsetBy(dx: 0, dy: -drop), xRadius: radius, yRadius: radius).fill()
        let path = NSBezierPath(roundedRect: cap, xRadius: radius, yRadius: radius)
        Lantor.kbd.setFill()
        path.fill()
        if highlighted {
            Lantor.accentSoft.setFill()
            path.fill()
        }
        (highlighted ? Lantor.accent : Lantor.controlBorder).setStroke()
        path.lineWidth = 1
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: large ? Lantor.ink : Lantor.inkSecondary]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: cap.midX - size.width / 2, y: cap.midY - size.height / 2), withAttributes: attrs)
    }
}

/// "⌘C Copy" style hint: a keycap followed by a muted label.
@MainActor
func lantorHint(_ key: String, _ text: String) -> NSStackView {
    let label = Lantor.label(text, Lantor.font(12), Lantor.muted)
    let stack = NSStackView(views: [LantorKey(key), label])
    stack.orientation = .horizontal
    stack.spacing = 5
    stack.alignment = .centerY
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

// MARK: - Icon tile

/// 30pt rounded tile holding an SF Symbol, used in toggle rows and choice cards.
@MainActor
final class LantorIconTile: NSView {
    var symbolName: String { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    var tileSize: CGFloat

    init(_ symbolName: String, size: CGFloat = 30) {
        self.symbolName = symbolName
        self.tileSize = size
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        (selected ? Lantor.accent : Lantor.defaultFill).setFill()
        path.fill()
        let color = selected ? Lantor.accentInk : Lantor.inkSecondary
        if let image = Lantor.symbol(symbolName, size: tileSize * 0.47, weight: .medium, color: color) {
            let size = image.size
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
        }
    }
}

// MARK: - App icon

@MainActor
final class LantorAppIcon: NSView {
    private let size: CGFloat

    init(size: CGFloat) {
        self.size = size
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        // macOS app icons carry transparent padding around the squircle; draw slightly oversized.
        let image = Lantor.appIcon
        let bleed = size * 0.1
        image.draw(in: bounds.insetBy(dx: -bleed, dy: -bleed), from: .zero, operation: .sourceOver, fraction: 1)
    }
}

// MARK: - Text field box

/// Lantor input: rounded field background that turns accent with a soft halo while editing.
@MainActor
final class LantorFieldBox: LantorSurface {
    let field: NSTextField
    private var observers: [NSObjectProtocol] = []

    init(_ field: NSTextField, height: CGFloat = 34, radius: CGFloat = 10, horizontalPadding: CGFloat = 12) {
        self.field = field
        super.init(fill: Lantor.input, stroke: Lantor.controlBorder, radius: radius)
        ringInset = 3
        draggable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = field.font ?? Lantor.font(13)
        field.textColor = Lantor.ink
        addSubview(field)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height + ringInset * 2),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ringInset + horizontalPadding),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(ringInset + horizontalPadding)),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }

    /// Focus follows the field editor, so the halo shows on click/tab before any typing.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let editing = self.field.currentEditor() != nil && self.window?.firstResponder === self.field.currentEditor()
                if self.focused != editing { self.focused = editing }
            }
        })
    }

    func setPlaceholder(_ text: String, size: CGFloat = 13) {
        field.placeholderAttributedString = NSAttributedString(string: text, attributes: [
            .foregroundColor: Lantor.placeholder, .font: field.font ?? Lantor.font(size),
        ])
    }
}

// MARK: - Pills inside text

/// Rounded pill drawn inline in an NSTextView (TextKit 1): POS badges and usage chips.
@MainActor
final class PillAttachmentCell: NSTextAttachmentCell {
    nonisolated private let text: String
    nonisolated(unsafe) private let pillFont: NSFont
    nonisolated private let ink: NSColor
    nonisolated private let fillColor: NSColor
    nonisolated private let strokeColor: NSColor?
    nonisolated private let horizontalPadding: CGFloat
    nonisolated private let pillHeight: CGFloat
    nonisolated private let cornerRadius: CGFloat?

    init(text: String, font: NSFont, ink: NSColor, fill: NSColor, stroke: NSColor? = nil, horizontalPadding: CGFloat = 9, height: CGFloat = 22, radius: CGFloat? = nil) {
        self.text = text
        self.pillFont = font
        self.ink = ink
        self.fillColor = fill
        self.strokeColor = stroke
        self.horizontalPadding = horizontalPadding
        self.pillHeight = height
        self.cornerRadius = radius
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func cellSize() -> NSSize {
        let width = ceil((text as NSString).size(withAttributes: [.font: pillFont]).width)
        return NSSize(width: width + horizontalPadding * 2, height: pillHeight)
    }

    override func cellBaselineOffset() -> NSPoint {
        // Center the pill on the surrounding text's x-height.
        NSPoint(x: 0, y: pillFont.descender - (pillHeight - (pillFont.ascender - pillFont.descender)) / 2)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        let r = cornerRadius ?? rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        fillColor.setFill()
        path.fill()
        if let strokeColor {
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: pillFont, .foregroundColor: ink]
        let size = (text as NSString).size(withAttributes: attrs)
        let flipped = controlView?.isFlipped ?? true
        let y = flipped ? cellFrame.midY - size.height / 2 : cellFrame.midY - size.height / 2
        (text as NSString).draw(at: NSPoint(x: cellFrame.minX + horizontalPadding, y: y), withAttributes: attrs)
    }

    static func attributedPill(_ text: String, font: NSFont, ink: NSColor, fill: NSColor, stroke: NSColor? = nil, horizontalPadding: CGFloat = 9, height: CGFloat = 22, radius: CGFloat? = nil) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = PillAttachmentCell(text: text, font: font, ink: ink, fill: fill, stroke: stroke, horizontalPadding: horizontalPadding, height: height, radius: radius)
        return NSAttributedString(attachment: attachment)
    }
}
