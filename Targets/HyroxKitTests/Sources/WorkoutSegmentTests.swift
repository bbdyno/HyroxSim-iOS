import XCTest
@testable import HyroxKit

final class WorkoutSegmentTests: XCTestCase {

    // MARK: - Convenience Constructors

    func testRunConvenienceConstructor() {
        let segment = WorkoutSegment.run()
        XCTAssertEqual(segment.type, .run)
        XCTAssertEqual(segment.distanceMeters, 1000)
        XCTAssertNil(segment.stationKind)
        XCTAssertNil(segment.weightKg)
    }

    func testRunWithCustomDistance() {
        let segment = WorkoutSegment.run(distanceMeters: 500)
        XCTAssertEqual(segment.distanceMeters, 500)
    }

    func testRoxZoneConvenienceConstructor() {
        let segment = WorkoutSegment.roxZone()
        XCTAssertEqual(segment.type, .roxZone)
        XCTAssertNil(segment.distanceMeters)
        XCTAssertNil(segment.stationKind)
    }

    func testStationConvenienceConstructor() {
        let segment = WorkoutSegment.station(.skiErg, target: .distance(meters: 1000))
        XCTAssertEqual(segment.type, .station)
        XCTAssertEqual(segment.stationKind, .skiErg)
        XCTAssertEqual(segment.stationTarget, .distance(meters: 1000))
        XCTAssertNil(segment.distanceMeters)
    }

    func testStationWithWeight() {
        let segment = WorkoutSegment.station(.sledPush, target: .distance(meters: 50), weightKg: 152, weightNote: "sled total")
        XCTAssertEqual(segment.weightKg, 152)
        XCTAssertEqual(segment.weightNote, "sled total")
    }

    // MARK: - Validation (valid cases)

    func testValidRunSegment() {
        XCTAssertNoThrow(try WorkoutSegment.run().validate())
    }

    func testValidStationSegment() {
        XCTAssertNoThrow(try WorkoutSegment.station(.wallBalls, target: .reps(count: 100), weightKg: 6).validate())
    }

    func testValidRoxZoneSegment() {
        XCTAssertNoThrow(try WorkoutSegment.roxZone().validate())
    }

    // MARK: - Validation (invalid cases)

    func testRunWithStationKindThrows() {
        let segment = WorkoutSegment(type: .run, stationKind: .skiErg)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .runSegmentHasStationData)
        }
    }

    func testRunWithWeightThrows() {
        let segment = WorkoutSegment(type: .run, weightKg: 10)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .runSegmentHasStationData)
        }
    }

    func testRoxZoneWithWeightThrows() {
        let segment = WorkoutSegment(type: .roxZone, weightKg: 10)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .runSegmentHasStationData)
        }
    }

    func testStationWithDistanceThrows() {
        let segment = WorkoutSegment(type: .station, distanceMeters: 1000, stationKind: .skiErg)
        XCTAssertThrowsError(try segment.validate()) { error in
            XCTAssertEqual(error as? WorkoutSegment.ValidationError, .stationSegmentHasDistanceData)
        }
    }
}
