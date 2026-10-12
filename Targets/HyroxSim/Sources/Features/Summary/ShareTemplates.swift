//
//  ShareTemplates.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

/// 공유 이미지 레이아웃. 첫 번째만 무료다.
enum ShareTemplate: Int, CaseIterable {
    /// 기존 요약 카드 (9:16).
    case classic
    /// 완주 시간을 화면 가득 (9:16, 스토리).
    case bigNumber
    /// 구간 기록 표 (4:5, 게시물).
    case splits

    var canvasSize: CGSize {
        switch self {
        case .classic, .bigNumber: return CGSize(width: 1080, height: 1920)
        case .splits: return CGSize(width: 1080, height: 1350)
        }
    }

    var title: String {
        switch self {
        case .classic: return HyroxSimStrings.Localizable.Share.Template.classic
        case .bigNumber: return HyroxSimStrings.Localizable.Share.Template.bigNumber
        case .splits: return HyroxSimStrings.Localizable.Share.Template.splits
        }
    }
}

/// 새 공유 레이아웃이 그리는 값. 기록에서 바로 만든다.
struct ShareCardData {

    struct Split {
        let title: String
        let time: String
        let tone: SegmentStripView.Cell
    }

    let eventTitle: String
    let division: String?
    let dateText: String
    let totalTime: String
    /// 목표 대비 (예: "−0:28"). 목표가 없으면 nil.
    let delta: String?
    let deltaIsAhead: Bool
    let cells: [SegmentStripView.Cell]
    /// 러닝 합계 + 스테이션 8개, 코스 순서.
    let splits: [Split]
    /// "TOP 18%". 수준 데이터가 없거나 공식 코스가 아니면 nil.
    let topPercentText: String?

    @MainActor
    init(workout: CompletedWorkout, topPercent: Double?) {
        let viewModel = WorkoutSummaryViewModel(workout: workout)
        eventTitle = workout.templateName
        division = workout.division?.shortName
        dateText = workout.finishedAt.formatted(.dateTime.year().month(.abbreviated).day())
        totalTime = DurationFormatter.hms(workout.totalActiveDuration)
        let goals = workout.segments.compactMap(\.goalDurationSeconds)
        if goals.count == workout.segments.count, !goals.isEmpty {
            let gap = workout.totalActiveDuration - goals.reduce(0, +)
            delta = (gap <= 0 ? "−" : "+") + DurationFormatter.ms(abs(gap))
            deltaIsAhead = gap <= 0
        } else {
            delta = nil
            deltaIsAhead = true
        }
        cells = SegmentStripView.cells(for: workout)

        var rows: [Split] = []
        let running = (workout.runSegments + workout.roxZoneSegments).reduce(0) { $0 + $1.activeDuration }
        if running > 0 {
            rows.append(Split(
                title: HyroxSimStrings.Localizable.Share.running, time: DurationFormatter.ms(running), tone: .neutral
            ))
        }
        for section in viewModel.sections {
            guard let station = section.station else { continue }
            let tone: SegmentStripView.Cell
            switch station.delta.tone {
            case .ahead: tone = .ahead
            case .behind: tone = .behind
            case .neutral: tone = .neutral
            }
            // 한 시간을 넘지 않는 구간은 "0:" 을 떼어 러닝 합계와 같은 모양으로.
            let time = station.durationText.hasPrefix("0:") && station.durationText.count > 5
                ? String(station.durationText.dropFirst(2)) : station.durationText
            rows.append(Split(title: station.title.uppercased(), time: time, tone: tone))
        }
        splits = rows
        topPercentText = topPercent.map {
            HyroxSimStrings.Localizable.Level.topFormat(LevelViewModel.percentText($0, clamped: false)).uppercased()
        }
    }
}

/// 새 레이아웃 두 가지를 그린다. 화면 스냅샷이 아니라 값으로 그려서 항상 같은 구도가 나온다.
@MainActor
struct ShareTemplateRenderer {

    let data: ShareCardData

    func makeImage(_ template: ShareTemplate) -> UIImage {
        precondition(template != .classic, "classic is drawn by SummaryShareCardRenderer")
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: template.canvasSize, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: template.canvasSize)
            UIColor.black.setFill()
            context.fill(bounds)
            switch template {
            case .bigNumber: drawBigNumber(in: bounds, context: context.cgContext)
            case .splits: drawSplits(in: bounds, context: context.cgContext)
            case .classic: break
            }
        }
    }

    // MARK: - 큰 숫자 (9:16)

    private func drawBigNumber(in bounds: CGRect, context: CGContext) {
        let margin: CGFloat = 90
        let width = bounds.width - margin * 2
        var y: CGFloat = 420

        y = draw(brandLine(), at: y, x: margin, width: width, font: DesignTokens.Font.wide(30, weight: .heavy),
                 color: DesignTokens.Color.textSecondary, kern: 7) + 60
        y = draw(data.eventTitle.uppercased(), at: y, x: margin, width: width,
                 font: DesignTokens.Font.wide(64, weight: .black), color: .white, maxLines: 3) + 14
        y = draw(metaLine(), at: y, x: margin, width: width, font: .systemFont(ofSize: 34, weight: .medium),
                 color: DesignTokens.Color.textSecondary, maxLines: 2) + 150

        y = draw(HyroxSimStrings.Localizable.Share.finish.uppercased(), at: y, x: margin, width: width,
                 font: DesignTokens.Font.wide(30, weight: .heavy), color: DesignTokens.Color.accent, kern: 7) + 8
        y = drawFitted(data.totalTime, at: y, x: margin, width: width, maxSize: 300,
                       color: DesignTokens.Color.accent) + 30

        y = drawStrip(at: y, x: margin, width: width, height: 26, context: context) + 54

        if let delta = data.delta {
            let color = data.deltaIsAhead ? DesignTokens.Color.accent : DesignTokens.Color.overGoal
            let labelBottom = draw(HyroxSimStrings.Localizable.Share.vsGoal.uppercased(), at: y + 44, x: margin, width: width / 2,
                                   font: DesignTokens.Font.wide(28, weight: .heavy),
                                   color: DesignTokens.Color.textSecondary, kern: 5)
            _ = draw(delta, at: y, x: margin + width / 2, width: width / 2, font: DesignTokens.Font.bigNumber(110),
                     color: color, alignment: .right)
            y = max(labelBottom, y + 130) + 30
        }
        if let top = data.topPercentText {
            hairline(at: y, x: margin, width: width, context: context)
            _ = draw(top, at: y + 34, x: margin, width: width, font: DesignTokens.Font.wide(54, weight: .black), color: .white)
        }
        drawFooter(in: bounds, margin: margin)
    }

    // MARK: - 구간 표 (4:5)

    private func drawSplits(in bounds: CGRect, context: CGContext) {
        let margin: CGFloat = 80
        let width = bounds.width - margin * 2
        var y: CGFloat = 80

        y = draw(brandLine(), at: y, x: margin, width: width, font: DesignTokens.Font.wide(26, weight: .heavy),
                 color: DesignTokens.Color.textSecondary, kern: 6) + 26
        // 제목과 완주 시간을 한 줄에.
        let timeFont = DesignTokens.Font.bigNumber(120)
        let timeWidth = (data.totalTime as NSString).size(withAttributes: [.font: timeFont]).width + 8
        _ = draw(data.totalTime, at: y - 10, x: bounds.width - margin - timeWidth, width: timeWidth,
                 font: timeFont, color: DesignTokens.Color.accent, alignment: .right)
        let titleBottom = draw(data.eventTitle.uppercased(), at: y, x: margin, width: width - timeWidth - 30,
                               font: DesignTokens.Font.wide(44, weight: .black), color: .white, maxLines: 2)
        let metaBottom = draw(metaLine(), at: titleBottom + 8, x: margin, width: width - timeWidth - 30,
                              font: .systemFont(ofSize: 28, weight: .medium),
                              color: DesignTokens.Color.textSecondary, maxLines: 2)
        y = max(metaBottom, y + 130) + 30
        y = drawStrip(at: y, x: margin, width: width, height: 20, context: context) + 34

        let footerTop = bounds.height - 120
        let rowHeight = min(96, (footerTop - y) / CGFloat(max(data.splits.count, 1)))
        for split in data.splits {
            hairline(at: y, x: margin, width: width, context: context)
            let textY = y + (rowHeight - 44) / 2
            _ = draw(split.title, at: textY, x: margin, width: width * 0.66,
                     font: DesignTokens.Font.wide(34, weight: .bold), color: .white)
            let color: UIColor = split.tone == .neutral ? .white : split.tone.color
            _ = draw(split.time, at: textY - 4, x: margin + width * 0.66, width: width * 0.34,
                     font: DesignTokens.Font.number(44), color: color, alignment: .right)
            y += rowHeight
        }
        hairline(at: y, x: margin, width: width, context: context)
        drawFooter(in: bounds, margin: margin)
    }

    // MARK: - 공통

    private func brandLine() -> String { "HYROX SIM" }

    private func metaLine() -> String {
        [data.division, data.dateText].compactMap { $0 }.joined(separator: " · ")
    }

    private func drawFooter(in bounds: CGRect, margin: CGFloat) {
        _ = draw("HYROXSIM", at: bounds.height - 96, x: margin, width: bounds.width - margin * 2,
                 font: DesignTokens.Font.wide(24, weight: .heavy), color: DesignTokens.Color.textTertiary, kern: 6)
    }

    private func hairline(at y: CGFloat, x: CGFloat, width: CGFloat, context: CGContext) {
        context.setFillColor(UIColor(white: 0.22, alpha: 1).cgColor)
        context.fill(CGRect(x: x, y: y, width: width, height: 2))
    }

    private func drawStrip(at y: CGFloat, x: CGFloat, width: CGFloat, height: CGFloat, context: CGContext) -> CGFloat {
        guard !data.cells.isEmpty else { return y }
        let gap: CGFloat = 6
        let count = CGFloat(data.cells.count)
        let cellWidth = (width - gap * (count - 1)) / count
        for (index, cell) in data.cells.enumerated() {
            context.setFillColor(cell.color.cgColor)
            context.fill(CGRect(x: x + CGFloat(index) * (cellWidth + gap), y: y, width: cellWidth, height: height))
        }
        return y + height
    }

    /// 글자를 그리고 아래 끝 y 를 돌려준다. 폭을 넘으면 줄을 바꾸고, `maxLines` 를 넘으면 말줄임.
    @discardableResult
    private func draw(
        _ text: String, at y: CGFloat, x: CGFloat, width: CGFloat, font: UIFont, color: UIColor,
        kern: CGFloat = 0, alignment: NSTextAlignment = .left, maxLines: Int = 1
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = maxLines == 1 ? .byTruncatingTail : .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: paragraph
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let limit = CGSize(width: width, height: font.lineHeight * CGFloat(maxLines) + 2)
        let measured = string.boundingRect(
            with: limit, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil
        )
        let rect = CGRect(x: x, y: y, width: width, height: min(ceil(measured.height), limit.height))
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return rect.maxY
    }

    /// 한 줄에 들어가는 가장 큰 크기로 숫자를 그린다.
    private func drawFitted(_ text: String, at y: CGFloat, x: CGFloat, width: CGFloat, maxSize: CGFloat, color: UIColor) -> CGFloat {
        var size = maxSize
        var font = DesignTokens.Font.bigNumber(size)
        while size > 60, (text as NSString).size(withAttributes: [.font: font]).width > width {
            size -= 6
            font = DesignTokens.Font.bigNumber(size)
        }
        return draw(text, at: y, x: x, width: width, font: font, color: color)
    }
}
