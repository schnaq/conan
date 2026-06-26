import XCTest
@testable import ConanCore

final class WatsonModelsTests: XCTestCase {
    func testDecodeReport() throws {
        let json = """
        {
          "projects": [
            { "name": "bechtle", "tags": [], "time": 296.0 },
            { "name": "unlock", "tags": [{ "name": "feature", "time": 100.0 }], "time": 4548.0 }
          ],
          "time": 4844.0,
          "timespan": { "from": "2026-06-26T00:00:00+02:00", "to": "2026-06-26T23:59:59.999999+02:00" }
        }
        """

        let report = try JSONDecoder().decode(WatsonReport.self, from: Data(json.utf8))

        XCTAssertEqual(report.projects.count, 2)
        XCTAssertEqual(report.projects[0].name, "bechtle")
        XCTAssertEqual(report.projects[0].time, 296.0)
        XCTAssertTrue(report.projects[0].tags.isEmpty)
        XCTAssertEqual(report.projects[1].tags.first?.name, "feature")
        XCTAssertEqual(report.projects[1].tags.first?.time, 100.0)
        XCTAssertEqual(report.time, 4844.0)
        XCTAssertEqual(report.timespan.from, "2026-06-26T00:00:00+02:00")
    }
}
