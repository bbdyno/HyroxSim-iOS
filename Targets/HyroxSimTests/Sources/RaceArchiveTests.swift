//
//  RaceArchiveTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import HyroxCore
@testable import HyroxSim

@MainActor
final class RaceArchiveTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("race-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func race(_ name: String, daysAgo: Double, total: Int) -> RaceResult {
        RaceResult(
            eventName: name, date: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400),
            division: .menOpenSingle, totalSeconds: total, stationSeconds: ["skiErg": 240]
        )
    }

    // MARK: - 저장소

    func testStoreStartsEmptyAndKeepsNewestFirst() throws {
        let store = RaceResultStore(directory: directory)
        XCTAssertTrue(store.all().isEmpty)

        try store.save(race("Old", daysAgo: 200, total: 5400))
        try store.save(race("New", daysAgo: 5, total: 5100))

        XCTAssertEqual(store.all().map(\.eventName), ["New", "Old"])
    }

    /// 앱을 다시 켜도 남아 있어야 한다.
    func testStoreSurvivesRelaunch() throws {
        let saved = race("Seoul", daysAgo: 10, total: 5000)
        try RaceResultStore(directory: directory).save(saved)

        XCTAssertEqual(RaceResultStore(directory: directory).all(), [saved])
    }

    func testSavingTheSameIdReplaces_andDeleteRemoves() throws {
        let store = RaceResultStore(directory: directory)
        var item = race("Seoul", daysAgo: 10, total: 5000)
        try store.save(item)
        item.totalSeconds = 4900
        try store.save(item)

        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.totalSeconds, 4900)

        try store.delete(id: item.id)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertTrue(RaceResultStore(directory: directory).all().isEmpty)
    }

    /// 깨진 파일을 빈 목록으로 덮어쓰지 않는다 — 원본을 옆에 남긴다.
    func testCorruptFileIsKeptAside() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("race-results.json")
        try Data("not json".utf8).write(to: file)

        let store = RaceResultStore(directory: directory)
        XCTAssertTrue(store.all().isEmpty)
        let backup = directory.appendingPathComponent("race-results.corrupt.json")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "not json")
    }

    func testSaveNotifies() throws {
        let store = RaceResultStore(directory: directory)
        let changed = expectation(forNotification: RaceResultStore.didChangeNotification, object: store)
        try store.save(race("Seoul", daysAgo: 1, total: 5000))
        wait(for: [changed], timeout: 1)
    }

    // MARK: - 사진 인식

    /// 결과 표처럼 그린 이미지를 실제 Vision 으로 읽어 본다.
    func testScannerReadsARenderedSplitTable() async throws {
        let rows: [(String, String)] = [
            ("Running 1", "00:05:03"), ("1000m SkiErg", "00:03:57"),
            ("Running 2", "00:04:00"), ("50m Sled Push", "00:01:37"),
            ("Running 3", "00:04:17"), ("50m Sled Pull", "00:02:35"),
            ("Running 4", "00:04:05"), ("80m Burpee Broad Jump", "00:02:33"),
            ("Running 5", "00:04:17"), ("1000m Row", "00:04:12"),
            ("Running 6", "00:04:04"), ("200m Farmers Carry", "00:01:28"),
            ("Running 7", "00:03:54"), ("100m Sandbag Lunges", "00:02:41"),
            ("Running 8", "00:04:14"), ("Wall Balls", "00:03:56"),
            ("Roxzone Time", "00:03:58"), ("Run Total", "00:33:51"), ("Best Run Lap", "00:03:54")
        ]
        let size = CGSize(width: 750, height: CGFloat(rows.count) * 60 + 80)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: UIColor.white
            ]
            for (index, row) in rows.enumerated() {
                let y = CGFloat(index) * 60 + 40
                (row.0 as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attributes)
                (row.1 as NSString).draw(at: CGPoint(x: 500, y: y), withAttributes: attributes)
            }
        }

        let parsed = try await RaceResultScanner.scan(image)

        XCTAssertEqual(parsed.stationSeconds, [
            .skiErg: 237, .sledPush: 97, .sledPull: 155, .burpeeBroadJumps: 153,
            .rowing: 252, .farmersCarry: 88, .sandbagLunges: 161, .wallBalls: 236
        ])
        XCTAssertEqual(parsed.runLapSeconds, [303, 240, 257, 245, 257, 244, 234, 254])
        XCTAssertEqual(parsed.roxzoneSeconds, 238)
        XCTAssertEqual(parsed.runTotalSeconds, 2031)
        XCTAssertEqual(parsed.resolvedTotalSeconds, 3648)
    }

    /// 실제 결과 화면 캡처로 확인한다. 캡처는 저장소에 넣지 않으므로, 폴더를 알려 줄 때만 돈다:
    /// `TEST_RUNNER_RACE_SAMPLE_DIR=/path xcodebuild test …` (1.png = 구간 표, 2.png = 공유 카드).
    func testScannerReadsRealSampleScreenshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["RACE_SAMPLE_DIR"] else {
            throw XCTSkip("set RACE_SAMPLE_DIR to run against real screenshots")
        }
        let folder = URL(fileURLWithPath: path)
        let table = try XCTUnwrap(UIImage(contentsOfFile: folder.appendingPathComponent("1.png").path))
        let card = try XCTUnwrap(UIImage(contentsOfFile: folder.appendingPathComponent("2.png").path))

        let fromTable = try await RaceResultScanner.scan(table)
        XCTAssertTrue(fromTable.missingStations.isEmpty)
        XCTAssertEqual(fromTable.stationSeconds[.wallBalls], 236)
        XCTAssertEqual(fromTable.runLapSeconds.compactMap { $0 }.count, 8)
        XCTAssertEqual(fromTable.resolvedTotalSeconds, 3648)

        let fromCard = try await RaceResultScanner.scan(card)
        XCTAssertTrue(fromCard.missingStations.isEmpty)
        XCTAssertEqual(fromCard.stationSeconds[.wallBalls], 367)
        XCTAssertEqual(fromCard.totalSeconds, 3809)
        XCTAssertEqual(fromCard.runTotalSeconds, 1753)
    }
}
