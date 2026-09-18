//
//  PhoneMirrorWorkoutView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/8/26.
//

import SwiftUI
import WatchKit
import HyroxCore

/// 폰에서 시작된 운동을 워치에서 실시간으로 보여주는 컴패니언 뷰.
/// 워치 자체 ActiveWorkoutView 와 동일 레이아웃을 WorkoutDisplayView 로 공유하고,
/// HR 세션 라이프사이클과 goal alert 훅만 이 얇은 래퍼에서 담당한다.
struct PhoneMirrorWorkoutView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let model: PhoneMirrorWorkoutModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            WorkoutDisplayView(model: model)
                .task(id: context.date) {
                    model.interpolate(at: context.date)
                }
        }
        .overlay {
            if model.isStale {
                staleOverlay
            }
        }
        .onAppear {
            model.goalAlertHandler = {
                WKInterfaceDevice.current().play(.notification)
            }
            Task { await model.startHRSession() }
        }
        .onDisappear { model.stopHRSession() }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// 폰 상태가 끊겼을 때의 탈출 경로. 미러 화면엔 뒤로가기가 없어 이 버튼이 유일한 출구다.
    private var staleOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.red)

            Text("No updates from phone")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Button {
                WKInterfaceDevice.current().play(.stop)
                model.closeMirror()
            } label: {
                Text("Close Mirror")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.94).ignoresSafeArea())
    }
}
