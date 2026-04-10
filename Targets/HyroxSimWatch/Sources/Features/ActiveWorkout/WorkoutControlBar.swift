//
//  WorkoutControlBar.swift
//  HyroxSimWatch
//
//  Created by Codex on 4/10/26.
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
        GeometryReader { proxy in
            let width = proxy.size.width
            let spacing = max(8, width * 0.035)
            let sideSize = min(max(width * 0.23, 44), 54)
            let primarySize = min(max(width * 0.33, 60), 74)

            HStack(spacing: spacing) {
                circularButton(
                    systemName: isPaused ? "play.fill" : "pause.fill",
                    size: sideSize,
                    fill: Color.gray.opacity(0.22),
                    foreground: .white,
                    accessibilityLabel: isPaused ? "Resume Workout" : "Pause Workout",
                    action: onTogglePause
                )

                circularButton(
                    systemName: isLastSegment ? "checkmark" : "arrow.right",
                    size: primarySize,
                    fill: isLastSegment ? .green : accentColor,
                    foreground: .white,
                    accessibilityLabel: isLastSegment ? "Finish Workout" : "Next Segment",
                    action: onAdvance
                )

                circularButton(
                    systemName: "xmark",
                    size: sideSize,
                    fill: Color.red.opacity(0.28),
                    foreground: .white,
                    accessibilityLabel: "End Workout",
                    action: { showEndConfirmation = true }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 82)
        .confirmationDialog("End Workout?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button("End Workout", role: .destructive, action: onEnd)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the red button only if you want to stop this session now.")
        }
    }

    private func circularButton(
        systemName: String,
        size: CGFloat,
        fill: Color,
        foreground: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: max(1.5, size * 0.035))
                Image(systemName: systemName)
                    .font(.system(size: size * 0.34, weight: .black))
                    .foregroundStyle(foreground)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
