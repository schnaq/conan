import XCTest
@testable import ConanCore

final class RecentCombosTests: XCTestCase {
    private func frame(_ project: String, _ tags: [String], _ start: String) -> WatsonLogFrame {
        WatsonLogFrame(project: project, tags: tags, start: start)
    }

    func testDistinctMostRecentFirst() {
        let frames = [
            frame("a", [],          "2026-06-20T09:00:00+02:00"),
            frame("a", ["x"],       "2026-06-21T09:00:00+02:00"),
            frame("b", ["y", "z"],  "2026-06-22T09:00:00+02:00"),
            frame("a", ["x"],       "2026-06-23T09:00:00+02:00"),   // dup of a+x, newer
        ]
        let combos = RecentCombos.from(frames)
        XCTAssertEqual(combos.map(\.display), ["a +x", "b +y +z", "a"])
    }

    func testTagsSortedForStableDedupAndDisplay() {
        let frames = [frame("p", ["zeta", "alpha"], "2026-06-23T09:00:00+02:00")]
        let combos = RecentCombos.from(frames)
        XCTAssertEqual(combos.first?.tags, ["alpha", "zeta"])
        XCTAssertEqual(combos.first?.display, "p +alpha +zeta")
    }

    func testUntaggedDisplaysAsBareName() {
        let combos = RecentCombos.from([frame("solo", [], "2026-06-23T09:00:00+02:00")])
        XCTAssertEqual(combos.first?.display, "solo")
    }

    func testRespectsLimit() {
        let frames = (0..<20).map { frame("p\($0)", [], "2026-06-\(String(format: "%02d", 1 + $0))T09:00:00+02:00") }
        XCTAssertEqual(RecentCombos.from(frames, limit: 5).count, 5)
    }

    func testDecodesLogFrameIgnoringExtraKeys() throws {
        let json = """
        [{"id":"abc","project":"bechtle","start":"2026-06-22T08:53:37+02:00","stop":"2026-06-22T09:57:22+02:00","tags":["meeting","review"]}]
        """
        let frames = try JSONDecoder().decode([WatsonLogFrame].self, from: Data(json.utf8))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].project, "bechtle")
        XCTAssertEqual(frames[0].tags, ["meeting", "review"])
        XCTAssertEqual(frames[0].start, "2026-06-22T08:53:37+02:00")
    }
}
