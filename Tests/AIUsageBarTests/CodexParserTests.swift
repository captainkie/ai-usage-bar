import XCTest
@testable import AIUsageBar

final class CodexParserTests: XCTestCase {
    func testMetaThenTokenCount() {
        let lines = [
          #"{"type":"session_meta","timestamp":"2026-07-20T09:00:00Z","payload":{"cwd":"/Users/x/proj","model":"gpt-5-codex","session_id":"c1","originator":"codex_cli"}}"#,
          #"{"type":"event_msg","timestamp":"2026-07-20T09:05:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":80,"reasoning_output_tokens":40}}}}"#
        ]
        let events = SessionParser.parseCodex(lines: lines)
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.provider, .codex)
        XCTAssertEqual(e.model, "gpt-5-codex")
        XCTAssertEqual(e.project, "/Users/x/proj")
        XCTAssertEqual(e.input, 100)      // 120 - 20 cached
        XCTAssertEqual(e.cacheRead, 20)
        XCTAssertEqual(e.output, 120)     // 80 + 40 reasoning
        XCTAssertEqual(e.cacheWrite, 0)
    }
    func testTokenCountBeforeMetaIsSkipped() {
        let lines = [ #"{"type":"event_msg","timestamp":"2026-07-20T09:05:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"output_tokens":10}}}}"# ]
        XCTAssertTrue(SessionParser.parseCodex(lines: lines).isEmpty)
    }
}
