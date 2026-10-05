import XCTest
@testable import JitCLI

final class LocalCLITests: XCTestCase, @unchecked Sendable {
    // MARK: Backend selection

    func testProviderMigrationKeepsAPIUsersAndDefaultsNoKeyUsersToCodex() {
        XCTAssertEqual(AIBackend.load(savedValue: nil, apiKey: ""), .codexCLI)
        XCTAssertEqual(AIBackend.load(savedValue: nil, apiKey: "  \n"), .codexCLI)
        XCTAssertEqual(AIBackend.load(savedValue: nil, apiKey: "existing-key"), .chatAPI)
        XCTAssertEqual(AIBackend.load(savedValue: "codexCLI", apiKey: "existing-key"), .codexCLI)
        XCTAssertEqual(AIBackend.load(savedValue: "claudeCLI", apiKey: "existing-key"), .claudeCLI)
        XCTAssertEqual(AIBackend.load(savedValue: "chatAPI", apiKey: ""), .chatAPI)
        XCTAssertEqual(AIBackend.claudeCLI.localTool, .claude)
        XCTAssertNil(AIBackend.chatAPI.localTool)
    }

    // MARK: Codex events

    func testJSONLFramesSplitUnicodeAndDeduplicatesSnapshots() {
        let source = """
        {"type":"item.updated","item":{"id":"reply","type":"agent_message","text":"你"}}
        {"type":"item.updated","item":{"id":"reply","type":"agent_message","text":"你好🌈"}}
        {"type":"item.completed","item":{"id":"reply","type":"agent_message","text":"你好🌈"}}
        {"type":"turn.completed"}
        """
        var events = CodexEvents()
        var deltas = ""
        for byte in source.utf8 { deltas += events.feed(Data([byte])).joined() }
        deltas += events.feed(Data(), eof: true).joined()
        XCTAssertEqual(deltas, "你好🌈")
        XCTAssertEqual(events.output, "你好🌈")
        XCTAssertTrue(events.completed)
    }

    func testToolAndCommentaryEventsDoNotBecomeTheResult() {
        let source = """
        {"type":"item.completed","item":{"id":"tool","type":"command_execution","text":"private tool output"}}
        {"type":"item.completed","item":{"id":"note","type":"agent_message","phase":"commentary","text":"Working…"}}
        {"type":"item.completed","item":{"id":"final","type":"agent_message","phase":"final_answer","text":"Result"}}
        {"type":"turn.failed","error":{"message":"Quota exceeded"}}
        """
        var events = CodexEvents()
        XCTAssertEqual(events.feed(Data(source.utf8), eof: true), ["Result"])
        XCTAssertEqual(events.failure, "Quota exceeded")
        XCTAssertFalse(events.completed)
    }

    /// Captured from Codex 0.159.3 without a proxy: the WebSocket retries are
    /// reported as top-level `error` events, then the turn still completes.
    func testReconnectNoticesDoNotFailACompletedCodexTurn() {
        let source = """
        {"type":"thread.started","thread_id":"t"}
        {"type":"turn.started"}
        {"type":"error","message":"Reconnecting... 2/5 (request timed out)"}
        {"type":"error","message":"Reconnecting... 5/5 (request timed out)"}
        {"type":"item.completed","item":{"id":"item_0","type":"error","message":"Falling back from WebSockets to HTTPS transport. request timed out"}}
        {"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"早上好。"}}
        {"type":"turn.completed","usage":{"input_tokens":1}}
        """
        var events = CodexEvents()
        XCTAssertEqual(events.feed(Data(source.utf8), eof: true), ["早上好。"])
        XCTAssertTrue(events.completed)
        XCTAssertNil(events.failure)
        XCTAssertEqual(events.lastWarning, "Reconnecting... 5/5 (request timed out)")
    }

    // MARK: Claude events

    func testClaudeStreamsTextDeltasAndIgnoresThinking() {
        let source = """
        {"type":"system","subtype":"init","tools":[],"model":"claude-haiku-4-5"}
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"secret plan"}}}
        {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"你"}}}
        {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"好🌈"}}}
        {"type":"assistant","message":{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"你好🌈"}]}}
        {"type":"result","subtype":"success","is_error":false,"result":"你好🌈!"}
        """
        var events = ClaudeEvents()
        var deltas = ""
        for byte in source.utf8 { deltas += events.feed(Data([byte])).joined() }
        deltas += events.feed(Data(), eof: true).joined()
        XCTAssertEqual(deltas, "你好🌈")
        XCTAssertEqual(events.output, "你好🌈!", "The result event is authoritative.")
        XCTAssertTrue(events.completed)
        XCTAssertNil(events.failure)
    }

    func testClaudeWithoutPartialMessagesUsesTheAssistantSnapshot() {
        let source = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Bonjour"}]}}
        {"type":"result","subtype":"success","is_error":false}
        """
        var events = ClaudeEvents()
        XCTAssertEqual(events.feed(Data(source.utf8), eof: true), ["Bonjour"])
        XCTAssertEqual(events.output, "Bonjour")
    }

    /// Captured from Claude Code 2.1.286 with an empty config directory.
    func testClaudeErrorResultIsAFailureNotOutput() {
        let source = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Not logged in · Please run /login"}]},"error":"authentication_failed"}
        {"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}
        """
        var events = ClaudeEvents()
        XCTAssertEqual(events.feed(Data(source.utf8), eof: true), [])
        XCTAssertTrue(events.completed)
        XCTAssertEqual(events.failure, "Not logged in · Please run /login")
        XCTAssertEqual(LocalCLIError.fromDiagnostic(events.failure!, tool: .claude).kind, .notSignedIn)
    }

    func testClaudeArgumentsDisableToolsAndCustomizations() {
        let arguments = ClaudeCLI.arguments(model: "haiku")
        XCTAssertEqual(arguments.first, "-p")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--tools")! + 1], "")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--output-format")! + 1], "stream-json")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--model")! + 1], "haiku")
        for flag in ["--safe-mode", "--no-session-persistence", "--include-partial-messages", "--verbose", "--system-prompt"] {
            XCTAssertTrue(arguments.contains(flag), flag)
        }
        XCTAssertFalse(ClaudeCLI.arguments(model: "").contains("--model"))
        XCTAssertFalse(arguments.contains("--dangerously-skip-permissions"))
    }

    func testClaudeSlashPromptsStayPlainText() {
        XCTAssertEqual(ClaudeCLI.stdinPrompt("/cost"), " /cost")
        XCTAssertEqual(ClaudeCLI.stdinPrompt("Translate /cost"), "Translate /cost")
    }

    // MARK: Errors

    func testDiagnosticsMapToActionableErrors() {
        XCTAssertEqual(LocalCLIError.fromDiagnostic("Failed to authenticate. API Error: 403 Request not allowed", tool: .claude).kind, .blocked)
        XCTAssertEqual(LocalCLIError.fromDiagnostic("401 Unauthorized", tool: .codex).kind, .notSignedIn)
        XCTAssertEqual(LocalCLIError.fromDiagnostic("error: unknown option '--safe-mode'", tool: .claude).kind, .outdatedCLI)
        XCTAssertEqual(LocalCLIError.fromDiagnostic("error: unexpected argument '--ephemeral'", tool: .codex).kind, .outdatedCLI)
        XCTAssertTrue(LocalCLIError(.claude, .notSignedIn).localizedDescription.contains("claude auth login"))
        XCTAssertTrue(LocalCLIError(.codex, .notSignedIn).localizedDescription.contains("codex login"))
        XCTAssertTrue(LocalCLIError(.claude, .notSignedIn).needsSettings)
        XCTAssertFalse(LocalCLIError(.claude, .blocked).needsSettings)
    }

    func testDiagnosticsRedactCredentials() {
        let error = LocalCLIError.fromDiagnostic("Rejected sk-fake_test_credential and Bearer fake-auth-value", tool: .codex)
        XCTAssertFalse(error.localizedDescription.contains("fake_test_credential"))
        XCTAssertFalse(error.localizedDescription.contains("fake-auth-value"))
    }

    // MARK: Environment

    func testSystemProxySettingsBecomeProxyVariables() {
        let settings: [String: Any] = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7897,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897,
            "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 7897,
            "ExceptionsList": ["*.local", "169.254/16", "example.internal"],
        ]
        let environment = LocalCLI.proxyEnvironment(from: settings)
        XCTAssertEqual(environment["HTTPS_PROXY"], "http://127.0.0.1:7897")
        XCTAssertEqual(environment["http_proxy"], "http://127.0.0.1:7897")
        XCTAssertNil(environment["ALL_PROXY"], "SOCKS is only a fallback when no HTTP proxy is set.")
        XCTAssertEqual(environment["NO_PROXY"], "localhost,127.0.0.1,::1,.local,example.internal")
        XCTAssertEqual(LocalCLI.proxyEnvironment(from: ["SOCKSEnable": 1, "SOCKSProxy": "10.0.0.2", "SOCKSPort": 1080])["ALL_PROXY"], "socks5h://10.0.0.2:1080")
        XCTAssertEqual(LocalCLI.proxyEnvironment(from: ["HTTPSEnable": 0, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897]), [:])
    }

    func testChildEnvironmentAddsSystemProxyOnlyWhenTheShellHasNone() {
        let executable = URL(fileURLWithPath: "/opt/tools/bin/claude")
        let proxies: [String: Any] = ["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897]
        let gui = LocalCLI.childEnvironment(executable: executable, base: ["PATH": "/usr/bin:/bin", "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "LANTOR_AGENT_ID": "x", "CODEX_THREAD_ID": "t", "ANTHROPIC_API_KEY": "kept"], systemProxies: proxies)
        XCTAssertEqual(gui["HTTPS_PROXY"], "http://127.0.0.1:7897")
        XCTAssertTrue(gui["PATH"]!.hasPrefix("/opt/tools/bin:/usr/bin:/bin"))
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "LANTOR_AGENT_ID", "CODEX_THREAD_ID"] { XCTAssertNil(gui[key], key) }
        XCTAssertEqual(gui["ANTHROPIC_API_KEY"], "kept")

        let terminal = LocalCLI.childEnvironment(executable: executable, base: ["https_proxy": "http://proxy.corp:3128"], systemProxies: proxies)
        XCTAssertEqual(terminal["https_proxy"], "http://proxy.corp:3128")
        XCTAssertNil(terminal["HTTPS_PROXY"], "An explicit shell proxy wins over the system setting.")
    }

    // MARK: Processes

    func testExecutablePathWithSpacesAndInvalidPath() throws {
        let fixture = try makeFixture("#!/bin/sh\nexit 0\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        XCTAssertEqual(LocalCLI.executable(for: .codex, path: fixture.path), fixture)
        XCTAssertNil(LocalCLI.executable(for: .claude, path: fixture.deletingLastPathComponent().path))
        XCTAssertNil(LocalCLI.executable(for: .codex, path: "/does-not-exist/codex"))
    }

    func testProcessPassesPromptThroughStdinAndDrainsLargeStderr() async throws {
        let script = """
        #!/usr/bin/python3
        import json, sys
        prompt = sys.stdin.read()
        sys.stderr.write("diagnostic\\n" * 40000)
        assert '--sandbox' in sys.argv and sys.argv[sys.argv.index('--sandbox') + 1] == 'read-only'
        assert '--ignore-user-config' in sys.argv and '--ephemeral' in sys.argv
        assert '--model' not in sys.argv
        print(json.dumps({'type':'item.completed','item':{'id':'r','type':'agent_message','text':prompt}}))
        print(json.dumps({'type':'turn.completed'}))
        """
        let prompt = "Translate 你好🌈\nLiteral text: $(touch /never) 'quoted' `command`"
        let result = try await invoke(.codex, script: script, prompt: prompt)
        XCTAssertEqual(result, prompt)
    }

    func testFinalFileOverridesEarlierAgentOutput() async throws {
        let script = """
        #!/usr/bin/python3
        import json, sys
        sys.stdin.read()
        assert sys.argv[sys.argv.index('--model') + 1] == 'test-model'
        path = sys.argv[sys.argv.index('--output-last-message') + 1]
        with open(path, 'w') as output: output.write('Correct final answer')
        print(json.dumps({'type':'item.completed','item':{'id':'r','type':'agent_message','text':'Earlier answer'}}))
        print(json.dumps({'type':'turn.completed'}))
        """
        let result = try await invoke(.codex, script: script, model: "test-model")
        XCTAssertEqual(result, "Correct final answer")
    }

    func testFailedTurnNeverReturnsPartialOutputAsSuccess() async throws {
        let script = """
        #!/bin/sh
        cat >/dev/null
        printf '%s\\n' '{"type":"item.completed","item":{"id":"r","type":"agent_message","text":"Incomplete result"}}' '{"type":"turn.failed","error":{"message":"Quota exceeded"}}'
        """
        do {
            _ = try await invoke(.codex, script: script)
            XCTFail("A failed turn must fail even when the CLI exits zero.")
        } catch let error as LocalCLIError {
            XCTAssertTrue(error.localizedDescription.contains("Quota exceeded"))
        }
    }

    func testAuthFailureGivesLoginGuidance() async throws {
        let script = """
        #!/bin/sh
        printf '%s\\n' '{"type":"turn.failed","error":{"message":"401 Unauthorized"}}'
        exit 1
        """
        do {
            _ = try await invoke(.codex, script: script)
            XCTFail("Expected auth failure")
        } catch let error as LocalCLIError {
            XCTAssertTrue(error.localizedDescription.contains("codex login"))
            XCTAssertTrue(error.needsSettings)
        }
    }

    func testClaudeProcessStreamsAndKeepsSlashPromptsLiteral() async throws {
        let script = """
        #!/usr/bin/python3
        import json, os, sys
        prompt = sys.stdin.read()
        assert sys.argv[1] == '-p' and sys.argv[sys.argv.index('--tools') + 1] == ''
        assert '--safe-mode' in sys.argv and '--no-session-persistence' in sys.argv
        assert sys.argv[sys.argv.index('--model') + 1] == 'haiku'
        assert 'CLAUDECODE' not in os.environ
        assert os.environ.get('HTTPS_PROXY') == 'http://127.0.0.1:7897'
        for chunk in ('Echo:', prompt):
            print(json.dumps({'type':'stream_event','event':{'type':'content_block_delta','delta':{'type':'text_delta','text':chunk}}}), flush=True)
        print(json.dumps({'type':'result','subtype':'success','is_error':False,'result':'Echo:' + prompt}))
        """
        let partials = PartialRecorder()
        let result = try await invoke(.claude, script: script, prompt: "/cost", model: "haiku",
                                      base: ["PATH": "/usr/bin:/bin", "CLAUDECODE": "1"],
                                      proxies: ["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897],
                                      onPartial: { partials.append($0) })
        XCTAssertEqual(result, "Echo: /cost")
        XCTAssertEqual(partials.text, "Echo: /cost")
    }

    func testClaudeBlockedRequestExplainsNetwork() async throws {
        let script = """
        #!/bin/sh
        cat >/dev/null
        printf '%s\\n' '{"type":"result","subtype":"success","is_error":true,"result":"Failed to authenticate. API Error: 403 Request not allowed"}'
        exit 1
        """
        do {
            _ = try await invoke(.claude, script: script)
            XCTFail("Expected a blocked request")
        } catch let error as LocalCLIError {
            XCTAssertEqual(error.kind, .blocked)
            XCTAssertTrue(error.localizedDescription.contains("proxy"))
        }
    }

    func testOutdatedClaudeCLIIsReported() async throws {
        let script = "#!/bin/sh\necho \"error: unknown option '--safe-mode'\" >&2\nexit 1\n"
        do {
            _ = try await invoke(.claude, script: script)
            XCTFail("Expected outdated CLI")
        } catch let error as LocalCLIError {
            XCTAssertEqual(error.kind, .outdatedCLI)
            XCTAssertTrue(error.needsSettings)
        }
    }

    func testTimeoutStopsTheProcess() async throws {
        let start = Date()
        do {
            _ = try await invoke(.claude, script: "#!/bin/sh\nexec /bin/sleep 20\n", timeout: 0.15)
            XCTFail("Expected timeout")
        } catch let error as LocalCLIError {
            XCTAssertTrue(error.localizedDescription.contains("too long"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testCancellationStopsAnActiveRun() async throws {
        let fixture = try makeFixture("#!/bin/sh\nexec /bin/sleep 20\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let start = Date()
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let run = LocalCLI.run(tool: .codex, prompt: "hello", path: fixture.path) { continuation.resume(with: $0) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { run.cancel() }
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        }
    }

    func testTimeoutEscalatesWhenTheCLIIgnoresTermination() async throws {
        let start = Date()
        do {
            _ = try await invoke(.codex, script: "#!/usr/bin/python3\nimport signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(20)\n", timeout: 1)
            XCTFail("Expected timeout")
        } catch let error as LocalCLIError {
            XCTAssertTrue(error.localizedDescription.contains("too long"))
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 3)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    // MARK: Live CLIs (JIT_LIVE_CLI=1 swift test --filter Live)

    /// Runs the real CLIs the way a Finder-launched app does: no shell proxy
    /// variables and a minimal PATH, so the system proxy path is exercised.
    func testLiveCodexAndClaude() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JIT_LIVE_CLI"] == "1", "Set JIT_LIVE_CLI=1 to call the installed CLIs.")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = ["HOME": home, "USER": NSUserName(), "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let prompts = [
            "Translate the text into Chinese. Output only the translation.\n\nText:\nThe quick brown fox jumps over the lazy dog.",
            "/cost",
        ]
        for tool in LocalCLITool.allCases {
            guard LocalCLI.executable(for: tool, environment: base) != nil else { print("skip \(tool): not installed"); continue }
            for prompt in prompts {
                let start = Date()
                let partials = PartialRecorder()
                let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    _ = LocalCLI.run(tool: tool, prompt: prompt, model: "", path: "", timeout: 90, baseEnvironment: base,
                                     systemProxies: LocalCLI.systemProxySettings(), onPartial: { partials.append($0) }) { continuation.resume(with: $0) }
                }
                let elapsed = Date().timeIntervalSince(start)
                print(String(format: "LIVE %@ %.1fs partials=%d: %@", tool.rawValue, elapsed, partials.count, result.replacingOccurrences(of: "\n", with: " ⏎ ")))
                XCTAssertFalse(result.isEmpty)
                XCTAssertFalse(result.contains("subscription"), "A slash prompt must not run as a command.")
                XCTAssertLessThan(elapsed, 60)
            }
        }
    }

    // MARK: Helpers

    private final class PartialRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [String] = []
        func append(_ chunk: String) { lock.lock(); chunks.append(chunk); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return chunks.joined() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return chunks.count }
    }

    private func makeFixture(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jit cli fixture " + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake cli")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }

    private func invoke(
        _ tool: LocalCLITool, script: String, prompt: String = "hello", model: String = "", timeout: TimeInterval = 5,
        base: [String: String] = ProcessInfo.processInfo.environment, proxies: [String: Any]? = nil,
        onPartial: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        let fixture = try makeFixture(script)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        return try await withCheckedThrowingContinuation { continuation in
            _ = LocalCLI.run(tool: tool, prompt: prompt, model: model, path: fixture.path, timeout: timeout,
                             baseEnvironment: base, systemProxies: proxies, onPartial: onPartial) {
                continuation.resume(with: $0)
            }
        }
    }
}
