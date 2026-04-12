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
            workoutContent
                .task(id: context.date) {
                    model.triggerRefresh()
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
        .navigationDestination(isPresented: $showSummary) {
            if let workout = completedWorkout {
                SummaryView(workout: workout, onDone: {
                    navigationPath = NavigationPath()
                })
            }
        }
    }

    @ViewBuilder
    private var workoutContent: some View {
        VStack(spacing: isLuminanceReduced ? 4 : 6) {
            HStack(spacing: 4) {
                if !isLuminanceReduced, model.gpsActive {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(model.gpsStrong ? .green : .orange)
                }
                Text(model.segmentLabel)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(displayAccentColor)
                    .multilineTextAlignment(.center)
            }

            if let sub = model.segmentSubLabel {
                Text(sub)
                    .font(.system(size: isLuminanceReduced ? 10 : 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isLuminanceReduced ? 0.7 : 0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Text(model.segmentElapsedText)
                .font(.system(size: isLuminanceReduced ? 36 : 42, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.66)
                .lineLimit(1)

            if isLuminanceReduced {
                Text(model.totalElapsedText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))

                Text(model.goalDeltaText)
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(goalDeltaColor)
            } else {
                goalBlock

                Text(model.totalElapsedText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.58))

                middleBlock

                HStack(spacing: 4) {
                    Text(model.heartRateText)
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(displayHeartColor)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(displayHeartColor)
                }
            }

            Spacer(minLength: 2)

            if !isLuminanceReduced {
                WorkoutControlBar(
                    isPaused: model.isPaused,
                    isLastSegment: model.isLastSegment,
                    accentColor: accentColor,
                    onTogglePause: {
                        WKInterfaceDevice.current().play(.click)
                        model.togglePause()
                    },
                    onAdvance: {
                        WKInterfaceDevice.current().play(model.isLastSegment ? .success : .directionUp)
                        model.advance()
                    },
                    onEnd: {
                        WKInterfaceDevice.current().play(.stop)
                        model.endWorkout()
                    }
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .background(displayBackground.ignoresSafeArea())
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

    @ViewBuilder
    private var middleBlock: some View {
        switch model.accentKind {
        case .run, .roxZone:
            HStack(spacing: 8) {
                metricPill(value: model.paceText, label: "PACE", tint: .white)
                metricPill(value: model.distanceText, label: "DIST", tint: displayAccentColor)
            }
        case .station:
            VStack(spacing: 4) {
                Text(model.stationNameText ?? "—")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(displayAccentColor)
                    .multilineTextAlignment(.center)
                if let target = model.stationTargetText {
                    Text(target)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
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

    private var displayBackground: Color {
        if isLuminanceReduced { return .black }
        if model.isOverGoal { return Color(red: 0.34, green: 0.06, blue: 0.06) }

        switch model.accentKind {
        case .run: return Color(red: 0.05, green: 0.15, blue: 0.3)
        case .roxZone: return Color(red: 0.25, green: 0.15, blue: 0.0)
        case .station: return Color(red: 0.15, green: 0.12, blue: 0.0)
        }
    }

    private var goalDeltaColor: Color {
        if model.goalText == "—" { return .white.opacity(0.8) }
        return model.isOverGoal ? .red : .green
    }

    private var goalBlock: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("GOAL")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.55))
                Text(model.goalText)
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Text(model.goalDeltaText)
                .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(goalDeltaColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(model.isOverGoal ? 0.12 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricPill(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
