//
//  SummaryShareCardRenderer.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import UIKit

/// 공유 카드에 들어갈 내용. 뷰모델이 채우고 렌더러가 그린다.
///
/// 화면 스냅샷 대신 값으로 받는 이유: 요약 화면 레이아웃이 바뀌어도 공유 이미지는
/// 항상 같은 구도로 나오고, 스크롤 위치·다크 얼럿 같은 화면 상태에 영향받지 않는다.
struct SummaryShareCardContent {

    struct Highlight {
        let title: String
        let valueText: String
        /// 막대 길이. 가장 큰 항목을 1.0 으로 둔 상대값.
        let ratio: Double
    }

    let title: String
    let division: String?
    let dateText: String
    let totalTimeText: String
    let goalText: String?
    let deltaText: String?
    let deltaTone: WorkoutSummaryViewModel.DeltaTone
    /// 격차 분석 섹션 제목. 분석이 없으면 nil.
    let highlightTitle: String?
    /// 격차 분석 상위 구간.
    let highlights: [Highlight]
    /// 격차 분석이 없을 때 대신 보여줄 구간(스테이션 기록).
    let fallbackHighlights: [Highlight]
}

/// 요약을 세로 스토리 비율(1080×1920) 이미지로 그린다.
///
/// 블랙 배경 + 골드 액센트라는 앱 디자인 시스템을 그대로 따른다.
@MainActor
struct SummaryShareCardRenderer {

    /// 인스타그램 스토리 기준 크기. `scale = 1` 로 그려서 결과 픽셀이 그대로 1080×1920 이 된다.
    static let canvasSize = CGSize(width: 1080, height: 1920)

    private enum Metric {
        static let margin: CGFloat = 96
        static let brandTop: CGFloat = 120
        static let rowHeight: CGFloat = 132
        static let barHeight: CGFloat = 10
        static let cornerRadius: CGFloat = 32
    }

    private let content: SummaryShareCardContent

    init(content: SummaryShareCardContent) {
        self.content = content
    }

    func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: Self.canvasSize, format: format)
        return renderer.image { context in
            draw(in: context.cgContext)
        }
    }

    // MARK: - Drawing

    private func draw(in context: CGContext) {
        let bounds = CGRect(origin: .zero, size: Self.canvasSize)
        DesignTokens.Color.background.setFill()
        context.fill(bounds)

        let contentWidth = Self.canvasSize.width - Metric.margin * 2
        var cursor = Metric.brandTop

        cursor = drawBrand(at: cursor, width: contentWidth)
        cursor += 56
        cursor = drawTitleBlock(at: cursor, width: contentWidth)
        cursor += 40
        cursor = drawTotalBlock(at: cursor, width: contentWidth)

        let highlights = content.highlights.isEmpty ? content.fallbackHighlights : content.highlights
        if !highlights.isEmpty {
            cursor += 72
            cursor = drawHighlights(highlights, at: cursor, width: contentWidth)
        }

        drawFooter(width: contentWidth)
    }

    private func drawBrand(at y: CGFloat, width: CGFloat) -> CGFloat {
        let brand = NSAttributedString(
            string: "HYROX SIM",
            attributes: [
                .font: UIFont.systemFont(ofSize: 44, weight: .black),
                .foregroundColor: DesignTokens.Color.accent,
                .kern: 6
            ]
        )
        brand.draw(at: CGPoint(x: Metric.margin, y: y))

        let ruleY = y + brand.size().height + 28
        DesignTokens.Color.accent.setFill()
        UIBezierPath(rect: CGRect(x: Metric.margin, y: ruleY, width: width, height: 4)).fill()
        return ruleY + 4
    }

    private func drawTitleBlock(at y: CGFloat, width: CGFloat) -> CGFloat {
        var cursor = y

        if let division = content.division {
            let text = NSAttributedString(
                string: division.uppercased(),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                    .foregroundColor: DesignTokens.Color.textSecondary,
                    .kern: 3
                ]
            )
            text.draw(in: CGRect(x: Metric.margin, y: cursor, width: width, height: 48))
            cursor += 54
        }

        let title = NSAttributedString(
            string: content.title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 56, weight: .heavy),
                .foregroundColor: DesignTokens.Color.textPrimary
            ]
        )
        let titleRect = CGRect(x: Metric.margin, y: cursor, width: width, height: 140)
        title.draw(with: titleRect, options: [.usesLineFragmentOrigin], context: nil)
        return cursor + min(140, ceil(title.boundingRect(
            with: CGSize(width: width, height: 140),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).height))
    }

    private func drawTotalBlock(at y: CGFloat, width: CGFloat) -> CGFloat {
        var cursor = y

        // "1:23:45" 는 190pt 로도 여백 안에 들어가지만, 두 자리 시간대는 넘친다.
        let totalFontSize: CGFloat = content.totalTimeText.count > 7 ? 150 : 190
        let total = NSAttributedString(
            string: content.totalTimeText,
            attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: totalFontSize, weight: .black),
                .foregroundColor: DesignTokens.Color.textPrimary
            ]
        )
        total.draw(at: CGPoint(x: Metric.margin, y: cursor))
        cursor += total.size().height + 16

        var footnotes: [NSAttributedString] = []
        if let goalText = content.goalText {
            footnotes.append(
                NSAttributedString(
                    string: HyroxSimStrings.Localizable.Summary.goalFormat(goalText),
                    attributes: [
                        .font: UIFont.monospacedDigitSystemFont(ofSize: 38, weight: .semibold),
                        .foregroundColor: DesignTokens.Color.textSecondary
                    ]
                )
            )
        }
        if let deltaText = content.deltaText {
            footnotes.append(
                NSAttributedString(
                    string: deltaText,
                    attributes: [
                        .font: UIFont.monospacedDigitSystemFont(ofSize: 38, weight: .black),
                        .foregroundColor: color(for: content.deltaTone)
                    ]
                )
            )
        }

        var x = Metric.margin
        for note in footnotes {
            note.draw(at: CGPoint(x: x, y: cursor))
            x += note.size().width + 32
        }

        return footnotes.isEmpty ? cursor : cursor + (footnotes[0].size().height)
    }

    private func drawHighlights(
        _ highlights: [SummaryShareCardContent.Highlight],
        at y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        var cursor = y

        if let highlightTitle = content.highlightTitle {
            let header = NSAttributedString(
                string: highlightTitle.uppercased(),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 32, weight: .black),
                    .foregroundColor: DesignTokens.Color.accent,
                    .kern: 4
                ]
            )
            header.draw(at: CGPoint(x: Metric.margin, y: cursor))
            cursor += header.size().height + 28
        }

        let cardHeight = CGFloat(highlights.count) * Metric.rowHeight + 48
        let cardRect = CGRect(x: Metric.margin, y: cursor, width: width, height: cardHeight)
        DesignTokens.Color.surface.setFill()
        UIBezierPath(roundedRect: cardRect, cornerRadius: Metric.cornerRadius).fill()

        var rowY = cursor + 24
        for highlight in highlights {
            drawHighlightRow(highlight, y: rowY, width: width)
            rowY += Metric.rowHeight
        }

        return cursor + cardHeight
    }

    private func drawHighlightRow(
        _ highlight: SummaryShareCardContent.Highlight,
        y: CGFloat,
        width: CGFloat
    ) {
        let inset: CGFloat = 40
        let x = Metric.margin + inset
        let rowWidth = width - inset * 2

        let value = NSAttributedString(
            string: highlight.valueText,
            attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .black),
                .foregroundColor: DesignTokens.Color.accent
            ]
        )
        let valueSize = value.size()
        value.draw(at: CGPoint(x: x + rowWidth - valueSize.width, y: y))

        let title = NSAttributedString(
            string: highlight.title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                .foregroundColor: DesignTokens.Color.textPrimary
            ]
        )
        title.draw(
            with: CGRect(x: x, y: y, width: rowWidth - valueSize.width - 24, height: 56),
            options: [.usesLineFragmentOrigin],
            context: nil
        )

        let barY = y + 74
        DesignTokens.Color.surfaceElevated.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: x, y: barY, width: rowWidth, height: Metric.barHeight),
            cornerRadius: Metric.barHeight / 2
        ).fill()

        let ratio = highlight.ratio.isFinite ? min(1, max(0, highlight.ratio)) : 0
        guard ratio > 0 else { return }
        DesignTokens.Color.accent.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: x, y: barY, width: rowWidth * ratio, height: Metric.barHeight),
            cornerRadius: Metric.barHeight / 2
        ).fill()
    }

    private func drawFooter(width: CGFloat) {
        let footer = NSAttributedString(
            string: "\(content.dateText)  ·  \(HyroxSimStrings.Localizable.Summary.Share.tagline)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 30, weight: .medium),
                .foregroundColor: DesignTokens.Color.textTertiary
            ]
        )
        let size = footer.size()
        footer.draw(at: CGPoint(x: Metric.margin, y: Self.canvasSize.height - Metric.margin - size.height))
    }

    private func color(for tone: WorkoutSummaryViewModel.DeltaTone) -> UIColor {
        switch tone {
        case .ahead:
            return DesignTokens.Color.success
        case .behind:
            return .systemRed
        case .neutral:
            return DesignTokens.Color.textSecondary
        }
    }
}
