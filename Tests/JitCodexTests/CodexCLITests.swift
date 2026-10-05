import XCTest
@testable import JitCodex

final class CodexCLITests: XCTestCase, @unchecked Sendable {
    func testProviderMigrationKeepsAPIUsersAndDefaultsNoKeyUsersToCodex() {
        XCTAssertEqual(AIBackend.load(savedValue: nil, apiKey: ""), .codexCLI)
        XCTAssertEqual(AIBackend.load(savedValue: nil, apiKey: "  \n"), .codexCLI)
        XCTAssertEqual(AIBackend.load(savedValue: nil, apiKey: "existing-key"), .chatAPI)
        XCTAssertEqual(AIBackend.load(savedValue: "codexCLI", apiKey: "existing-key"), .codexCLI)
        XCTAssertEqual(AIBackend.load(savedValue: "chatAPI", apiKey: ""), .chatAPI)
    }

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

    func testExecutablePathWithSpacesAndInvalidPath() throws {
        let fixture = try makeFixture("#!/bin/sh\nexit 0\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        XCTAssertEqual(CodexCLI.executable(path: fixture.path), fixture)
        XCTAssertNil(CodexCLI.executable(path: fixture.deletingLastPathComponent().path))
        XCTAssertNil(CodexCLI.executable(path: "/does-not-exist/codex"))
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
        let result = try await invoke(script: script, prompt: prompt)
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
        let result = try await invoke(script: script, model: "test-model")
        XCTAssertEqual(result, "Correct final answer")
    }

    func testFailedTurnNeverReturnsPartialOutputAsSuccess() async throws {
        let script = """
        #!/bin/sh
        cat >/dev/null
        printf '%s\\n' '{"type":"item.completed","item":{"id":"r","type":"agent_message","text":"Incomplete result"}}' '{"type":"turn.failed","error":{"message":"Quota exceeded"}}'
        """
        do {
            _ = try await invoke(script: script)
            XCTFail("A failed turn must fail even when the CLI exits zero.")
        } catch let error as CodexCLIError {
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
            _ = try await invoke(script: script)
            XCTFail("Expected auth failure")
        } catch let error as CodexCLIError {
            XCTAssertTrue(error.localizedDescription.contains("codex login"))
            XCTAssertTrue(error.needsSettings)
        }
    }

    func testTimeoutStopsTheProcess() async throws {
        let start = Date()
        do {
            _ = try await invoke(script: "#!/bin/sh\nexec /bin/sleep 20\n", timeout: 0.15)
            XCTFail("Expected timeout")
        } catch let error as CodexCLIError {
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
                let run = CodexCLI.run(prompt: "hello", path: fixture.path) { continuation.resume(with: $0) }
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
            _ = try await invoke(script: "#!/usr/bin/python3\nimport signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(20)\n", timeout: 1)
            XCTFail("Expected timeout")
        } catch let error as CodexCLIError {
            XCTAssertTrue(error.localizedDescription.contains("too long"))
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 3)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testDiagnosticsRedactCredentials() {
        let error = CodexCLIError.fromDiagnostic("Rejected sk-fake_test_credential and Bearer fake-auth-value")
        XCTAssertFalse(error.localizedDescription.contains("fake_test_credential"))
        XCTAssertFalse(error.localizedDescription.contains("fake-auth-value"))
    }

    private func makeFixture(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jit cli fixture " + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake codex")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }

    private func invoke(script: String, prompt: String = "hello", model: String = "", timeout: TimeInterval = 5) async throws -> String {
        let fixture = try makeFixture(script)
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        return try await withCheckedThrowingContinuation { continuation in
            _ = CodexCLI.run(prompt: prompt, model: model, path: fixture.path, timeout: timeout) {
                continuation.resume(with: $0)
            }
        }
    }
}
