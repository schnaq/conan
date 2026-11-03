import XCTest
@testable import ConanMacropad

final class PadProtocolTests: XCTestCase {
    func testDecodesEveryEvent() {
        XCTAssertEqual(PadEvent.decode(#"{"t":"hello","v":1}"#), .hello)
        XCTAssertEqual(PadEvent.decode(#"{"t":"key","n":0}"#), .key(0))
        XCTAssertEqual(PadEvent.decode(#"{"t":"key","n":8}"#), .key(8))
        XCTAssertEqual(PadEvent.decode(#"{"t":"stop"}"#), .stop)
        XCTAssertEqual(PadEvent.decode(#"{"t":"neben","down":true}"#), .neben(down: true))
        XCTAssertEqual(PadEvent.decode(#"{"t":"today","down":false}"#), .today(down: false))
        XCTAssertEqual(PadEvent.decode(#"{"t":"enc","d":-2}"#), .encoder(-2))
        XCTAssertEqual(PadEvent.decode(#"{"t":"press"}"#), .press)
    }

    func testRejectsInvalidLines() {
        XCTAssertNil(PadEvent.decode(""))
        XCTAssertNil(PadEvent.decode("{\"t\":\"key\""))          // cut off mid-line
        XCTAssertNil(PadEvent.decode(#"{"t":"key","n":9}"#))      // no such key
        XCTAssertNil(PadEvent.decode(#"{"t":"key"}"#))
        XCTAssertNil(PadEvent.decode(#"{"t":"enc","d":0}"#))
        XCTAssertNil(PadEvent.decode(#"{"t":"dance"}"#))
        XCTAssertNil(PadEvent.decode("Traceback (most recent call last):"))
    }

    func testStateLineIsVersionedJSONEndingInNewline() throws {
        var state = PadState()
        state.mood = "work"
        state.title = "kunde-a"
        let line = state.encodedLine()
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any])
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual(object["mood"] as? String, "work")
        XCTAssertEqual(object["view"] as? String, "main")
        XCTAssertEqual((object["leds"] as? [String])?.count, 12)
        XCTAssertEqual((object["grid"] as? [Any])?.count, 9)
        XCTAssertEqual(object["fx"] as? String, "none")
    }

    func testLineBufferJoinsChunksAndSplitsLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("{\"t\":".utf8)), [])
        XCTAssertEqual(buffer.append(Data("\"stop\"}\n{\"t\":\"press\"}\n{\"t".utf8)), [#"{"t":"stop"}"#, #"{"t":"press"}"#])
        XCTAssertEqual(buffer.append(Data("\":\"hello\"}\r\n".utf8)), [#"{"t":"hello"}"#])
    }

    func testLineBufferDropsOverlongLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data(String(repeating: "x", count: 2000).utf8)), [])
        XCTAssertEqual(buffer.append(Data("yyy\n{\"t\":\"stop\"}\n".utf8)), [#"{"t":"stop"}"#])
    }
}
