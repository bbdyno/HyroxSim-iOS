//
//  SummaryView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import HyroxKit

struct SummaryView: View {
    let workout: CompletedWorkout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(DurationFormatter.hms(workout.totalDuration))
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())

                Text(workout.division?.displayName ?? workout.templateName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                metricRow("Distance", DistanceFormatter.short(workout.totalDistanceMeters))
                metricRow("Avg HR", workout.averageHeartRate.map(String.init) ?? "—")
                metricRow("Max HR", workout.maxHeartRate.map(String.init) ?? "—")
                metricRow("Segments", "\(workout.segments.count)")

                Divider()

                ForEach(Array(workout.segments.enumerated()), id: \.element.id) { index, record in
                    HStack {
                        Circle()
                            .fill(accentColor(for: record.type))
                            .frame(width: 6, height: 6)
                        Text("\(index + 1).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(label(for: record))
                            .font(.caption)
                        Spacer()
                        Text(DurationFormatter.ms(record.activeDuration))
                            .font(.caption.monospacedDigit())
                    }
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Complete")
        .navigationBarBackButtonHidden(true)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private func label(for record: SegmentRecord) -> String {
        switch record.type {
        case .run: return "Run"
        case .roxZone: return "Rox Zone"
        case .station: return record.stationDisplayName ?? "Station"
        }
    }

    private func accentColor(for type: SegmentType) -> Color {
        switch type {
        case .run: return .blue
        case .roxZone: return .orange
        case .station: return .purple
        }
    }
}
