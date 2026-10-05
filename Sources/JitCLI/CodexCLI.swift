import Foundation

enum CodexCLI {
    static func arguments(model: String, outputFile: URL) throws -> [String] {
        let quoted = String(decoding: try JSONEncoder().encode(LocalCLI.instruction), as: UTF8.self)
        var arguments = ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--json", "--color", "never",
                         "-c", "approval_policy=\"never\"", "-c", "developer_instructions=" + quoted,
                         "-c", "features.shell_tool=false", "-c", "features.unified_exec=false", "-c", "features.apps=false", "-c", "features.plugins=false",
                         "--output-last-message", outputFile.path]
        if !model.isEmpty { arguments += ["--model", model] }
        return arguments + ["-"]
    }
}

/// `codex exec --json` events. Agent messages arrive as whole snapshots
/// (item.started/updated/completed), not token deltas.
struct CodexEvents: CLIEventStream {
    private var framer = JSONLFramer()
    private var messages: [String: String] = [:]
    private var order: [String] = []
    private(set) var completed = false
    private(set) var failure: String?
    private(set) var lastWarning: String?
    var output: String { order.compactMap { messages[$0] }.joined(separator: "\n") }

    mutating func feed(_ bytes: Data, eof: Bool = false) -> [String] {
        framer.feed(bytes, eof: eof).compactMap { handle($0) }.filter { !$0.isEmpty }
    }

    private mutating func handle(_ event: [String: Any]) -> String? {
        guard let type = event["type"] as? String else { return nil }
        switch type {
        case "turn.completed":
            completed = true
        case "turn.failed":
            failure = (event["error"] as? [String: Any])?["message"] as? String ?? event["message"] as? String ?? "The Codex turn failed."
        case "error":
            // Top-level `error` events are also used for recoverable notices
            // such as "Reconnecting... 2/5"; only turn.failed ends the turn.
            lastWarning = event["message"] as? String ?? lastWarning
        default:
            break
        }
        guard ["item.started", "item.updated", "item.completed"].contains(type),
              let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message",
              let text = item["text"] as? String else { return nil }
        if let phase = item["phase"] as? String, phase != "final_answer" { return nil }
        let id = item["id"] as? String ?? "message"
        let previous = messages[id] ?? ""
        if messages[id] == nil { order.append(id) }
        messages[id] = text
        return text.hasPrefix(previous) ? String(text.dropFirst(previous.count)) : nil
    }
}
