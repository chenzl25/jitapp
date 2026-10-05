import CFNetwork
import Darwin
import Foundation

public enum AIBackend: String, Sendable, CaseIterable {
    case codexCLI
    case claudeCLI
    case chatAPI

    public static func load(savedValue: String?, apiKey: String) -> AIBackend {
        if let savedValue, let backend = AIBackend(rawValue: savedValue) { return backend }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .codexCLI : .chatAPI
    }

    public var localTool: LocalCLITool? {
        switch self {
        case .codexCLI: return .codex
        case .claudeCLI: return .claude
        case .chatAPI: return nil
        }
    }
}

public enum LocalCLITool: String, Sendable, CaseIterable {
    case codex
    case claude

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        }
    }

    public var executableName: String { rawValue }

    public var loginCommand: String {
        switch self {
        case .codex: return "codex login"
        case .claude: return "claude auth login"
        }
    }
}

public struct LocalCLIError: LocalizedError, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case notFound, invalidPath, notSignedIn, blocked, timedOut, emptyResponse, outdatedCLI
        case requestFailed(String)
    }

    public let tool: LocalCLITool
    public let kind: Kind

    public init(_ tool: LocalCLITool, _ kind: Kind) {
        self.tool = tool
        self.kind = kind
    }

    public var errorDescription: String? {
        let name = tool.displayName
        switch kind {
        case .notFound: return "\(name) CLI was not found. Install \(name), then run \(tool.loginCommand) in Terminal."
        case .invalidPath: return "The \(name) path is not executable. Choose the \(tool.executableName) executable in AI Model settings."
        case .notSignedIn: return "Sign in to \(name) by running \(tool.loginCommand) in Terminal, then try again. No API key is needed in Jit."
        case .blocked: return "\(name) could not reach its service (403 Request not allowed). Check your network or proxy, then try again."
        case .timedOut: return "\(name) took too long to respond. Try again."
        case .emptyResponse: return "\(name) returned no text. Try again."
        case .outdatedCLI: return "Update \(name) CLI to use it with Jit, then try again."
        case .requestFailed(let message): return "\(name) request failed: \(message)"
        }
    }

    public var needsSettings: Bool {
        switch kind {
        case .notFound, .invalidPath, .notSignedIn, .outdatedCLI: return true
        default: return false
        }
    }

    static func fromDiagnostic(_ diagnostic: String, tool: LocalCLITool) -> LocalCLIError {
        let lower = diagnostic.lowercased()
        // Checked before the login patterns: Claude reports a region or proxy
        // block as "Failed to authenticate. API Error: 403 Request not allowed".
        if lower.contains("request not allowed") { return LocalCLIError(tool, .blocked) }
        let loginPatterns = ["401", "not logged in", "not signed in", "please log in", "please run /login", "authentication", "invalid api key", "oauth token has expired"]
        if loginPatterns.contains(where: lower.contains) { return LocalCLIError(tool, .notSignedIn) }
        if ["unexpected argument", "unrecognized option", "unknown option"].contains(where: lower.contains) {
            return LocalCLIError(tool, .outdatedCLI)
        }
        let redacted = diagnostic
            .replacingOccurrences(of: "sk-[a-zA-Z0-9_-]+", with: "[redacted]", options: .regularExpression)
            .replacingOccurrences(of: "(?i)bearer\\s+[^\\s]+", with: "Bearer [redacted]", options: .regularExpression)
        let message = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalCLIError(tool, .requestFailed(message.isEmpty ? "Please check your \(tool.displayName) login and connection." : String(message.suffix(600))))
    }
}

public enum LocalCLI {
    static let instruction = "You are a concise text assistant for translation, rewriting, and English vocabulary learning. Process only the text supplied in the prompt. Do not use tools, inspect files, or run commands. Return only the requested result without progress updates."

    public static func executable(for tool: LocalCLITool, path: String = "", environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
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
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(tool.executableName)
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
            "/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.claude/local", home + "/.npm-global/bin", home + "/.volta/bin", home + "/.bun/bin", "/usr/bin", "/bin"
        ]
        var seen = Set<String>()
        return candidates.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    /// Variables that tie a child CLI to an enclosing agent session (for
    /// example when Jit itself is launched from a Codex or Claude terminal).
    static let sessionVariables: Set<String> = [
        "CODEX_THREAD_ID", "CODEX_SESSION_ID", "CODEX_TURN_ID",
        "CLAUDECODE", "CLAUDE_PID", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
        "CLAUDE_CODE_EXECPATH", "CLAUDE_CODE_SSE_PORT",
    ]

    static let proxyVariables = ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"]

    static func childEnvironment(executable: URL, base: [String: String], systemProxies: [String: Any]?) -> [String: String] {
        var environment = base
        // GUI apps do not inherit the Terminal's PATH. Include the selected
        // CLI directory so npm's /usr/bin/env node wrapper also works.
        environment["PATH"] = ([executable.deletingLastPathComponent().path] + searchPaths(environment: base)).joined(separator: ":")
        for key in Array(environment.keys) where key.hasPrefix("LANTOR_") || sessionVariables.contains(key) {
            environment.removeValue(forKey: key)
        }
        // Apps opened from Finder do not see the shell's proxy variables, and
        // neither CLI reads the macOS proxy settings on its own. Without this,
        // Codex retries its WebSocket for about two minutes and Claude can be
        // rejected with 403 on networks that need the proxy.
        if !proxyVariables.contains(where: { !(base[$0] ?? "").isEmpty }), let systemProxies {
            environment.merge(proxyEnvironment(from: systemProxies)) { current, _ in current }
        }
        return environment
    }

    /// Converts `CFNetworkCopySystemProxySettings()` keys into the standard
    /// proxy variables understood by Codex (Rust) and Claude Code (Node).
    static func proxyEnvironment(from settings: [String: Any]) -> [String: String] {
        func endpoint(_ prefix: String) -> String? {
            guard (settings[prefix + "Enable"] as? NSNumber)?.boolValue == true,
                  let host = (settings[prefix + "Proxy"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else { return nil }
            let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
            guard let port = (settings[prefix + "Port"] as? NSNumber)?.intValue, port > 0 else { return bracketed }
            return "\(bracketed):\(port)"
        }
        var environment: [String: String] = [:]
        let https = endpoint("HTTPS") ?? endpoint("HTTP")
        let http = endpoint("HTTP") ?? endpoint("HTTPS")
        if let https { environment["HTTPS_PROXY"] = "http://" + https; environment["https_proxy"] = "http://" + https }
        if let http { environment["HTTP_PROXY"] = "http://" + http; environment["http_proxy"] = "http://" + http }
        if https == nil, http == nil, let socks = endpoint("SOCKS") {
            environment["ALL_PROXY"] = "socks5h://" + socks
            environment["all_proxy"] = "socks5h://" + socks
        }
        guard !environment.isEmpty else { return [:] }
        let exceptions = (settings["ExceptionsList"] as? [String] ?? [])
            .map { $0.hasPrefix("*.") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty && !$0.contains("/") && !$0.contains("*") }
        var seen = Set<String>()
        let noProxy = (["localhost", "127.0.0.1", "::1"] + exceptions).filter { seen.insert($0).inserted }.joined(separator: ",")
        environment["NO_PROXY"] = noProxy
        environment["no_proxy"] = noProxy
        return environment
    }

    static func systemProxySettings() -> [String: Any]? {
        CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
    }

    public static func run(
        tool: LocalCLITool, prompt: String, model: String = "", path: String = "", timeout: TimeInterval = 120,
        onPartial: @escaping @Sendable (String) -> Void = { _ in },
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) -> LocalCLIRun {
        run(tool: tool, prompt: prompt, model: model, path: path, timeout: timeout, baseEnvironment: ProcessInfo.processInfo.environment,
            systemProxies: systemProxySettings(), onPartial: onPartial, completion: completion)
    }

    static func run(
        tool: LocalCLITool, prompt: String, model: String, path: String, timeout: TimeInterval,
        baseEnvironment: [String: String], systemProxies: [String: Any]?,
        onPartial: @escaping @Sendable (String) -> Void = { _ in },
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) -> LocalCLIRun {
        let run = LocalCLIRun(tool: tool, prompt: prompt, model: model, path: path, timeout: timeout,
                              baseEnvironment: baseEnvironment, systemProxies: systemProxies, onPartial: onPartial, completion: completion)
        DispatchQueue.global(qos: .userInitiated).async { run.execute() }
        return run
    }
}

/// JSONL framing uses bytes so split UTF-8 code points survive pipe boundaries.
struct JSONLFramer {
    private var buffer = Data()

    mutating func feed(_ bytes: Data, eof: Bool = false) -> [[String: Any]] {
        buffer.append(bytes)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 10) {
            lines.append(Data(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        if eof, !buffer.isEmpty {
            lines.append(buffer)
            buffer.removeAll()
        }
        return lines.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

/// Parses one CLI's JSONL stdout into text deltas and a final status.
protocol CLIEventStream {
    /// Returns newly streamed text.
    mutating func feed(_ bytes: Data, eof: Bool) -> [String]
    /// True once the CLI reported the end of the turn.
    var completed: Bool { get }
    /// A terminal failure reported by the CLI.
    var failure: String? { get }
    /// A non-terminal warning, used only to explain a run that fails later.
    var lastWarning: String? { get }
    var output: String { get }
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

public final class LocalCLIRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    private var finished = false
    private let tool: LocalCLITool
    private let prompt: String
    private let model: String
    private let path: String
    private let timeout: TimeInterval
    private let baseEnvironment: [String: String]
    private let systemProxies: [String: Any]?
    private let onPartial: @Sendable (String) -> Void
    private let completion: @Sendable (Result<String, Error>) -> Void

    init(tool: LocalCLITool, prompt: String, model: String, path: String, timeout: TimeInterval,
         baseEnvironment: [String: String], systemProxies: [String: Any]?,
         onPartial: @escaping @Sendable (String) -> Void, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        self.tool = tool; self.prompt = prompt; self.model = model; self.path = path; self.timeout = timeout
        self.baseEnvironment = baseEnvironment; self.systemProxies = systemProxies
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
        let result: Result<String, Error> = cancelled ? .failure(CancellationError()) : (timedOut ? .failure(LocalCLIError(tool, .timedOut)) : result)
        lock.unlock()
        completion(result)
    }

    func execute() {
        guard let executable = LocalCLI.executable(for: tool, path: path, environment: baseEnvironment) else {
            finish(.failure(LocalCLIError(tool, path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .notFound : .invalidPath))); return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jit-\(tool.rawValue)-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let outputURL = directory.appendingPathComponent("response.txt")
            let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            var input = prompt
            var events: any CLIEventStream
            let child = Process()
            switch tool {
            case .codex:
                child.arguments = try CodexCLI.arguments(model: selectedModel, outputFile: outputURL)
                events = CodexEvents()
            case .claude:
                child.arguments = ClaudeCLI.arguments(model: selectedModel)
                input = ClaudeCLI.stdinPrompt(prompt)
                events = ClaudeEvents()
            }
            child.executableURL = executable
            child.currentDirectoryURL = directory
            child.environment = LocalCLI.childEnvironment(executable: executable, base: baseEnvironment, systemProxies: systemProxies)
            let stdin = Pipe(), output = Pipe(), errors = Pipe()
            child.standardInput = stdin; child.standardOutput = output; child.standardError = errors
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
                try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            } catch {
                // A CLI startup failure may close stdin before consuming it;
                // its JSON/stderr error below is more useful than EPIPE.
            }
            try? stdin.fileHandleForWriting.close()
            while true {
                let bytes = output.fileHandleForReading.readData(ofLength: 8192)
                if bytes.isEmpty { break }
                for delta in events.feed(bytes, eof: false) { onPartial(delta) }
            }
            for delta in events.feed(Data(), eof: true) { onPartial(delta) }
            child.waitUntilExit()
            stderrDone.wait()
            guard child.terminationStatus == 0, events.completed, events.failure == nil else {
                let stderrText = diagnostics.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = events.failure ?? (stderrText.isEmpty ? nil : stderrText) ?? events.lastWarning ?? ""
                finish(.failure(LocalCLIError.fromDiagnostic(reason, tool: tool))); return
            }
            // Codex also writes its final message to a file, which wins over
            // streamed snapshots if an event revised earlier text.
            var finalFile: String?
            if tool == .codex { finalFile = try? String(contentsOf: outputURL, encoding: .utf8) }
            let text = (finalFile ?? events.output).trimmingCharacters(in: .whitespacesAndNewlines)
            finish(text.isEmpty ? .failure(LocalCLIError(tool, .emptyResponse)) : .success(text))
        } catch {
            finish(.failure(error))
        }
    }
}
