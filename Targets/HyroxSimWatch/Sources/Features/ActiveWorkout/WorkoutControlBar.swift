//
//  WorkoutControlBar.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/12/26.
//

import SwiftUI
import WatchKit

struct WorkoutControlBar: View {
    let isLastSegment: Bool
    let accentColor: Color
    let edgeClearance: CGFloat
    let knobSize: CGFloat
    let onAdvance: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isEngaged = false
    @State private var didComplete = false
    @State private var lastHapticMilestone = 0

    var body: some View {
        GeometryReader { proxy in
            let knobRadius = knobSize / 2
            let minCenterX = knobRadius + edgeClearance
            let maxCenterX = proxy.size.width - knobRadius - edgeClearance
            let minCenterY = knobRadius + edgeClearance
            let maxCenterY = proxy.size.height - knobRadius - edgeClearance
            let start = CGPoint(
                x: minCenterX,
                y: maxCenterY
            )
            let end = CGPoint(
                x: maxCenterX,
                y: minCenterY
            )
            let current = point(along: progress, from: start, to: end)
            let isActive = isEngaged || progress > 0
            let slideAccent = isLastSegment ? Color.green : accentColor

            ZStack {
                // Idle hint — knob 근처 짧은 트랙만 표시하여 드래그 방향 인지
                if !isActive {
                    let hintEnd = point(along: 0.18, from: start, to: end)
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: hintEnd)
                    }
                    .stroke(
                        slideAccent.opacity(0.12),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    )
                }

                if isActive {
                    // 전체 경로 배경
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(
                        slideAccent.opacity(0.12),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
                    )

                    // 드래그 진행 라인
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: current)
                    }
                    .stroke(
                        Color.white.opacity(0.28),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )

                    // 도착지 원
                    Circle()
                        .strokeBorder(slideAccent.opacity(0.55), lineWidth: 2)
                        .background(Circle().fill(slideAccent.opacity(0.10)))
                        .frame(width: knobSize, height: knobSize)
                        .position(end)
                }

                knobView(
                    symbolName: isLastSegment ? "checkmark" : "arrow.up.right",
                    current: current
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !didComplete else { return }
                            if !isEngaged {
                                let dx = value.startLocation.x - start.x
                                let dy = value.startLocation.y - start.y
                                let startDistance = sqrt(dx * dx + dy * dy)
                                guard startDistance <= knobSize * 0.95 else { return }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    isEngaged = true
                                }
                                lastHapticMilestone = 0
                                WKInterfaceDevice.current().play(.click)
                            }

                            let nextProgress = projectedProgress(for: value.location, start: start, end: end)
                            let milestone = min(Int(nextProgress * 4), 3)
                            if milestone > lastHapticMilestone {
                                lastHapticMilestone = milestone
                                WKInterfaceDevice.current().play(.click)
                            }
                            progress = nextProgress
                        }
                        .onEnded { _ in
                            guard isEngaged else { return }
                            let completed = progress >= 0.92
                            lastHapticMilestone = 0
                            if completed {
                                didComplete = true
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                                    progress = 1
                                }
                                // knob reset 후 세그먼트 전환 — 순서 중요
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    resetControl()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        onAdvance()
                                    }
                                }
                            } else {
                                resetControl()
                            }
                        }
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .accessibilityElement()
        .accessibilityLabel(isLastSegment ? "Slide to finish workout" : "Slide to next segment")
    }

    private func knobView(symbolName: String, current: CGPoint) -> some View {
        Circle()
            .fill(.white)
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.black)
            }
            .frame(width: knobSize, height: knobSize)
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
            .position(current)
    }

    private func point(along progress: CGFloat, from start: CGPoint, to end: CGPoint) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    private func projectedProgress(for location: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }

        let lx = location.x - start.x
        let ly = location.y - start.y
        let projection = (lx * dx + ly * dy) / lengthSquared
        return min(max(projection, 0), 1)
    }

    private func resetControl() {
        didComplete = false
        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            progress = 0
            isEngaged = false
        }
    }
}

struct WorkoutActionPage: View {
    let isPaused: Bool
    let onTogglePause: () -> Void
    let onEnd: () -> Void

    @State private var showEndConfirmation = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            HStack(spacing: 16) {
                actionCircleButton(
                    title: isPaused ? "Resume" : "Pause",
                    systemName: isPaused ? "play.fill" : "pause.fill",
                    fill: Color.white.opacity(0.1),
                    action: onTogglePause
                )

                actionCircleButton(
                    title: "End",
                    systemName: "xmark",
                    fill: Color.red.opacity(0.24),
                    action: { showEndConfirmation = true }
                )
            }

            Text("Swipe back")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.34))

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .confirmationDialog("End Workout?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button("End Workout", role: .destructive, action: onEnd)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the red control only if you want to stop this session now.")
        }
    }

    private func actionCircleButton(
        title: String,
        systemName: String,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(fill)
                    Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1.5)
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}
