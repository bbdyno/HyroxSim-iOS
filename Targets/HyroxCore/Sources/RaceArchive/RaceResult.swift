//
//  RaceResult.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 실제 대회에서 받은 공식 기록 한 건.
///
/// 앱에서 잰 운동 기록(`CompletedWorkout`)과 따로 둔다. 대회 기록은 사용자가 결과 화면을
/// 보고 옮긴 값이라 구간이 빠져 있을 수 있고(공유 카드에는 러닝 랩이 없다), 심박·위치도 없다.
public struct RaceResult: Identifiable, Codable, Hashable, Sendable {

    public enum Source: String, Codable, Hashable, Sendable {
        case manual
        /// 결과 화면 사진에서 읽은 값 (사용자가 확인하고 저장).
        case scan
    }

    public let id: UUID
    public var eventName: String
    public var date: Date
    public var division: HyroxDivision
    /// 공식 완주 시간(초).
    public var totalSeconds: Int
    /// 스테이션 기록(초). 키는 `StationKind.dataKey`. 모르는 스테이션은 빠져 있다.
    public var stationSeconds: [String: Int]
    /// 러닝 8회 합계(초).
    public var runTotalSeconds: Int?
    /// 러닝 랩 기록(초), 순서대로. 랩을 모르면 비어 있다.
    public var runLapSeconds: [Int]
    /// 록스존 합계(초).
    public var roxzoneSeconds: Int?
    public var source: Source
    public var note: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        eventName: String,
        date: Date,
        division: HyroxDivision,
        totalSeconds: Int,
        stationSeconds: [String: Int] = [:],
        runTotalSeconds: Int? = nil,
        runLapSeconds: [Int] = [],
        roxzoneSeconds: Int? = nil,
        source: Source = .manual,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventName = eventName
        self.date = date
        self.division = division
        self.totalSeconds = totalSeconds
        self.stationSeconds = stationSeconds
        self.runTotalSeconds = runTotalSeconds
        self.runLapSeconds = runLapSeconds
        self.roxzoneSeconds = roxzoneSeconds
        self.source = source
        self.note = note
        self.createdAt = createdAt
    }

    public func seconds(for station: StationKind) -> Int? {
        station.dataKey.flatMap { stationSeconds[$0] }
    }

    /// 공식 8개 스테이션 기록이 전부 있는가. 있어야 구간별 약점을 볼 수 있다.
    public var hasAllStations: Bool {
        StationKind.standardOrder.allSatisfy { seconds(for: $0) != nil }
    }

    /// 러닝 + 록스존 합계(초). 대회 데이터가 이 둘을 합쳐서 주므로 비교에 쓰는 값이다.
    ///
    /// 러닝 합계와 록스존을 둘 다 알면 더한다. 아니면 완주 시간에서 스테이션을 뺀다 —
    /// 대회 기록은 러닝·록스존·스테이션이 빈틈없이 이어지므로 나머지가 곧 러닝 + 록스존이다.
    public var runningAndRoxzoneSeconds: Int? {
        if let run = runTotalSeconds, let rox = roxzoneSeconds { return run + rox }
        guard hasAllStations else { return nil }
        let stations = StationKind.standardOrder.compactMap { seconds(for: $0) }.reduce(0, +)
        let rest = totalSeconds - stations
        return rest > 0 ? rest : nil
    }

    /// 수준 판정·약점 진단에 넣을 수 있게 공식 코스 기록 모양으로 바꾼다.
    ///
    /// 스테이션이 하나라도 빠졌으면 nil. 러닝은 랩을 알면 랩대로, 모르면 8등분한다
    /// (진단은 러닝을 합계로만 본다). 록스존은 러닝에 합쳐 넣는다.
    public func asCompletedWorkout() -> CompletedWorkout? {
        guard hasAllStations, let running = runningAndRoxzoneSeconds else { return nil }
        let laps: [Double]
        if runLapSeconds.count == 8, let rox = roxzoneSeconds {
            // 록스존을 랩마다 고르게 얹는다.
            laps = runLapSeconds.map { Double($0) + Double(rox) / 8 }
        } else {
            laps = Array(repeating: Double(running) / 8, count: 8)
        }

        var segments: [SegmentRecord] = []
        var cursor = date
        for (index, kind) in StationKind.standardOrder.enumerated() {
            segments.append(SegmentRecord(
                segmentId: UUID(), index: segments.count, type: .run,
                startedAt: cursor, endedAt: cursor.addingTimeInterval(laps[index]),
                plannedDistanceMeters: 1000
            ))
            cursor = cursor.addingTimeInterval(laps[index])
            let station = Double(seconds(for: kind) ?? 0)
            segments.append(SegmentRecord(
                segmentId: UUID(), index: segments.count, type: .station,
                startedAt: cursor, endedAt: cursor.addingTimeInterval(station),
                stationDisplayName: kind.displayName
            ))
            cursor = cursor.addingTimeInterval(station)
        }
        return CompletedWorkout(
            id: id, templateName: eventName, division: division,
            startedAt: date, finishedAt: cursor, segments: segments
        )
    }
}
