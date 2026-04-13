//
//  ActiveWorkoutView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import WatchKit
import HyroxCore
import HyroxPersistenceApple

struct ActiveWorkoutView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var model: WatchActiveWorkoutModel
    @State private var completedWorkout: CompletedWorkout?
    @State private var showSummary = false
    @Binding var navigationPath: NavigationPath

    init(template: WorkoutTemplate, persistence: PersistenceController, syncCoordinator: (any SyncCoordinator)?, navigationPath: Binding<NavigationPath>) {
        _model = State(initialValue: WatchActiveWorkoutModel(
            template: template, persistence: persistence, syncCoordinator: syncCoordinator
        ))
        _navigationPath = navigationPath
    }

    var body: some View {
        // AOD에서는 1초 cadence로 낮춰 화면 부담과 전력 소모를 줄인다.
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            GeometryReader { proxy in
                workoutContent(in: proxy)
                    .task(id: context.date) {
                        model.triggerRefresh()
                    }
                }
        }
        .onAppear {
            model.finishHandler = { workout in
                completedWorkout = workout
                showSummary = true
            }
            model.errorHandler = { err in print("Workout error: \(err)") }
            model.goalAlertHandler = {
                WKInterfaceDevice.current().play(.notification)
            }
            Task { await model.start() }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSummary) {
            if let workout = completedWorkout {
                SummaryView(workout: workout, onDone: {
                    navigationPath = NavigationPath()
                })
            }
        }
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

    @ViewBuilder
    private func metricsPage(in proxy: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = proxy.size.width < 190 ? 10 : 12
        let topPadding: CGFloat = isLuminanceReduced ? 28 : 34
        let timerSize: CGFloat = isLuminanceReduced ? 38 : 40
        let bottomContentInset: CGFloat = isLuminanceReduced ? 20 : 42
        let edgeClearance = max(proxy.size.width * 0.08, 14)

        VStack(spacing: 2) {
            Text(model.segmentElapsedText)
                .font(.system(size: timerSize, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            totalTimeLine

            activityTitleBlock

            if model.goalText != "—" {
                deltaLine(fontSize: isLuminanceReduced ? 18 : 24)
            }

            if !isLuminanceReduced {
                if let detail = detailText {
                    Text(detail)
                        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(detailColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }

                heartRateLine
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
                    knobSize: 44,
                    onAdvance: {
                        WKInterfaceDevice.current().play(model.isLastSegment ? .success : .directionUp)
                        model.advance()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(nil, value: model.accentKind)
                .animation(nil, value: model.isOverGoal)
            }
        }
    }

    private var accentColor: Color {
        switch model.accentKind {
        case .run: return .blue
        case .roxZone: return .orange
        case .station: return .yellow
        }
    }

    private var displayAccentColor: Color {
        isLuminanceReduced ? .white : accentColor
    }

    private var currentTitleText: String {
        model.currentDisplayTitle
    }

    private var nextTitleText: String? {
        model.nextDisplayTitle.map { "NEXT \($0)" }
    }

    private var activityTitleBlock: some View {
        VStack(spacing: 2) {
            Text(currentTitleText)
                .font(.system(size: isLuminanceReduced ? 14 : 20, weight: .bold))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)

            if !isLuminanceReduced, let next = nextTitleText {
                Text(next)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var detailText: String? {
        switch model.accentKind {
        case .run:
            return model.paceText == "—" ? "PACE —" : "PACE \(model.paceText)"
        case .roxZone:
            return nil
        case .station:
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
        switch model.accentKind {
        case .station:
            return displayAccentColor
        case .roxZone:
            return .white.opacity(0.88)
        case .run:
            return displayAccentColor
        }
    }

    private var detailColor: Color {
        switch model.accentKind {
        case .run:
            return .white.opacity(0.86)
        case .roxZone:
            return .white.opacity(0.72)
        case .station:
            return .white.opacity(0.84)
        }
    }

    @ViewBuilder
    private var displayBackgroundView: some View {
        ZStack {
            Color.black

            // 세그먼트 타입별 배경 틴트
            switch model.accentKind {
            case .run:
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.06, blue: 0.18).opacity(0.55),
                        Color(red: 0.01, green: 0.02, blue: 0.08).opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Color.blue.opacity(0.04)
            case .roxZone:
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.10, blue: 0.02).opacity(0.55),
                        Color(red: 0.08, green: 0.04, blue: 0.01).opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Color.orange.opacity(0.04)
            case .station:
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.16, blue: 0.02).opacity(0.55),
                        Color(red: 0.08, green: 0.06, blue: 0.01).opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Color.yellow.opacity(0.04)
            }

            // 골 초과 시 붉은 오버레이 (기존 로직 유지)
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
        .animation(.easeInOut(duration: 0.4), value: model.accentKind)
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

    private var totalTimeLine: some View {
        Text(model.totalElapsedText)
            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
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
