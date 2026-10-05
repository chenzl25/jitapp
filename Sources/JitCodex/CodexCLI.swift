import Foundation
import Darwin

public enum AIBackend: String, Sendable {
    case codexCLI
    case chatAPI

    public static func load(savedValue: String?, apiKey: String) -> AIBackend {
        if let savedValue, let backend = AIBackend(rawValue: savedValue) { return backend }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .codexCLI : .chatAPI
    }
}

public enum CodexCLIError: LocalizedError, Sendable {
    case notFound, invalidPath, notSignedIn, timedOut, emptyResponse, outdatedCLI
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "Codex CLI was not found. Install Codex, then run codex login in Terminal."
        case .invalidPath: return "The Codex path is not executable. Choose the codex executable in AI Model settings."
        case .notSignedIn: return "Sign in to Codex by running codex login in Terminal, then try again. No API key is needed in Jit."
        case .timedOut: return "Codex took too long to respond. Try again."
        case .emptyResponse: return "Codex returned no text. Try again."
        case .outdatedCLI: return "Update Codex CLI to use it with Jit, then try again."
        case .requestFailed(let message): return "Codex request failed: \(message)"
        }
    }

    public var needsSettings: Bool {
        switch self {
        case .notFound, .invalidPath, .notSignedIn, .outdatedCLI: return true
        default: return false
        }
    }

    static func fromDiagnostic(_ diagnostic: String) -> CodexCLIError {
        let lower = diagnostic.lowercased()
        if lower.contains("401") || lower.contains("not logged in") || lower.contains("not signed in") || lower.contains("please log in") || lower.contains("authentication") {
            return .notSignedIn
        }
        if lower.contains("unexpected argument") || lower.contains("unrecognized option") { return .outdatedCLI }
        let redacted = diagnostic
            .replacingOccurrences(of: "sk-[a-zA-Z0-9_-]+", with: "[redacted]", options: .regularExpression)
            .replacingOccurrences(of: "(?i)bearer\\s+[^\\s]+", with: "Bearer [redacted]", options: .regularExpression)
        let message = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        return .requestFailed(message.isEmpty ? "Please check your Codex login and connection." : String(message.suffix(600)))
    }
}

public enum CodexCLI {
    public static func executable(path: String = "", environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let explicit = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let manager = FileManager.default
        if !explicit.isEmpty {
            let expanded = NSString(string: explicit).expandingTildeInPath
            guard expanded.hasPrefix("/"), manager.isExecutableFile(atPath: expanded) else { return nil }
            var directory: ObjCBool = false
            guard manager.fileExists(atPath: expanded, isDirectory: &directory), !directory.boolValue else { return nil }
            return URL(fileURLWithPath: expanded)
        }
        for directory in searchPaths(environment: environment) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("codex")
            var isDirectory: ObjCBool = false
            if manager.isExecutableFile(atPath: candidate.path), manager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    static func searchPaths(environment: [String: String]) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + [
            "/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.npm-global/bin", home + "/.volta/bin", "/usr/bin", "/bin"
        ]
        var seen = Set<String>()
        return candidates.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    public static func run(
        prompt: String, model: String = "", path: String = "", timeout: TimeInterval = 120,
        onPartial: @escaping @Sendable (String) -> Void = { _ in },
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) -> CodexRun {
        let run = CodexRun(prompt: prompt, model: model, path: path, timeout: timeout, onPartial: onPartial, completion: completion)
        DispatchQueue.global(qos: .userInitiated).async { run.execute() }
        return run
    }
}

/// JSONL framing uses bytes so split UTF-8 code points survive pipe boundaries.
struct CodexEvents {
    private var buffer = Data()
    private var messages: [String: String] = [:]
    private var order: [String] = []
    private(set) var completed = false
    private(set) var failure: String?
    var output: String { order.compactMap { messages[$0] }.joined(separator: "\n") }

    mutating func feed(_ bytes: Data, eof: Bool = false) -> [String] {
        buffer.append(bytes)
        var deltas: [String] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let delta = handle(line), !delta.isEmpty { deltas.append(delta) }
        }
        if eof, !buffer.isEmpty {
            if let delta = handle(buffer), !delta.isEmpty { deltas.append(delta) }
            buffer.removeAll()
        }
        return deltas
    }

    private mutating func handle(_ line: Data) -> String? {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = event["type"] as? String else { return nil }
        if type == "turn.completed" { completed = true }
        if type == "turn.failed" || type == "error" {
            failure = (event["error"] as? [String: Any])?["message"] as? String ?? event["message"] as? String ?? "The Codex turn failed."
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

private final class DiagnosticBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        bytes.append(data)
        if bytes.count > 16_384 { bytes.removeFirst(bytes.count - 16_384) }
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }
}

public final class CodexRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    private var finished = false
    private let prompt: String
    private let model: String
    private let path: String
    private let timeout: TimeInterval
    private let onPartial: @Sendable (String) -> Void
    private let completion: @Sendable (Result<String, Error>) -> Void

    init(prompt: String, model: String, path: String, timeout: TimeInterval, onPartial: @escaping @Sendable (String) -> Void, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        self.prompt = prompt; self.model = model; self.path = path; self.timeout = timeout
        self.onPartial = onPartial; self.completion = completion
    }

    public func cancel() { stop(timedOut: false) }

    private func stop(timedOut: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if timedOut { self.timedOut = true } else { cancelled = true }
        if let process, process.isRunning {
            let pid = process.processIdentifier
            if getpgid(pid) == pid { _ = kill(-pid, SIGTERM) } else { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.forceStop(pid: pid)
            }
        }
    }

    private func forceStop(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        guard !finished, let process, process.isRunning, process.processIdentifier == pid else { return }
        if getpgid(pid) == pid { _ = kill(-pid, SIGKILL) } else { _ = kill(pid, SIGKILL) }
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        process = nil
        let result: Result<String, Error> = cancelled ? .failure(CancellationError()) : (timedOut ? .failure(CodexCLIError.timedOut) : result)
        lock.unlock()
        completion(result)
    }

    func execute() {
        guard let executable = CodexCLI.executable(path: path) else {
            finish(.failure(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CodexCLIError.notFound : CodexCLIError.invalidPath)); return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jit-codex-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let outputURL = directory.appendingPathComponent("response.txt")
            let child = Process()
            child.executableURL = executable
            child.currentDirectoryURL = directory
            let instruction = "You are a concise text assistant for translation, rewriting, and English vocabulary learning. Process only the text supplied in the prompt. Do not use tools, inspect files, or run commands. Return only the requested result without progress updates."
            let quoted = String(decoding: try JSONEncoder().encode(instruction), as: UTF8.self)
            child.arguments = ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--json", "--color", "never",
                               "-c", "approval_policy=\"never\"", "-c", "developer_instructions=" + quoted,
                               "-c", "features.shell_tool=false", "-c", "features.unified_exec=false", "-c", "features.apps=false", "-c", "features.plugins=false",
                               "--output-last-message", outputURL.path]
            let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedModel.isEmpty { child.arguments! += ["--model", selectedModel] }
            child.arguments! += ["-"]
            var environment = ProcessInfo.processInfo.environment
            // GUI apps do not inherit the Terminal's PATH. Include the selected
            // CLI directory so npm's /usr/bin/env node wrapper also works.
            environment["PATH"] = ([executable.deletingLastPathComponent().path] + CodexCLI.searchPaths(environment: environment)).joined(separator: ":")
            for key in Array(environment.keys) where key.hasPrefix("LANTOR_") || ["CODEX_THREAD_ID", "CODEX_SESSION_ID", "CODEX_TURN_ID"].contains(key) {
                environment.removeValue(forKey: key)
            }
            child.environment = environment
            let input = Pipe(), output = Pipe(), errors = Pipe()
            child.standardInput = input; child.standardOutput = output; child.standardError = errors
            lock.lock()
            if cancelled { lock.unlock(); finish(.failure(CancellationError())); return }
            process = child
            do { try child.run() } catch { lock.unlock(); throw error }
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.stop(timedOut: true) }
            let diagnostics = DiagnosticBuffer()
            let stderrDone = DispatchGroup()
            stderrDone.enter()
            DispatchQueue.global().async {
                while true {
                    let bytes = errors.fileHandleForReading.readData(ofLength: 8192)
                    if bytes.isEmpty { break }
                    diagnostics.append(bytes)
                }
                stderrDone.leave()
            }
            do {
                try input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
            } catch {
                // A CLI startup failure may close stdin before consuming it;
                // its JSON/stderr error below is more useful than EPIPE.
            }
            try? input.fileHandleForWriting.close()
            var events = CodexEvents()
            while true {
                let bytes = output.fileHandleForReading.readData(ofLength: 8192)
                if bytes.isEmpty { break }
                for delta in events.feed(bytes) { onPartial(delta) }
            }
            for delta in events.feed(Data(), eof: true) { onPartial(delta) }
            child.waitUntilExit()
            stderrDone.wait()
            guard child.terminationStatus == 0, events.completed, events.failure == nil else {
                finish(.failure(CodexCLIError.fromDiagnostic(events.failure ?? diagnostics.text))); return
            }
            let text = ((try? String(contentsOf: outputURL, encoding: .utf8)) ?? events.output).trimmingCharacters(in: .whitespacesAndNewlines)
            finish(text.isEmpty ? .failure(CodexCLIError.emptyResponse) : .success(text))
        } catch {
            finish(.failure(error))
        }
    }
}
