//
//  RaceLapPage.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 9/20/26.
//

import SwiftUI
import WatchKit
import HyroxCore

/// 랩 카운터 페이지 — 워치 운동 화면의 세 번째 페이지.
///
/// 대회장에서는 런 랩을 선수가 직접 센다. 누락하면 3분/5분/7분 또는 실격이라
/// 가장 가까운 화면(손목)에 큰 숫자로 두고, 크라운·탭·버튼 셋 다로 올릴 수 있게 했다.
/// 랩 수는 기록에 남기지 않는 화면 보조 정보다.
///
/// 같은 페이지에 **누적 델타**를 크게 실었다. 대회에서 의미 있는 숫자는 구간 델타가 아니라
/// "지금까지 누적으로 앞서 있는가"이기 때문이다.
struct RaceLapPage<Model: WorkoutDisplaying & AnyObject>: View {

    let model: Model
    let accentColor: Color

    @State private var crownValue: Double = 0

    /// 크라운으로 셀 수 있는 최대 바퀴. 1 km 트랙 한 바퀴가 아무리 짧아도 이 위로는 가지 않는다.
    private static var maxLaps: Double { 99 }

    var body: some View {
        VStack(spacing: 4) {
            Text("LAP")
                .font(.system(size: 12, weight: .black))
                // 지금 구간 색을 그대로 써서 어느 런의 랩인지 한눈에 이어 보이게 한다.
                .foregroundStyle(model.isLapCounterAvailable ? accentColor : .white.opacity(0.4))

            Text("\(model.lapCount)")
                .font(.system(size: 64, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(model.isLapCounterAvailable ? .white : .white.opacity(0.35))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    WKInterfaceDevice.current().play(.click)
                    model.incrementLap()
                }
                .accessibilityLabel(Strings.addLap)

            HStack(spacing: 16) {
                stepButton(symbol: "minus", label: Strings.removeLap) {
                    model.decrementLap()
                }
                .disabled(model.lapCount == 0)
                .opacity(model.lapCount == 0 ? 0.35 : 1)

                stepButton(symbol: "plus", label: Strings.addLap) {
                    model.incrementLap()
                }
            }

            if model.totalGoalText != "—" {
                totalDeltaBlock
            } else {
                Text(Strings.lapHint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .background(Color.black.ignoresSafeArea())
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: Self.maxLaps,
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear { crownValue = Double(model.lapCount) }
        .onChange(of: crownValue) { _, newValue in
            let rounded = Int(newValue.rounded())
            guard rounded != model.lapCount else { return }
            model.setLapCount(rounded)
        }
        .onChange(of: model.lapCount) { _, newValue in
            // 구간 전환으로 0 이 되거나 버튼으로 바뀐 값을 크라운 위치에 되맞춘다.
            guard Int(crownValue.rounded()) != newValue else { return }
            crownValue = Double(newValue)
        }
    }

    /// 누적 델타 — 레이스 페이지에서는 이 숫자가 주인공이다.
    private var totalDeltaBlock: some View {
        VStack(spacing: 0) {
            Text("TOTAL")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text(model.totalDeltaText)
                .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(model.isOverTotalGoal ? .red : .green)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    private func stepButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 32)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - 문구

    /// 워치 번들에서 직접 읽는다 — 키가 레이스 데이 기능 전체에서 하나로 유지되도록.
    private enum Strings {
        static var addLap: String { localized("race_day.add_lap", fallback: "Add lap") }
        static var removeLap: String { localized("race_day.remove_lap", fallback: "Remove lap") }
        static var lapHint: String { localized("race_day.lap_hint", fallback: "Count your own laps") }

        private static func localized(_ key: String, fallback: String) -> String {
            Bundle.module.localizedString(forKey: key, value: fallback, table: "Localizable")
        }
    }
}
