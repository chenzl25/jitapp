import Foundation

/// The Words (vocabulary) output split into the sections the palette renders as a card.
///
/// The parser accepts the format requested by the default Words prompt
/// (`Headword:`, `Part of speech:`, `IPA:`, `Meaning:`, `Usage:`, `Examples:`, `Notes:`)
/// and tolerates common model drift: numbering (`1) Headword:`), markdown bold,
/// Chinese labels, and inline lists. Partial text parses too, so the card can
/// fill in while the response streams.
public struct VocabularyCard: Equatable, Sendable {
    public struct Usage: Equatable, Sendable {
        public var phrase: String
        public var note: String?

        public init(phrase: String, note: String? = nil) {
            self.phrase = phrase
            self.note = note
        }
    }

    public struct Example: Equatable, Sendable {
        public var text: String
        public var translation: String?

        public init(text: String, translation: String? = nil) {
            self.text = text
            self.translation = translation
        }
    }

    public var headword: String
    public var partOfSpeech: String?
    public var pronunciation: String?
    public var meaning: String?
    public var usage: [Usage] = []
    public var examples: [Example] = []
    public var notes: String?

    public init(
        headword: String,
        partOfSpeech: String? = nil,
        pronunciation: String? = nil,
        meaning: String? = nil,
        usage: [Usage] = [],
        examples: [Example] = [],
        notes: String? = nil
    ) {
        self.headword = headword
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.usage = usage
        self.examples = examples
        self.notes = notes
    }

    enum Section {
        case headword, partOfSpeech, pronunciation, meaning, usage, examples, notes
    }

    private static let labels: [(Section, [String])] = [
        (.headword, ["headword", "word", "term", "单词", "词条"]),
        (.partOfSpeech, ["part of speech", "pos", "词性"]),
        (.pronunciation, ["pronunciation", "ipa", "phonetic", "phonetics", "发音", "音标"]),
        (.meaning, ["meaning", "definition", "meanings", "释义", "含义", "意思"]),
        (.usage, ["usage", "collocations", "collocation", "common usage", "用法", "搭配", "常见搭配"]),
        (.examples, ["examples", "example", "example sentences", "例句"]),
        (.notes, ["notes", "note", "tips", "备注", "注意", "提示"]),
    ]

    private static let headerPattern = try! NSRegularExpression(pattern: #"^([A-Za-z 一-鿿]{1,24}?)\s*[:：]\s*(.*)$"#)
    private static let bulletPattern = try! NSRegularExpression(pattern: #"^(?:[-*•·]|\d+[.)、])\s+(.*)$"#)
    private static let ipaPattern = try! NSRegularExpression(pattern: #"/[^/\n]{1,60}/|\[[^\]\n]{1,60}\]"#)
    private static let posInParens = try! NSRegularExpression(pattern: #"\(\s*([a-z]{1,6}\.?(?:\s*/\s*[a-z]{1,6}\.?)*)\s*\)"#, options: [.caseInsensitive])

    /// Returns nil when the text does not look like a Words card (no headword),
    /// so the caller can fall back to generic formatting.
    public static func parse(_ text: String) -> VocabularyCard? {
        var card = VocabularyCard(headword: "")
        var section: Section?
        var sawHeadword = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = clean(rawLine)
            if line.isEmpty { continue }

            if let (found, value) = header(in: line) {
                section = found
                if found == .headword { sawHeadword = true }
                if !value.isEmpty {
                    card.apply(value, to: found, inline: true)
                }
                continue
            }
            guard let section else { continue }
            let item = bulletValue(line) ?? line
            card.apply(item, to: section, inline: false)
        }

        card.normalize()
        // A headword alone is fine while streaming; it fills in as more arrives.
        guard sawHeadword, !card.headword.isEmpty else { return nil }
        return card
    }

    // MARK: Line helpers

    static func clean(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespaces)
        // Strip markdown headings and bold markers around labels.
        while value.hasPrefix("#") { value.removeFirst() }
        value = value.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        value = value.trimmingCharacters(in: .whitespaces)
        // "1) Headword: …" → "Headword: …" (only when a label follows).
        if let range = value.range(of: #"^\d+[.)、]\s*"#, options: .regularExpression) {
            let rest = String(value[range.upperBound...])
            if header(in: rest) != nil { value = rest }
        }
        return value
    }

    static func header(in line: String) -> (Section, String)? {
        let ns = line as NSString
        guard let match = headerPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let label = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
        let value = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        for (section, names) in labels where names.contains(label) {
            return (section, value)
        }
        return nil
    }

    static func bulletValue(_ line: String) -> String? {
        let ns = line as NSString
        guard let match = bulletPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// Mostly-CJK lines are translations of the example above them.
    static func isMostlyCJK(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let cjk = letters.filter { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
        return Double(cjk.count) / Double(letters.count) > 0.5
    }

    static func firstMatch(_ regex: NSRegularExpression, in text: String) -> (String, NSRange)? {
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (ns.substring(with: match.range), match.range)
    }

    // MARK: Section filling

    private mutating func apply(_ value: String, to section: Section, inline: Bool) {
        switch section {
        case .headword:
            if headword.isEmpty {
                setHeadword(value)
            }
        case .partOfSpeech:
            partOfSpeech = Self.join(partOfSpeech, value, separator: " ")
        case .pronunciation:
            pronunciation = Self.join(pronunciation, value, separator: " ")
        case .meaning:
            meaning = Self.join(meaning, value, separator: "\n")
        case .usage:
            let items = inline ? Self.splitInlineList(value) : [value]
            for item in items where !item.isEmpty {
                usage.append(Self.usage(from: item))
            }
        case .examples:
            addExample(value)
        case .notes:
            notes = Self.join(notes, value, separator: "\n")
        }
    }

    private mutating func setHeadword(_ value: String) {
        var word = value
        if let (ipa, range) = Self.firstMatch(Self.ipaPattern, in: word) {
            if pronunciation == nil { pronunciation = ipa }
            word = (word as NSString).replacingCharacters(in: range, with: "")
        }
        let ns = word as NSString
        if let match = Self.posInParens.firstMatch(in: word, range: NSRange(location: 0, length: ns.length)) {
            if partOfSpeech == nil { partOfSpeech = ns.substring(with: match.range(at: 1)) }
            word = ns.replacingCharacters(in: match.range, with: "")
        }
        headword = word.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-—–·,，")))
    }

    private mutating func addExample(_ value: String) {
        for separator in [" | ", "｜", " || ", "|"] where value.contains(separator) {
            let parts = value.components(separatedBy: separator)
            let text = parts[0].trimmingCharacters(in: .whitespaces)
            let translation = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            examples.append(Example(text: text, translation: translation.isEmpty ? nil : translation))
            return
        }
        if Self.isMostlyCJK(value), let last = examples.indices.last, examples[last].translation == nil {
            examples[last].translation = value
            return
        }
        examples.append(Example(text: value))
    }

    private mutating func normalize() {
        if let ipa = pronunciation, let (slashed, _) = Self.firstMatch(Self.ipaPattern, in: ipa) {
            pronunciation = slashed
        }
        if let pos = partOfSpeech {
            let trimmed = pos.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".()")))
            partOfSpeech = trimmed.isEmpty ? nil : trimmed
        }
        for key in [\VocabularyCard.meaning, \VocabularyCard.notes, \VocabularyCard.pronunciation] {
            if let value = self[keyPath: key]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty {
                self[keyPath: key] = nil
            }
        }
    }

    private static func join(_ current: String?, _ value: String, separator: String) -> String {
        guard let current, !current.isEmpty else { return value }
        return current + separator + value
    }

    private static func splitInlineList(_ value: String) -> [String] {
        let parts = value.components(separatedBy: CharacterSet(charactersIn: ";；"))
        let list = parts.count > 1 ? parts : value.components(separatedBy: CharacterSet(charactersIn: ",，"))
        return list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// "ephemeral storage — 临时存储" → phrase + note.
    private static func usage(from item: String) -> Usage {
        for separator in [" — ", " – ", " - ", "：", ": ", "（"] {
            guard let range = item.range(of: separator) else { continue }
            let phrase = item[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            var note = item[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if separator == "（", note.hasSuffix("）") { note.removeLast() }
            if !phrase.isEmpty, !note.isEmpty {
                return Usage(phrase: phrase, note: note)
            }
        }
        return Usage(phrase: item)
    }
}
