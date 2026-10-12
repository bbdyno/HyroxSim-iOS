//
//  WorkoutDisplayView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/18/26.
//

import SwiftUI
import WatchKit
import HyroxCore

/// 워치 자체 운동(ActiveWorkoutView) 과 폰 미러(PhoneMirrorWorkoutView) 가 공유하는
/// 실시간 메트릭 레이아웃. 데이터/명령은 WorkoutDisplaying 프로토콜로 추상화된다.
struct WorkoutDisplayView<Model: WorkoutDisplaying & AnyObject>: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let model: Model

    var body: some View {
        GeometryReader { proxy in
            workoutContent(in: proxy)
        }
    }

    @ViewBuilder
    private func workoutContent(in proxy: GeometryProxy) -> some View {
        if isLuminanceReduced {
            metricsPage(in: proxy)
        } else {
            TabView {
                metricsPage(in: proxy)

                // 대회용 랩 카운터 — 워치 자체 운동에서만 붙는다(폰 미러는 폰이 센다).
                if model.supportsLapCounter {
                    RaceLapPage(model: model, accentColor: accentColor)
                }

                WorkoutActionPage(
                    isPaused: model.isPaused,
                    onTogglePause: {
                        WKInterfaceDevice.current().play(.click)
                        model.togglePause()
                    },
                    onEnd: {
                        WKInterfaceDevice.current().play(.stop)
                        model.endWorkout()
                    }
                )
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(displayBackgroundView.ignoresSafeArea())
        }
    }

    /// 한눈에 읽히는 것만 둔다: 구간 띠, 지금 구간 이름, 큰 타이머, 목표 대비, 그리고 심박·총 시간.
    /// 페이스·다음 구간·총 목표 대비는 뺐다 — 작은 화면에서 숫자가 많으면 아무것도 안 읽힌다.
    /// 자세한 조작은 옆 페이지(스와이프)에 그대로 있다.
    @ViewBuilder
    private func metricsPage(in proxy: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = proxy.size.width < 190 ? 10 : 12
        let topPadding: CGFloat = 4
        let isCompact = proxy.size.height < 190
        let timerSize: CGFloat = isLuminanceReduced ? 44 : (isCompact ? 50 : 58)
        let edgeClearance = max(proxy.size.width * 0.08, 14)
        let knobSize: CGFloat = 44
        // 넘김 손잡이는 왼쪽 아래 구석에 있다. 심박·총 시간은 그 오른쪽 같은 높이에 둔다 —
        // 손잡이 위로 한 줄을 통째로 비우면 타이머가 작아진다.
        let bottomContentInset: CGFloat = isLuminanceReduced ? 14 : edgeClearance + (knobSize - 20) / 2
        let knobColumn: CGFloat = edgeClearance + knobSize + 6 - horizontalPadding

        VStack(spacing: 0) {
            if !model.stripCells.isEmpty {
                WatchSegmentStrip(cells: model.stripCells, dimmed: isLuminanceReduced)
                    .frame(height: 5)
                    .padding(.bottom, 6)
            }

            Text(currentTitleText.uppercased())
                .font(.system(size: 12, weight: .heavy).width(.expanded))
                .tracking(1.2)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(model.segmentElapsedText)
                .font(.system(size: timerSize, weight: .black).italic().monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if model.goalText != "—" {
                Text(model.goalDeltaText)
                    .font(.system(size: isLuminanceReduced ? 20 : 26, weight: .black).italic().monospacedDigit())
                    .foregroundStyle(goalDeltaColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            } else if !isLuminanceReduced, model.accent == .station, let target = model.stationTargetText {
                // 목표 시간이 없는 스테이션은 수행량이라도 보여 준다.
                Text(target)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            if !isLuminanceReduced {
                HStack(alignment: .lastTextBaseline) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(model.heartRateText)
                            .font(.system(size: 17, weight: .heavy).monospacedDigit())
                    }
                    .foregroundStyle(model.heartRateText == "—" ? .white.opacity(0.5) : displayHeartColor)
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(model.totalElapsedText)
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, knobColumn)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomContentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(displayBackgroundView.ignoresSafeArea())
        .overlay {
            if !isLuminanceReduced {
                WorkoutControlBar(
                    isLastSegment: model.isLastSegment,
                    accentColor: accentColor,
                    edgeClearance: edgeClearance,
                    knobSize: knobSize,
                    onAdvance: {
                        WKInterfaceDevice.current().play(model.isLastSegment ? .success : .directionUp)
                        model.advance()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(nil, value: model.accent)
                .animation(nil, value: model.isOverGoal)
            }
        }
    }

    private var accentColor: Color {
        switch model.accent {
        case .run: return .blue
        case .roxZone: return .orange
        case .station: return .yellow
        }
    }

    private var displayAccentColor: Color {
        isLuminanceReduced ? .white : accentColor
    }

    private var currentTitleText: String {
        model.isConnected ? model.currentDisplayTitle : "PHONE DISCONNECTED"
    }

    private var heartColor: Color {
        switch model.heartRateZone {
        case .z1: return .gray
        case .z2: return .blue
        case .z3: return .green
        case .z4: return .orange
        case .z5: return .red
        case .none: return .white
        }
    }

    private var displayHeartColor: Color {
        isLuminanceReduced ? .white : heartColor
    }

    private var titleColor: Color {
        if !model.isConnected { return .red }
        switch model.accent {
        case .station: return displayAccentColor
        case .roxZone: return .white.opacity(0.88)
        case .run: return displayAccentColor
        }
    }

    /// 운동 중 배경은 항상 블랙 — 구간 종류는 이름 색으로만 구분한다(폰과 같은 규칙).
    private var displayBackgroundView: some View { Color.black }

    private var goalDeltaColor: Color {
        if model.goalText == "—" { return .white.opacity(0.8) }
        // 앞서면 골드, 뒤지면 오렌지 (폰과 같은 규칙).
        return model.isOverGoal ? WatchPalette.overGoal : WatchPalette.accent
    }

}

// MARK: - 구간 띠

enum WatchPalette {
    static let accent = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let overGoal = Color(red: 1.0, green: 0.48, blue: 0.2)
}

/// 레이스 전체를 한 줄로. 끝난 칸은 목표 대비 색, 지금 칸은 흰색.
struct WatchSegmentStrip: View {
    let cells: [SegmentStripState]
    var dimmed = false

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 1.5
            let count = CGFloat(max(cells.count, 1))
            let width = max((proxy.size.width - gap * (count - 1)) / count, 1)
            HStack(spacing: gap) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    Rectangle().fill(color(for: cell)).frame(width: width)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for cell: SegmentStripState) -> Color {
        switch cell {
        case .ahead: return dimmed ? .white.opacity(0.7) : WatchPalette.accent
        case .behind: return dimmed ? .white.opacity(0.45) : WatchPalette.overGoal
        case .neutral: return .white.opacity(0.45)
        case .current: return .white
        case .upcoming: return .white.opacity(0.18)
        }
    }
}
