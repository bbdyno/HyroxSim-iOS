//
//  ConfirmStartView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import HyroxCore
import HyroxPersistenceApple

struct ConfirmStartView: View {
    let template: WorkoutTemplate
    let persistence: PersistenceController
    let syncCoordinator: (any SyncCoordinator)?
    @Binding var navigationPath: NavigationPath
    @State private var showActive = false

    private let accent = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        VStack(spacing: 10) {
            Text(template.division?.displayName ?? template.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            let stations = template.segments.filter { $0.type == .station }.count
            let mins = Int(template.estimatedDurationSeconds / 60)
            Text("\(stations) stations · ~\(mins) min")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)

            Button {
                showActive = true
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .foregroundStyle(.black)
        }
        .padding()
        .background(Color.black)
        .navigationDestination(isPresented: $showActive) {
            ActiveWorkoutView(template: template, persistence: persistence, syncCoordinator: syncCoordinator, navigationPath: $navigationPath)
                .navigationBarBackButtonHidden(true)
        }
    }
}
