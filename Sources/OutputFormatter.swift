import AppKit
import JitText

/// Renders the model's plain-text / light-markdown output as Lantor-styled attributed text:
/// "Label: value" sections, bullets, `**bold**`, `code`, /IPA/ runs, and the Words card.
@MainActor
enum OutputFormatter {
    @MainActor
    struct Style {
        var body: NSFont = Lantor.font(15)
        var ink: NSColor = Lantor.ink
        var secondaryInk: NSColor = Lantor.inkSecondary
        var muted: NSColor = Lantor.muted
        var accent: NSColor = Lantor.accent
    }

    private static let sectionPattern = try! NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s*\**([^:：*]{1,40}?)\**\s*[:：]\s*(.*)$"#)
    private static let numberedPattern = try! NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s+(.*)$"#)
    private static let bulletPattern = try! NSRegularExpression(pattern: #"^\s*[-*•]\s+(.*)$"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^\s*#{1,6}\s+(.*)$"#)
    private static let inlinePattern = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|`([^`\n]+)`|(?<![\w:])/([^/\n]{1,60})/(?![\w/])"#)

    private static func paragraph(spacingBefore: CGFloat = 0, lineSpacing: CGFloat = 4, after: CGFloat = 4) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = after
        style.paragraphSpacingBefore = spacingBefore
        return style
    }

    // MARK: Generic output

    static func attributedString(from text: String, style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            result.append(renderLine(line, isFirst: index == 0, style: style))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: style.body]))
            }
        }
        return result
    }

    private static func sectionLabel(_ text: String, spacingBefore: CGFloat, style: Style) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: Lantor.font(11, .bold),
            .foregroundColor: style.muted,
            .kern: 0.3,
            .paragraphStyle: paragraph(spacingBefore: spacingBefore, lineSpacing: 0, after: 3),
        ])
    }

    private static func renderLine(_ line: String, isFirst: Bool, style: Style) -> NSAttributedString {
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)
        let body = paragraph()

        if let match = sectionPattern.firstMatch(in: line, range: full) {
            let label = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let value = nsLine.substring(with: match.range(at: 3))
            guard label.split(separator: " ").count <= 3, label.count <= 24 else {
                return renderNumbered(line, style: style)
            }
            let out = NSMutableAttributedString(attributedString: sectionLabel(label, spacingBefore: isFirst ? 0 : 10, style: style))
            if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(NSAttributedString(string: "\n", attributes: [.font: style.body]))
                out.append(inline(value, font: style.body, color: style.ink, paragraph: body, style: style))
            }
            return out
        }
        if let match = headingPattern.firstMatch(in: line, range: full) {
            let value = nsLine.substring(with: match.range(at: 1))
            return inline(value, font: Lantor.font(style.body.pointSize + 1, .semibold), color: style.ink, paragraph: paragraph(spacingBefore: isFirst ? 0 : 8), style: style)
        }
        if let match = bulletPattern.firstMatch(in: line, range: full) {
            let value = nsLine.substring(with: match.range(at: 1))
            let bullet = paragraph(lineSpacing: 3, after: 3)
            bullet.firstLineHeadIndent = 2
            bullet.headIndent = 18
            bullet.tabStops = [NSTextTab(textAlignment: .left, location: 18)]
            let out = NSMutableAttributedString(string: "•\t", attributes: [
                .font: style.body, .foregroundColor: style.muted, .paragraphStyle: bullet,
            ])
            out.append(inline(value, font: style.body, color: style.ink, paragraph: bullet, style: style))
            return out
        }
        if numberedPattern.firstMatch(in: line, range: full) != nil {
            return renderNumbered(line, style: style)
        }
        return inline(line, font: style.body, color: style.ink, paragraph: body, style: style)
    }

    private static func renderNumbered(_ line: String, style: Style) -> NSAttributedString {
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)
        let numbered = paragraph(spacingBefore: 2, lineSpacing: 3, after: 3)
        if let match = numberedPattern.firstMatch(in: line, range: full) {
            let number = nsLine.substring(with: match.range(at: 1))
            let value = nsLine.substring(with: match.range(at: 2))
            numbered.firstLineHeadIndent = 0
            numbered.headIndent = 22
            numbered.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
            let out = NSMutableAttributedString(string: "\(number).\t", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: style.body.pointSize - 1, weight: .semibold),
                .foregroundColor: style.muted, .paragraphStyle: numbered,
            ])
            out.append(inline(value, font: style.body, color: style.ink, paragraph: numbered, style: style))
            return out
        }
        return inline(line, font: style.body, color: style.ink, paragraph: numbered, style: style)
    }

    private static func inline(_ text: String, font: NSFont, color: NSColor, paragraph: NSParagraphStyle, style: Style) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let out = NSMutableAttributedString()
        let nsText = text as NSString
        var cursor = 0
        for match in inlinePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            if match.range.location > cursor {
                out.append(NSAttributedString(string: nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), attributes: base))
            }
            if match.range(at: 1).location != NSNotFound {
                var attrs = base
                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                out.append(NSAttributedString(string: nsText.substring(with: match.range(at: 1)), attributes: attrs))
            } else if match.range(at: 2).location != NSNotFound {
                var attrs = base
                attrs[.font] = Lantor.mono(font.pointSize - 1.5)
                attrs[.backgroundColor] = Lantor.defaultFill
                out.append(NSAttributedString(string: nsText.substring(with: match.range(at: 2)), attributes: attrs))
            } else if match.range(at: 3).location != NSNotFound {
                var attrs = base
                attrs[.font] = Lantor.mono(font.pointSize - 1)
                attrs[.foregroundColor] = style.muted
                out.append(NSAttributedString(string: "/" + nsText.substring(with: match.range(at: 3)) + "/", attributes: attrs))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            out.append(NSAttributedString(string: nsText.substring(from: cursor), attributes: base))
        }
        return out
    }

    // MARK: Words card

    /// Headword + POS badge + IPA, then Meaning / Usage chips / Examples / Notes sections.
    static func vocabularyCard(_ card: VocabularyCard, style: Style) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let headParagraph = paragraph(lineSpacing: 2, after: 2)
        // Leave room for the speak button drawn in the card's top-right corner.
        headParagraph.tailIndent = -40
        out.append(NSAttributedString(string: card.headword, attributes: [
            .font: Lantor.font(22, .bold), .foregroundColor: style.ink, .paragraphStyle: headParagraph, .kern: -0.2,
        ]))
        let spacer = NSAttributedString(string: "  ", attributes: [.font: Lantor.font(15), .paragraphStyle: headParagraph])
        if let pos = card.partOfSpeech {
            out.append(spacer)
            out.append(PillAttachmentCell.attributedPill(
                pos.uppercased(), font: Lantor.font(11, .bold), ink: Lantor.fileInk, fill: Lantor.fileSoft,
                horizontalPadding: 7, height: 20, radius: 6
            ))
        }
        if let ipa = card.pronunciation {
            out.append(spacer)
            out.append(NSAttributedString(string: ipa, attributes: [
                .font: Lantor.mono(13), .foregroundColor: style.muted, .paragraphStyle: headParagraph,
            ]))
        }

        let bodyFont = Lantor.font(14)
        func section(_ title: String) {
            out.append(NSAttributedString(string: "\n"))
            out.append(sectionLabel(title, spacingBefore: 10, style: style))
            out.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        }

        if let meaning = card.meaning {
            section("Meaning")
            out.append(inline(meaning, font: bodyFont, color: style.ink, paragraph: paragraph(lineSpacing: 3, after: 2), style: style))
        }
        if !card.usage.isEmpty {
            section("Usage")
            let chipParagraph = paragraph(lineSpacing: 7, after: 4)
            let hasNotes = card.usage.contains { $0.note != nil }
            for (index, item) in card.usage.enumerated() {
                out.append(PillAttachmentCell.attributedPill(
                    item.phrase, font: Lantor.font(12.5, .medium), ink: Lantor.accentSoftInk,
                    fill: Lantor.accentSoft, stroke: Lantor.accentSoftBorder, horizontalPadding: 9, height: 23
                ))
                if let note = item.note {
                    out.append(NSAttributedString(string: "  " + note, attributes: [
                        .font: Lantor.font(13), .foregroundColor: style.muted, .paragraphStyle: chipParagraph,
                    ]))
                }
                if index < card.usage.count - 1 {
                    out.append(NSAttributedString(string: hasNotes ? "\n" : "  ", attributes: [.font: bodyFont, .paragraphStyle: chipParagraph]))
                }
            }
            out.addAttribute(.paragraphStyle, value: chipParagraph, range: NSRange(location: out.length - 1, length: 1))
        }
        if !card.examples.isEmpty {
            section("Examples")
            for (index, example) in card.examples.enumerated() {
                let last = index == card.examples.count - 1
                let textParagraph = paragraph(lineSpacing: 2, after: example.translation == nil && !last ? 6 : 1)
                out.append(inline(example.text, font: bodyFont, color: style.ink, paragraph: textParagraph, style: style))
                if let translation = example.translation {
                    out.append(NSAttributedString(string: "\n"))
                    out.append(NSAttributedString(string: translation, attributes: [
                        .font: Lantor.font(13), .foregroundColor: style.muted, .paragraphStyle: paragraph(lineSpacing: 2, after: last ? 0 : 7),
                    ]))
                }
                if !last { out.append(NSAttributedString(string: "\n")) }
            }
        }
        if let notes = card.notes {
            section("Notes")
            out.append(inline(notes, font: Lantor.font(13.5), color: style.secondaryInk, paragraph: paragraph(lineSpacing: 3), style: style))
        }
        return out
    }

    /// Accent block appended while a response streams.
    static func caret() -> NSAttributedString {
        PillAttachmentCell.attributedPill("", font: Lantor.font(15), ink: .clear, fill: Lantor.accent, horizontalPadding: 3.5, height: 16, radius: 2)
    }
}
