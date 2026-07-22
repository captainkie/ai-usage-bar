import XCTest
@testable import AIUsageBar

final class ScanTests: XCTestCase {
    func testScanClaudeDir() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aub-\(UUID().uuidString)")
        let projDir = tmp.appendingPathComponent("Users-x-proj")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00Z","sessionId":"s","cwd":"/Users/x/proj","message":{"model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":10}}}"#
        try line.write(to: projDir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let events = SessionParser.scanClaude(root: tmp)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].project, "/Users/x/proj")
    }
}
