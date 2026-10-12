//
//  RaceResultTextParser.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 글자 인식이 돌려준 한 덩어리. 좌표는 이미지 크기에 대한 비율(0...1), 원점은 왼쪽 위.
public struct RecognizedTextLine: Hashable, Sendable, Codable {
    public let text: String
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(text: String, x: Double, y: Double, w: Double, h: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    var midY: Double { y + h / 2 }
}

/// 결과 화면에서 읽어 낸 값. 못 읽은 것은 비어 있다 — 사용자가 확인·보완한 뒤 저장한다.
public struct ParsedRaceResult: Hashable, Sendable {
    public var stationSeconds: [StationKind: Int] = [:]
    /// 러닝 랩, 1번부터. 못 읽은 랩은 nil.
    public var runLapSeconds: [Int?] = Array(repeating: nil, count: 8)
    public var runTotalSeconds: Int?
    public var roxzoneSeconds: Int?
    public var totalSeconds: Int?
    /// 화면에서 찾은 대회 이름 후보 (예: "HYROX 2025 ANAHEIM").
    public var eventName: String?

    public var missingStations: [StationKind] {
        StationKind.standardOrder.filter { stationSeconds[$0] == nil }
    }

    /// 완주 시간. 화면에 총 시간이 없으면(구간 표에는 없다) 구간을 더해서 낸다.
    public var resolvedTotalSeconds: Int? {
        if let totalSeconds { return totalSeconds }
        guard missingStations.isEmpty, let rox = roxzoneSeconds else { return nil }
        let run = runTotalSeconds ?? {
            let laps = runLapSeconds.compactMap { $0 }
            return laps.count == 8 ? laps.reduce(0, +) : nil
        }()
        guard let run else { return nil }
        return run + rox + stationSeconds.values.reduce(0, +)
    }

    /// 쓸 만한 것을 하나라도 읽었는가.
    public var isEmpty: Bool {
        stationSeconds.isEmpty && totalSeconds == nil && runTotalSeconds == nil
    }
}

/// HYROX 결과 화면의 글자에서 구간 기록을 찾는다.
///
/// 두 가지 모양을 다룬다.
/// - **구간 표**: `Split | Time | Place` — 이름과 시간이 같은 줄에 있다.
/// - **공유 카드**: 이름 아래 줄에 시간이 있다.
///
/// 그래서 이름마다 "같은 줄 오른쪽의 시간"을 먼저 찾고, 없으면 "바로 아래 줄의 시간"을 쓴다.
public enum RaceResultTextParser {

    private enum Label: Hashable {
        case station(StationKind)
        case running(Int?)      // 1...8, 번호를 못 읽었으면 nil
        case roxzone
        case runTotal
        case total
    }

    public static func parse(_ lines: [RecognizedTextLine]) -> ParsedRaceResult {
        var result = ParsedRaceResult()
        let times: [(line: RecognizedTextLine, seconds: Int)] = lines.compactMap { line in
            seconds(from: line.text).map { (line, $0) }
        }
        guard !times.isEmpty else { return result }

        var usedTimes = Set<Int>()
        var unnumberedRuns: [(y: Double, seconds: Int)] = []

        // 위에서 아래로. 같은 시간을 두 이름이 나눠 갖지 않게 한다.
        for line in lines.sorted(by: { $0.y < $1.y }) {
            guard seconds(from: line.text) == nil, let label = label(for: line.text) else { continue }
            guard let match = nearestTime(to: line, in: times, excluding: usedTimes) else { continue }
            usedTimes.insert(match.index)
            let value = match.seconds
            switch label {
            case .station(let kind):
                if result.stationSeconds[kind] == nil { result.stationSeconds[kind] = value }
            case .running(let number):
                if let number, (1...8).contains(number), result.runLapSeconds[number - 1] == nil {
                    result.runLapSeconds[number - 1] = value
                } else {
                    unnumberedRuns.append((line.y, value))
                }
            case .roxzone:
                if result.roxzoneSeconds == nil { result.roxzoneSeconds = value }
            case .runTotal:
                if result.runTotalSeconds == nil { result.runTotalSeconds = value }
            case .total:
                if result.totalSeconds == nil { result.totalSeconds = value }
            }
        }

        // 번호를 못 읽은 러닝("Running !")은 비어 있는 칸에 위에서부터 채운다.
        // 빈 칸 수와 딱 맞을 때만 — 어긋나면 잘못된 랩에 넣느니 비워 둔다.
        let emptySlots = result.runLapSeconds.indices.filter { result.runLapSeconds[$0] == nil }
        if !unnumberedRuns.isEmpty, unnumberedRuns.count == emptySlots.count {
            for (slot, run) in zip(emptySlots, unnumberedRuns.sorted { $0.y < $1.y }) {
                result.runLapSeconds[slot] = run.seconds
            }
        }

        result.eventName = eventName(in: lines)
        return result
    }

    // MARK: - 시간

    /// "00:05:03", "1:03:29", "05:03" → 초. 글자 인식이 흔히 틀리는 O/o → 0, l/I → 1 을 되돌린다.
    public static func seconds(from text: String) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: ";", with: ":")
        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        let total = numbers.reduce(0) { $0 * 60 + $1 }
        return total > 0 ? total : nil
    }

    // MARK: - 이름

    private static func label(for text: String) -> Label? {
        let lower = text.lowercased()
        let letters = lower.filter { $0.isLetter }

        // 합계류를 먼저 — "run total" 이 러닝으로, "total run-time" 이 총 시간으로 읽히면 안 된다.
        if letters.contains("bestrun") { return nil }
        if letters.contains("runtotal") || letters.contains("totalrun") { return .runTotal }
        if letters.contains("totaltime") || letters == "total" || letters.contains("finishtime") { return .total }
        if letters.contains("roxzone") { return .roxzone }

        if letters.contains("ski") { return .station(.skiErg) }
        if letters.contains("sledpush") { return .station(.sledPush) }
        if letters.contains("sledpull") { return .station(.sledPull) }
        if letters.contains("burpee") { return .station(.burpeeBroadJumps) }
        if letters.contains("farmer") { return .station(.farmersCarry) }
        if letters.contains("sandbag") || letters.hasSuffix("lunges") && letters.count > 6 {
            return .station(.sandbagLunges)
        }
        if letters.contains("wallball") { return .station(.wallBalls) }

        if letters.hasPrefix("running") || letters == "run" {
            let tail = lower.drop { !$0.isNumber && $0 != "!" && $0 != "|" }
            let digits = tail.filter(\.isNumber)
            if let number = Int(digits) { return .running(number) }
            return .running(nil)
        }
        // "1000m Row" — 러닝·록스존을 거른 뒤에 본다.
        if letters.hasSuffix("row") || letters.contains("rowing") || letters.contains("mrow") {
            return .station(.rowing)
        }
        return nil
    }

    // MARK: - 짝짓기

    private static func nearestTime(
        to label: RecognizedTextLine,
        in times: [(line: RecognizedTextLine, seconds: Int)],
        excluding used: Set<Int>
    ) -> (index: Int, seconds: Int)? {
        // 1) 같은 줄 오른쪽.
        var best: (index: Int, distance: Double)?
        for (index, time) in times.enumerated() where !used.contains(index) {
            let sameRow = abs(time.line.midY - label.midY) <= max(label.h, time.line.h) * 0.6
            guard sameRow, time.line.x > label.x else { continue }
            let distance = time.line.x - label.x
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        if let best { return (best.index, times[best.index].seconds) }

        // 2) 바로 아래 줄, 가로로 겹치는 것.
        for (index, time) in times.enumerated() where !used.contains(index) {
            let gap = time.line.y - (label.y + label.h)
            guard gap > -label.h * 0.3, gap < label.h * 2.5 else { continue }
            let overlaps = time.line.x < label.x + label.w && label.x < time.line.x + time.line.w
            guard overlaps else { continue }
            if best == nil || gap < best!.distance { best = (index, gap) }
        }
        return best.map { ($0.index, times[$0.index].seconds) }
    }

    // MARK: - 대회 이름

    /// "2025 ANAHEIM" 처럼 연도가 들어간 줄을 대회 이름으로 본다.
    private static func eventName(in lines: [RecognizedTextLine]) -> String? {
        for line in lines.sorted(by: { $0.y < $1.y }) {
            let words = line.text.split(separator: " ")
            guard words.count >= 2, words.count <= 5,
                  let year = words.compactMap({ Int($0) }).first(where: { (2017...2100).contains($0) }),
                  seconds(from: line.text) == nil else { continue }
            let rest = words.filter { Int($0) != year }.joined(separator: " ")
            guard rest.contains(where: \.isLetter) else { continue }
            return "HYROX \(year) \(rest)"
        }
        return nil
    }
}
