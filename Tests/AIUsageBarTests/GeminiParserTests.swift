import XCTest
@testable import AIUsageBar

final class GeminiParserTests: XCTestCase {
    func testParsesGeminiMessages() {
        let json = #"""
        {"sessionId":"g1","messages":[
          {"type":"user","timestamp":"2026-07-20T08:00:00Z","content":"hi"},
          {"type":"gemini","timestamp":"2026-07-20T08:00:05Z","model":"gemini-2.5-pro","tokens":{"input":100,"output":50,"cached":20,"thoughts":30}}
        ]}
        """#
        let events = SessionParser.parseGemini(contents: json, project: "gemini:abc123")
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.provider, .gemini)
        XCTAssertEqual(e.model, "gemini-2.5-pro")
        XCTAssertEqual(e.input, 80)     // 100 - 20 cached
        XCTAssertEqual(e.cacheRead, 20)
        XCTAssertEqual(e.output, 80)    // 50 + 30 thoughts
    }
}
