//
//  SummaryView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import HyroxCore

struct SummaryView: View {
    let workout: CompletedWorkout
    var onDone: (() -> Void)? = nil

    private let accent = Color(red: 1.0, green: 0.84, blue: 0.0)
    private var totalGoal: TimeInterval? {
        let values = workout.segments.compactMap(\.goalDurationSeconds)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(DurationFormatter.hms(workout.totalDuration))
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)

                if let totalGoal {
                    Text(DurationFormatter.signedMs(workout.totalDuration - totalGoal))
                        .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(deltaColor(for: workout.totalDuration - totalGoal))
                }

                Text(workout.templateName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                heartSummaryRow

                ForEach(Array(workout.segments.enumerated()), id: \.element.id) { index, record in
                    segmentRow(for: record, at: index)
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
            .padding(.vertical, 4)
        }
        .background(Color.black)
        .navigationTitle(Text(onDone != nil ? "nav.complete" : "nav.detail"))
        .navigationBarBackButtonHidden(onDone != nil)
    }

    private var heartSummaryRow: some View {
        HStack(spacing: 12) {
            heartMetric(label: "AVG", value: workout.averageHeartRate.map(String.init) ?? "—")
            Divider()
                .frame(height: 16)
                .overlay(Color.white.opacity(0.14))
            heartMetric(label: "MAX", value: workout.maxHeartRate.map(String.init) ?? "—")
        }
        .padding(.vertical, 2)
    }

    private func heartMetric(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.gray)
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private func segmentRow(for record: SegmentRecord, at index: Int) -> some View {
        let isStation = record.type == .station
        let isRox = record.type == .roxZone

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                if isStation {
                    let stationIndex = workout.segments[0...index].filter { $0.type == .station }.count
                    Text(String(format: "%02d", stationIndex))
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(segmentLabel(for: record))
                        .font(.system(size: 14, weight: isStation ? .bold : .semibold))
                        .foregroundStyle(isRox ? .gray.opacity(0.72) : .white)
                }

                Spacer(minLength: 6)

                Text(DurationFormatter.hms(record.activeDuration))
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isRox ? .gray.opacity(0.72) : .white)
            }

            if let goal = record.goalDurationSeconds {
                HStack {
                    Text(DurationFormatter.signedMs(record.activeDuration - goal))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(deltaColor(for: record.activeDuration - goal))
                    Spacer()
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))
        }
        .padding(.top, 6)
    }

    private func segmentLabel(for record: SegmentRecord) -> String {
        switch record.type {
        case .run: return "Run"
        case .roxZone: return "Rox Zone"
        case .station: return workout.resolvedStationDisplayName(for: record) ?? "Station"
        }
    }

    private func deltaColor(for delta: TimeInterval) -> Color {
        if delta < 0 { return .green }
        if delta > 0 { return .red }
        return .white
    }
}
