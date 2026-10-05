import Foundation

enum ClaudeCLI {
    /// Print mode with every customization off: `--safe-mode` skips CLAUDE.md,
    /// hooks, plugins, skills and MCP servers while keeping the saved login;
    /// `--tools ""` removes all built-in tools.
    static func arguments(model: String) -> [String] {
        var arguments = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                         "--safe-mode", "--tools", "", "--no-session-persistence",
                         "--system-prompt", LocalCLI.instruction]
        if !model.isEmpty { arguments += ["--model", model] }
        return arguments
    }

    /// In print mode a prompt that starts with "/" runs as a slash command
    /// (for example "/cost"). A leading space keeps it plain text.
    static func stdinPrompt(_ prompt: String) -> String {
        prompt.hasPrefix("/") ? " " + prompt : prompt
    }
}

/// `claude -p --output-format stream-json --include-partial-messages` events.
struct ClaudeEvents: CLIEventStream {
    private var framer = JSONLFramer()
    private var streamed = ""
    private var snapshot: String?
    private var result: String?
    private(set) var completed = false
    private(set) var failure: String?
    private(set) var lastWarning: String?
    var output: String { result ?? snapshot ?? streamed }

    mutating func feed(_ bytes: Data, eof: Bool = false) -> [String] {
        framer.feed(bytes, eof: eof).compactMap { handle($0) }.filter { !$0.isEmpty }
    }

    private mutating func handle(_ event: [String: Any]) -> String? {
        switch event["type"] as? String {
        case "stream_event":
            guard let inner = event["event"] as? [String: Any], inner["type"] as? String == "content_block_delta",
                  let delta = inner["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            streamed += text
            return text
        case "assistant":
            guard let message = event["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { return nil }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            if event["error"] != nil { lastWarning = text; return nil }
            guard !text.isEmpty else { return nil }
            snapshot = text
            // Without partial messages the whole reply arrives here.
            guard streamed.isEmpty else { return nil }
            streamed = text
            return text
        case "result":
            completed = true
            if event["is_error"] as? Bool == true {
                let errors = (event["errors"] as? [String])?.joined(separator: "\n")
                failure = (event["result"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? errors ?? lastWarning ?? "The Claude request failed."
            } else {
                result = event["result"] as? String
            }
            return nil
        default:
            return nil
        }
    }
}
