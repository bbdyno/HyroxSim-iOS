//
//  WorkoutControlBar.swift
//  HyroxSimWatch
//
//  Created by Codex on 4/12/26.
//

import SwiftUI

struct WorkoutControlBar: View {
    let isPaused: Bool
    let isLastSegment: Bool
    let accentColor: Color
    let onTogglePause: () -> Void
    let onAdvance: () -> Void
    let onEnd: () -> Void

    @State private var showEndConfirmation = false

    var body: some View {
        HStack(spacing: 10) {
            circularButton(
                systemName: isPaused ? "play.fill" : "pause.fill",
                size: 44,
                fill: Color.white.opacity(0.12),
                accessibilityLabel: isPaused ? "Resume Workout" : "Pause Workout",
                action: onTogglePause
            )

            DiagonalSlideControl(
                title: isLastSegment ? "FINISH" : "NEXT",
                accentColor: isLastSegment ? .green : accentColor,
                symbolName: isLastSegment ? "checkmark" : "arrow.up.right",
                onComplete: onAdvance
            )

            circularButton(
                systemName: "xmark",
                size: 44,
                fill: Color.red.opacity(0.22),
                accessibilityLabel: "End Workout",
                action: { showEndConfirmation = true }
            )
        }
        .frame(height: 82)
        .confirmationDialog("End Workout?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button("End Workout", role: .destructive, action: onEnd)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the red control only if you want to stop this session now.")
        }
    }

    private func circularButton(
        systemName: String,
        size: CGFloat,
        fill: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1.5)
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DiagonalSlideControl: View {
    let title: String
    let accentColor: Color
    let symbolName: String
    let onComplete: () -> Void

    @State private var offset: CGSize = .zero
    @State private var didComplete = false

    private let size = CGSize(width: 94, height: 64)
    private let knobSize: CGFloat = 34
    private let padding: CGFloat = 7

    var body: some View {
        let travelX = size.width - knobSize - padding * 2
        let travelY = size.height - knobSize - padding * 2
        let progress = min(
            max(offset.width / travelX, 0),
            max(-offset.height / travelY, 0)
        )

        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.12))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(accentColor.opacity(0.28))
                .mask(alignment: .bottomLeading) {
                    Rectangle()
                        .frame(
                            width: knobSize + padding * 2 + travelX * progress,
                            height: knobSize + padding * 2 + travelY * progress
                        )
                }

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1.5)

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white.opacity(max(0.18, 0.88 - progress)))
                Text("↗")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Circle()
                .fill(.white)
                .overlay {
                    Image(systemName: symbolName)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.black)
                }
                .frame(width: knobSize, height: knobSize)
                .offset(x: offset.width - travelX / 2, y: offset.height + travelY / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !didComplete else { return }
                            let clampedX = min(max(0, value.translation.width), travelX)
                            let clampedY = max(min(0, value.translation.height), -travelY)
                            offset = CGSize(width: clampedX, height: clampedY)
                        }
                        .onEnded { _ in
                            let completed = offset.width >= travelX * 0.82 && -offset.height >= travelY * 0.82
                            if completed {
                                didComplete = true
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.8)) {
                                    offset = CGSize(width: travelX, height: -travelY)
                                }
                                onComplete()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                    didComplete = false
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        offset = .zero
                                    }
                                }
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    offset = .zero
                                }
                            }
                        }
                )
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(title == "FINISH" ? "Slide to finish workout" : "Slide to next segment")
    }
}
