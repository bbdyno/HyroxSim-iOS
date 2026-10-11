//
//  SegmentStripView.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import UIKit
import HyroxCore

/// 레이스 전체를 한 줄로 보여주는 구간 띠. 런 블록과 스테이션이 번갈아 한 칸씩.
/// 칸 색으로 목표 대비 앞섬/뒤짐, 현재 위치, 남은 구간을 표시한다.
final class SegmentStripView: UIView {

    enum Cell: Equatable {
        case ahead, behind, current, upcoming, neutral

        var color: UIColor {
            switch self {
            case .ahead: return DesignTokens.Color.accent
            case .behind: return DesignTokens.Color.overGoal
            case .current: return .white
            case .upcoming: return UIColor(white: 0.2, alpha: 1)
            case .neutral: return UIColor(white: 0.45, alpha: 1)
            }
        }
    }

    var cells: [Cell] = [] {
        didSet { if cells != oldValue { setNeedsDisplay() } }
    }

    private let cellHeight: CGFloat
    private let gap: CGFloat = 2

    init(cellHeight: CGFloat = 10) {
        self.cellHeight = cellHeight
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = false
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: cellHeight)
    }

    override func draw(_ rect: CGRect) {
        guard !cells.isEmpty, bounds.width > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
        let count = CGFloat(cells.count)
        let width = max((bounds.width - gap * (count - 1)) / count, 1)
        for (index, cell) in cells.enumerated() {
            ctx.setFillColor(cell.color.cgColor)
            ctx.fill(CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height))
        }
    }
}

// MARK: - Plan blocks

/// 띠의 한 칸에 해당하는 계획 단위: 런 블록(런 + 앞뒤 록스존) 또는 스테이션.
struct PlanBlock: Hashable {
    let tag: String
    let title: String
    let goalSeconds: TimeInterval
    let isStation: Bool
}

extension WorkoutTemplate {

    /// 요약 화면의 "Running n + Rox Zone / 스테이션" 묶음과 같은 규칙으로 나눈다.
    var planBlocks: [PlanBlock] {
        var blocks: [PlanBlock] = []
        var runGoal: TimeInterval = 0
        var runDistance: Double = 0
        var hasRun = false
        var runIndex = 0
        var stationIndex = 0

        func goal(_ segment: WorkoutSegment) -> TimeInterval {
            segment.goalDurationSeconds ?? WorkoutSegment.defaultGoalDurationSeconds(
                for: segment.type,
                distanceMeters: segment.distanceMeters
            )
        }

        func flushRun() {
            guard hasRun else { return }
            runIndex += 1
            let distance = runDistance > 0 ? DistanceFormatter.short(runDistance).uppercased() : ""
            blocks.append(PlanBlock(
                tag: "R\(runIndex)",
                title: distance.isEmpty ? "RUN" : "RUN \(distance)",
                goalSeconds: runGoal,
                isStation: false
            ))
            runGoal = 0
            runDistance = 0
            hasRun = false
        }

        for segment in segments {
            switch segment.type {
            case .run, .roxZone:
                hasRun = true
                runGoal += goal(segment)
                if segment.type == .run { runDistance += segment.distanceMeters ?? 0 }
            case .station:
                flushRun()
                stationIndex += 1
                blocks.append(PlanBlock(
                    tag: String(format: "%02d", stationIndex),
                    title: segment.stationKind?.courseLabel ?? "STATION",
                    goalSeconds: goal(segment),
                    isStation: true
                ))
            }
        }
        flushRun()
        return blocks
    }
}

@MainActor
extension SegmentStripView {

    /// 완료한 운동을 띠 칸 색으로 바꾼다. 목표가 없던 구간은 중립색.
    static func cells(for workout: CompletedWorkout) -> [Cell] {
        func cell(_ tone: WorkoutSummaryViewModel.DeltaTone) -> Cell {
            switch tone {
            case .ahead: return .ahead
            case .behind: return .behind
            case .neutral: return .neutral
            }
        }
        var cells: [Cell] = []
        for section in WorkoutSummaryViewModel(workout: workout).sections {
            if let runGroup = section.runGroup { cells.append(cell(runGroup.delta.tone)) }
            if let station = section.station { cells.append(cell(station.delta.tone)) }
        }
        return cells
    }
}

// MARK: - Shared helpers

extension StationKind {
    /// 표와 띠 옆에 들어가는 짧은 대문자 이름.
    var courseLabel: String {
        switch self {
        case .skiErg: return "SKIERG"
        case .sledPush: return "SLED PUSH"
        case .sledPull: return "SLED PULL"
        case .burpeeBroadJumps: return "BURPEE BJ"
        case .rowing: return "ROWING"
        case .farmersCarry: return "FARMERS"
        case .sandbagLunges: return "LUNGES"
        case .wallBalls: return "WALL BALLS"
        case .custom(let name): return name.uppercased()
        }
    }
}

extension UILabel {
    /// Uppercase caption with letter spacing.
    func setTracked(_ text: String, kern: CGFloat) {
        attributedText = NSAttributedString(string: text, attributes: [.kern: kern])
    }
}
