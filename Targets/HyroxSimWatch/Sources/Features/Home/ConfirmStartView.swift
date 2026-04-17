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
    @State private var resolvedTemplate: WorkoutTemplate
    private let goalOverrideStore = TemplateGoalOverrideStore()

    private let accent = Color(red: 1.0, green: 0.84, blue: 0.0)

    init(
        template: WorkoutTemplate,
        persistence: PersistenceController,
        syncCoordinator: (any SyncCoordinator)?,
        navigationPath: Binding<NavigationPath>
    ) {
        self.template = template
        self.persistence = persistence
        self.syncCoordinator = syncCoordinator
        self._navigationPath = navigationPath
        self._resolvedTemplate = State(initialValue: TemplateGoalOverrideStore().resolvedTemplate(from: template))
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(resolvedTemplate.division?.displayName ?? resolvedTemplate.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            let stations = resolvedTemplate.segments.filter { $0.type == .station }.count
            Text("\(stations) stations")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gray)

            goalLabel

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
        .onReceive(NotificationCenter.default.publisher(for: .hyroxTemplateGoalOverrideUpdated)) { _ in
            resolvedTemplate = goalOverrideStore.resolvedTemplate(from: template)
        }
        .navigationDestination(isPresented: $showActive) {
            ActiveWorkoutView(template: resolvedTemplate, persistence: persistence, syncCoordinator: syncCoordinator, navigationPath: $navigationPath)
                .navigationBarBackButtonHidden(true)
        }
    }

    @ViewBuilder
    private var goalLabel: some View {
        let total = Int(resolvedTemplate.estimatedDurationSeconds.rounded())
        VStack(spacing: 2) {
            Text("GOAL")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(accent)
                .tracking(0.5)
            Text(formatHMS(total))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    private func formatHMS(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
