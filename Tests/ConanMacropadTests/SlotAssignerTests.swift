import XCTest
@testable import ConanMacropad

final class SlotAssignerTests: XCTestCase {
    func testFirstAssignmentByRank() {
        let slots = SlotAssigner.assign(previous: [], totals: ["b": 10, "a": 30, "c": 20], slots: 3)
        XCTAssertEqual(slots, ["a", "c", "b"])
    }

    func testKeepsSlotsOfStayingProjects() {
        let slots = SlotAssigner.assign(previous: ["b", "a", "c"], totals: ["a": 30, "b": 20, "c": 10], slots: 3)
        XCTAssertEqual(slots, ["b", "a", "c"])
    }

    func testNewcomerTakesVacatedSlot() {
        // "b" drops out of the top 3; "d" takes exactly b's slot, the others stay put.
        let slots = SlotAssigner.assign(previous: ["a", "b", "c"], totals: ["a": 30, "b": 1, "c": 20, "d": 25], slots: 3)
        XCTAssertEqual(slots, ["a", "d", "c"])
    }

    func testFewerProjectsThanSlotsLeavesNil() {
        let slots = SlotAssigner.assign(previous: [], totals: ["a": 5], slots: 3)
        XCTAssertEqual(slots, ["a", nil, nil])
    }

    func testTieBreakAlphabetical() {
        let slots = SlotAssigner.assign(previous: [], totals: ["z": 10, "m": 10, "a": 10], slots: 2)
        XCTAssertEqual(slots, ["a", "m"])
    }

    func testDefaultsToNineSlots() {
        XCTAssertEqual(SlotAssigner.assign(previous: [], totals: [:]).count, 9)
    }
}
