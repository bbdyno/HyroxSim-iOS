import XCTest
@testable import HyroxKit

@MainActor
final class TemplatePersistenceTests: XCTestCase {

    private func makeController() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    private func makeSampleTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            name: "Custom HYROX Lite",
            segments: [
                .run(distanceMeters: 500),
                .roxZone(),
                .station(.skiErg, target: .distance(meters: 500)),
                .run(distanceMeters: 500),
                .roxZone(),
                .station(.rowing, target: .distance(meters: 500))
            ]
        )
    }

    func testSaveAndFetchTemplate() throws {
        let ctrl = try makeController()
        let template = makeSampleTemplate()

        try ctrl.saveTemplate(template)
        let fetched = try ctrl.fetchAllTemplates()

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, template.id)
        XCTAssertEqual(fetched[0].name, "Custom HYROX Lite")
        XCTAssertFalse(fetched[0].isBuiltIn)
    }

    func testTemplateSegmentsRoundTrip() throws {
        let ctrl = try makeController()
        let template = makeSampleTemplate()

        try ctrl.saveTemplate(template)
        let fetched = try ctrl.fetchTemplate(id: template.id)

        XCTAssertEqual(fetched.segments.count, 6)
        XCTAssertEqual(fetched.segments[0].type, .run)
        XCTAssertEqual(fetched.segments[0].distanceMeters, 500)
        XCTAssertEqual(fetched.segments[2].stationKind, .skiErg)
        XCTAssertEqual(fetched.segments[5].stationKind, .rowing)
    }

    func testDeleteTemplate() throws {
        let ctrl = try makeController()
        let template = makeSampleTemplate()

        try ctrl.saveTemplate(template)
        try ctrl.deleteTemplate(id: template.id)

        let fetched = try ctrl.fetchAllTemplates()
        XCTAssertEqual(fetched.count, 0)
    }

    func testFetchAllEmptyReturnsEmptyArray() throws {
        let ctrl = try makeController()
        let fetched = try ctrl.fetchAllTemplates()
        XCTAssertEqual(fetched.count, 0)
    }
}
