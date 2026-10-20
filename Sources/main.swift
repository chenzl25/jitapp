import AVFoundation
import AppKit
import Carbon.HIToolbox
import Foundation
import NaturalLanguage
import ServiceManagement
import JitCLI

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
    var backend: AIBackend
    var codexPath: String
    var codexModel: String
    var claudePath: String
    var claudeModel: String
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
    You are an English vocabulary coach for a Chinese-speaking learner. Explain the selected English word or phrase.

    Reply in exactly this plain-text format, with no markdown and no extra sections:
    Headword: <the word or phrase to learn>
    Part of speech: <adj / noun / verb / phrase …>
    IPA: /<IPA>/
    Meaning: <Chinese meaning> — <short English definition>
    Usage:
    - <common collocation, 2-4 words>
    - <common collocation, 2-4 words>
    - <common collocation, 2-4 words>
    Examples:
    - <short English example sentence> | <Chinese translation>
    - <short English example sentence> | <Chinese translation>
    Notes: <one short note on register, common mistakes or similar words; omit this line if not useful>

    If the text is a whole sentence, pick its most useful word or phrase as the headword.

    Text:
    {{text}}
    """

    /// Earlier built-in Words prompts; a saved copy that still matches one is upgraded
    /// so the palette can render the structured Words card.
    static let legacyVocabularyPromptTemplates = [
        """
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
        """,
    ]

    static let defaults = AppConfig(
        backend: .codexCLI,
        codexPath: "",
        codexModel: "",
        claudePath: "",
        claudeModel: "",
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
                displayName: "Polish",
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
                displayName: "Words",
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
        case "refine": item.displayName = "Polish"
        case "custom": item.displayName = "Custom"
        case "vocabulary": item.displayName = "Words"
        default: break
        }
        let trimmed = item.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            item.promptTemplate = defaultPromptTemplate(for: item.id)
        } else if item.id == "vocabulary",
                  legacyVocabularyPromptTemplates.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }) {
            item.promptTemplate = defaultVocabularyPromptTemplate
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
        config.backend = AIBackend.load(savedValue: d.string(forKey: "aiBackend"), apiKey: config.apiKey)
        // A new user with only Claude Code installed starts on Claude instead
        // of a Codex setup prompt.
        if d.string(forKey: "aiBackend") == nil, config.backend == .codexCLI,
           LocalCLI.executable(for: .codex) == nil, LocalCLI.executable(for: .claude) != nil {
            config.backend = .claudeCLI
        }
        config.codexPath = d.string(forKey: "codexPath") ?? ""
        config.codexModel = d.string(forKey: "codexModel") ?? ""
        config.claudePath = d.string(forKey: "claudePath") ?? ""
        config.claudeModel = d.string(forKey: "claudeModel") ?? ""
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

    /// The selected local CLI with its path and model, or nil for API mode.
    var localCLI: (tool: LocalCLITool, path: String, model: String)? {
        switch backend {
        case .codexCLI: return (.codex, codexPath, codexModel)
        case .claudeCLI: return (.claude, claudePath, claudeModel)
        case .chatAPI: return nil
        }
    }

    var hasRequiredConnectionSettings: Bool {
        if let cli = localCLI { return LocalCLI.executable(for: cli.tool, path: cli.path) != nil }
        return !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var connectionSetupMessage: String {
        guard let cli = localCLI else { return "Add an API endpoint, key, and model to start running actions." }
        return "Install \(cli.tool.displayName) and run \(cli.tool.loginCommand) in Terminal, or choose another AI connection."
    }

    var connectionModelName: String {
        guard let cli = localCLI else { return model }
        return cli.model.isEmpty ? "\(cli.tool.displayName) default" : cli.model
    }

    /// Header chip text in the palette: "Codex · gpt-5.1", "Claude Code · default", or the API model.
    var connectionShortLabel: String {
        guard let cli = localCLI else { return model.oneLinePreview(32) }
        let name = cli.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cli.tool.displayName) · \(name.isEmpty ? "default" : name.oneLinePreview(24))"
    }

    /// "English → 简体中文" for the Translate selection card.
    func translationDirectionLabel(for text: String) -> String {
        let target = TranslationLanguage.nativeName(for: effectiveTargetLanguage(for: text))
        guard let dominant = LanguageDetector.dominantLanguage(of: text),
              let source = TranslationLanguage.all.first(where: { LanguageDetector.matches(languageName: $0.name, dominant) }) else {
            return "Auto → \(target)"
        }
        return "\(source.native) → \(target)"
    }

    func save() {
        let d = UserDefaults.standard
        d.set(backend.rawValue, forKey: "aiBackend")
        d.set(codexPath, forKey: "codexPath")
        d.set(codexModel, forKey: "codexModel")
        d.set(claudePath, forKey: "claudePath")
        d.set(claudeModel, forKey: "claudeModel")
        d.set(baseURL, forKey: "baseURL")
        d.set(apiKey, forKey: "apiKey")
        d.set(model, forKey: "model")
        d.set(targetLanguage, forKey: "targetLanguage")
        if let data = try? JSONEncoder().encode(features) {
            d.set(data, forKey: "featureConfigs")
        }
    }

    static let generalInstructionPromptTemplate = """
    You are a helpful assistant. Respond to the user's request directly and concisely.

    User request:
    {{instruction}}
    """

    func resolvedPrompt(for feature: FeatureConfig, text: String, instruction: String? = nil) -> String {
        var template = feature.promptTemplate.isEmpty ? AppConfig.defaultPromptTemplate(for: feature.id) : feature.promptTemplate
        // With no selection, an instruction-only feature acts as a general prompt box.
        if feature.requiresInstruction, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            template = AppConfig.generalInstructionPromptTemplate
        }
        return template
            .replacingOccurrences(of: "{{targetLanguage}}", with: effectiveTargetLanguage(for: text))
            .replacingOccurrences(of: "{{instruction}}", with: instruction ?? "")
            .replacingOccurrences(of: "{{text}}", with: text)
    }

    /// Flips the translation direction when the text is already in the target language:
    /// e.g. Chinese → English, and English → Chinese when English is the configured target.
    func effectiveTargetLanguage(for text: String) -> String {
        let target = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dominant = LanguageDetector.dominantLanguage(of: text),
              LanguageDetector.matches(languageName: target, dominant) else { return target }
        return LanguageDetector.matches(languageName: "English", dominant) ? "Chinese" : "English"
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
    struct Selection {
        let text: String
        let bounds: NSRect?
    }

    /// Fast path: read the selection through Accessibility synchronously.
    /// Must run before Jit activates itself so the source app still owns focus.
    func readSelectionViaAccessibility() -> Selection? {
        guard AXIsProcessTrusted(), let element = focusedElement() else { return nil }
        guard let text = readDirectSelectedText(from: element)
            ?? readSelectedTextByRange(from: element)
            ?? readSelectedTextByRanges(from: element) else { return nil }
        return Selection(text: text, bounds: selectionBounds(from: element))
    }

    /// Slow path: simulate ⌘C in the frontmost app and read the pasteboard, restoring it afterwards.
    func captureSelectedTextViaCopy(completion: @escaping @MainActor (String?) -> Void) {
        // Wait a moment for global hotkey modifiers (e.g. Option) to be released,
        // otherwise some editors may treat simulated Cmd+C as a different shortcut.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let snapshot = PasteboardSnapshot.capture()
            let oldCount = NSPasteboard.general.changeCount
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

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard status == .success, let focusedRef else { return nil }
        return (focusedRef as! AXUIElement)
    }

    /// Screen rectangle of the selected range in Cocoa coordinates (bottom-left origin), when the app exposes it.
    private func selectionBounds(from element: AXUIElement) -> NSRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        let value = boundsRef as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect),
              rect.width > 0 || rect.height > 0, rect.width < 20_000, rect.height < 20_000 else { return nil }
        guard let primary = NSScreen.screens.first else { return nil }
        let flippedY = primary.frame.maxY - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }

    private func readDirectSelectedText(from element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef)
        guard selectedStatus == .success, let selectedText = selectedRef as? String else { return nil }
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readSelectedTextByRange(from element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard rangeStatus == .success, let rangeRef else { return nil }
        return readTextByRangeValue(rangeRef, from: element)
    }

    private func readSelectedTextByRanges(from element: AXUIElement) -> String? {
        var rangesRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangesAttribute as CFString, &rangesRef)
        guard status == .success, let ranges = rangesRef as? [Any], let first = ranges.first else { return nil }
        return readTextByRangeValue(first as CFTypeRef, from: element)
    }

    private func readTextByRangeValue(_ valueRef: CFTypeRef, from element: AXUIElement) -> String? {
        guard CFGetTypeID(valueRef) == AXValueGetTypeID() else { return nil }
        let axValue = valueRef as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var cfRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &cfRange) else { return nil }
        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
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
        if let cli = config.localCLI {
            _ = LocalCLI.run(tool: cli.tool, prompt: config.resolvedPrompt(for: feature, text: text, instruction: instruction), model: cli.model, path: cli.path, completion: completion)
            return
        }
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
                    completion(.failure(TranslationService.httpError(status: http.statusCode, body: data)))
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
        if let cli = config.localCLI {
            let run = LocalCLI.run(tool: cli.tool, prompt: config.resolvedPrompt(for: feature, text: text, instruction: instruction), model: cli.model, path: cli.path, onPartial: onPartial, completion: completion)
            return TextProcessingRun(cancelHandler: { run.cancel() }, retaining: [run])
        }
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
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(stream == true ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    static func httpError(status: Int, body: Data?) -> NSError {
        let raw = body.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = raw.count > 240 ? String(raw.prefix(240)) + "…" : raw
        let message: String
        switch status {
        case 401, 403:
            message = "API key was rejected (\(status)). Check the key and Base URL in Settings."
        case 404:
            message = "Endpoint not found (404). Check the Base URL and model name in Settings."
        case 429:
            message = "Rate limited (429). Wait a moment and retry."
        case 500...599:
            message = "The API service returned \(status). Retry in a moment."
        default:
            message = "Request failed (\(status))."
        }
        return NSError(
            domain: "Translator",
            code: status,
            userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? message : "\(message)\n\(detail)"]
        )
    }

}

@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var stateHandler: ((Bool) -> Void)?
    private(set) var voice: AVSpeechSynthesisVoice?

    static let voiceDefaultsKey = "speechVoiceIdentifier"

    override init() {
        super.init()
        voice = Self.savedVoice() ?? Self.preferredEnglishVoice()
        synthesizer.delegate = self
    }

    /// The voice chosen in Settings, or nil for automatic (best installed).
    var selectedVoiceIdentifier: String? {
        Self.savedVoice()?.identifier
    }

    func selectVoice(identifier: String?) {
        if let identifier, AVSpeechSynthesisVoice(identifier: identifier) != nil {
            UserDefaults.standard.set(identifier, forKey: Self.voiceDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.voiceDefaultsKey)
        }
        stop()
        voice = Self.savedVoice() ?? Self.preferredEnglishVoice()
    }

    private static func savedVoice() -> AVSpeechSynthesisVoice? {
        UserDefaults.standard.string(forKey: voiceDefaultsKey).flatMap(AVSpeechSynthesisVoice.init(identifier:))
    }

    /// Installed English voices, best first, without novelty voices.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") && score($0) > -500 }
            .sorted { score($0) > score($1) || (score($0) == score($1) && $0.name < $1.name) }
    }

    var voiceDescription: String {
        guard let voice else { return "System default" }
        return "\(voice.name) · \(Self.qualityLabel(voice.quality)) · \(voice.language)"
    }

    var hasHighQualityVoice: Bool {
        voice.map { $0.quality != .default } ?? false
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
        let utterance = AVSpeechUtterance(string: normalized)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
        onStateChange(true)
        return true
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish()
    }

    private func finish() {
        stateHandler?(false)
        stateHandler = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    /// Best installed English voice: premium > enhanced > compact, preferring en-US, skipping novelty voices.
    static func preferredEnglishVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .max { score($0) < score($1) }
    }

    private static func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        var value = 0
        switch voice.quality {
        case .premium: value += 300
        case .enhanced: value += 200
        default: break
        }
        switch voice.language {
        case "en-US": value += 30
        case "en-GB": value += 20
        default: value += 10
        }
        let identifier = voice.identifier.lowercased()
        if identifier.contains("super-compact") {
            value -= 50
        }
        // Skip Eloquence and the legacy/novelty "com.apple.speech.synthesis.voice.*" voices.
        if identifier.contains("eloquence") || identifier.contains("speech.synthesis.voice") {
            value -= 1000
        }
        return value
    }

    static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Compact"
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
        closeWindow()
    }

    @objc private func closeWindow() {
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
}

// MARK: - Result history

struct HistoryEntry: Codable, Sendable {
    let id: UUID
    let modeID: String
    let modeTitle: String
    let selectedText: String
    let instruction: String?
    let output: String
    let date: Date
}

@MainActor
final class HistoryStore {
    static let shared = HistoryStore()
    private static let defaultsKey = "resultHistory"
    private static let limit = 30

    private(set) var entries: [HistoryEntry] = []
    var onChange: (() -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func entry(withID id: String) -> HistoryEntry? {
        entries.first { $0.id.uuidString == id }
    }

    /// Most recent distinct Custom instructions, newest first.
    func recentInstructions(limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries where entry.modeID == "custom" {
            guard let instruction = entry.instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty,
                  seen.insert(instruction.lowercased()).inserted else { continue }
            result.append(instruction)
            if result.count == limit { break }
        }
        return result
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        onChange?()
    }
}

extension String {
    /// Single-line preview for menus and hints.
    func oneLinePreview(_ maxLength: Int) -> String {
        let collapsed = self
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > maxLength ? String(collapsed.prefix(maxLength)) + "…" : collapsed
    }
}

// MARK: - Language detection (auto translation direction)

enum LanguageDetector {
    static func dominantLanguage(of text: String) -> NLLanguage? {
        let sample = String(text.prefix(400))
        guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        return confidence >= 0.5 ? language : nil
    }

    static func matches(languageName: String, _ language: NLLanguage) -> Bool {
        let name = languageName.lowercased()
        let table: [(keys: [String], languages: [NLLanguage])] = [
            (["chinese", "中文", "汉语", "zh"], [.simplifiedChinese, .traditionalChinese]),
            (["english", "英语", "en"], [.english]),
            (["japanese", "日语", "ja"], [.japanese]),
            (["korean", "韩语", "ko"], [.korean]),
            (["french", "fr"], [.french]),
            (["german", "de"], [.german]),
            (["spanish", "es"], [.spanish]),
            (["portuguese", "pt"], [.portuguese]),
            (["italian", "it"], [.italian]),
            (["russian", "ru"], [.russian]),
        ]
        for row in table where row.keys.contains(where: { name == $0 || name.contains($0) && $0.count > 2 }) {
            return row.languages.contains(language)
        }
        return false
    }
}

/// Target languages offered in Settings. `name` is stored and sent to the prompt; `native` is shown.
enum TranslationLanguage {
    static let all: [(name: String, native: String)] = [
        ("Chinese", "简体中文"), ("English", "English"), ("Japanese", "日本語"), ("Korean", "한국어"),
        ("French", "Français"), ("German", "Deutsch"), ("Spanish", "Español"), ("Portuguese", "Português"),
        ("Italian", "Italiano"), ("Russian", "Русский"),
    ]

    static func nativeName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })?.native ?? trimmed
    }
}

// MARK: - Friendly error messages

enum FriendlyError {
    /// Maps transport and API errors to a short actionable message.
    /// `needsSettings` is true when the fix most likely lives in Settings.
    static func describe(_ error: Error) -> (message: String, needsSettings: Bool) {
        if let cliError = error as? LocalCLIError {
            return (cliError.localizedDescription, cliError.needsSettings)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return ("No internet connection.", false)
            case .timedOut:
                return ("The request timed out. Check the Base URL or try again.", true)
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
                return ("Cannot reach the API server. Check the Base URL in Settings.", true)
            case .cancelled:
                return ("Canceled.", false)
            default:
                return ("Network error: \(urlError.localizedDescription)", false)
            }
        }
        let nsError = error as NSError
        let detail = shortDetail(nsError.localizedDescription)
        switch nsError.code {
        case 400:
            return ("The API rejected the request (400). Check the model name in Settings.\n\(detail)", true)
        case 401, 403:
            return ("API key missing or rejected (\(nsError.code)). Open Settings to fix it.", true)
        case 402:
            return ("The API account has insufficient balance (402).", true)
        case 404:
            return ("Model or Base URL not found (404). Check Settings.", true)
        case 429:
            return ("Rate limited (429). Wait a moment and retry.", false)
        case 500...599:
            return ("The API service returned \(nsError.code). Retry in a moment.", false)
        default:
            return (nsError.localizedDescription, false)
        }
    }

    private static func shortDetail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 240 ? String(trimmed.prefix(240)) + "…" : trimmed
    }
}

let app = NSApplication.shared
#if DEBUG
if SnapshotRenderer.runIfRequested() { exit(0) }
#endif
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
