//
//  WatchHistoryView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import HyroxKit

struct WatchHistoryView: View {
    let persistence: PersistenceController
    @State private var workouts: [CompletedWorkout] = []

    private let accent = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        Group {
            if workouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 24))
                        .foregroundStyle(.gray)
                    Text("기록 없음")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.gray)
                }
            } else {
                List {
                    ForEach(workouts) { workout in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.division?.shortName ?? workout.templateName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(DurationFormatter.hms(workout.totalDuration))
                                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(accent)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                    .onDelete(perform: deleteWorkouts)
                }
                .listStyle(.plain)
            }
        }
        .background(Color.black)
        .navigationTitle("History")
        .onAppear { reload() }
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            let workout = workouts[index]
            try? persistence.deleteCompletedWorkout(id: workout.id)
        }
        workouts.remove(atOffsets: offsets)
    }

    private func reload() {
        workouts = (try? persistence.fetchAllCompletedWorkouts()) ?? []
    }
}
