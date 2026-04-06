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
    @State private var showEndConfirm = false
    @State private var completedWorkout: CompletedWorkout?
    @State private var showSummary = false

    init(template: WorkoutTemplate, persistence: PersistenceController) {
        _model = State(initialValue: WatchActiveWorkoutModel(
            template: template, persistence: persistence
        ))
    }

    var body: some View {
        VStack(spacing: 4) {
            // Header — segment label with accent color
            Text(model.segmentLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accentColor)

            if let sub = model.segmentSubLabel {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }

            // Segment time — large
            Text(model.segmentElapsedText)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            // Total time — smaller
            Text(model.totalElapsedText)
                .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.gray)

            // Middle data row
            middleBlock
                .padding(.vertical, 2)

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

            // Buttons — compact
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

                Button { showEndConfirm = true } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 4)
        .background(Color.black)
        .onAppear {
            model.finishHandler = { workout in
                completedWorkout = workout
                showSummary = true
            }
            model.errorHandler = { err in print("Workout error: \(err)") }
            Task { await model.start() }
        }
        .navigationBarBackButtonHidden(true)
        .alert("End workout?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) { model.endWorkout() }
        }
        .navigationDestination(isPresented: $showSummary) {
            if let workout = completedWorkout {
                SummaryView(workout: workout)
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

    @ViewBuilder
    private var middleBlock: some View {
        switch model.accentKind {
        case .run, .roxZone:
            HStack(spacing: 16) {
                VStack(spacing: 0) {
                    Text(model.paceText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("PACE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.gray)
                }
                VStack(spacing: 0) {
                    Text(model.distanceText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("DIST")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.gray)
                }
            }
        case .station:
            VStack(spacing: 1) {
                Text(model.stationNameText ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(model.stationTargetText ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
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
