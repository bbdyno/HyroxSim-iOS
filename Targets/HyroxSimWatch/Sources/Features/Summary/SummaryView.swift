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
    var onDone: (() -> Void)? = nil

    private let accent = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(DurationFormatter.hms(workout.totalDuration))
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)

                Text(workout.division?.shortName ?? workout.templateName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)

                Rectangle().fill(accent.opacity(0.3)).frame(height: 0.5).padding(.vertical, 4)

                metricRow("Avg HR", workout.averageHeartRate.map(String.init) ?? "—")
                metricRow("Max HR", workout.maxHeartRate.map(String.init) ?? "—")

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.vertical, 4)

                ForEach(Array(workout.segments.enumerated()), id: \.element.id) { index, record in
                    HStack(spacing: 4) {
                        if record.type == .station {
                            let stIdx = workout.segments[0...index].filter { $0.type == .station }.count
                            Text(String(format: "%02d", stIdx))
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(accent)
                                .cornerRadius(2)
                        }
                        Text(segmentLabel(for: record))
                            .font(.system(size: 11, weight: record.type == .station ? .bold : .regular))
                            .foregroundStyle(record.type == .roxZone ? .gray.opacity(0.5) : .white)
                        Spacer()
                        Text(DurationFormatter.ms(record.activeDuration))
                            .font(.system(size: 11, design: .rounded).monospacedDigit())
                            .foregroundStyle(record.type == .roxZone ? .gray.opacity(0.5) : .white)
                    }
                }

                if let onDone {
                    Button("Done") { onDone() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color.black)
        .navigationTitle(onDone != nil ? "Complete" : "Detail")
        .navigationBarBackButtonHidden(onDone != nil)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.gray)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        }
    }

    private func segmentLabel(for record: SegmentRecord) -> String {
        switch record.type {
        case .run: return "Running"
        case .roxZone: return "Rox Zone"
        case .station: return record.stationDisplayName ?? "Station"
        }
    }
}
