//
//  WorkoutLiveActivity.swift
//  HyroxSimWidgets
//
//  Created by bbdyno on 4/7/26.
//

import ActivityKit
import SwiftUI
import WidgetKit
import HyroxLiveActivityApple

/// HYROX 운동 Live Activity — Dynamic Island + 잠금화면
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // 잠금화면 배너
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.segmentLabel)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accentColor(context.state.accentKind))
                        if let sub = context.state.segmentSubLabel {
                            Text(sub)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.segmentElapsed)
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(context.state.totalElapsed)
                            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(context.state.heartRate, systemImage: "heart.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                            Spacer()
                            if context.state.isPaused {
                                Text("PAUSED")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        // 다음에 뭐가 오는지 — 대회장에서는 현재 구간보다 이쪽이 더 쓸모 있다.
                        if let next = context.state.nextTargetText {
                            nextTargetLine(next)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // Compact — 왼쪽: 세그먼트 타입 아이콘
                Image(systemName: compactIcon(context.state.accentKind))
                    .foregroundStyle(accentColor(context.state.accentKind))
                    .font(.system(size: 12, weight: .bold))
            } compactTrailing: {
                // Compact — 오른쪽: 세그먼트 시간
                Text(context.state.segmentElapsed)
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                // Minimal — 아이콘만
                Image(systemName: "figure.run")
                    .foregroundStyle(accentColor(context.state.accentKind))
            }
        }
    }

    // MARK: - 잠금화면

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: compactIcon(context.state.accentKind))
                        .foregroundStyle(accentColor(context.state.accentKind))
                        .font(.system(size: 11))
                    Text(context.state.segmentLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentColor(context.state.accentKind))
                }
                if let sub = context.state.segmentSubLabel {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let next = context.state.nextTargetText {
                    nextTargetLine(next)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.segmentElapsed)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                Text(context.state.totalElapsed)
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // 심박
            VStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 10))
                Text(context.state.heartRate)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
            }
        }
        .padding(16)
        .background(Color.black)
    }

    // MARK: - 다음 목표

    /// "NEXT Wall Balls · 04:10" 한 줄. 잠금화면과 확장 아일랜드가 같은 모양을 쓴다.
    private func nextTargetLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text("NEXT")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Helpers

    private func accentColor(_ kind: String) -> Color {
        switch kind {
        case "run": return .blue
        case "roxZone": return .orange
        case "station": return Color(red: 1.0, green: 0.84, blue: 0.0)
        default: return .white
        }
    }

    private func compactIcon(_ kind: String) -> String {
        switch kind {
        case "run": return "figure.run"
        case "roxZone": return "arrow.right.circle"
        case "station": return "dumbbell.fill"
        default: return "figure.run"
        }
    }
}
