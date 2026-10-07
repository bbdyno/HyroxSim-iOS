//
//  RacePaceCardRenderer.swift
//  HyroxSim
//
//  Created by bbdyno on 9/20/26.
//

import UIKit
import HyroxCore

/// 페이스 카드를 한 장의 이미지로 굽는다.
///
/// 대회장에서는 앱을 열고 있을 여유가 없다. 캡처해서 잠금화면에 두거나 팀에 보내는 쪽이
/// 훨씬 현실적이라 공유용 이미지를 따로 만든다. 그래서 글자는 화면보다 크게,
/// 색은 블랙+골드로 — 조명이 어두운 실내에서도 읽히도록.
enum RacePaceCardRenderer {

    private enum Metrics {
        static let width: CGFloat = 900
        static let margin: CGFloat = 56
        static let rowHeight: CGFloat = 64
        static let sectionGap: CGFloat = 28
    }

    private enum Palette {
        static let background = UIColor.black
        static let accent = DesignTokens.Color.accent
        static let primary = UIColor.white
        static let secondary = UIColor(white: 0.62, alpha: 1)
        static let rowFill = UIColor(white: 1, alpha: 0.05)
        static let run = DesignTokens.Color.runAccent
        static let station = DesignTokens.Color.accent
    }

    /// 카드 이미지를 만든다. 목표가 없는 카드는 표가 비어 있어 nil 을 돌려준다.
    static func image(for card: RacePaceCard) -> UIImage? {
        guard card.hasGoals, !card.rows.isEmpty else { return nil }

        let headerHeight = headerHeight(for: card)
        let tableHeight = CGFloat(card.rows.count) * Metrics.rowHeight
        let footerHeight: CGFloat = 132
        let totalHeight = headerHeight + tableHeight + footerHeight

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        format.opaque = true

        let size = CGSize(width: Metrics.width, height: totalHeight)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { context in
            Palette.background.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            var cursor = drawHeader(card, in: size)
            cursor = drawRows(card, startingAt: cursor, width: size.width)
            drawFooter(card, startingAt: cursor, width: size.width)
        }
    }

    // MARK: - 헤더

    private static func headerHeight(for card: RacePaceCard) -> CGFloat {
        var height = Metrics.margin + 58 // 제목
        if card.subtitle != nil { height += 38 }
        height += 96 // 목표 총시간
        height += 34 // 컬럼 헤더
        if card.isScaledToRaceGoal { height += 34 }
        return height + Metrics.sectionGap
    }

    private static func drawHeader(_ card: RacePaceCard, in size: CGSize) -> CGFloat {
        let contentWidth = size.width - Metrics.margin * 2
        var y = Metrics.margin

        draw(
            card.title.uppercased(),
            font: .systemFont(ofSize: 46, weight: .black),
            color: Palette.accent,
            in: CGRect(x: Metrics.margin, y: y, width: contentWidth, height: 58)
        )
        y += 58

        if let subtitle = card.subtitle {
            draw(
                subtitle,
                font: .systemFont(ofSize: 26, weight: .semibold),
                color: Palette.secondary,
                in: CGRect(x: Metrics.margin, y: y, width: contentWidth, height: 34)
            )
            y += 38
        }

        if let total = card.totalGoalSeconds {
            draw(
                DurationFormatter.hms(total),
                font: .monospacedDigitSystemFont(ofSize: 76, weight: .black),
                color: Palette.primary,
                in: CGRect(x: Metrics.margin, y: y + 4, width: contentWidth, height: 88)
            )
        }
        y += 96

        if card.isScaledToRaceGoal {
            draw(
                RaceDayLocalization.PaceCard.scaledNotice,
                font: .systemFont(ofSize: 22, weight: .semibold),
                color: Palette.secondary,
                in: CGRect(x: Metrics.margin, y: y, width: contentWidth, height: 30)
            )
            y += 34
        }

        drawColumnHeaders(at: y, width: size.width)
        y += 34

        return y + Metrics.sectionGap
    }

    private static func drawColumnHeaders(at y: CGFloat, width: CGFloat) {
        let font = UIFont.systemFont(ofSize: 20, weight: .black)
        draw(
            RaceDayLocalization.PaceCard.columnSegment,
            font: font,
            color: Palette.secondary,
            in: CGRect(x: Metrics.margin, y: y, width: 360, height: 26)
        )
        draw(
            RaceDayLocalization.PaceCard.columnSplit,
            font: font,
            color: Palette.secondary,
            alignment: .right,
            in: CGRect(x: width - Metrics.margin - 400, y: y, width: 180, height: 26)
        )
        draw(
            RaceDayLocalization.PaceCard.columnCumulative,
            font: font,
            color: Palette.secondary,
            alignment: .right,
            in: CGRect(x: width - Metrics.margin - 200, y: y, width: 200, height: 26)
        )
    }

    // MARK: - 표

    private static func drawRows(_ card: RacePaceCard, startingAt top: CGFloat, width: CGFloat) -> CGFloat {
        var y = top

        for (index, row) in card.rows.enumerated() {
            let rowRect = CGRect(x: Metrics.margin - 16, y: y, width: width - (Metrics.margin - 16) * 2, height: Metrics.rowHeight)
            if index.isMultiple(of: 2) {
                let path = UIBezierPath(roundedRect: rowRect.insetBy(dx: 0, dy: 2), cornerRadius: 10)
                Palette.rowFill.setFill()
                path.fill()
            }

            let titleColor: UIColor = row.kind == .run ? Palette.run : Palette.station
            draw(
                row.title,
                font: .systemFont(ofSize: 30, weight: .bold),
                color: titleColor,
                in: CGRect(x: Metrics.margin, y: y + 8, width: 330, height: 36)
            )

            if let detail = row.detail {
                draw(
                    detail,
                    font: .systemFont(ofSize: 19, weight: .medium),
                    color: Palette.secondary,
                    in: CGRect(x: Metrics.margin, y: y + 40, width: 330, height: 22)
                )
            }

            if let goal = row.goalSeconds {
                draw(
                    DurationFormatter.ms(goal),
                    font: .monospacedDigitSystemFont(ofSize: 30, weight: .semibold),
                    color: Palette.secondary,
                    alignment: .right,
                    in: CGRect(x: width - Metrics.margin - 400, y: y + 14, width: 180, height: 38)
                )
            }

            if let cumulative = row.cumulativeSeconds {
                draw(
                    DurationFormatter.hms(cumulative),
                    font: .monospacedDigitSystemFont(ofSize: 38, weight: .black),
                    color: Palette.primary,
                    alignment: .right,
                    in: CGRect(x: width - Metrics.margin - 200, y: y + 10, width: 200, height: 44)
                )
            }

            y += Metrics.rowHeight
        }

        return y
    }

    // MARK: - 푸터

    private static func drawFooter(_ card: RacePaceCard, startingAt top: CGFloat, width: CGFloat) {
        let contentWidth = width - Metrics.margin * 2
        var y = top + 20

        let separator = UIBezierPath(
            rect: CGRect(x: Metrics.margin, y: y, width: contentWidth, height: 1)
        )
        UIColor(white: 1, alpha: 0.12).setFill()
        separator.fill()
        y += 22

        draw(
            RaceDayLocalization.PaceCard.fastLaneHint,
            font: .systemFont(ofSize: 22, weight: .medium),
            color: Palette.secondary,
            in: CGRect(x: Metrics.margin, y: y, width: contentWidth, height: 30)
        )
        y += 38

        draw(
            "HYROX SIM",
            font: .systemFont(ofSize: 20, weight: .black),
            color: Palette.accent,
            in: CGRect(x: Metrics.margin, y: y, width: contentWidth, height: 26)
        )
    }

    // MARK: - 그리기 도우미

    private static func draw(
        _ text: String,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        in rect: CGRect
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
