//
//  PhoneMirrorWorkoutView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/8/26.
//

import SwiftUI
import WatchKit
import HyroxKit

/// 폰에서 시작된 운동을 워치에서 실시간으로 보여주는 컴패니언 뷰.
/// ActiveWorkoutView와 유사한 레이아웃이지만, 워치 자체 엔진 없이 폰 상태만 표시.
struct PhoneMirrorWorkoutView: View {
    @Bindable var model: PhoneMirrorWorkoutModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 4) {
                // Badge
                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.system(size: 8))
                        .foregroundStyle(model.isConnected ? .yellow : .red)
                    Text(model.isConnected ? "LIVE FROM iPHONE" : "DISCONNECTED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(model.isConnected ? .yellow : .red)
                }

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
                    Button { model.sendTogglePause() } label: {
                        Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)

                    Button {
                        WKInterfaceDevice.current().play(.success)
                        model.sendAdvance()
                    } label: {
                        Text(model.isLastSegment ? "FINISH" : "NEXT")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isLastSegment ? .yellow : accentColor)

                    Button {
                        WKInterfaceDevice.current().play(.stop)
                        model.sendEnd()
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
        .onAppear { Task { await model.startHRSession() } }
        .onDisappear { model.stopHRSession() }
        .navigationBarBackButtonHidden(true)
    }

    private var accentColor: Color {
        switch model.accentKindRaw {
        case "run": return .blue
        case "roxZone": return .orange
        default: return .yellow
        }
    }

    @ViewBuilder
    private var middleBlock: some View {
        switch model.accentKindRaw {
        case "run", "roxZone":
            VStack(spacing: 0) {
                Text(model.paceText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("PACE").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
            }
        default:
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
