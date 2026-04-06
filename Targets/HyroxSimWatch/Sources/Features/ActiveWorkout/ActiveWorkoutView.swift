//
//  ActiveWorkoutView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import WatchKit
import HyroxKit

struct ActiveWorkoutView: View {
    @State private var model: WatchActiveWorkoutModel
    @State private var completedWorkout: CompletedWorkout?
    @State private var showSummary = false
    @Binding var navigationPath: NavigationPath

    init(template: WorkoutTemplate, persistence: PersistenceController, navigationPath: Binding<NavigationPath>) {
        _model = State(initialValue: WatchActiveWorkoutModel(
            template: template, persistence: persistence
        ))
        _navigationPath = navigationPath
    }

    var body: some View {
        // TimelineView가 0.5초마다 뷰를 강제 재평가 → 실시간 갱신 보장
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let _ = model.triggerRefresh() // 매 틱마다 모델 갱신
            workoutContent
        }
        .onAppear {
            model.finishHandler = { workout in
                completedWorkout = workout
                showSummary = true
            }
            model.errorHandler = { err in print("Workout error: \(err)") }
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
        VStack(spacing: 4) {
            // Header
            HStack(spacing: 4) {
                if model.gpsActive {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(model.gpsStrong ? .green : .orange)
                }
                Text(model.segmentLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentColor)
            }

            if let sub = model.segmentSubLabel {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }

            // Segment time
            Text(model.segmentElapsedText)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            // Total time
            Text(model.totalElapsedText)
                .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.gray)

            middleBlock.padding(.vertical, 2)

            // Heart rate
            HStack(spacing: 3) {
                Text(model.heartRateText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(heartColor)
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(heartColor)
            }

            Spacer(minLength: 2)

            // Buttons
            HStack(spacing: 8) {
                Button { model.togglePause() } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.gray)

                Button {
                    WKInterfaceDevice.current().play(.success)
                    model.advance()
                } label: {
                    Text(model.isLastSegment ? "FINISH" : "NEXT")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isLastSegment ? .yellow : accentColor)

                Button {
                    WKInterfaceDevice.current().play(.stop)
                    model.endWorkout()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 4)
        .background(Color.black)
    }

    private var accentColor: Color {
        switch model.accentKind {
        case .run: return .blue
        case .roxZone: return .orange
        case .station: return .yellow
        }
    }

    @ViewBuilder
    private var middleBlock: some View {
        switch model.accentKind {
        case .run, .roxZone:
            HStack(spacing: 16) {
                VStack(spacing: 0) {
                    Text(model.paceText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("PACE").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
                }
                VStack(spacing: 0) {
                    Text(model.distanceText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text("DIST").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
                }
            }
        case .station:
            VStack(spacing: 1) {
                Text(model.stationNameText ?? "—")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.yellow)
                Text(model.stationTargetText ?? "")
                    .font(.system(size: 11)).foregroundStyle(.gray)
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
}
