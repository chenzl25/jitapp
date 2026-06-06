import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement

final class BubblePanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class DraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    static func jitDynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: alpha)
        }
    }
}

@MainActor
private enum LantorVisual {
    static let surface = NSColor.jitDynamic(light: 0xfbfcfd, dark: 0x374151)
    static let panel = NSColor.jitDynamic(light: 0xf4f6f9, dark: 0x303844)
    static let panelStrong = NSColor.jitDynamic(light: 0xf7f8fa, dark: 0x3d4858)
    static let input = NSColor.jitDynamic(light: 0xfbfcfd, dark: 0x2a3340)
    static let control = NSColor.jitDynamic(light: 0xedf1f5, dark: 0x404b5c)
    static let ink = NSColor.jitDynamic(light: 0x20242b, dark: 0xf4f6fa)
    static let secondaryInk = NSColor.jitDynamic(light: 0x4f5661, dark: 0xdde3ec)
    static let mutedInk = NSColor.jitDynamic(light: 0x68717d, dark: 0xb3bdcc)
    static let border = NSColor.jitDynamic(light: 0x20242c, dark: 0xe2e8f0, alpha: 0.16)
    static let borderSubtle = NSColor.jitDynamic(light: 0x20242c, dark: 0xe2e8f0, alpha: 0.10)
    static let accent = NSColor.jitDynamic(light: 0x0a84ff, dark: 0x69aafc)
    static let accentInk = NSColor.jitDynamic(light: 0xffffff, dark: 0x07111f)
    static let accentSoft = NSColor.jitDynamic(light: 0x0a84ff, dark: 0x69aafc, alpha: 0.12)
    static let accentSoftBorder = NSColor.jitDynamic(light: 0x0a84ff, dark: 0x69aafc, alpha: 0.30)
    static let thinkingSoft = NSColor.jitDynamic(light: 0x5ac8fa, dark: 0x5ac8fa, alpha: 0.16)
    static let thinkingInk = NSColor.jitDynamic(light: 0x0071a8, dark: 0x7dd3fc)
    static let successSoft = NSColor.jitDynamic(light: 0x34c759, dark: 0x34c759, alpha: 0.15)
    static let successInk = NSColor.jitDynamic(light: 0x167d32, dark: 0x67d084)
    static let warningSoft = NSColor.jitDynamic(light: 0xff9f0a, dark: 0xffb142, alpha: 0.17)
    static let warningInk = NSColor.jitDynamic(light: 0x9a5a00, dark: 0xffc166)
    static let errorSoft = NSColor.jitDynamic(light: 0xff453a, dark: 0xff453a, alpha: 0.14)
    static let errorInk = NSColor.jitDynamic(light: 0xc91810, dark: 0xffb4ab)
}

struct FeatureConfig: Codable {
    var id: String
    var displayName: String
    var hotkeyKey: String
    var hotkeyOption: Bool
    var hotkeyCommand: Bool
    var hotkeyControl: Bool
    var hotkeyShift: Bool
    var promptTemplate: String
    var enabled: Bool
    var supportsReplace: Bool
    var requiresInstruction: Bool

    enum CodingKeys: String, CodingKey {
        case id, displayName, hotkeyKey, hotkeyOption, hotkeyCommand, hotkeyControl, hotkeyShift, promptTemplate, enabled, supportsReplace, requiresInstruction
    }

    init(
        id: String,
        displayName: String,
        hotkeyKey: String,
        hotkeyOption: Bool,
        hotkeyCommand: Bool,
        hotkeyControl: Bool,
        hotkeyShift: Bool,
        promptTemplate: String,
        enabled: Bool,
        supportsReplace: Bool,
        requiresInstruction: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.hotkeyKey = hotkeyKey
        self.hotkeyOption = hotkeyOption
        self.hotkeyCommand = hotkeyCommand
        self.hotkeyControl = hotkeyControl
        self.hotkeyShift = hotkeyShift
        self.promptTemplate = promptTemplate
        self.enabled = enabled
        self.supportsReplace = supportsReplace
        self.requiresInstruction = requiresInstruction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        hotkeyKey = try container.decode(String.self, forKey: .hotkeyKey)
        hotkeyOption = try container.decode(Bool.self, forKey: .hotkeyOption)
        hotkeyCommand = try container.decode(Bool.self, forKey: .hotkeyCommand)
        hotkeyControl = try container.decode(Bool.self, forKey: .hotkeyControl)
        hotkeyShift = try container.decode(Bool.self, forKey: .hotkeyShift)
        promptTemplate = try container.decode(String.self, forKey: .promptTemplate)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        supportsReplace = try container.decodeIfPresent(Bool.self, forKey: .supportsReplace) ?? false
        requiresInstruction = try container.decodeIfPresent(Bool.self, forKey: .requiresInstruction) ?? false
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if hotkeyOption { flags.insert(.option) }
        if hotkeyCommand { flags.insert(.command) }
        if hotkeyControl { flags.insert(.control) }
        if hotkeyShift { flags.insert(.shift) }
        return flags
    }
}

struct AppConfig {
    var baseURL: String
    var apiKey: String
    var model: String
    var targetLanguage: String
    var features: [FeatureConfig]

    static let defaultTranslationPromptTemplate = """
    Translate the text into {{targetLanguage}} with fast response.

    Output format (plain text):
    1) Translation: give the full direct translation first.
    2) Useful English words/phrases (English only): list 3-6 useful English words/phrases from the original text, each with:
       - brief English meaning
       - one common English collocation/usage
       - one short English example sentence

    Do NOT include phonetics/IPA, long grammar analysis, or long examples.
    Keep it practical and concise.

    Text:
    {{text}}
    """

    static let defaultRefinePromptTemplate = """
    Improve the following text to be grammatically correct, natural, and fluent.

    Output format (plain text):
    1) Improved text
    2) Key improvements: 2-5 concise bullet points in Chinese

    Text:
    {{text}}
    """

    static let defaultCustomPromptTemplate = """
    You are a text assistant. Apply the user's instruction to the selected text.

    User instruction:
    {{instruction}}

    Selected text:
    {{text}}

    Return only the final processed text, no explanation.
    """

    static let defaultVocabularyPromptTemplate = """
    You are an English vocabulary coach. Help the user learn the selected English word, phrase, or sentence.

    Output format (plain text):
    1) Headword: the main English word or phrase to learn.
    2) Pronunciation: give IPA if confident, plus a simple pronunciation hint.
    3) Meaning: explain the meaning in Chinese, with the core English sense.
    4) Usage: list 2-4 common collocations or sentence patterns.
    5) Examples: give 2 short English example sentences, each followed by a Chinese translation.
    6) Notes: mention common mistakes, register, or similar words only if useful.

    Keep it concise, practical, and focused on learning the word.

    Text:
    {{text}}
    """

    static let defaults = AppConfig(
        baseURL: "https://api.deepseek.com/v1",
        apiKey: "",
        model: "deepseek-chat",
        targetLanguage: "Chinese",
        features: [
            FeatureConfig(
                id: "translate",
                displayName: "Translate",
                hotkeyKey: "D",
                hotkeyOption: true,
                hotkeyCommand: false,
                hotkeyControl: false,
                hotkeyShift: false,
                promptTemplate: AppConfig.defaultTranslationPromptTemplate,
                enabled: true,
                supportsReplace: false,
                requiresInstruction: false
            ),
            FeatureConfig(
                id: "refine",
                displayName: "Refine",
                hotkeyKey: "S",
                hotkeyOption: true,
                hotkeyCommand: false,
                hotkeyControl: false,
                hotkeyShift: false,
                promptTemplate: AppConfig.defaultRefinePromptTemplate,
                enabled: true,
                supportsReplace: true,
                requiresInstruction: false
            ),
            FeatureConfig(
                id: "custom",
                displayName: "Custom",
                hotkeyKey: "A",
                hotkeyOption: true,
                hotkeyCommand: false,
                hotkeyControl: false,
                hotkeyShift: false,
                promptTemplate: AppConfig.defaultCustomPromptTemplate,
                enabled: true,
                supportsReplace: true,
                requiresInstruction: true
            ),
            FeatureConfig(
                id: "vocabulary",
                displayName: "Vocabulary",
                hotkeyKey: "V",
                hotkeyOption: true,
                hotkeyCommand: false,
                hotkeyControl: false,
                hotkeyShift: false,
                promptTemplate: AppConfig.defaultVocabularyPromptTemplate,
                enabled: true,
                supportsReplace: false,
                requiresInstruction: false
            )
        ]
    )

    static func defaultPromptTemplate(for featureID: String) -> String {
        switch featureID {
        case "translate":
            return defaultTranslationPromptTemplate
        case "refine":
            return defaultRefinePromptTemplate
        case "custom":
            return defaultCustomPromptTemplate
        case "vocabulary":
            return defaultVocabularyPromptTemplate
        default:
            return defaultTranslationPromptTemplate
        }
    }

    static func normalizedFeature(_ feature: FeatureConfig) -> FeatureConfig {
        var item = feature
        switch item.id {
        case "translate": item.displayName = "Translate"
        case "refine": item.displayName = "Refine"
        case "custom": item.displayName = "Custom"
        case "vocabulary": item.displayName = "Vocabulary"
        default: break
        }
        if item.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.promptTemplate = defaultPromptTemplate(for: item.id)
        }
        return item
    }

    static func mergedFeatures(with savedFeatures: [FeatureConfig]) -> [FeatureConfig] {
        var savedByID: [String: FeatureConfig] = [:]
        for feature in savedFeatures {
            savedByID[feature.id] = normalizedFeature(feature)
        }
        var result = defaults.features.map { defaultFeature -> FeatureConfig in
            savedByID.removeValue(forKey: defaultFeature.id) ?? defaultFeature
        }
        result.append(contentsOf: savedByID.values)
        return result
    }

    static func load() -> AppConfig {
        let d = UserDefaults.standard
        var config = AppConfig.defaults
        if let value = d.string(forKey: "baseURL")?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { config.baseURL = value }
        if let value = d.string(forKey: "apiKey") { config.apiKey = value }
        if let value = d.string(forKey: "model")?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { config.model = value }
        if let value = d.string(forKey: "targetLanguage")?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { config.targetLanguage = value }
        if let featuresData = d.data(forKey: "featureConfigs"),
           let decoded = try? JSONDecoder().decode([FeatureConfig].self, from: featuresData),
           !decoded.isEmpty {
            config.features = AppConfig.mergedFeatures(with: decoded)
        } else {
            // Backward compatibility: migrate old single-hotkey settings to translate feature.
            if let value = d.string(forKey: "hotkeyKey"),
               let idx = config.features.firstIndex(where: { $0.id == "translate" }) {
                config.features[idx].hotkeyKey = value
            }
            if d.object(forKey: "hotkeyOption") != nil,
               let idx = config.features.firstIndex(where: { $0.id == "translate" }) {
                config.features[idx].hotkeyOption = d.bool(forKey: "hotkeyOption")
            }
            if d.object(forKey: "hotkeyCommand") != nil,
               let idx = config.features.firstIndex(where: { $0.id == "translate" }) {
                config.features[idx].hotkeyCommand = d.bool(forKey: "hotkeyCommand")
            }
            if d.object(forKey: "hotkeyControl") != nil,
               let idx = config.features.firstIndex(where: { $0.id == "translate" }) {
                config.features[idx].hotkeyControl = d.bool(forKey: "hotkeyControl")
            }
            if d.object(forKey: "hotkeyShift") != nil,
               let idx = config.features.firstIndex(where: { $0.id == "translate" }) {
                config.features[idx].hotkeyShift = d.bool(forKey: "hotkeyShift")
            }
            if let value = d.string(forKey: "translationPromptTemplate"),
               !value.isEmpty,
               let idx = config.features.firstIndex(where: { $0.id == "translate" }) {
                config.features[idx].promptTemplate = value
            }
        }
        return config
    }

    var hasRequiredConnectionSettings: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: "baseURL")
        d.set(apiKey, forKey: "apiKey")
        d.set(model, forKey: "model")
        d.set(targetLanguage, forKey: "targetLanguage")
        if let data = try? JSONEncoder().encode(features) {
            d.set(data, forKey: "featureConfigs")
        }
    }

    func resolvedPrompt(for feature: FeatureConfig, text: String, instruction: String? = nil) -> String {
        let template = feature.promptTemplate.isEmpty ? AppConfig.defaultPromptTemplate(for: feature.id) : feature.promptTemplate
        return template
            .replacingOccurrences(of: "{{targetLanguage}}", with: targetLanguage)
            .replacingOccurrences(of: "{{instruction}}", with: instruction ?? "")
            .replacingOccurrences(of: "{{text}}", with: text)
    }
}

@MainActor
final class KeyCodeMapper {
    static let shared = KeyCodeMapper()

    private let keyToCode: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C), "D": UInt32(kVK_ANSI_D),
        "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F), "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H),
        "I": UInt32(kVK_ANSI_I), "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O), "P": UInt32(kVK_ANSI_P),
        "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R), "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T),
        "U": UInt32(kVK_ANSI_U), "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9)
    ]
    private lazy var codeToKey: [UInt32: String] = {
        var map: [UInt32: String] = [:]
        for (key, code) in keyToCode {
            map[code] = key
        }
        return map
    }()

    func keyCode(for key: String) -> UInt32? {
        keyToCode[key.uppercased()]
    }

    func key(for keyCode: UInt32) -> String? {
        codeToKey[keyCode]
    }
}

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    struct Registration {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: NSEvent.ModifierFlags
        let action: () -> Void
    }

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    func registerAll(_ registrations: [Registration]) -> Bool {
        unregister()
        actions.removeAll()
        for item in registrations {
            actions[item.id] = item.action
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr, let action = manager.actions[hotKeyID.id] {
                    action()
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if handlerStatus != noErr {
            return false
        }

        for item in registrations {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x46594E59), id: item.id) // FYNY
            let carbonModifiers = carbonFlags(from: item.modifiers)
            let registerStatus = RegisterEventHotKey(
                item.keyCode,
                carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            if registerStatus != noErr || ref == nil {
                unregister()
                return false
            }
            hotKeyRefs[item.id] = ref
        }
        return true
    }

    func unregister() {
        for (_, hotKeyRef) in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        actions.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func carbonFlags(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        let itemMaps: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary<NSPasteboard.PasteboardType, Data>(uniqueKeysWithValues: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        }
        return PasteboardSnapshot(items: itemMaps)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for itemMap in items {
            let item = NSPasteboardItem()
            for (type, data) in itemMap {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}

@MainActor
final class SelectionCaptureService {
    func captureSelectedText(completion: @escaping @MainActor (String?) -> Void) {
        // Wait a moment for global hotkey modifiers (e.g. Option) to be released,
        // otherwise some editors may treat simulated Cmd+C as a different shortcut.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let axText = self.readSelectedTextUsingAccessibility() {
                completion(axText)
                return
            }

            let snapshot = PasteboardSnapshot.capture()
            let pasteboard = NSPasteboard.general
            let oldCount = pasteboard.changeCount
            self.attemptCopyAndRead(snapshot: snapshot, oldCount: oldCount, retries: 2, completion: completion)
        }
    }

    private func attemptCopyAndRead(
        snapshot: PasteboardSnapshot,
        oldCount: Int,
        retries: Int,
        completion: @escaping @MainActor (String?) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        simulateCopyShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            if pasteboard.changeCount != oldCount {
                let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
                snapshot.restore()
                completion(text?.isEmpty == false ? text : nil)
                return
            }

            if retries > 0 {
                self.attemptCopyAndRead(snapshot: snapshot, oldCount: oldCount, retries: retries - 1, completion: completion)
                return
            }

            snapshot.restore()
            completion(nil)
        }
    }

    private func simulateCopyShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let cKey: CGKeyCode = 8

        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    private func readSelectedTextUsingAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedStatus == .success, let focusedRef else { return nil }

        let focusedElement = focusedRef as! AXUIElement
        if let selected = readDirectSelectedText(from: focusedElement) {
            return selected
        }
        if let selected = readSelectedTextByRange(from: focusedElement) {
            return selected
        }
        if let selected = readSelectedTextByRanges(from: focusedElement) {
            return selected
        }
        return nil
    }

    private func readDirectSelectedText(from element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        guard selectedStatus == .success, let selectedText = selectedRef as? String else {
            return nil
        }
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readSelectedTextByRange(from element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeStatus == .success, let rangeRef else { return nil }
        return readTextByRangeValue(rangeRef, from: element)
    }

    private func readSelectedTextByRanges(from element: AXUIElement) -> String? {
        var rangesRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangesAttribute as CFString,
            &rangesRef
        )
        guard status == .success, let ranges = rangesRef as? [Any], let first = ranges.first else {
            return nil
        }
        return readTextByRangeValue(first as CFTypeRef, from: element)
    }

    private func readTextByRangeValue(_ valueRef: CFTypeRef, from element: AXUIElement) -> String? {
        guard CFGetTypeID(valueRef) == AXValueGetTypeID() else { return nil }
        let axValue = valueRef as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var cfRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &cfRange) else { return nil }

        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )
        guard valueStatus == .success, let fullText = valueRef as? String else { return nil }

        let nsText = fullText as NSString
        let location = cfRange.location
        let length = cfRange.length
        guard location >= 0, length > 0, location + length <= nsText.length else { return nil }
        let selected = nsText.substring(with: NSRange(location: location, length: length))
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func replaceSelectedText(with newText: String, targetApp: NSRunningApplication?) {
        let snapshot = PasteboardSnapshot.capture()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)

        targetApp?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.simulatePasteShortcut()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                snapshot.restore()
            }
        }
    }

    private func simulatePasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKey: CGKeyCode = 9

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}

struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool?
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
            enum CodingKeys: String, CodingKey {
                case content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                if let stringContent = try? container.decode(String.self, forKey: .content) {
                    content = stringContent
                    return
                }

                if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                    content = parts.map { $0.text }.joined(separator: "\n")
                    return
                }

                content = ""
            }

            struct ContentPart: Decodable {
                let text: String
            }
        }

        let message: Message
    }

    let choices: [Choice]
}

struct ChatStreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String

            enum CodingKeys: String, CodingKey {
                case content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                if let stringContent = try? container.decode(String.self, forKey: .content) {
                    content = stringContent
                    return
                }

                if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                    content = parts.map { $0.text }.joined(separator: "\n")
                    return
                }

                content = ""
            }

            struct ContentPart: Decodable {
                let text: String
            }
        }

        let delta: Delta?
    }

    let choices: [Choice]
}

final class TextProcessingRun {
    private let cancelHandler: @Sendable () -> Void
    private let retainedObjects: [Any]

    init(cancelHandler: @escaping @Sendable () -> Void, retaining retainedObjects: [Any] = []) {
        self.cancelHandler = cancelHandler
        self.retainedObjects = retainedObjects
    }

    func cancel() {
        cancelHandler()
    }
}

final class StreamingChatDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onPartial: @Sendable (String) -> Void
    private let completion: @Sendable (Result<String, Error>) -> Void
    private var lineBuffer = ""
    private var responseBody = ""
    private var output = ""
    private var statusCode = 0
    private var didComplete = false

    init(
        onPartial: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        self.onPartial = onPartial
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard (200..<300).contains(statusCode) else {
            if responseBody.count < 16_000 {
                responseBody += String(data: data, encoding: .utf8) ?? ""
            }
            return
        }

        lineBuffer += String(data: data, encoding: .utf8) ?? ""
        processBufferedLines()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didComplete else { return }
        didComplete = true
        defer { session.finishTasksAndInvalidate() }

        if let error {
            completion(.failure(error))
            return
        }

        if !(200..<300).contains(statusCode) {
            completion(.failure(NSError(domain: "Translator", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed (\(statusCode)): \(responseBody)"])))
            return
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            completion(.failure(NSError(domain: "Translator", code: 502, userInfo: [NSLocalizedDescriptionKey: "Model returned empty content."])))
        } else {
            completion(.success(trimmed))
        }
    }

    private func processBufferedLines() {
        while let newline = lineBuffer.firstIndex(where: { $0 == "\n" }) {
            let line = String(lineBuffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            lineBuffer.removeSubrange(...newline)
            handle(line: line)
        }
    }

    private func handle(line: String) {
        guard line.hasPrefix("data:") else { return }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" { return }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatStreamResponse.self, from: data) else { return }
        let delta = chunk.choices.compactMap { $0.delta?.content }.joined()
        guard !delta.isEmpty else { return }
        output += delta
        onPartial(delta)
    }
}

final class TranslationService {
    func process(
        text: String,
        config: AppConfig,
        feature: FeatureConfig,
        instruction: String? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        do {
            let request = try makeRequest(text: text, config: config, feature: feature, instruction: instruction, stream: nil)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(NSError(domain: "Translator", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid service response."])))
                    return
                }

                guard let data else {
                    completion(.failure(NSError(domain: "Translator", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Empty response."])))
                    return
                }

                guard (200..<300).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    completion(.failure(NSError(domain: "Translator", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed (\(http.statusCode)): \(body)"])))
                    return
                }

                do {
                    let result = try JSONDecoder().decode(ChatResponse.self, from: data)
                    let translated = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if translated.isEmpty {
                        completion(.failure(NSError(domain: "Translator", code: 502, userInfo: [NSLocalizedDescriptionKey: "Model returned empty content."])))
                    } else {
                        completion(.success(translated))
                    }
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    func processStreaming(
        text: String,
        config: AppConfig,
        feature: FeatureConfig,
        instruction: String? = nil,
        onPartial: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) -> TextProcessingRun {
        do {
            let request = try makeRequest(text: text, config: config, feature: feature, instruction: instruction, stream: true)
            let delegate = StreamingChatDelegate(onPartial: onPartial, completion: completion)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)
            task.resume()
            return TextProcessingRun(
                cancelHandler: {
                    task.cancel()
                    session.invalidateAndCancel()
                },
                retaining: [delegate, session, task]
            )
        } catch {
            completion(.failure(error))
            return TextProcessingRun(cancelHandler: {})
        }
    }

    private func makeRequest(
        text: String,
        config: AppConfig,
        feature: FeatureConfig,
        instruction: String?,
        stream: Bool?
    ) throws -> URLRequest {
        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "Translator", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please set API Key in Settings first."])
        }

        let urlString = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Translator", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Base URL."])
        }

        let prompt = config.resolvedPrompt(for: feature, text: text, instruction: instruction)
        let requestBody = ChatRequest(
            model: config.model,
            messages: [
                .init(role: "system", content: "You are a concise text assistant for translation, rewriting, and English vocabulary learning."),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            stream: stream
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(stream == true ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

}

@MainActor
final class SpeechService: NSObject, NSSpeechSynthesizerDelegate {
    private let synthesizer: NSSpeechSynthesizer
    private var stateHandler: ((Bool) -> Void)?

    override init() {
        if let voice = Self.preferredEnglishVoice(), let synthesizer = NSSpeechSynthesizer(voice: voice) {
            self.synthesizer = synthesizer
        } else {
            self.synthesizer = NSSpeechSynthesizer()
        }
        super.init()
        synthesizer.delegate = self
        synthesizer.rate = 175
    }

    func toggle(text: String, onStateChange: @escaping @MainActor (Bool) -> Void) -> Bool {
        if synthesizer.isSpeaking {
            stop()
            return false
        }

        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        stateHandler = onStateChange
        let started = synthesizer.startSpeaking(normalized)
        onStateChange(started)
        if !started {
            stateHandler = nil
        }
        return started
    }

    func stop() {
        guard synthesizer.isSpeaking else {
            stateHandler?(false)
            stateHandler = nil
            return
        }
        synthesizer.stopSpeaking()
        stateHandler?(false)
        stateHandler = nil
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        stateHandler?(false)
        stateHandler = nil
    }

    private static func preferredEnglishVoice() -> NSSpeechSynthesizer.VoiceName? {
        let preferred = [
            "com.apple.voice.compact.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.compact.en-GB.Daniel",
            "com.apple.voice.enhanced.en-GB.Daniel"
        ]
        let available = NSSpeechSynthesizer.availableVoices
        for voiceID in preferred {
            if let voice = available.first(where: { $0.rawValue == voiceID }) {
                return voice
            }
        }
        return available.first { voice in
            let value = voice.rawValue.lowercased()
            return value.contains(".en-") || value.contains("samantha") || value.contains("daniel")
        }
    }
}

@MainActor
final class LoginItemManager {
    func statusText() -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Launch at Login: Enabled"
        case .requiresApproval:
            return "Launch at Login: Waiting for System Approval"
        default:
            return "Launch at Login: Disabled"
        }
    }

    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }

    func toggle() throws {
        if isEnabled() {
            try SMAppService.mainApp.unregister()
        } else {
            try SMAppService.mainApp.register()
        }
    }
}

@MainActor
final class ResultWindowController: NSWindowController, NSWindowDelegate {
    private let textView = NSTextView()
    private let titleLabel = NSTextField(labelWithString: "Jit APP")
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init() {
        let panel = BubblePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.borderless],
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
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)
        panel.delegate = self

        let container = DraggableView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = LantorVisual.border.cgColor
        container.layer?.backgroundColor = LantorVisual.surface.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = LantorVisual.secondaryInk
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder

        textView.frame = NSRect(x: 0, y: 0, width: 520, height: 280)
        textView.isEditable = false
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = LantorVisual.ink
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainer?.lineFragmentPadding = 2
        scroll.documentView = textView

        guard let contentView = panel.contentView else { return }
        contentView.addSubview(container)
        container.addSubview(titleLabel)
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),

            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        stopOutsideClickMonitor()
    }

    func showError(_ message: String, selectedText: String? = nil, featureName: String = "Jit APP") {
        titleLabel.stringValue = "Jit APP · \(featureName)"
        if let selectedText {
            textView.string = "Selected Text\n\(preview(selectedText))\n\nError\n\(message)"
        } else {
            textView.string = "Error\n\(message)"
        }
        applyTextStyle()
        presentNearCursor()
    }

    private func applyTextStyle() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .foregroundColor: LantorVisual.ink,
            .font: NSFont.systemFont(ofSize: 14)
        ]
        let ns = textView.string as NSString
        textView.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: ns.length))
        textView.typingAttributes = attrs
    }

    private func preview(_ text: String) -> String {
        if text.count <= 800 { return text }
        let idx = text.index(text.startIndex, offsetBy: 800)
        return String(text[..<idx]) + "..."
    }

    private func presentNearCursor() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = mouse.x + 14
        var y = mouse.y - frame.height - 14

        if x + frame.width > visible.maxX { x = visible.maxX - frame.width - 8 }
        if x < visible.minX { x = visible.minX + 8 }
        if y < visible.minY { y = mouse.y + 14 }
        if y + frame.height > visible.maxY { y = visible.maxY - frame.height - 8 }
        if y < visible.minY { y = visible.minY + 8 }

        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        startOutsideClickMonitor()
    }

    private func startOutsideClickMonitor() {
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
        let location = NSEvent.mouseLocation
        if !window.frame.contains(location) {
            window.orderOut(nil)
            stopOutsideClickMonitor()
        }
    }
}

@MainActor
final class PromptEditorWindowController: NSWindowController {
    private var textView: NSTextView!
    private let defaultTemplate: String
    var onSave: ((String) -> Void)?

    init(currentTemplate: String, defaultTemplate: String) {
        self.defaultTemplate = defaultTemplate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Prompt"
        super.init(window: window)
        let initial = currentTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTemplate : currentTemplate
        buildUI(currentTemplate: initial)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI(currentTemplate: String) {
        guard let contentView = window?.contentView else { return }

        let hintLabel = NSTextField(labelWithString: "Available placeholders: {{targetLanguage}} / {{text}} / {{instruction}}")
        hintLabel.font = NSFont.systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        if let editor = scroll.documentView as? NSTextView {
            editor.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            editor.insertionPointColor = .textColor
            editor.drawsBackground = true
            editor.backgroundColor = .textBackgroundColor
            editor.typingAttributes = [
                .foregroundColor: NSColor.textColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ]
            let attr = NSAttributedString(
                string: currentTemplate,
                attributes: [
                    .foregroundColor: NSColor.textColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                ]
            )
            editor.textStorage?.setAttributedString(attr)
            editor.isRichText = false
            editor.isAutomaticTextCompletionEnabled = false
            self.textView = editor
        }

        let restoreButton = NSButton(title: "Restore Default", target: self, action: #selector(restoreDefault))
        restoreButton.bezelStyle = .rounded
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: "Save Prompt", target: self, action: #selector(savePrompt))
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(hintLabel)
        contentView.addSubview(scroll)
        contentView.addSubview(restoreButton)
        contentView.addSubview(saveButton)
        contentView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            hintLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: restoreButton.topAnchor, constant: -12),

            restoreButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            restoreButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            closeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    @objc private func restoreDefault() {
        textView?.string = defaultTemplate
    }

    @objc private func savePrompt() {
        let text = textView?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        onSave?(text)
    }

    @objc private func closeWindow() {
        window?.close()
    }
}

@MainActor
final class CommandInputWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let compactSize = NSSize(width: 620, height: 218)
        static let maxHeight: CGFloat = 720
        static let outputHeightIncrease: CGFloat = 300
    }

    private enum PanelPhase {
        case idle
        case running
        case done
        case error
    }

    private enum ActionButtonKind {
        case primary
        case secondary
        case warning
    }

    struct Mode {
        let id: String
        let title: String
        let requiresInstruction: Bool
        let supportsReplace: Bool
        let promptPreview: String
    }

    private let commandField = NSTextField(string: "")
    private let titleLabel = NSTextField(labelWithString: "Jit Action")
    private let phaseChip = NSTextField(labelWithString: "Ready")
    private let modeStack = NSStackView()
    private var modeButtons: [NSButton] = []
    private let hintLabel = NSTextField(labelWithString: "Select an action, then run it on the selected text.")
    private let commandContainer = NSView()
    private let outputTextView = NSTextView()
    private let outputScroll = NSScrollView()
    private let progressIndicator = NSProgressIndicator()
    private let speakButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var expanded = false
    private let modes: [Mode]
    private var currentModeIndex: Int = 0
    private let selectedText: String
    private let selectedPreview: String
    private var customInstructionDraft: String = ""
    private var activeRun: TextProcessingRun?
    private var isRunning = false
    private var isSpeakingSelectedText = false
    private var outputDidStream = false
    private var runGeneration = 0
    var onSubmit: ((String, String?, @escaping @Sendable (String) -> Void, @escaping @Sendable (Result<String, Error>) -> Void) -> TextProcessingRun?)?
    var onToggleSpeech: ((String, @escaping @MainActor (Bool) -> Void) -> Bool)?
    var onStopSpeech: (() -> Void)?
    var onReplace: ((String) -> Void)?
    var onClose: (() -> Void)?

    init(selectedText: String, anchor: NSPoint, modes: [Mode], defaultModeID: String = "custom") {
        self.modes = modes.isEmpty ? [Mode(id: "custom", title: "Custom", requiresInstruction: true, supportsReplace: true, promptPreview: "Custom instruction mode")] : modes
        self.selectedText = selectedText
        self.selectedPreview = selectedText.count > 80 ? String(selectedText.prefix(80)) + "..." : selectedText
        let panel = BubblePanel(
            contentRect: NSRect(origin: .zero, size: Layout.compactSize),
            styleMask: [.borderless],
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
        panel.minSize = Layout.compactSize
        panel.maxSize = NSSize(width: Layout.compactSize.width, height: Layout.maxHeight)
        super.init(window: panel)
        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in
            self?.handlePanelKeyDown(event) ?? false
        }
        buildUI(selectedText: selectedText)
        if let idx = self.modes.firstIndex(where: { $0.id == defaultModeID }) {
            currentModeIndex = idx
        }
        refreshModeUI()
        position(near: anchor)
        installEscapeHandler()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI(selectedText: String) {
        guard let contentView = window?.contentView else { return }
        let container = DraggableView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = LantorVisual.border.cgColor
        container.layer?.backgroundColor = LantorVisual.surface.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = LantorVisual.ink
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stylePhaseChip(.idle)
        phaseChip.translatesAutoresizingMaskIntoConstraints = false
        phaseChip.setContentHuggingPriority(.required, for: .horizontal)

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headerRow = NSStackView(views: [titleLabel, headerSpacer, phaseChip])
        headerRow.orientation = .horizontal
        headerRow.spacing = 10
        headerRow.alignment = .centerY
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        modeStack.orientation = .horizontal
        modeStack.spacing = 6
        modeStack.alignment = .centerY
        modeStack.distribution = .fillEqually
        modeStack.wantsLayer = true
        modeStack.layer?.cornerRadius = 10
        modeStack.layer?.masksToBounds = true
        modeStack.layer?.backgroundColor = LantorVisual.panel.cgColor
        modeStack.layer?.borderWidth = 1
        modeStack.layer?.borderColor = LantorVisual.borderSubtle.cgColor
        modeStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modeButtons = modes.enumerated().map { index, mode in
            let button = NSButton(title: compactTitle(for: mode), target: self, action: #selector(modeButtonTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("\(index)")
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.masksToBounds = true
            button.translatesAutoresizingMaskIntoConstraints = false
            button.lineBreakMode = .byTruncatingTail
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            modeStack.addArrangedSubview(button)
            return button
        }

        hintLabel.stringValue = "Run on selected text: \(selectedPreview)"
        hintLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        hintLabel.textColor = LantorVisual.mutedInk
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        commandField.placeholderString = "Type instruction..."
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.font = NSFont.systemFont(ofSize: 15)
        commandField.textColor = LantorVisual.ink
        commandField.placeholderAttributedString = NSAttributedString(
            string: "Type instruction...",
            attributes: [.foregroundColor: LantorVisual.mutedInk]
        )
        commandField.drawsBackground = false
        commandField.isBordered = false
        commandField.focusRingType = .default
        commandField.usesSingleLineMode = true
        commandField.lineBreakMode = .byTruncatingTail
        commandField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        commandField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        commandContainer.translatesAutoresizingMaskIntoConstraints = false
        commandContainer.wantsLayer = true
        commandContainer.layer?.cornerRadius = 10
        commandContainer.layer?.masksToBounds = true
        commandContainer.layer?.backgroundColor = LantorVisual.input.cgColor
        commandContainer.layer?.borderWidth = 1
        commandContainer.layer?.borderColor = LantorVisual.border.cgColor
        commandContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        commandContainer.addSubview(commandField)

        outputScroll.translatesAutoresizingMaskIntoConstraints = false
        outputScroll.hasVerticalScroller = true
        outputScroll.borderType = .noBorder
        outputScroll.drawsBackground = true
        outputScroll.backgroundColor = LantorVisual.panel
        outputScroll.wantsLayer = true
        outputScroll.layer?.cornerRadius = 12
        outputScroll.layer?.masksToBounds = true
        outputScroll.layer?.borderWidth = 1
        outputScroll.layer?.borderColor = LantorVisual.borderSubtle.cgColor
        outputScroll.isHidden = true

        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.drawsBackground = true
        outputTextView.backgroundColor = LantorVisual.panel
        outputTextView.font = NSFont.systemFont(ofSize: 14)
        outputTextView.textColor = LantorVisual.ink
        outputTextView.insertionPointColor = LantorVisual.accent
        outputTextView.isRichText = false
        outputTextView.importsGraphics = false
        outputTextView.frame = NSRect(x: 0, y: 0, width: 520, height: 260)
        outputTextView.minSize = NSSize(width: 0, height: 0)
        outputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.autoresizingMask = [.width]
        outputTextView.typingAttributes = [
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineBreakMode = .byCharWrapping
                return p
            }(),
            .foregroundColor: LantorVisual.ink,
            .font: NSFont.systemFont(ofSize: 14)
        ]
        outputTextView.textContainerInset = NSSize(width: 6, height: 6)
        outputTextView.isVerticallyResizable = true
        outputTextView.isHorizontallyResizable = false
        outputTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.textContainer?.widthTracksTextView = true
        outputTextView.textContainer?.lineBreakMode = .byCharWrapping
        outputTextView.textContainer?.lineFragmentPadding = 2
        outputScroll.documentView = outputTextView

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.widthAnchor.constraint(equalToConstant: 18).isActive = true
        progressIndicator.heightAnchor.constraint(equalToConstant: 18).isActive = true

        speakButton.target = self
        speakButton.action = #selector(speakTapped)
        speakButton.translatesAutoresizingMaskIntoConstraints = false
        speakButton.isHidden = true
        speakButton.imagePosition = .imageOnly
        speakButton.toolTip = "Speak selected text"
        styleActionButton(speakButton, kind: .secondary, width: 38)
        updateSpeakButton(speaking: false)

        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.isHidden = true
        styleActionButton(copyButton, kind: .secondary, width: 72)

        replaceButton.target = self
        replaceButton.action = #selector(replaceTapped)
        replaceButton.translatesAutoresizingMaskIntoConstraints = false
        replaceButton.isHidden = true
        styleActionButton(replaceButton, kind: .secondary, width: 82)

        runButton.target = self
        runButton.action = #selector(runTapped)
        runButton.translatesAutoresizingMaskIntoConstraints = false
        styleActionButton(runButton, kind: .primary, width: 96)

        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        styleActionButton(cancelButton, kind: .secondary, width: 84)

        let actionRow = NSStackView(views: [progressIndicator, speakButton, copyButton, replaceButton, cancelButton, runButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        actionRow.alignment = .centerY
        actionRow.distribution = .gravityAreas
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(container)
        container.addSubview(headerRow)
        container.addSubview(modeStack)
        container.addSubview(hintLabel)
        container.addSubview(commandContainer)
        container.addSubview(outputScroll)
        container.addSubview(actionRow)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            headerRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            headerRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            headerRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            headerRow.heightAnchor.constraint(equalToConstant: 24),

            modeStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            modeStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            modeStack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 12),
            modeStack.heightAnchor.constraint(equalToConstant: 36),

            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            hintLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            hintLabel.topAnchor.constraint(equalTo: modeStack.bottomAnchor, constant: 10),

            commandContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            commandContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            commandContainer.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            commandContainer.heightAnchor.constraint(equalToConstant: 36),

            commandField.leadingAnchor.constraint(equalTo: commandContainer.leadingAnchor, constant: 11),
            commandField.trailingAnchor.constraint(equalTo: commandContainer.trailingAnchor, constant: -11),
            commandField.centerYAnchor.constraint(equalTo: commandContainer.centerYAnchor),

            outputScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            outputScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            outputScroll.topAnchor.constraint(equalTo: commandContainer.bottomAnchor, constant: 10),
            outputScroll.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -10),

            actionRow.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 14),
            actionRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            actionRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            actionRow.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func styleActionButton(_ button: NSButton, kind: ActionButtonKind, title: String? = nil, width: CGFloat? = nil) {
        if let title {
            button.title = title
        }
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
        button.layer?.borderWidth = 1

        let background: NSColor
        let border: NSColor
        let foreground: NSColor
        let weight: NSFont.Weight
        switch kind {
        case .primary:
            background = LantorVisual.accent
            border = LantorVisual.accent
            foreground = LantorVisual.accentInk
            weight = .semibold
        case .secondary:
            background = LantorVisual.control
            border = LantorVisual.border
            foreground = LantorVisual.secondaryInk
            weight = .medium
        case .warning:
            background = LantorVisual.warningSoft
            border = LantorVisual.warningInk.withAlphaComponent(0.32)
            foreground = LantorVisual.warningInk
            weight = .semibold
        }

        button.layer?.backgroundColor = background.cgColor
        button.layer?.borderColor = border.cgColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: weight),
                .foregroundColor: foreground
            ]
        )
        button.alphaValue = button.isEnabled ? 1 : 0.52
        if let width {
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
    }

    private func stylePhaseChip(_ phase: PanelPhase) {
        let text: String
        let background: NSColor
        let foreground: NSColor
        switch phase {
        case .idle:
            text = "Ready"
            background = LantorVisual.accentSoft
            foreground = LantorVisual.accent
        case .running:
            text = "Streaming"
            background = LantorVisual.thinkingSoft
            foreground = LantorVisual.thinkingInk
        case .done:
            text = "Done"
            background = LantorVisual.successSoft
            foreground = LantorVisual.successInk
        case .error:
            text = "Error"
            background = LantorVisual.errorSoft
            foreground = LantorVisual.errorInk
        }
        phaseChip.stringValue = text
        phaseChip.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        phaseChip.textColor = foreground
        phaseChip.alignment = .center
        phaseChip.wantsLayer = true
        phaseChip.layer?.cornerRadius = 8
        phaseChip.layer?.masksToBounds = true
        phaseChip.layer?.backgroundColor = background.cgColor
        phaseChip.translatesAutoresizingMaskIntoConstraints = false
        if phaseChip.constraints.first(where: { $0.identifier == "phaseChipWidth" }) == nil {
            let width = phaseChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
            width.identifier = "phaseChipWidth"
            width.isActive = true
            phaseChip.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }
    }

    private func styleModeButtons() {
        for (index, button) in modeButtons.enumerated() {
            let selected = index == currentModeIndex
            button.layer?.backgroundColor = (selected ? LantorVisual.accentSoft : NSColor.clear).cgColor
            button.layer?.borderWidth = selected ? 1 : 0
            button.layer?.borderColor = LantorVisual.accentSoftBorder.cgColor
            button.alphaValue = button.isEnabled ? 1 : 0.52
            button.attributedTitle = NSAttributedString(
                string: compactTitle(for: modes[index]),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium),
                    .foregroundColor: selected ? LantorVisual.accent : LantorVisual.secondaryInk
                ]
            )
        }
    }

    func focus() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        if modes[currentModeIndex].requiresInstruction {
            window.makeFirstResponder(commandField)
        } else {
            window.makeFirstResponder(nil)
        }
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

    @objc private func runTapped() {
        guard !isRunning else { return }
        let mode = modes[currentModeIndex]
        let rawInstruction = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode.requiresInstruction && rawInstruction.isEmpty {
            NSSound.beep()
            return
        }
        let instruction = mode.requiresInstruction ? rawInstruction : nil
        startRunning(mode: mode)

        runGeneration += 1
        let generation = runGeneration
        activeRun = onSubmit?(
            mode.id,
            instruction,
            { [weak self] delta in
                Task { @MainActor in
                    self?.appendOutput(delta, generation: generation)
                }
            },
            { [weak self] result in
                Task { @MainActor in
                    self?.finishRunning(result: result, mode: mode, generation: generation)
                }
            }
        )

        if activeRun == nil {
            finishRunning(
                result: .failure(NSError(domain: "JitAPP", code: 500, userInfo: [NSLocalizedDescriptionKey: "No processing handler is configured."])),
                mode: mode,
                generation: generation
            )
        }
    }

    @objc private func cancelTapped() {
        if isRunning {
            runGeneration += 1
            activeRun?.cancel()
            activeRun = nil
            isRunning = false
            setRunningState(false, mode: modes[currentModeIndex])
            setOutputText("Canceled.")
            hintLabel.stringValue = "Canceled."
            stylePhaseChip(.idle)
            copyButton.isHidden = true
            replaceButton.isHidden = true
            window?.makeFirstResponder(commandField)
            return
        }
        window?.close()
    }

    @objc private func speakTapped() {
        guard speechAvailable(for: modes[currentModeIndex]) else { return }
        let started = onToggleSpeech?(selectedText) { [weak self] speaking in
            self?.setSpeechState(speaking)
        } ?? false
        setSpeechState(started)
    }

    @objc private func replaceTapped() {
        let output = outputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return }
        onReplace?(output)
    }

    @objc private func copyTapped() {
        let output = outputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        styleActionButton(copyButton, kind: .secondary, title: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            self.styleActionButton(self.copyButton, kind: .secondary, title: "Copy")
        }
    }

    func windowWillClose(_ notification: Notification) {
        activeRun?.cancel()
        activeRun = nil
        isRunning = false
        onStopSpeech?()
        stopOutsideClickMonitor()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        onClose?()
    }

    private func installEscapeHandler() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handlePanelKeyDown(event) ? nil : event
        }
    }

    private func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC
            cancelTapped()
            return true
        }
        if !isRunning && (event.keyCode == 36 || event.keyCode == 76) { // Return / Enter
            runTapped()
            return true
        }
        if !isRunning && event.keyCode == 126 { // Up
            moveMode(delta: -1)
            return true
        }
        if !isRunning && event.keyCode == 125 { // Down
            moveMode(delta: 1)
            return true
        }
        return false
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
        let location = NSEvent.mouseLocation
        if !window.frame.contains(location) {
            window.close()
        }
    }

    private func startRunning(mode: Mode) {
        isRunning = true
        outputDidStream = false
        expandForOutputIfNeeded()
        setOutputText("Waiting for \(mode.title)...")
        hintLabel.stringValue = "Running \(mode.title)..."
        stylePhaseChip(.running)
        setRunningState(true, mode: mode)
    }

    private func finishRunning(result: Result<String, Error>, mode: Mode, generation: Int) {
        guard generation == runGeneration else { return }
        activeRun = nil
        isRunning = false
        setRunningState(false, mode: mode)
        expandForOutputIfNeeded()

        switch result {
        case .success(let output):
            let displayedOutput = outputDidStream ? outputTextView.string : output
            setOutputText(displayedOutput)
            hintLabel.stringValue = "Completed \(mode.title)."
            stylePhaseChip(.done)
            outputTextView.isEditable = true
            window?.makeFirstResponder(outputTextView)
            copyButton.isHidden = false
            replaceButton.isHidden = !mode.supportsReplace
        case .failure(let error):
            if error is CancellationError { return }
            setOutputText("Failed: \(error.localizedDescription)")
            hintLabel.stringValue = "\(mode.title) failed."
            stylePhaseChip(.error)
            outputTextView.isEditable = false
            window?.makeFirstResponder(outputTextView)
            copyButton.isHidden = true
            replaceButton.isHidden = true
        }
    }

    private func appendOutput(_ delta: String, generation: Int) {
        guard generation == runGeneration, isRunning else { return }
        let current = outputDidStream ? outputTextView.string : ""
        outputDidStream = true
        setOutputText(current + delta, emptyPlaceholder: "")
        scrollOutputToEnd()
    }

    private func setRunningState(_ running: Bool, mode: Mode) {
        modeButtons.forEach { $0.isEnabled = !running }
        commandField.isEnabled = !running && mode.requiresInstruction
        commandField.isEditable = !running && mode.requiresInstruction
        outputTextView.isEditable = false
        speakButton.isEnabled = speechAvailable(for: mode)
        speakButton.isHidden = !speechAvailable(for: mode)
        copyButton.isEnabled = !running
        replaceButton.isEnabled = !running
        runButton.isEnabled = !running
        cancelButton.isEnabled = true
        styleActionButton(cancelButton, kind: running ? .warning : .secondary, title: running ? "Stop" : "Cancel")
        styleActionButton(runButton, kind: .primary)
        styleActionButton(copyButton, kind: .secondary)
        styleActionButton(replaceButton, kind: .secondary)
        styleModeButtons()
        if running {
            progressIndicator.startAnimation(nil)
            copyButton.isHidden = true
            replaceButton.isHidden = true
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func moveMode(delta: Int) {
        guard !modes.isEmpty else { return }
        let oldMode = modes[currentModeIndex]
        if oldMode.requiresInstruction {
            customInstructionDraft = commandField.stringValue
        }
        let count = modes.count
        currentModeIndex = (currentModeIndex + delta + count) % count
        refreshModeUI()
    }

    @objc private func modeButtonTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let selected = Int(raw) else { return }
        guard selected >= 0, selected < modes.count else { return }
        let oldMode = modes[currentModeIndex]
        if oldMode.requiresInstruction {
            customInstructionDraft = commandField.stringValue
        }
        currentModeIndex = selected
        refreshModeUI()
        if modes[currentModeIndex].requiresInstruction {
            window?.makeFirstResponder(commandField)
        }
    }

    private func refreshModeUI() {
        let mode = modes[currentModeIndex]
        if !speechAvailable(for: mode), isSpeakingSelectedText {
            onStopSpeech?()
            isSpeakingSelectedText = false
            updateSpeakButton(speaking: false)
        }
        hintLabel.stringValue = "\(mode.title) · \(selectedPreview)"
        hintLabel.maximumNumberOfLines = 1
        styleModeButtons()
        speakButton.isHidden = !speechAvailable(for: mode)
        speakButton.isEnabled = speechAvailable(for: mode)
        commandContainer.layer?.backgroundColor = (mode.requiresInstruction ? LantorVisual.input : LantorVisual.panel).cgColor
        if mode.requiresInstruction {
            commandField.isEditable = true
            commandField.isEnabled = true
            commandField.placeholderAttributedString = NSAttributedString(
                string: "Instruction for \(mode.title)...",
                attributes: [.foregroundColor: LantorVisual.mutedInk]
            )
            commandField.stringValue = customInstructionDraft
            commandField.toolTip = nil
            styleActionButton(runButton, kind: .primary, title: "Run")
        } else {
            commandField.isEditable = false
            commandField.isEnabled = false
            commandField.placeholderAttributedString = NSAttributedString(string: "")
            commandField.stringValue = actionHint(for: mode)
            commandField.toolTip = mode.promptPreview
            styleActionButton(runButton, kind: .primary, title: "Run")
        }
    }

    private func compactTitle(for mode: Mode) -> String {
        switch mode.id {
        case "custom":
            return "Custom"
        case "refine":
            return "Polish"
        case "translate":
            return "Translate"
        case "vocabulary":
            return "Words"
        default:
            return mode.title
        }
    }

    private func actionHint(for mode: Mode) -> String {
        switch mode.id {
        case "refine":
            return "Polish the selected text"
        case "translate":
            return "Translate the selected text"
        case "vocabulary":
            return "Speak for pronunciation, Run for meaning and usage"
        default:
            return "Uses the saved prompt for \(mode.title)"
        }
    }

    private func speechAvailable(for mode: Mode) -> Bool {
        mode.id == "vocabulary"
    }

    private func setSpeechState(_ speaking: Bool) {
        isSpeakingSelectedText = speaking
        updateSpeakButton(speaking: speaking)
        if speechAvailable(for: modes[currentModeIndex]) {
            hintLabel.stringValue = speaking ? "Speaking · \(selectedPreview)" : "\(modes[currentModeIndex].title) · \(selectedPreview)"
        }
    }

    private func updateSpeakButton(speaking: Bool) {
        let symbolName = speaking ? "speaker.slash.fill" : "speaker.wave.2.fill"
        speakButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: speaking ? "Stop speaking" : "Speak selected text")
        speakButton.image?.isTemplate = true
        speakButton.toolTip = speaking ? "Stop speaking" : "Speak selected text"
        speakButton.contentTintColor = speaking ? LantorVisual.warningInk : LantorVisual.secondaryInk
        styleActionButton(speakButton, kind: speaking ? .warning : .secondary)
        speakButton.imagePosition = .imageOnly
    }

    private func setOutputText(_ text: String, emptyPlaceholder: String = "(No content returned)") {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = normalized.isEmpty ? emptyPlaceholder : text
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .foregroundColor: LantorVisual.ink,
            .font: NSFont.systemFont(ofSize: 14)
        ]
        // Force text container width to visible viewport so wrapping always follows bubble width.
        let viewportWidth = max(120, outputScroll.contentSize.width - 12)
        outputTextView.textContainer?.containerSize = NSSize(width: viewportWidth, height: CGFloat.greatestFiniteMagnitude)
        outputTextView.textContainer?.widthTracksTextView = false
        outputTextView.frame.size.width = viewportWidth
        outputTextView.string = display
        let ns = display as NSString
        outputTextView.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: ns.length))
        outputTextView.typingAttributes = attrs
    }

    private func scrollOutputToEnd() {
        let range = NSRange(location: (outputTextView.string as NSString).length, length: 0)
        outputTextView.scrollRangeToVisible(range)
    }

    private func expandForOutputIfNeeded() {
        guard let window, !expanded else {
            outputScroll.isHidden = false
            return
        }
        expanded = true
        outputScroll.isHidden = false
        var frame = window.frame
        frame.origin.y -= Layout.outputHeightIncrease
        frame.size.height += Layout.outputHeightIncrease
        frame.size.width = Layout.compactSize.width
        window.setFrame(frame, display: true, animate: true)
    }

    private func position(near anchor: NSPoint) {
        guard let window else { return }
        let frame = window.frame
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.x - 28
        var y = anchor.y - frame.height - 8 // prefer below selected text
        if x + frame.width > visible.maxX { x = visible.maxX - frame.width - 8 }
        if x < visible.minX { x = visible.minX + 8 }
        if y < visible.minY { y = anchor.y + 12 } // fallback to above cursor if no room below
        if y + frame.height > visible.maxY { y = visible.maxY - frame.height - 8 }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    @MainActor
    private enum Theme {
        static let sidebarWidth: CGFloat = 236
        static let contentPadding: CGFloat = 24
        static let sectionSpacing: CGFloat = 18
        static let cardPadding: CGFloat = 18
        static let cardCornerRadius: CGFloat = 14
        static let fieldCornerRadius: CGFloat = 8
        static let onboardingContentWidth: CGFloat = 580

        static let sidebarSelection = NSColor.controlAccentColor.withAlphaComponent(0.16)
        static let sidebarText = NSColor.labelColor
        static let sidebarSecondaryText = NSColor.secondaryLabelColor
        static let cardStroke = NSColor.separatorColor.withAlphaComponent(0.42)
        static let chipGreenBackground = NSColor.systemGreen.withAlphaComponent(0.15)
        static let chipGreenText = NSColor.systemGreen
        static let chipOrangeBackground = NSColor.systemOrange.withAlphaComponent(0.15)
        static let chipOrangeText = NSColor.systemOrange
        static let fieldBackground = NSColor.controlBackgroundColor.withAlphaComponent(0.82)
        static let inlineError = NSColor.systemRed
        static let inlineSuccess = NSColor.systemGreen

        static let largeTitleFont = NSFont.systemFont(ofSize: 28, weight: .semibold)
        static let sectionTitleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
        static let bodyFont = NSFont.systemFont(ofSize: 13)
        static let captionFont = NSFont.systemFont(ofSize: 12)
        static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    }

    private enum SettingsSection: String, CaseIterable {
        case getStarted
        case connection
        case entry
        case prompts
        case permissions

        var title: String {
            switch self {
            case .getStarted: return "Get Started"
            case .connection: return "AI Model"
            case .entry: return "Shortcut"
            case .prompts: return "Actions"
            case .permissions: return "Permissions"
            }
        }

        var subtitle: String {
            switch self {
            case .getStarted: return "Setup checklist and next step"
            case .connection: return "Endpoint, API key, and model"
            case .entry: return "Global hotkey for the action palette"
            case .prompts: return "Translate, refine, vocabulary, and custom prompts"
            case .permissions: return "System access requirements"
            }
        }

        var symbol: String {
            switch self {
            case .getStarted: return "checklist"
            case .connection: return "network"
            case .entry: return "command"
            case .prompts: return "text.bubble"
            case .permissions: return "lock.shield"
            }
        }
    }

    @MainActor
    final class FeatureHotkeyControls {
        let id: String
        var hotkeyKey: String
        var hotkeyOption: Bool
        var hotkeyCommand: Bool
        var hotkeyControl: Bool
        var hotkeyShift: Bool
        let shortcutPreview = NSTextField(labelWithString: "")
        let recordButton = NSButton(title: "Record Shortcut...", target: nil, action: nil)

        init(feature: FeatureConfig) {
            self.id = feature.id
            self.hotkeyKey = feature.hotkeyKey
            self.hotkeyOption = feature.hotkeyOption
            self.hotkeyCommand = feature.hotkeyCommand
            self.hotkeyControl = feature.hotkeyControl
            self.hotkeyShift = feature.hotkeyShift

            shortcutPreview.font = Theme.monoFont
            shortcutPreview.textColor = .labelColor
            shortcutPreview.alignment = .left
            shortcutPreview.stringValue = ""
        }
    }

    @MainActor
    final class FlippedStackView: NSStackView {
        override var isFlipped: Bool { true }
    }

    private let baseURLField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let targetLanguageField = NSTextField(string: "")
    private var featureConfigs: [FeatureConfig] = []
    private var featureControls: [String: FeatureHotkeyControls] = [:]
    private var promptEditorWindowController: PromptEditorWindowController?
    private var sectionButtons: [SettingsSection: NSButton] = [:]
    private var sectionPages: [SettingsSection: NSView] = [:]
    private var currentSection: SettingsSection = .connection
    private weak var detailTitleLabel: NSTextField?
    private weak var detailSubtitleLabel: NSTextField?
    private weak var detailPageStack: NSStackView?
    private weak var footerStatusLabel: NSTextField?
    private weak var connectionAdvancedStack: NSStackView?
    private var hotkeyCaptureMonitor: Any?
    private var capturingHotkeyFeatureID: String?

    var onSave: ((AppConfig) -> Void)?
    var onTest: ((AppConfig, FeatureConfig, @escaping @MainActor (Result<String, Error>) -> Void) -> Void)?
    var onDiagnosePermissions: (() -> String)?
    var onRequestPermissions: (() -> String)?
    var onResetPermissions: (() -> String)?

    init(config: AppConfig) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jit APP Settings"
        window.minSize = NSSize(width: 780, height: 500)
        super.init(window: window)
        window.delegate = self

        baseURLField.stringValue = config.baseURL
        apiKeyField.stringValue = config.apiKey
        modelField.stringValue = config.model
        targetLanguageField.stringValue = config.targetLanguage
        featureConfigs = config.features

        configureInputFields()
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        stopHotkeyCapture()
    }

    func focusPrimaryField() {
        window?.makeFirstResponder(apiKeyField)
    }

    func showGetStartedSection() {
        showSection(.getStarted, animated: false)
    }

    func showPermissionsSection() {
        showSection(.permissions, animated: false)
    }

    func refreshPermissionStatus(showFooter: Bool = false) {
        sectionPages[.getStarted] = nil
        sectionPages[.permissions] = nil
        if currentSection == .getStarted || currentSection == .permissions {
            showSection(currentSection, animated: false, clearFooter: false)
        }

        guard showFooter else { return }
        let report = onDiagnosePermissions?() ?? ""
        if report.isEmpty {
            setFooterStatus("Permission status refreshed.", kind: .neutral)
            return
        }

        let allAllowed = report.contains("Accessibility: Allowed") &&
            report.contains("Input Monitoring (ListenEvent): Allowed") &&
            report.contains("Event Posting (PostEvent): Allowed")
        if allAllowed {
            setFooterStatus("Permission status refreshed: all required permissions are allowed.", kind: .success)
        } else {
            setFooterStatus("Permission status refreshed: some permissions are still missing.", kind: .error)
        }
    }

    private func configureInputFields() {
        [baseURLField, apiKeyField, modelField, targetLanguageField].forEach { field in
            field.font = NSFont.systemFont(ofSize: 14)
            field.focusRingType = .default
            field.drawsBackground = false
            field.isBordered = false
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.translatesAutoresizingMaskIntoConstraints = false
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        sectionButtons.removeAll()
        sectionPages.removeAll()
        featureControls.removeAll()
        connectionAdvancedStack = nil
        currentSection = .getStarted

        let split = NSStackView()
        split.orientation = .horizontal
        split.spacing = 0
        split.distribution = .fill
        split.alignment = .centerY
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(sidebarView())
        split.addArrangedSubview(detailView())
        split.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: Theme.sidebarWidth).isActive = true

        contentView.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            split.topAnchor.constraint(equalTo: contentView.topAnchor),
            split.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.showSection(.getStarted, animated: false)
        }
    }

    private func sidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.state = .active
        sidebar.blendingMode = .withinWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.borderWidth = 1
        sidebar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let iconView = NSImageView()
        if let image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "Jit APP") {
            iconView.image = image
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
            iconView.contentTintColor = .controlAccentColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 36).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let appTitle = label("Jit APP", font: NSFont.systemFont(ofSize: 17, weight: .semibold), color: Theme.sidebarText)
        let appSubtitle = label("Setup & Preferences", font: Theme.bodyFont, color: Theme.sidebarSecondaryText)
        let identityStack = NSStackView(views: [appTitle, appSubtitle])
        identityStack.orientation = .vertical
        identityStack.spacing = 2
        identityStack.alignment = .leading

        let topRow = NSStackView(views: [iconView, identityStack])
        topRow.orientation = .horizontal
        topRow.spacing = 10
        topRow.alignment = .centerY

        let navStack = NSStackView()
        navStack.orientation = .vertical
        navStack.spacing = 6
        navStack.alignment = .leading
        for section in SettingsSection.allCases {
            let button = sidebarButton(for: section)
            sectionButtons[section] = button
            navStack.addArrangedSubview(button)
        }

        let container = NSStackView(views: [topRow, navStack])
        container.orientation = .vertical
        container.spacing = 20
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            container.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18)
        ])
        return sidebar
    }

    private func sidebarButton(for section: SettingsSection) -> NSButton {
        let button = NSButton(title: section.title, target: self, action: #selector(sidebarSectionTapped(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(section.rawValue)
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = Theme.sidebarSecondaryText
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        if let image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title) {
            button.image = image
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        }
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth - 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    @objc private func sidebarSectionTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let section = SettingsSection(rawValue: raw) else { return }
        showSection(section, animated: true)
    }

    private func showSection(_ section: SettingsSection, animated: Bool, clearFooter: Bool = true) {
        stopHotkeyCapture()
        currentSection = section
        updateSidebarSelection(section)
        if clearFooter {
            setFooterStatus(nil)
        }
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
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                nextPage.animator().alphaValue = 1
            }
        }
    }

    private func pageView(for section: SettingsSection) -> NSView {
        if let page = sectionPages[section] { return page }

        let content: NSView
        switch section {
        case .getStarted:
            content = getStartedSectionView()
        case .connection:
            content = connectionSectionView()
        case .entry:
            content = entrySectionView()
        case .prompts:
            content = promptsSectionView()
        case .permissions:
            content = permissionsSectionView()
        }

        let pageStack = NSStackView()
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = Theme.sectionSpacing
        if section == .getStarted || section == .prompts {
            pageStack.addArrangedSubview(content)
        } else {
            pageStack.addArrangedSubview(contentCard(content))
        }
        sectionPages[section] = pageStack
        return pageStack
    }

    private func contentCard(_ content: NSView) -> NSView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.state = .active
        card.blendingMode = .withinWindow
        card.wantsLayer = true
        card.layer?.cornerRadius = Theme.cardCornerRadius
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Theme.cardStroke.cgColor

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

    private func detailView() -> NSView {
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.state = .active
        background.blendingMode = .withinWindow
        background.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(background)

        let titleLabel = label("", font: NSFont.systemFont(ofSize: 27, weight: .semibold), color: .labelColor)
        let subtitleLabel = label("", font: Theme.bodyFont, color: .secondaryLabelColor)
        subtitleLabel.maximumNumberOfLines = 2
        detailTitleLabel = titleLabel
        detailSubtitleLabel = subtitleLabel

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.spacing = 4
        headerStack.alignment = .leading
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let pageScroll = NSScrollView()
        pageScroll.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.hasVerticalScroller = true
        pageScroll.borderType = .noBorder
        pageScroll.drawsBackground = false
        pageScroll.contentInsets = NSEdgeInsets(
            top: Theme.contentPadding,
            left: Theme.contentPadding,
            bottom: Theme.contentPadding,
            right: Theme.contentPadding
        )
        let pageStack = FlippedStackView()
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = 0
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.documentView = pageStack
        detailPageStack = pageStack

        let statusLabel = label("", font: Theme.captionFont, color: .secondaryLabelColor)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footerStatusLabel = statusLabel

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        stylePrimaryButton(saveButton)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actionRow = NSStackView(views: [statusLabel, spacer, saveButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.distribution = .fill
        actionRow.alignment = .centerY
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        saveButton.widthAnchor.constraint(equalToConstant: 140).isActive = true
        actionRow.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        detail.addSubview(headerStack)
        detail.addSubview(separator)
        detail.addSubview(pageScroll)
        detail.addSubview(actionRow)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            background.topAnchor.constraint(equalTo: detail.topAnchor),
            background.bottomAnchor.constraint(equalTo: detail.bottomAnchor),

            headerStack.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: Theme.contentPadding),
            headerStack.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -Theme.contentPadding),
            headerStack.topAnchor.constraint(equalTo: detail.topAnchor, constant: 18),

            separator.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            separator.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),

            pageScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            pageScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            pageScroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 0),
            pageScroll.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -12),

            pageStack.widthAnchor.constraint(equalTo: pageScroll.widthAnchor, constant: -(Theme.contentPadding * 2)),

            actionRow.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: Theme.contentPadding),
            actionRow.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -Theme.contentPadding),
            actionRow.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -Theme.contentPadding)
        ])
        return detail
    }

    private var hasDraftConnectionSettings: Bool {
        !baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var requiredPermissionsAllowed: Bool {
        AXIsProcessTrusted() &&
            CGPreflightListenEventAccess() &&
            CGPreflightPostEventAccess()
    }

    private var setupIsReady: Bool {
        hasDraftConnectionSettings && requiredPermissionsAllowed
    }

    private var completedSetupStepCount: Int {
        var count = 0
        if hasDraftConnectionSettings { count += 1 }
        if requiredPermissionsAllowed { count += 1 }
        if setupIsReady { count += 1 }
        return count
    }

    private var actionPaletteShortcutText: String {
        guard let entryFeature = featureConfigs.first(where: { $0.id == "custom" }) else {
            return "the action palette shortcut"
        }
        return shortcutDisplay(
            key: entryFeature.hotkeyKey,
            option: entryFeature.hotkeyOption,
            command: entryFeature.hotkeyCommand,
            control: entryFeature.hotkeyControl,
            shift: entryFeature.hotkeyShift
        )
    }

    private func getStartedSectionView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.alignment = .leading

        let completedCount = completedSetupStepCount
        let ready = setupIsReady
        container.addArrangedSubview(onboardingHeroView(completedCount: completedCount, ready: ready))
        container.addArrangedSubview(setupProgressView(completedCount: completedCount))

        let pasteKeyButton = onboardingButton("Paste Key", action: #selector(pasteAPIKey), primary: !hasDraftConnectionSettings, width: 92)
        let aiModelButton = onboardingButton("AI Model", action: #selector(openConnectionSectionTapped), width: 92)
        let testButton = onboardingButton("Test", action: #selector(testTapped), width: 76, enabled: hasDraftConnectionSettings)
        container.addArrangedSubview(onboardingStepView(
            number: 1,
            title: "Connect AI",
            detail: hasDraftConnectionSettings
                ? "Base URL, API key, and model are filled. Test once before relying on the palette."
                : "Defaults cover Base URL and Model. Paste your API key, save, then test the connection.",
            status: hasDraftConnectionSettings ? "Configured" : "Required",
            complete: hasDraftConnectionSettings,
            actions: [pasteKeyButton, aiModelButton, testButton]
        ))

        let grantButton = onboardingButton("Grant Access", action: #selector(requestPermissionsTapped), primary: !requiredPermissionsAllowed, width: 112)
        let permissionsButton = onboardingButton("Permissions", action: #selector(openPermissionsSectionTapped), width: 104)
        container.addArrangedSubview(onboardingStepView(
            number: 2,
            title: "Grant System Access",
            detail: permissionSummaryText(),
            status: requiredPermissionsAllowed ? "Allowed" : "Required",
            complete: requiredPermissionsAllowed,
            actions: [grantButton, permissionsButton]
        ))

        let doneButton = onboardingButton("Done", action: #selector(closeSettingsTapped), primary: ready, width: 76, enabled: ready)
        let shortcutButton = onboardingButton("Shortcut", action: #selector(openShortcutSectionTapped), width: 90)
        let actionsButton = onboardingButton("Actions", action: #selector(openActionsSectionTapped), width: 82)
        container.addArrangedSubview(onboardingStepView(
            number: 3,
            title: "Try the Palette",
            detail: ready
                ? "Select text in any app, press \(actionPaletteShortcutText), choose an action, then run it."
                : "Finish connection and permissions first. The default palette shortcut is \(actionPaletteShortcutText).",
            status: ready ? "Ready" : "Locked",
            complete: ready,
            actions: [doneButton, shortcutButton, actionsButton]
        ))

        let wrapper = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 18),
            container.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -18),
            container.topAnchor.constraint(equalTo: wrapper.topAnchor),
            container.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func onboardingHeroView(completedCount: Int, ready: Bool) -> NSView {
        let title = label(ready ? "Jit is ready." : "Finish setup to use Jit.", font: Theme.largeTitleFont, color: .labelColor)
        let subtitle = label(
            ready
                ? "The app can stay in the menu bar. Use the palette shortcut on selected text in any app."
                : "Follow the checklist once. Required settings and permissions are separated from optional preferences.",
            font: Theme.bodyFont,
            color: .secondaryLabelColor
        )
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [textStack, spacer, statusChip(text: ready ? "Ready" : "\(completedCount)/3", allowed: ready)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.widthAnchor.constraint(equalToConstant: Theme.onboardingContentWidth).isActive = true
        return row
    }

    private func setupProgressView(completedCount: Int) -> NSView {
        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 3
        progress.doubleValue = Double(completedCount)
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        let caption = label("\(completedCount) of 3 setup steps complete", font: Theme.captionFont, color: .secondaryLabelColor)
        caption.alignment = .right
        caption.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [progress, caption])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: Theme.onboardingContentWidth).isActive = true
        return row
    }

    private func onboardingStepView(
        number: Int,
        title: String,
        detail: String,
        status: String,
        complete: Bool,
        actions: [NSButton]
    ) -> NSView {
        let icon = NSImageView()
        let symbolName = complete ? "checkmark.circle.fill" : "\(number).circle"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            icon.image = image
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            icon.contentTintColor = complete ? Theme.chipGreenText : .secondaryLabelColor
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let titleLabel = label(title, font: NSFont.systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
        let detailLabel = label(detail, font: Theme.captionFont, color: .secondaryLabelColor)
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.spacing = 3
        textStack.alignment = .leading

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [icon, textStack, spacer, statusChip(text: status, allowed: complete)])
        header.orientation = .horizontal
        header.spacing = 10
        header.alignment = .centerY
        header.distribution = .fill

        let body = NSStackView(views: [header])
        body.orientation = .vertical
        body.spacing = 10
        body.alignment = .leading

        if !actions.isEmpty {
            let actionRow = NSStackView(views: actions)
            actionRow.orientation = .horizontal
            actionRow.spacing = 8
            actionRow.alignment = .centerY
            body.addArrangedSubview(actionRow)
        }

        let card = styledRow(body)
        card.widthAnchor.constraint(equalToConstant: Theme.onboardingContentWidth).isActive = true
        return card
    }

    private func onboardingButton(
        _ title: String,
        action: Selector,
        primary: Bool = false,
        width: CGFloat,
        enabled: Bool = true
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        if primary {
            stylePrimaryButton(button)
        } else {
            styleSecondaryButton(button)
        }
        button.isEnabled = enabled
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        return button
    }

    private func permissionSummaryText() -> String {
        let items = [
            "Accessibility \(AXIsProcessTrusted() ? "Allowed" : "Required")",
            "Input Monitoring \(CGPreflightListenEventAccess() ? "Allowed" : "Required")",
            "Post Events \(CGPreflightPostEventAccess() ? "Allowed" : "Required")"
        ]
        return items.joined(separator: " · ")
    }

    private func connectionSectionView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading

        let requiredLabel = label("Connection Setup", font: Theme.sectionTitleFont, color: .labelColor)
        let requiredHint = label("Set endpoint, API key, and model for requests.", font: Theme.captionFont, color: .secondaryLabelColor)
        requiredHint.maximumNumberOfLines = 2
        let requiredHeader = NSStackView(views: [requiredLabel, requiredHint])
        requiredHeader.orientation = .vertical
        requiredHeader.spacing = 2
        requiredHeader.alignment = .leading
        stack.addArrangedSubview(requiredHeader)

        stack.addArrangedSubview(formRow("Base URL", control: fieldContainer(for: baseURLField, minWidth: 500)))
        stack.addArrangedSubview(apiKeyRow())
        stack.addArrangedSubview(formRow("Model", control: fieldContainer(for: modelField, minWidth: 320)))

        let testButton = NSButton(title: "Test Connection (Translate)", target: self, action: #selector(testTapped))
        styleSecondaryButton(testButton)
        testButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(formRow("Validate", control: testButton))

        let advancedToggle = NSButton(checkboxWithTitle: "Show Advanced Settings", target: self, action: #selector(toggleConnectionAdvanced))
        advancedToggle.font = Theme.bodyFont
        let hasCustomTarget = targetLanguageField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() != AppConfig.defaults.targetLanguage.lowercased()
        advancedToggle.state = hasCustomTarget ? .on : .off
        stack.addArrangedSubview(advancedToggle)

        let advancedStack = NSStackView()
        advancedStack.orientation = .vertical
        advancedStack.spacing = 10
        advancedStack.alignment = .leading
        advancedStack.addArrangedSubview(formRow("Target Language", control: fieldContainer(for: targetLanguageField, minWidth: 320)))
        advancedStack.isHidden = advancedToggle.state != .on
        connectionAdvancedStack = advancedStack
        stack.addArrangedSubview(advancedStack)
        return stack
    }

    private func entrySectionView() -> NSView {
        featureControls.removeAll()
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.alignment = .leading

        let title = label("Action Palette Shortcut", font: Theme.sectionTitleFont, color: .labelColor)
        let subtitle = label("Use one global shortcut to choose Translate, Refine, Vocabulary, or Custom for the selected text.", font: Theme.captionFont, color: .secondaryLabelColor)
        subtitle.maximumNumberOfLines = 2
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.spacing = 2
        header.alignment = .leading
        container.addArrangedSubview(header)

        if let entryFeature = featureConfigs.first(where: { $0.id == "custom" }) {
            let controls = FeatureHotkeyControls(feature: entryFeature)
            controls.recordButton.identifier = NSUserInterfaceItemIdentifier(entryFeature.id)
            controls.recordButton.target = self
            controls.recordButton.action = #selector(recordHotkeyTapped(_:))
            styleInlineButton(controls.recordButton)
            controls.recordButton.widthAnchor.constraint(equalToConstant: 148).isActive = true
            refreshHotkeyPreview(for: controls)
            featureControls[entryFeature.id] = controls

            let shortcutRow = NSStackView(views: [controls.shortcutPreview, controls.recordButton])
            shortcutRow.orientation = .horizontal
            shortcutRow.alignment = .centerY
            shortcutRow.spacing = 10
            shortcutRow.distribution = .fill
            controls.shortcutPreview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            container.addArrangedSubview(formRow("Current Shortcut", control: shortcutRow))
        }

        let hint = label(
            "Click Record Shortcut, then press keys. Existing entry shortcuts are blocked. Press Esc to cancel.",
            font: Theme.captionFont,
            color: .secondaryLabelColor
        )
        hint.maximumNumberOfLines = 2
        container.addArrangedSubview(hint)
        return container
    }

    private func promptsSectionView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.alignment = .leading
        container.addArrangedSubview(sectionHeader(
            title: "AI Actions",
            subtitle: "Tune the four actions available in the floating palette."
        ))

        for feature in featureConfigs {
            let title = label(feature.displayName, font: NSFont.systemFont(ofSize: 14, weight: .semibold), color: .labelColor)
            let subtitle = label(promptSubtitle(for: feature.id), font: Theme.captionFont, color: .secondaryLabelColor)
            let preview = label(promptPreview(for: feature), font: Theme.captionFont, color: .tertiaryLabelColor)
            preview.maximumNumberOfLines = 1
            preview.lineBreakMode = .byTruncatingTail
            let titleStack = NSStackView(views: [title, subtitle, preview])
            titleStack.orientation = .vertical
            titleStack.spacing = 3
            titleStack.alignment = .leading

            let editPrompt = NSButton(title: "Edit Prompt", target: self, action: #selector(editFeaturePromptTapped(_:)))
            editPrompt.identifier = NSUserInterfaceItemIdentifier(feature.id)
            styleInlineButton(editPrompt)
            editPrompt.widthAnchor.constraint(equalToConstant: 102).isActive = true

            let row = NSStackView(views: [titleStack, editPrompt])
            row.orientation = .horizontal
            row.distribution = .fill
            row.alignment = .centerY
            row.spacing = 10
            container.addArrangedSubview(styledRow(row))
        }
        return container
    }

    private func permissionsSectionView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.alignment = .leading
        container.addArrangedSubview(sectionHeader(
            title: "System Permissions",
            subtitle: "Grant access so Jit can read selected text, listen for shortcuts, and paste results."
        ))

        container.addArrangedSubview(permissionStatusRow(
            title: "Accessibility",
            allowed: AXIsProcessTrusted(),
            detail: "Needed to read selected text in other apps.",
            actionTitle: "Open Settings",
            actionSelector: #selector(openAccessibilitySettingsTapped),
            actionToolTip: "Open Privacy & Security -> Accessibility"
        ))
        container.addArrangedSubview(permissionStatusRow(
            title: "Input Monitoring",
            allowed: CGPreflightListenEventAccess(),
            detail: "Needed by some apps to detect global shortcuts.",
            actionTitle: "Open Settings",
            actionSelector: #selector(openInputMonitoringSettingsTapped),
            actionToolTip: "Open Privacy & Security -> Input Monitoring"
        ))
        container.addArrangedSubview(permissionStatusRow(
            title: "Post Events",
            allowed: CGPreflightPostEventAccess(),
            detail: "Needed when replacing text back into target apps.",
            actionTitle: "Open Settings",
            actionSelector: #selector(openPrivacySecuritySettingsTapped),
            actionToolTip: "Open Privacy & Security"
        ))

        let guide = label(
            "Quick Fix: 1) Grant Access, 2) enable Jit APP in System Settings if prompted, 3) return here and the status will refresh.",
            font: Theme.captionFont,
            color: .secondaryLabelColor
        )
        guide.maximumNumberOfLines = 2
        container.addArrangedSubview(guide)

        let actionTitle = label("Permission Actions", font: Theme.sectionTitleFont, color: .labelColor)
        actionTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        container.addArrangedSubview(actionTitle)

        let requestPermissionButton = NSButton(title: "Grant Access", target: self, action: #selector(requestPermissionsTapped))
        stylePrimaryButton(requestPermissionButton)
        let refreshPermissionButton = NSButton(title: "Refresh Status", target: self, action: #selector(refreshPermissionStatusTapped))
        styleSecondaryButton(refreshPermissionButton)
        let diagnoseButton = NSButton(title: "Copy Diagnostics", target: self, action: #selector(diagnosePermissionsTapped))
        styleSecondaryButton(diagnoseButton)
        let resetPermissionsButton = NSButton(title: "Reset Permissions", target: self, action: #selector(resetPermissionsTapped))
        styleDestructiveButton(resetPermissionsButton)
        [requestPermissionButton, refreshPermissionButton, diagnoseButton, resetPermissionsButton].forEach {
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }

        let quickActions = NSStackView(views: [requestPermissionButton, refreshPermissionButton, diagnoseButton])
        quickActions.orientation = .horizontal
        quickActions.spacing = 8
        quickActions.alignment = .centerY
        container.addArrangedSubview(styledRow(quickActions))

        let resetRow = NSStackView(views: [resetPermissionsButton])
        resetRow.orientation = .horizontal
        resetRow.spacing = 8
        resetRow.alignment = .centerY
        container.addArrangedSubview(styledRow(resetRow))
        return container
    }

    private func permissionStatusRow(
        title: String,
        allowed: Bool,
        detail: String,
        actionTitle: String? = nil,
        actionSelector: Selector? = nil,
        actionToolTip: String? = nil
    ) -> NSView {
        let icon = NSImageView()
        if let image = NSImage(systemSymbolName: allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", accessibilityDescription: title) {
            icon.image = image
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            icon.contentTintColor = allowed ? Theme.chipGreenText : Theme.chipOrangeText
        }

        let titleLabel = label(title, font: NSFont.systemFont(ofSize: 13, weight: .medium), color: .labelColor)
        let detailLabel = label(detail, font: Theme.captionFont, color: .secondaryLabelColor)
        detailLabel.maximumNumberOfLines = 2
        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading

        let chip = statusChip(text: allowed ? "Allowed" : "Required", allowed: allowed)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        var rowViews: [NSView] = [icon, textStack, spacer, chip]
        if !allowed, let actionTitle, let actionSelector {
            let openButton = NSButton(title: actionTitle, target: self, action: actionSelector)
            styleInlineButton(openButton)
            openButton.toolTip = actionToolTip
            rowViews.append(openButton)
        }

        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 10
        return styledRow(row)
    }

    private func statusChip(text: String, allowed: Bool) -> NSView {
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.masksToBounds = true
        chip.layer?.backgroundColor = (allowed ? Theme.chipGreenBackground : Theme.chipOrangeBackground).cgColor

        let labelView = label(
            text,
            font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            color: allowed ? Theme.chipGreenText : Theme.chipOrangeText
        )
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

    private func promptSubtitle(for featureID: String) -> String {
        switch featureID {
        case "translate":
            return "Direct translation prompt"
        case "refine":
            return "Rewrite and polish prompt"
        case "custom":
            return "Instruction-driven custom mode"
        case "vocabulary":
            return "English word study prompt"
        default:
            return "Custom prompt template"
        }
    }

    private func promptPreview(for feature: FeatureConfig) -> String {
        let firstLine = feature.promptTemplate
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        if firstLine.isEmpty {
            return "No prompt preview available."
        }
        return firstLine
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
        labelView.widthAnchor.constraint(equalToConstant: 130).isActive = true
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

    private func apiKeyRow() -> NSView {
        let pasteButton = NSButton(title: "Paste", target: self, action: #selector(pasteAPIKey))
        styleInlineButton(pasteButton)
        pasteButton.widthAnchor.constraint(equalToConstant: 78).isActive = true
        let row = NSStackView(views: [fieldContainer(for: apiKeyField, minWidth: 430), pasteButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return formRow("API Key", control: row)
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

    private enum FooterStatusKind {
        case neutral
        case success
        case error
    }

    private func setFooterStatus(_ message: String?, kind: FooterStatusKind = .neutral) {
        guard let footerStatusLabel else { return }
        let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        footerStatusLabel.stringValue = text
        switch kind {
        case .neutral:
            footerStatusLabel.textColor = .secondaryLabelColor
        case .success:
            footerStatusLabel.textColor = Theme.inlineSuccess
        case .error:
            footerStatusLabel.textColor = Theme.inlineError
        }
    }

    private func shortcutDisplay(
        key: String,
        option: Bool,
        command: Bool,
        control: Bool,
        shift: Bool
    ) -> String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(key.uppercased())
        return parts.joined()
    }

    private func hotkeyDisplay(for controls: FeatureHotkeyControls) -> String {
        let key = controls.hotkeyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return "?" }
        return shortcutDisplay(
            key: key,
            option: controls.hotkeyOption,
            command: controls.hotkeyCommand,
            control: controls.hotkeyControl,
            shift: controls.hotkeyShift
        )
    }

    private func refreshHotkeyPreview(for controls: FeatureHotkeyControls) {
        controls.shortcutPreview.stringValue = hotkeyDisplay(for: controls)
    }

    private func stopHotkeyCapture() {
        if let monitor = hotkeyCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyCaptureMonitor = nil
        }
        if let featureID = capturingHotkeyFeatureID,
           let controls = featureControls[featureID] {
            controls.recordButton.title = "Record Shortcut..."
            controls.recordButton.isEnabled = true
            refreshHotkeyPreview(for: controls)
        }
        capturingHotkeyFeatureID = nil
    }

    @objc private func recordHotkeyTapped(_ sender: NSButton) {
        guard let featureID = sender.identifier?.rawValue,
              let controls = featureControls[featureID] else { return }
        stopHotkeyCapture()
        capturingHotkeyFeatureID = featureID
        controls.recordButton.title = "Press keys..."
        controls.recordButton.isEnabled = false
        controls.shortcutPreview.stringValue = "Listening... (Esc to cancel)"
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleHotkeyCapture(event)
        }
    }

    private func handleHotkeyCapture(_ event: NSEvent) -> NSEvent? {
        guard let featureID = capturingHotkeyFeatureID,
              let controls = featureControls[featureID] else {
            stopHotkeyCapture()
            return event
        }
        if event.keyCode == 53 { // Esc
            stopHotkeyCapture()
            return nil
        }

        guard let key = KeyCodeMapper.shared.key(for: UInt32(event.keyCode)) else {
            NSSound.beep()
            return nil
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty {
            controls.shortcutPreview.stringValue = "Add at least one modifier key"
            NSSound.beep()
            return nil
        }

        let option = flags.contains(.option)
        let command = flags.contains(.command)
        let control = flags.contains(.control)
        let shift = flags.contains(.shift)
        let keyUpper = key.uppercased()
        let unchanged = controls.hotkeyKey.uppercased() == keyUpper &&
            controls.hotkeyOption == option &&
            controls.hotkeyCommand == command &&
            controls.hotkeyControl == control &&
            controls.hotkeyShift == shift
        if !unchanged,
           let conflict = conflictingFeature(
               key: keyUpper,
               option: option,
               command: command,
               control: control,
               shift: shift,
               excluding: featureID
           ) {
            controls.shortcutPreview.stringValue = "Already used by \(conflict.displayName): \(shortcutDisplay(key: keyUpper, option: option, command: command, control: control, shift: shift))"
            NSSound.beep()
            return nil
        }

        controls.hotkeyKey = keyUpper
        controls.hotkeyOption = option
        controls.hotkeyCommand = command
        controls.hotkeyControl = control
        controls.hotkeyShift = shift
        refreshHotkeyPreview(for: controls)
        stopHotkeyCapture()
        return nil
    }

    private func conflictingFeature(
        key: String,
        option: Bool,
        command: Bool,
        control: Bool,
        shift: Bool,
        excluding featureID: String
    ) -> FeatureConfig? {
        featureConfigs.first(where: { item in
            item.id != featureID &&
            item.id == "custom" &&
            item.enabled &&
            item.hotkeyKey.uppercased() == key &&
            item.hotkeyOption == option &&
            item.hotkeyCommand == command &&
            item.hotkeyControl == control &&
            item.hotkeyShift == shift
        })
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let textField = NSTextField(labelWithString: text)
        textField.font = font
        textField.textColor = color
        return textField
    }

    private func updateSidebarSelection(_ section: SettingsSection) {
        for (item, button) in sectionButtons {
            let selected = (item == section)
            button.layer?.backgroundColor = selected ? Theme.sidebarSelection.cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? Theme.sidebarText : Theme.sidebarSecondaryText
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium),
                .foregroundColor: selected ? Theme.sidebarText : Theme.sidebarSecondaryText
            ]
            button.attributedTitle = NSAttributedString(string: item.title, attributes: attrs)
        }
    }

    private func assembledFeaturesOrAlert() -> [FeatureConfig]? {
        var result: [FeatureConfig] = []
        for var feature in featureConfigs {
            if feature.id == "custom" {
                if let controls = featureControls[feature.id] {
                    let key = controls.hotkeyKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    guard key.count == 1, KeyCodeMapper.shared.keyCode(for: key) != nil else {
                        setFooterStatus("Entry hotkey key must be a single letter or number.", kind: .error)
                        return nil
                    }
                    feature.hotkeyKey = key
                    feature.hotkeyOption = controls.hotkeyOption
                    feature.hotkeyCommand = controls.hotkeyCommand
                    feature.hotkeyControl = controls.hotkeyControl
                    feature.hotkeyShift = controls.hotkeyShift
                    feature.enabled = true
                    if feature.enabled && feature.modifierFlags.isEmpty {
                        setFooterStatus("Entry hotkey must have at least one modifier key.", kind: .error)
                        return nil
                    }
                } else {
                    feature.enabled = true
                }
            } else {
                // translate/refine are mode-only now; no standalone hotkeys.
                feature.enabled = true
            }
            result.append(feature)
        }
        return result
    }

    private func buildConfigOrShowError() -> AppConfig? {
        if baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setFooterStatus("Base URL / API Key / Model cannot be empty.", kind: .error)
            return nil
        }
        guard let features = assembledFeaturesOrAlert() else { return nil }
        return AppConfig(
            baseURL: baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            model: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            targetLanguage: targetLanguageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            features: features
        )
    }

    @objc private func saveTapped() {
        stopHotkeyCapture()
        guard let config = buildConfigOrShowError() else { return }
        onSave?(config)
        sectionPages[.getStarted] = nil
        if currentSection == .getStarted {
            showSection(.getStarted, animated: false, clearFooter: false)
        }
        setFooterStatus("Saved.", kind: .success)
    }

    @objc private func testTapped() {
        guard let config = buildConfigOrShowError(),
              let feature = config.features.first(where: { $0.id == "translate" }) else { return }
        onTest?(config, feature) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.setFooterStatus("Connection OK. \(message)", kind: .success)
            case .failure(let error):
                self.setFooterStatus("Connection failed: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    @objc private func toggleConnectionAdvanced(_ sender: NSButton) {
        connectionAdvancedStack?.isHidden = sender.state != .on
    }

    @objc private func pasteAPIKey() {
        if let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            apiKeyField.stringValue = text
            sectionPages[.getStarted] = nil
            if currentSection == .getStarted {
                showSection(.getStarted, animated: false, clearFooter: false)
            }
            setFooterStatus("API key pasted.", kind: .success)
        } else {
            setFooterStatus("No usable text found in clipboard.", kind: .error)
        }
    }

    @objc private func openConnectionSectionTapped() {
        showSection(.connection, animated: true)
        window?.makeFirstResponder(apiKeyField)
    }

    @objc private func openPermissionsSectionTapped() {
        showSection(.permissions, animated: true)
    }

    @objc private func openShortcutSectionTapped() {
        showSection(.entry, animated: true)
    }

    @objc private func openActionsSectionTapped() {
        showSection(.prompts, animated: true)
    }

    @objc private func closeSettingsTapped() {
        window?.close()
    }

    @objc private func editFeaturePromptTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let feature = featureConfigs.first(where: { $0.id == id }) else { return }
        openPromptEditor(for: feature)
    }

    private func openPromptEditor(for feature: FeatureConfig) {
        let defaultTemplate = AppConfig.defaultPromptTemplate(for: feature.id)
        let editor = PromptEditorWindowController(currentTemplate: feature.promptTemplate, defaultTemplate: defaultTemplate)
        editor.onSave = { [weak self] newTemplate in
            guard let self else { return }
            if let index = self.featureConfigs.firstIndex(where: { $0.id == feature.id }) {
                self.featureConfigs[index].promptTemplate = newTemplate
                self.setFooterStatus("\(self.featureConfigs[index].displayName) prompt updated. Click Save to apply.", kind: .success)
            }
        }
        editor.showWindow(nil)
        editor.window?.center()
        editor.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        promptEditorWindowController = editor
    }

    @objc private func diagnosePermissionsTapped() {
        let report = onDiagnosePermissions?() ?? "No diagnostics available."
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        let allAllowed = report.contains("Accessibility: Allowed") &&
            report.contains("Input Monitoring (ListenEvent): Allowed") &&
            report.contains("Event Posting (PostEvent): Allowed")
        if allAllowed {
            setFooterStatus("All permissions look good. Diagnostics copied to clipboard.", kind: .success)
        } else {
            setFooterStatus("Some permissions are missing. Diagnostics copied to clipboard.", kind: .error)
        }
    }

    @objc private func requestPermissionsTapped() {
        let report = onRequestPermissions?() ?? "Permission request callback is not provided."
        refreshPermissionStatus(showFooter: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshPermissionStatus(showFooter: false)
        }
        let stillMissing = report.contains("Not Allowed")
        if stillMissing {
            setFooterStatus("Permission prompts requested. Grant access in System Settings, then return to Jit APP.", kind: .neutral)
        } else {
            setFooterStatus("Permissions already granted.", kind: .success)
        }
    }

    @objc private func refreshPermissionStatusTapped() {
        refreshPermissionStatus(showFooter: true)
    }

    @objc private func openPrivacySecuritySettingsTapped() {
        openSystemSettings(
            candidates: [
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
                "x-apple.systempreferences:com.apple.preference.security"
            ],
            successMessage: "Opened System Settings. Go to Privacy & Security."
        )
    }

    @objc private func openAccessibilitySettingsTapped() {
        openSystemSettings(
            candidates: [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ],
            successMessage: "Opened System Settings. Go to Privacy & Security -> Accessibility."
        )
    }

    @objc private func openInputMonitoringSettingsTapped() {
        openSystemSettings(
            candidates: [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ],
            successMessage: "Opened System Settings. Go to Privacy & Security -> Input Monitoring."
        )
    }

    @objc private func resetPermissionsTapped() {
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Reset Permissions?"
        confirm.informativeText = "This resets Jit APP permission records and may require re-granting access in System Settings."
        confirm.addButton(withTitle: "Cancel")
        confirm.addButton(withTitle: "Reset")
        if confirm.runModal() != .alertSecondButtonReturn {
            setFooterStatus("Permission reset canceled.", kind: .neutral)
            return
        }

        let report = onResetPermissions?() ?? "Permission reset callback is not provided."
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        setFooterStatus("Permission reset attempted. Result copied to clipboard. Restart Jit APP afterward.", kind: .neutral)
    }

    private func openSystemSettings(candidates: [String], successMessage: String) {
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                setFooterStatus(successMessage, kind: .neutral)
                return
            }
        }

        let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if NSWorkspace.shared.open(appURL) {
            setFooterStatus("Opened System Settings. Navigate to Privacy & Security manually.", kind: .neutral)
        } else {
            setFooterStatus("Failed to open System Settings.", kind: .error)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig.load()
    private let captureService = SelectionCaptureService()
    private let translationService = TranslationService()
    private let speechService = SpeechService()
    private let loginItemManager = LoginItemManager()
    private let resultWindowController = ResultWindowController()
    private var settingsWindowController: SettingsWindowController?
    private var commandInputWindowController: CommandInputWindowController?
    private var statusItem: NSStatusItem!
    private var loginItemMenuItem: NSMenuItem?
    private var isQuitting = false
    private var suppressReopenSettings = false
    private var isProcessing = false
    private var lastFeatureTriggeredAt: [String: Date] = [:]
    private var launchedAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAt = Date()
        setupMainMenu()
        rebuildStatusBarMenu()
        registerHotkeys()
        if shouldOpenSettingsOnLaunch() {
            presentSettings(showPermissions: false)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        settingsWindowController?.refreshPermissionStatus(showFooter: false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isQuitting { return false }
        if suppressReopenSettings { return false }
        if Date().timeIntervalSince(launchedAt) < 1.5 && !shouldOpenSettingsOnLaunch() {
            return false
        }
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Jit APP", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Jit APP", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Jit APP") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.title = " Jit"

        let menu = NSMenu()
        if let entryFeature = config.features.first(where: { $0.id == "custom" && $0.enabled }) {
            let item = NSMenuItem(title: "Run on Selected Text (\(hotkeyDisplay(for: entryFeature)))", action: #selector(runFeatureFromMenu(_:)), keyEquivalent: "")
            item.representedObject = entryFeature.id
            item.target = self
            menu.addItem(item)
        }
        loginItemMenuItem = NSMenuItem(title: loginItemManager.statusText(), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        if let loginItemMenuItem {
            menu.addItem(loginItemMenuItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { if $0.target == nil { $0.target = self } }
        statusItem.menu = menu
    }

    private func refreshMenuTitle() {
        rebuildStatusBarMenu()
        loginItemMenuItem?.title = loginItemManager.statusText()
    }

    private func hotkeyDisplay(for feature: FeatureConfig) -> String {
        var parts: [String] = []
        if feature.hotkeyControl { parts.append("⌃") }
        if feature.hotkeyOption { parts.append("⌥") }
        if feature.hotkeyShift { parts.append("⇧") }
        if feature.hotkeyCommand { parts.append("⌘") }
        parts.append(feature.hotkeyKey.uppercased())
        return parts.joined()
    }

    private func registerHotkeys() {
        var registrations: [HotKeyManager.Registration] = []
        var nextID: UInt32 = 1
        for feature in config.features where feature.enabled && feature.id == "custom" {
            guard let keyCode = KeyCodeMapper.shared.keyCode(for: feature.hotkeyKey) else {
                showError("\(feature.displayName) hotkey registration failed: invalid key \(feature.hotkeyKey).")
                continue
            }
            let featureID = feature.id
            registrations.append(.init(id: nextID, keyCode: keyCode, modifiers: feature.modifierFlags) { [weak self] in
                self?.handleFeatureTriggered(featureID: featureID)
            })
            nextID += 1
        }
        let ok = HotKeyManager.shared.registerAll(registrations)
        if !ok && !registrations.isEmpty {
            showError("Hotkey registration failed. Check whether key combinations conflict.")
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

    private func executeFeature(featureID: String) {
        guard let feature = config.features.first(where: { $0.id == featureID && $0.enabled }) else { return }
        if shouldOpenSettingsOnLaunch() {
            presentSettings(showPermissions: false)
            return
        }
        if isProcessing { return }
        isProcessing = true
        let sourceApp = NSWorkspace.shared.frontmostApplication

        captureService.captureSelectedText { [weak self] text in
            guard let self else { return }
            guard let text else {
                self.isProcessing = false
                self.presentSettings(showPermissions: false)
                return
            }

            self.isProcessing = false
            let modeIDs = ["custom", "refine", "translate", "vocabulary"]
            let modes = modeIDs.compactMap { id -> CommandInputWindowController.Mode? in
                guard let f = self.config.features.first(where: { $0.id == id && $0.enabled }) else { return nil }
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
            let input = CommandInputWindowController(
                selectedText: text,
                anchor: NSEvent.mouseLocation,
                modes: modes,
                defaultModeID: feature.id
            )
            input.onSubmit = { [weak self] modeID, instruction, onPartial, completion in
                guard let self else { return nil }
                guard let selectedFeature = self.config.features.first(where: { $0.id == modeID && $0.enabled }) else {
                    completion(.failure(NSError(domain: "JitAPP", code: 404, userInfo: [NSLocalizedDescriptionKey: "Selected mode is unavailable."])))
                    return nil
                }
                if self.isProcessing {
                    completion(.failure(NSError(domain: "JitAPP", code: 429, userInfo: [NSLocalizedDescriptionKey: "Please wait for the previous task to finish."])))
                    return nil
                }
                self.isProcessing = true
                return self.translationService.processStreaming(
                    text: text,
                    config: self.config,
                    feature: selectedFeature,
                    instruction: selectedFeature.requiresInstruction ? instruction : nil,
                    onPartial: onPartial
                ) { result in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        completion(result)
                    }
                }
            }
            input.onReplace = { [weak self] output in
                self?.captureService.replaceSelectedText(with: output, targetApp: sourceApp)
            }
            input.onToggleSpeech = { [weak self] selectedText, onStateChange in
                self?.speechService.toggle(text: selectedText, onStateChange: onStateChange) ?? false
            }
            input.onStopSpeech = { [weak self] in
                self?.speechService.stop()
            }
            input.onClose = { [weak self] in
                self?.speechService.stop()
                self?.commandInputWindowController = nil
            }
            suppressReopenSettings = true
            NSApp.activate(ignoringOtherApps: true)
            input.showWindow(nil)
            input.window?.makeKeyAndOrderFront(nil)
            input.window?.orderFrontRegardless()
            input.focus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.activate(ignoringOtherApps: true)
                input.focus()
            }
            input.beginAutoDismiss()
            self.commandInputWindowController = input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.suppressReopenSettings = false
            }
        }
    }

    @objc private func openSettings() {
        presentSettings(showPermissions: false)
    }

    private func presentSettings(showPermissions: Bool) {
        if isQuitting { return }
        if let controller = settingsWindowController, let window = controller.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if showPermissions {
                controller.showPermissionsSection()
            }
            return
        }

        let controller = SettingsWindowController(config: config)
        controller.onSave = { [weak self] newConfig in
            guard let self else { return }
            self.config = newConfig
            self.config.save()
            self.refreshMenuTitle()
            self.registerHotkeys()
        }
        controller.onTest = { [weak self] draftConfig, feature, completion in
            guard let self else { return }
            self.translationService.process(text: "hello", config: draftConfig, feature: feature) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let translated):
                        completion(.success("Request succeeded. Example response: \(translated)"))
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
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if showPermissions {
            controller.showPermissionsSection()
        } else {
            controller.showGetStartedSection()
        }
        settingsWindowController = controller
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try loginItemManager.toggle()
            refreshMenuTitle()
            if SMAppService.mainApp.status == .requiresApproval {
                showError("System approval is required for Launch at Login. Go to System Settings -> General -> Login Items.")
            }
        } catch {
            showError("Failed to update Launch at Login: \(error.localizedDescription)")
        }
    }

    @objc private func quit() {
        isQuitting = true
        settingsWindowController?.window?.close()
        settingsWindowController = nil
        HotKeyManager.shared.unregister()
        NSApp.terminate(nil)
    }

    private var hasRequiredPermissions: Bool {
        AXIsProcessTrusted() &&
            CGPreflightListenEventAccess() &&
            CGPreflightPostEventAccess()
    }

    private func shouldOpenSettingsOnLaunch() -> Bool {
        !config.hasRequiredConnectionSettings || !hasRequiredPermissions
    }

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

        return permissionReport() + "\n\nIf it still shows not allowed, enable permissions manually in System Settings and restart Jit APP."
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
        lines.append("Then restart Jit APP.")
        return lines.joined(separator: "\n")
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Jit APP"
        alert.informativeText = message
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
