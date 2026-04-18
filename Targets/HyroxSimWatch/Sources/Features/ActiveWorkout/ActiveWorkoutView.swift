//
//  ActiveWorkoutView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import WatchKit
import HyroxCore
import HyroxPersistenceApple

struct ActiveWorkoutView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var model: WatchActiveWorkoutModel
    @State private var completedWorkout: CompletedWorkout?
    @State private var showSummary = false
    @Binding var navigationPath: NavigationPath

    init(template: WorkoutTemplate, persistence: PersistenceController, syncCoordinator: (any SyncCoordinator)?, navigationPath: Binding<NavigationPath>) {
        _model = State(initialValue: WatchActiveWorkoutModel(
            template: template, persistence: persistence, syncCoordinator: syncCoordinator
        ))
        _navigationPath = navigationPath
    }

    var body: some View {
        // AOD에서는 1초 cadence로 낮춰 화면 부담과 전력 소모를 줄인다.
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 1 : 0.5)) { context in
            WorkoutDisplayView(model: model)
                .task(id: context.date) {
                    model.triggerRefresh()
                }
        }
        .onAppear {
            model.finishHandler = { workout in
                completedWorkout = workout
                showSummary = true
            }
            model.errorHandler = { err in print("Workout error: \(err)") }
            model.goalAlertHandler = {
                WKInterfaceDevice.current().play(.notification)
            }
            Task { await model.start() }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSummary) {
            if let workout = completedWorkout {
                SummaryView(workout: workout, onDone: {
                    navigationPath = NavigationPath()
                })
            }
        }
    }
}
