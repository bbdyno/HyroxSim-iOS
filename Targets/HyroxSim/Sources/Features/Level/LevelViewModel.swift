//
//  LevelViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import Foundation
import HyroxCore

/// 수준 판정 화면에 그릴 값. 계산은 `LevelAssessor` / `WeaknessDiagnoser` 가 하고,
/// 여기서는 표시용 문자열과 색 구분만 정한다.
struct LevelViewModel {

    struct Row: Hashable {
        enum Tone: Hashable { case lost, gained, even }
        let title: String
        let time: String
        let delta: String
        let level: String
        let tone: Tone
    }

    static let ageGroupKey = "profile.ageGroup"

    let workout: CompletedWorkout
    let dataset: PaceDataset
    private(set) var ageGroup: String?
    private(set) var assessment: LevelAssessment?
    let diagnosis: WeaknessDiagnosis?
    let ageGroupOptions: [String]

    private typealias L = HyroxSimStrings.Localizable.Level

    init(workout: CompletedWorkout, dataset: PaceDataset, ageGroup: String?) {
        self.workout = workout
        self.dataset = dataset
        let options = LevelAssessor.ageGroups(in: dataset)
        self.ageGroupOptions = options
        self.ageGroup = ageGroup.flatMap { options.contains($0) ? $0 : nil }
        self.diagnosis = WeaknessDiagnoser.diagnose(workout, dataset: dataset)
        refreshAssessment()
    }

    mutating func selectAgeGroup(_ label: String?) {
        ageGroup = label
        refreshAssessment()
    }

    private mutating func refreshAssessment() {
        // 순위와 구간 진단이 같은 기준이 되도록 일시정지를 뺀 시간을 쓴다.
        assessment = LevelAssessor.assess(
            finishSeconds: workout.totalActiveDuration, dataset: dataset, ageGroup: ageGroup
        )
    }

    // MARK: - Display

    var caption: String {
        let division = (workout.division ?? dataset.division)?.shortName ?? ""
        return "\(division) · \(DurationFormatter.hms(workout.totalActiveDuration))".uppercased()
    }

    /// 큰 숫자. "18%".
    var headlineValue: String {
        guard let assessment else { return "—" }
        return Self.percentText(assessment.overallTopPercent, clamped: assessment.isOverallClamped)
    }

    var populationText: String? {
        guard let assessment, let athletes = assessment.athletes else { return nil }
        let count = athletes.formatted(.number)
        if let season = assessment.seasonLabel { return L.populationSeasonFormat(count, season) }
        return L.populationFormat(count)
    }

    /// 분포 막대에서 내 위치. 0 = 가장 빠름, 1 = 가장 느림.
    var markerPosition: Double {
        min(1, max(0, (assessment?.overallTopPercent ?? 100) / 100))
    }

    var ageGroupTitle: String { ageGroup ?? L.ageGroupChoose }

    var ageGroupValue: String {
        guard let standing = assessment?.ageGroup else { return "—" }
        return L.topFormat(Self.percentText(standing.topPercent, clamped: standing.isClamped))
    }

    var milestoneTitle: String? {
        guard let milestone = assessment?.nextMilestone else { return nil }
        return L.milestoneFormat(Self.percentText(milestone.topPercent, clamped: false))
    }

    var milestoneGap: String? {
        guard let milestone = assessment?.nextMilestone else { return nil }
        return "−" + DurationFormatter.ms(milestone.gapSeconds)
    }

    var milestoneTarget: String? {
        guard let milestone = assessment?.nextMilestone else { return nil }
        return DurationFormatter.hms(milestone.finishSeconds)
    }

    var rows: [Row] {
        guard let diagnosis else { return [] }
        return diagnosis.items.map { item in
            let tone: Row.Tone = item.lostSeconds >= WeaknessDiagnosis.threshold ? .lost
                : (item.lostSeconds <= -WeaknessDiagnosis.threshold ? .gained : .even)
            let title: String
            switch item.kind {
            case .running: title = L.running
            case .station(let kind): title = kind.courseLabel
            }
            return Row(
                title: title,
                time: DurationFormatter.ms(item.actualSeconds),
                delta: Self.signed(item.lostSeconds),
                level: Self.percentText(item.levelTopPercent, clamped: false),
                tone: tone
            )
        }
    }

    var recoverableText: String? {
        guard let diagnosis, diagnosis.recoverableSeconds >= 1 else { return nil }
        return L.recoverableFormat(DurationFormatter.ms(diagnosis.recoverableSeconds))
    }

    /// 약점에 근력 스테이션이 있으면 근력 보강을 권한다.
    var suggestsStrengthWork: Bool {
        guard let diagnosis else { return false }
        return diagnosis.weaknesses.contains { item in
            guard case .station(let kind) = item.kind else { return false }
            return Self.strengthStations.contains(kind)
        }
    }

    var footnote: String { L.footnote(dataset.datasetVersion) }

    private static let strengthStations: Set<StationKind> = [
        .sledPush, .sledPull, .farmersCarry, .sandbagLunges, .wallBalls
    ]

    /// "18%", "0.6%", 범위 밖이면 "<0.1%" / ">99.9%".
    static func percentText(_ value: Double, clamped: Bool) -> String {
        if clamped { return value < 50 ? "<\(trimmed(value))%" : ">\(trimmed(value))%" }
        if value < 1 { return "\(trimmed(value))%" }
        return "\(Int(value.rounded()))%"
    }

    private static func trimmed(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private static func signed(_ seconds: Double) -> String {
        if abs(seconds) < 1 { return "±0:00" }
        return (seconds > 0 ? "+" : "−") + DurationFormatter.ms(abs(seconds))
    }
}
