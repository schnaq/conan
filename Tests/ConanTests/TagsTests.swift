import XCTest
@testable import ConanCore

final class TagsTests: XCTestCase {
    func testParsesSpaceSeparated() {
        XCTAssertEqual(Tags.parse("meeting review planning"), ["meeting", "review", "planning"])
    }

    func testStripsLeadingPlusAndCommas() {
        XCTAssertEqual(Tags.parse("+meeting, +review"), ["meeting", "review"])
    }

    func testTrimsAndDropsEmpties() {
        XCTAssertEqual(Tags.parse("   spaced   ,, "), ["spaced"])
    }

    func testDeduplicatesPreservingOrder() {
        XCTAssertEqual(Tags.parse("a b a c b"), ["a", "b", "c"])
    }

    func testEmptyInput() {
        XCTAssertEqual(Tags.parse(""), [])
        XCTAssertEqual(Tags.parse("   "), [])
    }
}
