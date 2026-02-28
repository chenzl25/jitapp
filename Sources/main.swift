import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
            )
        ]
    )

    static func load() -> AppConfig {
        let d = UserDefaults.standard
        var config = AppConfig.defaults
        if let value = d.string(forKey: "baseURL") { config.baseURL = value }
        if let value = d.string(forKey: "apiKey") { config.apiKey = value }
        if let value = d.string(forKey: "model") { config.model = value }
        if let value = d.string(forKey: "targetLanguage") { config.targetLanguage = value }
        if let featuresData = d.data(forKey: "featureConfigs"),
           let decoded = try? JSONDecoder().decode([FeatureConfig].self, from: featuresData),
           !decoded.isEmpty {
            config.features = decoded.map { feature in
                var item = feature
                switch item.id {
                case "translate": item.displayName = "Translate"
                case "refine": item.displayName = "Refine"
                case "custom": item.displayName = "Custom"
                default: break
                }
                return item
            }
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
        let template = feature.promptTemplate.isEmpty ? AppConfig.defaultTranslationPromptTemplate : feature.promptTemplate
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

    func keyCode(for key: String) -> UInt32? {
        keyToCode[key.uppercased()]
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

final class TranslationService {
    func process(
        text: String,
        config: AppConfig,
        feature: FeatureConfig,
        instruction: String? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        guard !config.apiKey.isEmpty else {
            completion(.failure(NSError(domain: "Translator", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please set API Key in Settings first."])))
            return
        }

        let urlString = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Translator", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Base URL."])))
            return
        }

        let prompt = config.resolvedPrompt(for: feature, text: text, instruction: instruction)
        let requestBody = ChatRequest(
            model: config.model,
            messages: [
                .init(role: "system", content: "You are a professional translator."),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(error))
            return
        }

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
    private let copyButton = NSButton(title: "Copy All", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var onReplace: (() -> Void)?

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
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)
        panel.delegate = self

        let container = NSVisualEffectView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.material = .windowBackground
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        copyButton.target = self
        copyButton.action = #selector(copyAllText)
        copyButton.bezelStyle = .rounded
        copyButton.font = NSFont.systemFont(ofSize: 12)
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        replaceButton.target = self
        replaceButton.action = #selector(replaceTapped)
        replaceButton.bezelStyle = .rounded
        replaceButton.font = NSFont.systemFont(ofSize: 12)
        replaceButton.translatesAutoresizingMaskIntoConstraints = false
        replaceButton.isHidden = true

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
        textView.textColor = NSColor(calibratedWhite: 0.1, alpha: 1.0)
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
        container.addSubview(copyButton)
        container.addSubview(replaceButton)
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: replaceButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),

            copyButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            replaceButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            replaceButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

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

    func showPending(selectedText: String, featureName: String) {
        replaceButton.isHidden = true
        onReplace = nil
        titleLabel.stringValue = "Jit APP · \(featureName)"
        textView.string = "Selected Text\n\(preview(selectedText))\n\nStatus\nRunning \(featureName)..."
        presentNearCursor()
    }

    func showResult(
        selectedText: String,
        output: String,
        featureName: String,
        outputLabel: String,
        allowReplace: Bool = false,
        onReplace: (() -> Void)? = nil
    ) {
        replaceButton.isHidden = !allowReplace
        self.onReplace = onReplace
        titleLabel.stringValue = "Jit APP · \(featureName)"
        textView.string = "Selected Text\n\(preview(selectedText))\n\n\(outputLabel)\n\(output)"
        presentNearCursor()
    }

    func showError(_ message: String, selectedText: String? = nil, featureName: String = "Jit APP") {
        replaceButton.isHidden = true
        onReplace = nil
        titleLabel.stringValue = "Jit APP · \(featureName)"
        if let selectedText {
            textView.string = "Selected Text\n\(preview(selectedText))\n\nError\n\(message)"
        } else {
            textView.string = "Error\n\(message)"
        }
        presentNearCursor()
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

    @objc private func copyAllText() {
        let all = textView.string
        guard !all.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(all, forType: .string)
    }

    @objc private func replaceTapped() {
        onReplace?()
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
        scroll.backgroundColor = .white

        if let editor = scroll.documentView as? NSTextView {
            editor.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            editor.insertionPointColor = .black
            editor.drawsBackground = true
            editor.backgroundColor = .white
            editor.typingAttributes = [
                .foregroundColor: NSColor.black,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ]
            let attr = NSAttributedString(
                string: currentTemplate,
                attributes: [
                    .foregroundColor: NSColor.black,
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
    struct Mode {
        let id: String
        let title: String
        let requiresInstruction: Bool
        let promptPreview: String
    }

    private let commandField = NSTextField(string: "")
    private let hintLabel = NSTextField(labelWithString: "Type an instruction and press Enter. Esc to cancel.")
    private let outputTextView = NSTextView()
    private let outputScroll = NSScrollView()
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var expanded = false
    private let modes: [Mode]
    private var currentModeIndex: Int = 0
    private let selectedPreview: String
    private var customInstructionDraft: String = ""
    var onSubmit: ((String, String?, @escaping @Sendable (Result<String, Error>) -> Void) -> Void)?
    var onReplace: ((String) -> Void)?
    var onClose: (() -> Void)?

    init(selectedText: String, anchor: NSPoint, modes: [Mode], defaultModeID: String = "custom") {
        self.modes = modes.isEmpty ? [Mode(id: "custom", title: "Custom", requiresInstruction: true, promptPreview: "Custom instruction mode")] : modes
        self.selectedPreview = selectedText.count > 80 ? String(selectedText.prefix(80)) + "..." : selectedText
        let panel = BubblePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.delegate = self
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
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1.0).cgColor

        hintLabel.stringValue = "Run on selected text: \(selectedPreview)"
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        commandField.placeholderString = "Type instruction..."
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.font = NSFont.systemFont(ofSize: 15)

        outputScroll.translatesAutoresizingMaskIntoConstraints = false
        outputScroll.hasVerticalScroller = true
        outputScroll.borderType = .bezelBorder
        outputScroll.drawsBackground = true
        outputScroll.backgroundColor = .textBackgroundColor
        outputScroll.isHidden = true

        outputTextView.isEditable = true
        outputTextView.isSelectable = true
        outputTextView.drawsBackground = true
        outputTextView.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 1.0)
        outputTextView.font = NSFont.systemFont(ofSize: 14)
        outputTextView.textColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        outputTextView.insertionPointColor = NSColor(calibratedWhite: 0.1, alpha: 1.0)
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
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
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

        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.isHidden = true

        replaceButton.target = self
        replaceButton.action = #selector(replaceTapped)
        replaceButton.bezelStyle = .rounded
        replaceButton.translatesAutoresizingMaskIntoConstraints = false
        replaceButton.isHidden = true

        contentView.addSubview(container)
        container.addSubview(hintLabel)
        container.addSubview(commandField)
        container.addSubview(outputScroll)
        container.addSubview(copyButton)
        container.addSubview(replaceButton)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            hintLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),

            commandField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            commandField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            commandField.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            commandField.heightAnchor.constraint(equalToConstant: 32),

            outputScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            outputScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            outputScroll.topAnchor.constraint(equalTo: commandField.bottomAnchor, constant: 8),
            outputScroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -8),

            replaceButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            replaceButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            copyButton.trailingAnchor.constraint(equalTo: replaceButton.leadingAnchor, constant: -8),
            copyButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
    }

    func focus() {
        window?.makeFirstResponder(commandField)
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
        let mode = modes[currentModeIndex]
        let rawInstruction = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode.requiresInstruction && rawInstruction.isEmpty { return }
        let instruction = mode.requiresInstruction ? rawInstruction : nil
        setLoadingState(true)
        onSubmit?(mode.id, instruction) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                self.setLoadingState(false)
                self.expandForOutputIfNeeded()
                switch result {
                case .success(let output):
                    self.setOutputText(output)
                    self.window?.makeFirstResponder(self.outputTextView)
                    self.copyButton.isHidden = false
                    self.replaceButton.isHidden = false
                case .failure(let error):
                    self.setOutputText("Failed: \(error.localizedDescription)")
                    self.window?.makeFirstResponder(self.outputTextView)
                    self.copyButton.isHidden = true
                    self.replaceButton.isHidden = true
                }
            }
        }
    }

    @objc private func cancelTapped() {
        window?.close()
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
    }

    func windowWillClose(_ notification: Notification) {
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
            if event.keyCode == 53 { // ESC
                self.cancelTapped()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
                self.runTapped()
                return nil
            }
            if event.keyCode == 126 { // Up
                self.moveMode(delta: -1)
                return nil
            }
            if event.keyCode == 125 { // Down
                self.moveMode(delta: 1)
                return nil
            }
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
            window.close()
        }
    }

    private func setLoadingState(_ loading: Bool) {
        let mode = modes[currentModeIndex]
        commandField.isEnabled = !loading && mode.requiresInstruction
        commandField.isEditable = mode.requiresInstruction
        copyButton.isEnabled = !loading
        replaceButton.isEnabled = !loading
        if loading {
            expandForOutputIfNeeded()
            setOutputText("Processing...")
            copyButton.isHidden = true
            replaceButton.isHidden = true
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

    private func refreshModeUI() {
        let mode = modes[currentModeIndex]
        hintLabel.stringValue = "Mode: \(mode.title)  (↑/↓ switch) · Enter run · Esc close\nSelected: \(selectedPreview)"
        hintLabel.maximumNumberOfLines = 2
        if mode.requiresInstruction {
            commandField.isEditable = true
            commandField.isEnabled = true
            commandField.placeholderString = "Instruction for \(mode.title)..."
            commandField.stringValue = customInstructionDraft
        } else {
            commandField.isEditable = false
            commandField.isEnabled = false
            commandField.placeholderString = ""
            commandField.stringValue = "System Prompt: \(mode.promptPreview)"
        }
    }

    private func setOutputText(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = normalized.isEmpty ? "(No content returned)" : text
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
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

    private func expandForOutputIfNeeded() {
        guard let window, !expanded else {
            outputScroll.isHidden = false
            return
        }
        expanded = true
        outputScroll.isHidden = false
        var frame = window.frame
        frame.origin.y -= 280
        frame.size.height += 280
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
final class SettingsWindowController: NSWindowController {
    @MainActor
    private enum Theme {
        static let bg0 = NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
        static let bg1 = NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 0.9)
        static let bg2 = NSColor(srgbRed: 0.22, green: 0.24, blue: 0.28, alpha: 1.0)
        static let stroke = NSColor.white.withAlphaComponent(0.10)
        static let textPrimary = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1.0)
        static let textSecondary = NSColor(srgbRed: 0.72, green: 0.75, blue: 0.80, alpha: 1.0)
        static let accent = NSColor(srgbRed: 0.40, green: 0.78, blue: 1.0, alpha: 1.0)
        static let accentStrong = NSColor(srgbRed: 0.33, green: 0.72, blue: 0.96, alpha: 1.0)

        static let windowPadding: CGFloat = 24
        static let sectionSpacing: CGFloat = 16
        static let cardPadding: CGFloat = 20
        static let rowSpacing: CGFloat = 12

        static let cardCorner: CGFloat = 16
        static let fieldCorner: CGFloat = 10
        static let buttonCorner: CGFloat = 14

        static let heroTitleFont = NSFont.systemFont(ofSize: 44, weight: .semibold)
        static let sectionTitleFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
        static let rowTitleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
        static let bodyFont = NSFont.systemFont(ofSize: 14)
        static let smallFont = NSFont.systemFont(ofSize: 13)

        static let entranceDuration: TimeInterval = 0.24
        static let entranceStagger: TimeInterval = 0.05
    }

    private enum ButtonStyle {
        case primary
        case secondary
        case ghost
        case accentText
    }

    @MainActor
    final class GradientOverlayView: NSView {
        private let baseGradient = CAGradientLayer()
        private let glowGradient = CAGradientLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            setupLayers()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            baseGradient.frame = bounds
            glowGradient.frame = bounds
        }

        private func setupLayers() {
            guard let root = layer else { return }
            root.masksToBounds = true

            baseGradient.startPoint = CGPoint(x: 0.0, y: 1.0)
            baseGradient.endPoint = CGPoint(x: 1.0, y: 0.0)
            baseGradient.colors = [
                NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0).cgColor,
                NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1.0).cgColor
            ]

            glowGradient.startPoint = CGPoint(x: 0.0, y: 0.5)
            glowGradient.endPoint = CGPoint(x: 0.35, y: 0.5)
            glowGradient.colors = [
                Theme.accent.withAlphaComponent(0.18).cgColor,
                Theme.accent.withAlphaComponent(0.02).cgColor,
                NSColor.clear.cgColor
            ]

            root.addSublayer(baseGradient)
            root.addSublayer(glowGradient)
        }
    }

    @MainActor
    final class FeatureHotkeyControls {
        let id: String
        let keyField = NSTextField(string: "")
        let optionButton = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
        let commandButton = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
        let controlButton = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
        let shiftButton = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
        let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)

        init(id: String) {
            self.id = id
            keyField.alignment = .center
            keyField.placeholderString = "Key"
            keyField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
            keyField.drawsBackground = false
            keyField.isBordered = false
            keyField.focusRingType = .none
            keyField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        }
    }

    private let baseURLField = NSTextField(string: "")
    private let apiKeyField = NSTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let targetLanguageField = NSTextField(string: "")
    private var featureConfigs: [FeatureConfig] = []
    private var featureControls: [String: FeatureHotkeyControls] = [:]
    private var promptEditorWindowController: PromptEditorWindowController?
    private var entranceViews: [NSView] = []
    private var didRunEntranceAnimation = false

    var onSave: ((AppConfig) -> Void)?
    var onQuit: (() -> Void)?
    var onTest: ((AppConfig, FeatureConfig, @escaping @MainActor (Result<String, Error>) -> Void) -> Void)?
    var onDiagnosePermissions: (() -> String)?
    var onRequestPermissions: (() -> String)?
    var onResetPermissions: (() -> String)?

    init(config: AppConfig) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 740),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jit APP Settings"
        window.minSize = NSSize(width: 860, height: 620)
        window.isOpaque = false
        window.backgroundColor = .clear
        super.init(window: window)

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

    func focusPrimaryField() {
        window?.makeFirstResponder(apiKeyField)
    }

    private func configureInputFields() {
        [baseURLField, apiKeyField, modelField, targetLanguageField].forEach { field in
            field.font = Theme.bodyFont
            field.textColor = Theme.textPrimary
            field.drawsBackground = false
            field.isBordered = false
            field.focusRingType = .none
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        setupWindowBackground(contentView)
        entranceViews.removeAll()

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = Theme.sectionSpacing
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let hero = heroView()
        contentStack.addArrangedSubview(hero)
        entranceViews.append(hero)

        let basic = NSStackView()
        basic.orientation = .vertical
        basic.spacing = Theme.rowSpacing
        basic.addArrangedSubview(row("Base URL", field: fieldContainer(for: baseURLField, minWidth: 560)))
        basic.addArrangedSubview(apiKeyRow())
        basic.addArrangedSubview(row("Model", field: fieldContainer(for: modelField, minWidth: 420)))
        basic.addArrangedSubview(row("Target Language", field: fieldContainer(for: targetLanguageField, minWidth: 420)))
        let testButton = NSButton(title: "Test Connection (Translate)", target: self, action: #selector(testTapped))
        styleButton(testButton, style: .secondary)
        testButton.widthAnchor.constraint(equalToConstant: 230).isActive = true
        basic.addArrangedSubview(testButton)
        let basicCard = cardView(
            title: "API Configuration",
            subtitle: "Set provider endpoint, credentials, and output language.",
            content: basic
        )
        contentStack.addArrangedSubview(basicCard)
        entranceViews.append(basicCard)

        let featuresCard = cardView(
            title: "Unified Entry",
            subtitle: "Configure Option+A entry hotkey and edit prompts per mode.",
            content: featuresRow()
        )
        contentStack.addArrangedSubview(featuresCard)
        entranceViews.append(featuresCard)

        let permissionsCard = cardView(
            title: "Permissions",
            subtitle: "Read selection and automation require system permissions.",
            content: permissionsPanel()
        )
        contentStack.addArrangedSubview(permissionsCard)
        entranceViews.append(permissionsCard)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentInsets = NSEdgeInsets(
            top: Theme.windowPadding,
            left: Theme.windowPadding,
            bottom: Theme.windowPadding,
            right: Theme.windowPadding
        )
        scroll.documentView = contentStack

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        styleButton(saveButton, style: .primary)
        let quitButton = NSButton(title: "Quit App", target: self, action: #selector(quitTapped))
        styleButton(quitButton, style: .ghost)
        let actionRow = NSStackView(views: [quitButton, saveButton])
        actionRow.orientation = .horizontal
        actionRow.distribution = .fillEqually
        actionRow.spacing = 12
        actionRow.alignment = .centerY
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scroll)
        contentView.addSubview(actionRow)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -14),
            contentStack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -(Theme.windowPadding * 2)),

            actionRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.windowPadding),
            actionRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.windowPadding),
            actionRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Theme.windowPadding),
            actionRow.heightAnchor.constraint(equalToConstant: 52)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.animateEntranceIfNeeded()
        }
    }

    private func setupWindowBackground(_ contentView: NSView) {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = Theme.bg0.cgColor

        let blur = NSVisualEffectView()
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .withinWindow
        contentView.addSubview(blur)

        let gradient = GradientOverlayView()
        gradient.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gradient)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blur.topAnchor.constraint(equalTo: contentView.topAnchor),
            blur.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradient.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gradient.topAnchor.constraint(equalTo: contentView.topAnchor),
            gradient.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func heroView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Theme.cardCorner
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = Theme.bg1.withAlphaComponent(0.75).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = Theme.stroke.cgColor
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.22
        container.layer?.shadowRadius = 28
        container.layer?.shadowOffset = NSSize(width: 0, height: -8)

        let track = NSView()
        track.translatesAutoresizingMaskIntoConstraints = false
        track.wantsLayer = true
        track.layer?.cornerRadius = 4
        track.layer?.masksToBounds = true
        track.layer?.backgroundColor = Theme.bg2.withAlphaComponent(0.8).cgColor

        let fill = NSView()
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 4
        fill.layer?.masksToBounds = true
        fill.layer?.backgroundColor = Theme.accent.cgColor
        fill.layer?.shadowColor = Theme.accent.cgColor
        fill.layer?.shadowOpacity = 0.7
        fill.layer?.shadowRadius = 12
        fill.layer?.shadowOffset = NSSize(width: 0, height: 0)
        track.addSubview(fill)

        let title = label(
            "Let's tune Jit APP",
            font: Theme.heroTitleFont,
            color: Theme.textPrimary
        )
        let subtitle = label(
            "Refined UI, same behavior. Configure API, prompts, and permissions below.",
            font: NSFont.systemFont(ofSize: 18, weight: .regular),
            color: Theme.textSecondary
        )
        subtitle.maximumNumberOfLines = 2

        let stack = NSStackView(views: [track, title, subtitle])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.cardPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Theme.cardPadding),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.cardPadding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.cardPadding),

            track.widthAnchor.constraint(equalTo: stack.widthAnchor),
            track.heightAnchor.constraint(equalToConstant: 8),

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.34)
        ])

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.8
        pulse.toValue = 1.0
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        fill.layer?.add(pulse, forKey: "progressPulse")
        return container
    }

    private func row(_ title: String, field: NSView) -> NSView {
        row(title, custom: field)
    }

    private func row(_ title: String, custom: NSView) -> NSView {
        let titleLabel = label(title, font: Theme.rowTitleFont, color: Theme.textPrimary)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        custom.setContentHuggingPriority(.defaultLow, for: .horizontal)
        custom.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [titleLabel, custom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func apiKeyRow() -> NSView {
        let pasteButton = NSButton(title: "Paste", target: self, action: #selector(pasteAPIKey))
        styleButton(pasteButton, style: .secondary)
        pasteButton.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let stack = NSStackView(views: [fieldContainer(for: apiKeyField, minWidth: 460), pasteButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return row("API Key", custom: stack)
    }

    private func featuresRow() -> NSView {
        featureControls.removeAll()
        let vertical = NSStackView()
        vertical.orientation = .vertical
        vertical.spacing = 14

        if let entryFeature = featureConfigs.first(where: { $0.id == "custom" }) {
            let controls = FeatureHotkeyControls(id: entryFeature.id)
            controls.keyField.stringValue = entryFeature.hotkeyKey
            controls.optionButton.state = entryFeature.hotkeyOption ? .on : .off
            controls.commandButton.state = entryFeature.hotkeyCommand ? .on : .off
            controls.controlButton.state = entryFeature.hotkeyControl ? .on : .off
            controls.shiftButton.state = entryFeature.hotkeyShift ? .on : .off
            controls.enabledButton.state = entryFeature.enabled ? .on : .off
            featureControls[entryFeature.id] = controls

            [controls.optionButton, controls.commandButton, controls.controlButton, controls.shiftButton, controls.enabledButton].forEach {
                styleToggle($0)
            }

            let title = label("Entry Hotkey (Option+A)", font: Theme.rowTitleFont, color: Theme.textPrimary)
            let row1 = NSStackView(views: [title, controls.enabledButton])
            row1.orientation = .horizontal
            row1.distribution = .fill
            row1.spacing = 12
            let row2 = NSStackView(views: [
                controls.optionButton,
                controls.commandButton,
                controls.controlButton,
                controls.shiftButton,
                fieldContainer(for: controls.keyField, minWidth: 72, height: 36)
            ])
            row2.orientation = .horizontal
            row2.spacing = 10
            row2.alignment = .centerY
            let block = NSStackView(views: [row1, row2])
            block.orientation = .vertical
            block.spacing = 10
            vertical.addArrangedSubview(block)
        }

        vertical.addArrangedSubview(dividerLine())

        let promptHint = label("Mode prompts used inside Option+A", font: Theme.smallFont, color: Theme.textSecondary)
        vertical.addArrangedSubview(promptHint)

        for feature in featureConfigs {
            let title = label(feature.displayName, font: Theme.rowTitleFont, color: Theme.textPrimary)
            let editPrompt = NSButton(title: "Edit Prompt", target: self, action: #selector(editFeaturePromptTapped(_:)))
            editPrompt.identifier = NSUserInterfaceItemIdentifier(feature.id)
            styleButton(editPrompt, style: .accentText)
            editPrompt.widthAnchor.constraint(equalToConstant: 110).isActive = true

            let row1 = NSStackView(views: [title, editPrompt])
            row1.orientation = .horizontal
            row1.distribution = .fill
            row1.spacing = 12
            row1.alignment = .centerY
            vertical.addArrangedSubview(row1)
        }
        return vertical
    }

    private func permissionsPanel() -> NSView {
        let permissions = NSStackView()
        permissions.orientation = .vertical
        permissions.spacing = 10
        let hint = label(
            "Missing permissions may prevent reading selected text and automation.",
            font: Theme.bodyFont,
            color: Theme.textSecondary
        )
        hint.maximumNumberOfLines = 2

        let diagnoseButton = NSButton(title: "Diagnose Permissions", target: self, action: #selector(diagnosePermissionsTapped))
        styleButton(diagnoseButton, style: .secondary)
        let requestPermissionButton = NSButton(title: "Request Permissions", target: self, action: #selector(requestPermissionsTapped))
        styleButton(requestPermissionButton, style: .secondary)
        let resetPermissionsButton = NSButton(title: "Reset Permissions", target: self, action: #selector(resetPermissionsTapped))
        styleButton(resetPermissionsButton, style: .secondary)

        permissions.addArrangedSubview(hint)
        permissions.addArrangedSubview(diagnoseButton)
        permissions.addArrangedSubview(requestPermissionButton)
        permissions.addArrangedSubview(resetPermissionsButton)
        return permissions
    }

    private func cardView(title: String, subtitle: String, content: NSView) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = Theme.cardCorner
        card.layer?.masksToBounds = false
        card.layer?.backgroundColor = Theme.bg1.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Theme.stroke.cgColor
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.18
        card.layer?.shadowRadius = 28
        card.layer?.shadowOffset = NSSize(width: 0, height: -8)

        let titleLabel = label(title, font: Theme.sectionTitleFont, color: Theme.textPrimary)
        let subtitleLabel = label(subtitle, font: Theme.bodyFont, color: Theme.textSecondary)
        subtitleLabel.maximumNumberOfLines = 2

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.spacing = 6
        header.alignment = .leading

        let stack = NSStackView(views: [header, content])
        stack.orientation = .vertical
        stack.spacing = Theme.rowSpacing
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.cardPadding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.cardPadding),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.cardPadding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.cardPadding)
        ])
        return card
    }

    private func fieldContainer(for field: NSTextField, minWidth: CGFloat, height: CGFloat = 40) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Theme.fieldCorner
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = Theme.bg2.withAlphaComponent(0.85).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = Theme.stroke.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(field)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            container.heightAnchor.constraint(equalToConstant: height),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func dividerLine() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.stroke.cgColor
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = font
        value.textColor = color
        return value
    }

    private func styleToggle(_ button: NSButton) {
        button.font = Theme.smallFont
        button.contentTintColor = Theme.textSecondary
    }

    private func styleButton(_ button: NSButton, style: ButtonStyle) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.masksToBounds = true
        button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        switch style {
        case .primary:
            button.layer?.cornerRadius = Theme.buttonCorner
            button.layer?.backgroundColor = Theme.accentStrong.cgColor
            button.layer?.borderWidth = 0
            button.contentTintColor = NSColor.black
            button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        case .secondary:
            button.layer?.cornerRadius = 10
            button.layer?.backgroundColor = Theme.bg2.withAlphaComponent(0.85).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = Theme.stroke.cgColor
            button.contentTintColor = Theme.textPrimary
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        case .ghost:
            button.layer?.cornerRadius = Theme.buttonCorner
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = Theme.stroke.cgColor
            button.contentTintColor = Theme.textPrimary
            button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        case .accentText:
            button.layer?.cornerRadius = 10
            button.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.12).cgColor
            button.layer?.borderWidth = 1
            button.layer?.borderColor = Theme.accent.withAlphaComponent(0.35).cgColor
            button.contentTintColor = Theme.accent
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
    }

    private func animateEntranceIfNeeded() {
        guard !didRunEntranceAnimation else { return }
        didRunEntranceAnimation = true
        for (index, view) in entranceViews.enumerated() {
            view.alphaValue = 0
            view.wantsLayer = true
            let delay = Theme.entranceStagger * Double(index)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let move = CABasicAnimation(keyPath: "transform.translation.y")
                move.fromValue = 8
                move.toValue = 0
                move.duration = Theme.entranceDuration
                move.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.layer?.add(move, forKey: "jit.settings.slideIn")
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Theme.entranceDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    view.animator().alphaValue = 1
                }
            }
        }
    }

    private func assembledFeaturesOrAlert() -> [FeatureConfig]? {
        var result: [FeatureConfig] = []
        for var feature in featureConfigs {
            if feature.id == "custom", let controls = featureControls[feature.id] {
                let key = controls.keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard key.count == 1, KeyCodeMapper.shared.keyCode(for: key) != nil else {
                    showAlert("Entry hotkey key must be a single letter or number.")
                    return nil
                }
                feature.hotkeyKey = key
                feature.hotkeyOption = controls.optionButton.state == .on
                feature.hotkeyCommand = controls.commandButton.state == .on
                feature.hotkeyControl = controls.controlButton.state == .on
                feature.hotkeyShift = controls.shiftButton.state == .on
                feature.enabled = controls.enabledButton.state == .on
                if feature.enabled && feature.modifierFlags.isEmpty {
                    showAlert("Entry hotkey must have at least one modifier key.")
                    return nil
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
            showAlert("Base URL / API Key / Model cannot be empty.")
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
        guard let config = buildConfigOrShowError() else { return }
        onSave?(config)
        window?.close()
    }

    @objc private func testTapped() {
        guard let config = buildConfigOrShowError(),
              let feature = config.features.first(where: { $0.id == "translate" }) else { return }
        onTest?(config, feature) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message): self.showInfo("Connection Success", message: message)
            case .failure(let error): self.showAlert("Connection failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func pasteAPIKey() {
        if let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            apiKeyField.stringValue = text
        } else {
            showAlert("No usable text found in clipboard.")
        }
    }

    @objc private func quitTapped() { onQuit?() }

    @objc private func editFeaturePromptTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let feature = featureConfigs.first(where: { $0.id == id }) else { return }
        openPromptEditor(for: feature)
    }

    private func openPromptEditor(for feature: FeatureConfig) {
        let defaultTemplate: String
        switch feature.id {
        case "translate":
            defaultTemplate = AppConfig.defaultTranslationPromptTemplate
        case "refine":
            defaultTemplate = AppConfig.defaultRefinePromptTemplate
        default:
            defaultTemplate = AppConfig.defaultCustomPromptTemplate
        }
        let editor = PromptEditorWindowController(currentTemplate: feature.promptTemplate, defaultTemplate: defaultTemplate)
        editor.onSave = { [weak self] newTemplate in
            guard let self else { return }
            if let index = self.featureConfigs.firstIndex(where: { $0.id == feature.id }) {
                self.featureConfigs[index].promptTemplate = newTemplate
                self.showInfo("Prompt Saved", message: "\(self.featureConfigs[index].displayName) prompt updated.")
            }
        }
        editor.showWindow(nil)
        editor.window?.center()
        editor.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        promptEditorWindowController = editor
    }

    @objc private func diagnosePermissionsTapped() {
        showInfo("Permission Diagnostics", message: onDiagnosePermissions?() ?? "No diagnostics available.")
    }

    @objc private func requestPermissionsTapped() {
        _ = onRequestPermissions?()
    }

    @objc private func resetPermissionsTapped() {
        showInfo("Permission Reset Result", message: onResetPermissions?() ?? "Permission reset callback is not provided.")
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.runModal()
    }

    private func showInfo(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = AppConfig.load()
    private let captureService = SelectionCaptureService()
    private let translationService = TranslationService()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        rebuildStatusBarMenu()
        registerHotkeys()
        requestAccessibilityPermissionHint()
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isQuitting { return false }
        if suppressReopenSettings { return false }
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
        if isProcessing { return }
        isProcessing = true
        let sourceApp = NSWorkspace.shared.frontmostApplication

        captureService.captureSelectedText { [weak self] text in
            guard let self else { return }
            guard let text else {
                self.isProcessing = false
                self.resultWindowController.showError(
                    "No selected text detected.\n\n" +
                    "Please select text in the target app, then press the hotkey.\n" +
                    "If it still fails, verify:\n" +
                    "1) System Settings -> Privacy & Security -> Accessibility allows Jit APP\n" +
                    "2) System Settings -> Privacy & Security -> Input Monitoring allows Jit APP (if present)\n" +
                    "3) The target app supports selected text read or Command+C copy\n",
                    featureName: feature.displayName
                )
                return
            }

            let runProcess: (String?) -> Void = { instruction in
                self.resultWindowController.showPending(selectedText: text, featureName: feature.displayName)
                self.translationService.process(text: text, config: self.config, feature: feature, instruction: instruction) { result in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        switch result {
                        case .success(let output):
                            self.resultWindowController.showResult(
                                selectedText: text,
                                output: output,
                                featureName: feature.displayName,
                                outputLabel: feature.id == "translate" ? "Translation" : "\(feature.displayName) Result",
                                allowReplace: feature.supportsReplace,
                                onReplace: { [weak self] in
                                    self?.captureService.replaceSelectedText(with: output, targetApp: sourceApp)
                                }
                            )
                        case .failure(let error):
                            self.resultWindowController.showError(
                                "\(feature.displayName) failed: \(error.localizedDescription)",
                                selectedText: text,
                                featureName: feature.displayName
                            )
                        }
                    }
                }
            }

            if feature.requiresInstruction {
                self.isProcessing = false
                let modeIDs = ["custom", "refine", "translate"]
                let modes = modeIDs.compactMap { id -> CommandInputWindowController.Mode? in
                    guard let f = self.config.features.first(where: { $0.id == id && $0.enabled }) else { return nil }
                    let promptPreview = f.promptTemplate
                        .split(separator: "\n")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first(where: { !$0.isEmpty }) ?? "\(f.displayName) prompt"
                    return .init(id: f.id, title: f.displayName, requiresInstruction: f.requiresInstruction, promptPreview: promptPreview)
                }
                let input = CommandInputWindowController(
                    selectedText: text,
                    anchor: NSEvent.mouseLocation,
                    modes: modes,
                    defaultModeID: feature.id
                )
                input.onSubmit = { [weak self] modeID, instruction, completion in
                    guard let self else { return }
                    guard let selectedFeature = self.config.features.first(where: { $0.id == modeID && $0.enabled }) else {
                        completion(.failure(NSError(domain: "JitAPP", code: 404, userInfo: [NSLocalizedDescriptionKey: "Selected mode is unavailable."])))
                        return
                    }
                    if self.isProcessing {
                        completion(.failure(NSError(domain: "JitAPP", code: 429, userInfo: [NSLocalizedDescriptionKey: "Please wait for the previous task to finish."])))
                        return
                    }
                    self.isProcessing = true
                    self.translationService.process(
                        text: text,
                        config: self.config,
                        feature: selectedFeature,
                        instruction: selectedFeature.requiresInstruction ? instruction : nil
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
                input.onClose = { [weak self] in
                    self?.commandInputWindowController = nil
                }
                suppressReopenSettings = true
                NSApp.activate(ignoringOtherApps: true)
                input.showWindow(nil)
                input.window?.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    input.focus()
                }
                input.beginAutoDismiss()
                self.commandInputWindowController = input
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.suppressReopenSettings = false
                }
            } else {
                runProcess(nil)
            }
        }
    }

    @objc private func openSettings() {
        if isQuitting { return }
        if let controller = settingsWindowController, let window = controller.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        controller.onQuit = { [weak self] in
            self?.quit()
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
        controller.focusPrimaryField()
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

    private func requestAccessibilityPermissionHint() {
        _ = AXIsProcessTrusted()
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
