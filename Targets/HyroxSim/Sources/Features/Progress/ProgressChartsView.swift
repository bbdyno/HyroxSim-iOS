//
//  ProgressChartsView.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import Charts
import SwiftUI
import HyroxCore

/// 진척 화면의 본문. UIKit 화면(`ProgressViewController`) 위에 얹힌다.
///
/// 계산은 하지 않는다 — `ProgressReport` 가 이미 시간순으로 정리된 값이고, 여기서는
/// 그것을 차트와 문장으로 바꾸기만 한다.
struct ProgressChartsView: View {

    let viewModel: ProgressViewModel

    private var report: ProgressReport { viewModel.report }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if report.hasEnoughRecords {
                    finishCard
                    percentileCard
                    runningCard
                    segmentsCard
                } else {
                    emptyCard
                }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty

    private var emptyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text(viewModel.lastLoadFailed ? L.loadFailed : L.emptyTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.primary)
                Text(L.emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.emptyCount(report.records.count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
            }
        }
    }

    // MARK: - Finish time

    private var finishCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L.sectionFinish)

                if let latest = report.latest {
                    Text(DurationFormatter.hms(latest.totalSeconds))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.primary)
                }

                if let delta = report.totalDeltaSeconds {
                    Text(Self.finishDeltaText(delta))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.deltaColor(delta))
                }

                if let fastest = report.fastest {
                    Text(L.best(DurationFormatter.hms(fastest.totalSeconds)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.tertiary)
                }

                TimeChart(points: report.totalSeries, color: Palette.accent)
            }
        }
    }

    // MARK: - Percentile

    private var percentileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L.sectionPercentile)

                let points = report.records.compactMap { record -> PercentilePoint? in
                    guard let percentile = record.percentile else { return nil }
                    return PercentilePoint(
                        id: record.id,
                        date: record.finishedAt,
                        percentile: percentile
                    )
                }

                if points.count >= ProgressAnalyzer.minimumRecordCount {
                    if let last = points.last {
                        Text(L.percentileValue(last.percentile))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.primary)
                    }
                    if let delta = report.percentileDelta {
                        Text(Self.percentileDeltaText(delta))
                            .font(.system(size: 13, weight: .semibold))
                            // 퍼센타일은 낮을수록 빠르다 — 음수가 좋은 소식.
                            .foregroundStyle(Self.deltaColor(delta))
                    }

                    Chart(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Percentile", point.percentile)
                        )
                        .foregroundStyle(Palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Percentile", point.percentile)
                        )
                        .foregroundStyle(Palette.accent)
                    }
                    // 위로 갈수록 빠른 쪽이 되도록 뒤집는다.
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Palette.grid)
                            AxisValueLabel {
                                if let percentile = value.as(Double.self) {
                                    Text(verbatim: "\(Int(percentile.rounded()))%")
                                        .foregroundStyle(Palette.tertiary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(Palette.grid)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .frame(height: 140)
                } else {
                    Text(L.percentileUnavailable)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Running

    private var runningCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L.sectionRunning)

                HStack(alignment: .top, spacing: 12) {
                    Stat(
                        title: L.firstPace,
                        value: DurationFormatter.pace(report.latest?.firstRunPaceSecondsPerKm),
                        detail: Self.paceDeltaText(report)
                    )
                    Stat(
                        title: L.fade,
                        value: Self.fadeText(report.latest?.runFadeRatio),
                        detail: Self.fadeDeltaText(report)
                    )
                }

                let points = report.records.compactMap { record -> FadePoint? in
                    guard let fade = record.runFadeRatio else { return nil }
                    return FadePoint(id: record.id, date: record.finishedAt, fade: fade)
                }

                if points.count >= ProgressAnalyzer.minimumRecordCount {
                    Chart {
                        // 1.00 = 마지막 런이 첫 런과 같은 속도. 이 선 아래로 붙을수록 좋다.
                        RuleMark(y: .value("Even", 1.0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Palette.grid)

                        ForEach(points) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Fade", point.fade)
                            )
                            .foregroundStyle(Palette.run)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Fade", point.fade)
                            )
                            .foregroundStyle(Palette.run)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Palette.grid)
                            AxisValueLabel {
                                if let fade = value.as(Double.self) {
                                    Text(verbatim: String(format: "%.2f", fade))
                                        .foregroundStyle(Palette.tertiary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(Palette.grid)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                    .frame(height: 120)
                }

                Text(L.fadeHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Segments

    private var segmentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(L.sectionSegments)

                let trends = report.stationTrends
                if trends.isEmpty {
                    Text(L.percentileUnavailable)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                } else {
                    Chart(trends) { trend in
                        BarMark(
                            x: .value("Latest", trend.latestSeconds),
                            y: .value("Segment", Self.title(for: trend.kind))
                        )
                        .foregroundStyle(Self.barColor(trend))
                        .cornerRadius(3)

                        PointMark(
                            x: .value("First", trend.earliestSeconds),
                            y: .value("Segment", Self.title(for: trend.kind))
                        )
                        .symbol(.diamond)
                        .symbolSize(44)
                        .foregroundStyle(Palette.secondary)
                    }
                    .chartYScale(domain: trends.map { Self.title(for: $0.kind) })
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine().foregroundStyle(Palette.grid)
                            AxisValueLabel {
                                if let seconds = value.as(Double.self) {
                                    Text(Self.compactTime(seconds))
                                        .foregroundStyle(Palette.tertiary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisValueLabel()
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .frame(height: CGFloat(trends.count) * 28 + 28)

                    Text(L.firstMarker)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)

                    VStack(spacing: 6) {
                        ForEach(trends.prefix(3)) { trend in
                            HStack {
                                Text(Self.title(for: trend.kind))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.primary)
                                Spacer()
                                Text(DurationFormatter.signedMs(trend.deltaSeconds))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Self.deltaColor(trend.deltaSeconds))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let division = report.division {
                Text(L.footerDivision(division.displayName))
            }
            if let version = viewModel.datasetVersion {
                Text(L.footerDataset(version))
            }
            let skipped = report.skippedCorruptCount + report.skippedIncompatibleCount
            if skipped > 0 {
                Text(L.footerSkipped(skipped))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.tertiary)
        .padding(.horizontal, 4)
    }

    // MARK: - Shared chart pieces

    /// 시간(초) 세로축을 쓰는 꺾은선 하나.
    private struct TimeChart: View {
        let points: [ProgressSeriesPoint]
        let color: Color

        var body: some View {
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Seconds", point.seconds)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Seconds", point.seconds)
                )
                .foregroundStyle(color)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(ProgressChartsView.compactTime(seconds))
                                .foregroundStyle(Palette.tertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .frame(height: 160)
        }
    }

    // MARK: - Presentation helpers

    static func title(for kind: ProgressSegmentKind) -> String {
        switch kind {
        case .run: return HyroxSimStrings.Localizable.Summary.Gap.Row.run
        case .roxZone: return HyroxSimStrings.Localizable.Summary.Gap.Row.roxZone
        case .station(let station): return station.displayName
        }
    }

    /// 축 라벨용 짧은 표기. 1시간을 넘으면 `1:30`, 아니면 `4:20`.
    static func compactTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func finishDeltaText(_ delta: TimeInterval) -> String {
        let rounded = delta.rounded()
        if rounded == 0 { return L.deltaSame }
        let magnitude = DurationFormatter.ms(abs(rounded))
        return rounded < 0 ? L.deltaFaster(magnitude) : L.deltaSlower(magnitude)
    }

    static func percentileDeltaText(_ delta: Double) -> String {
        let sign = delta <= 0 ? "" : "+"
        return String(format: "%@%.1f%%p", sign, delta)
    }

    static func fadeText(_ fade: Double?) -> String {
        guard let fade, fade.isFinite else { return "—" }
        return String(format: "%.2f", fade)
    }

    static func paceDeltaText(_ report: ProgressReport) -> String? {
        guard let first = report.earliest?.firstRunPaceSecondsPerKm,
              let last = report.latest?.firstRunPaceSecondsPerKm else { return nil }
        return DurationFormatter.signedMs(last - first)
    }

    static func fadeDeltaText(_ report: ProgressReport) -> String? {
        guard let first = report.earliest?.runFadeRatio,
              let last = report.latest?.runFadeRatio else { return nil }
        return String(format: "%@%.2f", last - first < 0 ? "" : "+", last - first)
    }

    static func deltaColor(_ delta: Double) -> Color {
        if delta < 0 { return Palette.success }
        if delta > 0 { return Palette.warning }
        return Palette.secondary
    }

    static func barColor(_ trend: ProgressSegmentTrend) -> Color {
        trend.isImproving ? Palette.accent : Palette.roxZone
    }

    // MARK: - Points

    private struct PercentilePoint: Identifiable {
        let id: UUID
        let date: Date
        let percentile: Double
    }

    private struct FadePoint: Identifiable {
        let id: UUID
        let date: Date
        let fade: Double
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }
}

private struct SectionHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Palette.accent)
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.tertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.primary)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// `DesignTokens` 의 SwiftUI 쪽 얼굴. 색은 한 곳에서만 정의한다.
private enum Palette {
    static let background = Color(DesignTokens.Color.background)
    static let surface = Color(DesignTokens.Color.surface)
    static let surfaceElevated = Color(DesignTokens.Color.surfaceElevated)
    static let accent = Color(DesignTokens.Color.accent)
    static let primary = Color(DesignTokens.Color.textPrimary)
    static let secondary = Color(DesignTokens.Color.textSecondary)
    static let tertiary = Color(DesignTokens.Color.textTertiary)
    static let run = Color(DesignTokens.Color.runAccent)
    static let roxZone = Color(DesignTokens.Color.roxZoneAccent)
    static let success = Color(DesignTokens.Color.success)
    static let warning = Color(DesignTokens.Color.destructive)
    static let grid = Color.white.opacity(0.08)
}

// MARK: - Localized strings

private enum L {
    static var emptyTitle: String { HyroxSimStrings.Localizable.Progress.Empty.title }
    static var emptyMessage: String { HyroxSimStrings.Localizable.Progress.Empty.message }
    static var loadFailed: String { HyroxSimStrings.Localizable.Progress.loadFailed }
    static var sectionFinish: String { HyroxSimStrings.Localizable.Progress.Section.finish }
    static var sectionPercentile: String { HyroxSimStrings.Localizable.Progress.Section.percentile }
    static var sectionRunning: String { HyroxSimStrings.Localizable.Progress.Section.running }
    static var sectionSegments: String { HyroxSimStrings.Localizable.Progress.Section.segments }
    static var deltaSame: String { HyroxSimStrings.Localizable.Progress.Finish.deltaSame }
    static var percentileUnavailable: String { HyroxSimStrings.Localizable.Progress.Percentile.unavailable }
    static var firstPace: String { HyroxSimStrings.Localizable.Progress.Running.firstPace }
    static var fade: String { HyroxSimStrings.Localizable.Progress.Running.fade }
    static var fadeHint: String { HyroxSimStrings.Localizable.Progress.Running.fadeHint }
    static var firstMarker: String { HyroxSimStrings.Localizable.Progress.Segments.firstMarker }

    static func emptyCount(_ count: Int) -> String {
        HyroxSimStrings.Localizable.Progress.Empty.countFormat(count)
    }

    static func best(_ time: String) -> String {
        HyroxSimStrings.Localizable.Progress.Finish.bestFormat(time)
    }

    static func deltaFaster(_ amount: String) -> String {
        HyroxSimStrings.Localizable.Progress.Finish.deltaFasterFormat(amount)
    }

    static func deltaSlower(_ amount: String) -> String {
        HyroxSimStrings.Localizable.Progress.Finish.deltaSlowerFormat(amount)
    }

    static func percentileValue(_ percentile: Double) -> String {
        HyroxSimStrings.Localizable.Progress.Percentile.valueFormat(Float(percentile))
    }

    static func footerDivision(_ division: String) -> String {
        HyroxSimStrings.Localizable.Progress.Footer.divisionFormat(division)
    }

    static func footerDataset(_ version: String) -> String {
        HyroxSimStrings.Localizable.Progress.Footer.datasetFormat(version)
    }

    static func footerSkipped(_ count: Int) -> String {
        HyroxSimStrings.Localizable.Progress.Footer.skippedFormat(count)
    }
}
