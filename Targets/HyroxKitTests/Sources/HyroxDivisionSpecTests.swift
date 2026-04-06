import XCTest
@testable import HyroxKit

final class HyroxDivisionSpecTests: XCTestCase {

    private let expectedOrder: [StationKind] = [
        .skiErg, .sledPush, .sledPull, .burpeeBroadJumps,
        .rowing, .farmersCarry, .sandbagLunges, .wallBalls
    ]

    func testAllDivisionsReturn8Stations() {
        for division in HyroxDivision.allCases {
            let specs = HyroxDivisionSpec.stations(for: division)
            XCTAssertEqual(specs.count, 8, "\(division) should have 8 stations")
        }
    }

    func testStationOrderIsCorrect() {
        for division in HyroxDivision.allCases {
            let specs = HyroxDivisionSpec.stations(for: division)
            let kinds = specs.map(\.kind)
            XCTAssertEqual(kinds, expectedOrder, "\(division) station order mismatch")
        }
    }

    func testMenOpenSledPushWeight() {
        let specs = HyroxDivisionSpec.stations(for: .menOpenSingle)
        let sledPush = specs.first { $0.kind == .sledPush }
        XCTAssertEqual(sledPush?.weightKg, 152)
    }

    func testWomenOpenWallBallsRepsAndWeight() {
        let specs = HyroxDivisionSpec.stations(for: .womenOpenSingle)
        let wallBalls = specs.first { $0.kind == .wallBalls }
        XCTAssertEqual(wallBalls?.target, .reps(count: 75))
        XCTAssertEqual(wallBalls?.weightKg, 4)
    }

    func testMenProSandbagLungesWeight() {
        let specs = HyroxDivisionSpec.stations(for: .menProSingle)
        let lunges = specs.first { $0.kind == .sandbagLunges }
        XCTAssertEqual(lunges?.weightKg, 30)
    }

    func testMixedDoubleUsesMenuOpenSpec() {
        let mixed = HyroxDivisionSpec.stations(for: .mixedDouble)
        let menOpen = HyroxDivisionSpec.stations(for: .menOpenSingle)
        XCTAssertEqual(mixed, menOpen)
    }
}
