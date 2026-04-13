//
//  PhoneMirrorWorkoutView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/8/26.
//

import SwiftUI
import WatchKit
import HyroxCore

/// 폰에서 시작된 운동을 워치에서 실시간으로 보여주는 컴패니언 뷰.
/// ActiveWorkoutView와 유사한 레이아웃이지만, 워치 자체 엔진 없이 폰 상태만 표시.
struct PhoneMirrorWorkoutView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Bindable var model: PhoneMirrorWorkoutModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { _ in
            GeometryReader { proxy in
                workoutContent(in: proxy)
            }
        }
        .onAppear {
            model.goalAlertHandler = {
                WKInterfaceDevice.current().play(.notification)
            }
            Task { await model.startHRSession() }
        }
        .onDisappear { model.stopHRSession() }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func workoutContent(in proxy: GeometryProxy) -> some View {
        if isLuminanceReduced {
            metricsPage(in: proxy)
        } else {
            TabView {
                metricsPage(in: proxy)

                WorkoutActionPage(
                    isPaused: model.isPaused,
                    onTogglePause: {
                        WKInterfaceDevice.current().play(.click)
                        model.sendTogglePause()
                    },
                    onEnd: {
                        WKInterfaceDevice.current().play(.stop)
                        model.sendEnd()
                    }
                )
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(displayBackgroundView.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private func metricsPage(in proxy: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = proxy.size.width < 190 ? 10 : 12
        let trailingStatusReserve: CGFloat = isLuminanceReduced ? 16 : 40
        let topPadding: CGFloat = isLuminanceReduced ? 28 : 34
        let timerSize: CGFloat = isLuminanceReduced ? 36 : 38
        let titleSlotHeight: CGFloat = isLuminanceReduced ? 18 : 24
        let nextSlotHeight: CGFloat = isLuminanceReduced ? 0 : 10
        let totalSlotHeight: CGFloat = isLuminanceReduced ? 12 : 12
        let deltaSlotHeight: CGFloat = isLuminanceReduced ? 22 : 26
        let detailSlotHeight: CGFloat = isLuminanceReduced ? 0 : 20
        let heartSlotHeight: CGFloat = isLuminanceReduced ? 0 : 20
        let bottomContentInset: CGFloat = isLuminanceReduced ? 20 : 56
        let edgeClearance = max(proxy.size.width * 0.06, 10)
        let horizontalEdgeInset = max(proxy.size.width * 0.18, 28)
        let routeEndTopInset = max(proxy.safeAreaInsets.top + 72, topPadding + 36)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(model.segmentElapsedText)
                    .font(.system(size: timerSize, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                Color.clear
                    .frame(width: trailingStatusReserve)
            }
            .frame(maxWidth: .infinity, minHeight: timerSize + 6, maxHeight: timerSize + 6)

            totalTimeLine
                .frame(height: totalSlotHeight)

            Color.clear.frame(height: isLuminanceReduced ? 2 : 2)

            activityTitleBlock(titleSlotHeight: titleSlotHeight, nextSlotHeight: nextSlotHeight)

            Color.clear.frame(height: isLuminanceReduced ? 4 : 6)

            deltaLine(fontSize: isLuminanceReduced ? 18 : 24)
                .frame(height: deltaSlotHeight)

            if !isLuminanceReduced {
                Color.clear.frame(height: 6)

                detailLine
                    .frame(height: detailSlotHeight)

                Color.clear.frame(height: 4)

                heartRateLine
                    .frame(height: heartSlotHeight)
            }
        }
        .padding(.leading, horizontalPadding)
        .padding(.trailing, horizontalPadding + trailingStatusReserve)
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
                    knobSize: 44,
                    onAdvance: {
                        WKInterfaceDevice.current().play(model.isLastSegment ? .success : .directionUp)
                        model.sendAdvance()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var accentColor: Color {
        switch model.accentKindRaw {
        case "run": return .blue
        case "roxZone": return .orange
        default: return .yellow
        }
    }

    private var displayAccentColor: Color {
        isLuminanceReduced ? .white : accentColor
    }

    private var currentTitleText: String {
        model.isConnected ? model.currentDisplayTitle : "PHONE DISCONNECTED"
    }

    private var nextTitleText: String? {
        guard model.isConnected else { return nil }
        return model.nextDisplayTitle.map { "NEXT \($0)" }
    }

    private func activityTitleBlock(titleSlotHeight: CGFloat, nextSlotHeight: CGFloat) -> some View {
        VStack(spacing: isLuminanceReduced ? 2 : 4) {
            Text(currentTitleText)
                .font(.system(size: isLuminanceReduced ? 14 : 18, weight: .bold))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: titleSlotHeight, maxHeight: titleSlotHeight)

            if !isLuminanceReduced {
                Text(nextTitleText ?? " ")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(nextTitleText == nil ? 0 : 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: nextSlotHeight, maxHeight: nextSlotHeight)
            }
        }
    }

    private var detailText: String? {
        switch model.accentKindRaw {
        case "run":
            return model.paceText == "—" ? "PACE —" : "PACE \(model.paceText)"
        case "roxZone":
            return nil
        default:
            return model.stationTargetText
        }
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
        if !model.isConnected {
            return .red
        }

        switch model.accentKindRaw {
        case "station":
            return displayAccentColor
        case "roxZone":
            return .white.opacity(0.85)
        case "run":
            return displayAccentColor
        default:
            return .white.opacity(0.85)
        }
    }

    private var detailColor: Color {
        switch model.accentKindRaw {
        case "run":
            return .white.opacity(0.86)
        case "roxZone":
            return .white.opacity(0.72)
        default:
            return .white.opacity(0.84)
        }
    }

    @ViewBuilder
    private var displayBackgroundView: some View {
        ZStack {
            Color.black
            if model.isOverGoal, model.goalText != "—" {
                LinearGradient(
                    colors: [
                        Color(red: 0.32, green: 0.04, blue: 0.07).opacity(0.55),
                        Color(red: 0.12, green: 0.01, blue: 0.02).opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Color.red.opacity(0.06)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isOverGoal)
    }

    private var goalDeltaColor: Color {
        if model.goalText == "—" { return .white.opacity(0.8) }
        return model.isOverGoal ? .red : .green
    }

    private func deltaLine(fontSize: CGFloat) -> some View {
        HStack {
            Spacer()
            Text(model.goalText == "—" ? " " : model.goalDeltaText)
                .font(.system(size: fontSize, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(model.goalText == "—" ? .clear : goalDeltaColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var detailLine: some View {
        Text(detailText ?? " ")
            .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(detailText == nil ? .clear : detailColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }

    private var totalTimeLine: some View {
        Text("TOTAL \(model.totalElapsedText)")
            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.52))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }

    private var heartRateLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(model.heartRateText == "—" ? .white.opacity(0.4) : displayHeartColor)
            Text(model.heartRateText)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(model.heartRateText == "—" ? .white.opacity(0.55) : displayHeartColor)
        }
        .frame(height: 22)
    }
}
