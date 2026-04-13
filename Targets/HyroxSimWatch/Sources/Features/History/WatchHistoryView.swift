//
//  WatchHistoryView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import HyroxCore
import HyroxPersistenceApple

struct WatchHistoryView: View {
    let persistence: PersistenceController
    @State private var workouts: [CompletedWorkout] = []

    private let accent = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        Group {
            if workouts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.gray)
                    Text("기록 없음")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.gray)
                }
            } else {
                List {
                    ForEach(workouts) { workout in
                        NavigationLink {
                            SummaryView(workout: workout, onDone: {})
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(workout.division?.shortName ?? workout.templateName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Text(DurationFormatter.hms(workout.totalDuration))
                                    .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                                    .foregroundStyle(accent)
                                Text(workout.finishedAt, style: .relative)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.gray)
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
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
            try? persistence.deleteCompletedWorkout(id: workouts[index].id)
        }
        workouts.remove(atOffsets: offsets)
    }

    private func reload() {
        workouts = (try? persistence.fetchAllCompletedWorkouts()) ?? []
    }
}
