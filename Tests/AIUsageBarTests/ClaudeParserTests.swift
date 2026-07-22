import XCTest
@testable import AIUsageBar

final class ClaudeParserTests: XCTestCase {
    func testParsesAssistantUsage() {
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00.123456Z","sessionId":"s1","cwd":"/Users/x/proj","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":50,"cache_read_input_tokens":30}}}"#
        let e = SessionParser.parseClaude(line: line, fallbackProject: "fb")
        XCTAssertEqual(e?.provider, .claude)
        XCTAssertEqual(e?.model, "claude-opus-4-8")
        XCTAssertEqual(e?.project, "/Users/x/proj")
        XCTAssertEqual(e?.input, 100); XCTAssertEqual(e?.output, 200)
        XCTAssertEqual(e?.cacheWrite, 50); XCTAssertEqual(e?.cacheRead, 30)
    }
    func testUserLineReturnsNil() {
        XCTAssertNil(SessionParser.parseClaude(line: #"{"type":"user","message":{"role":"user"}}"#, fallbackProject: "fb"))
    }
    func testSyntheticModelSkipped() {
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00Z","sessionId":"s","message":{"model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}"#
        XCTAssertNil(SessionParser.parseClaude(line: line, fallbackProject: "fb"))
    }
    func testFallbackProjectWhenNoCwd() {
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00Z","sessionId":"s","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1,"output_tokens":1}}}"#
        XCTAssertEqual(SessionParser.parseClaude(line: line, fallbackProject: "fb")?.project, "fb")
    }
}
