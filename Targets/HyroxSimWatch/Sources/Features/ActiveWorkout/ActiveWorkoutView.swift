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
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 6) {
                header
                Spacer()
                timeBlock
                middleBlock
                heartBlock
                Spacer()
                bottomButtons
            }
            .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.3) {
            WKInterfaceDevice.current().play(.success)
            model.advance()
        }
        .onAppear {
            model.finishHandler = { workout in
                completedWorkout = workout
                showSummary = true
            }
            model.errorHandler = { err in
                print("Workout error: \(err)")
            }
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

    private var backgroundColor: Color {
        switch model.accentKind {
        case .run: return .blue.opacity(0.85)
        case .roxZone: return .orange.opacity(0.85)
        case .station: return .purple.opacity(0.85)
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 0) {
            Text(model.segmentLabel)
                .font(.caption.bold())
                .foregroundStyle(.white)
            if let sub = model.segmentSubLabel {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private var timeBlock: some View {
        VStack(spacing: 2) {
            Text(model.segmentElapsedText)
                .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(model.totalElapsedText)
                .font(.system(size: 16, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    @ViewBuilder
    private var middleBlock: some View {
        switch model.accentKind {
        case .run, .roxZone:
            HStack(spacing: 12) {
                metricColumn(value: model.paceText, label: "PACE")
                metricColumn(value: model.distanceText, label: "KM")
            }
        case .station:
            VStack(spacing: 2) {
                Text(model.stationNameText ?? "—")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text(model.stationTargetText ?? "")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private var heartBlock: some View {
        HStack(spacing: 4) {
            Text(model.heartRateText)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(heartColor)
            Image(systemName: "heart.fill")
                .foregroundStyle(heartColor)
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

    @ViewBuilder
    private var bottomButtons: some View {
        VStack(spacing: 6) {
            // Prominent NEXT button
            Button {
                WKInterfaceDevice.current().play(.success)
                model.advance()
            } label: {
                Text("NEXT ▶")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.3))

            // Small control buttons
            HStack(spacing: 12) {
                Button { model.togglePause() } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button { showEndConfirm = true } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
    }

    private func metricColumn(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
