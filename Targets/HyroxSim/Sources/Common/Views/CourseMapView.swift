//
//  CourseMapView.swift
//  HyroxSim
//
//  Created by bbdyno on 10/7/26.
//

import UIKit
import HyroxCore

/// Serpentine race course with numbered station markers.
/// Runs are the track itself; stations sit on it in race order.
final class CourseMapView: UIView {

    struct Style {
        var rowGap: CGFloat
        var trackWidth: CGFloat
        var markerSize: CGFloat
        var showsLabels: Bool

        static let regular = Style(rowGap: 64, trackWidth: 22, markerSize: 22, showsLabels: true)
        static let compact = Style(rowGap: 44, trackWidth: 13, markerSize: 17, showsLabels: false)
    }

    struct Station {
        var label: String?
        var color: UIColor = DesignTokens.Color.accent
        var labelColor: UIColor = DesignTokens.Color.textSecondary
    }

    /// `stationsReached` markers are behind (or under) the athlete;
    /// `fractionToNext` is how far along the track to the next marker (or the finish).
    struct Progress: Equatable {
        var stationsReached: Int
        var fractionToNext: CGFloat
    }

    let style: Style

    var stations: [Station] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var progress: Progress? {
        didSet {
            if progress != oldValue { setNeedsDisplay() }
        }
    }

    init(style: Style = .regular) {
        self.style = style
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func height(stationCount: Int, style: Style) -> CGFloat {
        Geometry(width: 0, stationCount: stationCount, style: style).height
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height(stationCount: stations.count, style: style))
    }

    // MARK: - Geometry

    private struct Geometry {
        static let labelSpace: CGFloat = 18
        static let finishSpace: CGFloat = 16

        let width: CGFloat
        let stationCount: Int
        let style: Style
        let perRow: Int
        let rows: Int

        init(width: CGFloat, stationCount: Int, style: Style) {
            self.width = width
            self.stationCount = stationCount
            self.style = style
            perRow = max(2, Int((Double(stationCount) / 4).rounded(.up)))
            rows = max(1, Int((Double(stationCount) / Double(perRow)).rounded(.up)))
        }

        private var half: CGFloat { max(style.markerSize, style.trackWidth) / 2 }
        private var topInset: CGFloat { (style.showsLabels ? Self.labelSpace : 0) + half + 1 }
        var radius: CGFloat { style.rowGap / 2 }
        var leftTurnX: CGFloat { style.trackWidth / 2 + radius }
        var rightTurnX: CGFloat { width - style.trackWidth / 2 - radius }

        var height: CGFloat {
            topInset + CGFloat(rows - 1) * style.rowGap + half + 1 + (style.showsLabels ? Self.finishSpace : 0)
        }

        func rowY(_ row: Int) -> CGFloat { topInset + CGFloat(row) * style.rowGap }
        func isLeftToRight(_ row: Int) -> Bool { row % 2 == 0 }

        func rowStartX(_ row: Int) -> CGFloat {
            if row == 0 { return 0 }
            return isLeftToRight(row) ? leftTurnX : rightTurnX
        }

        func rowEndX(_ row: Int) -> CGFloat {
            if row == rows - 1 { return isLeftToRight(row) ? width : 0 }
            return isLeftToRight(row) ? rightTurnX : leftTurnX
        }

        private func straightLength(_ row: Int) -> CGFloat { abs(rowEndX(row) - rowStartX(row)) }
        private var arcLength: CGFloat { .pi * radius }

        func rowStartDistance(_ row: Int) -> CGFloat {
            (0..<row).reduce(0) { $0 + straightLength($1) + arcLength }
        }

        var totalLength: CGFloat { rowStartDistance(rows - 1) + straightLength(rows - 1) }

        func stationPoint(_ index: Int) -> CGPoint {
            let row = index / perRow
            let t = (CGFloat(index % perRow) + 0.5) / CGFloat(perRow)
            let span = rightTurnX - leftTurnX
            let x = isLeftToRight(row) ? leftTurnX + span * t : rightTurnX - span * t
            return CGPoint(x: x, y: rowY(row))
        }

        func stationDistance(_ index: Int) -> CGFloat {
            let row = index / perRow
            return rowStartDistance(row) + abs(stationPoint(index).x - rowStartX(row))
        }

        var stationSpacing: CGFloat { (rightTurnX - leftTurnX) / CGFloat(perRow) }

        func path() -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: rowY(0)))
            for row in 0..<rows {
                let endX = rowEndX(row)
                path.addLine(to: CGPoint(x: endX, y: rowY(row)))
                guard row < rows - 1 else { break }
                // Left-to-right rows turn around the right side (through angle 0).
                path.addArc(
                    center: CGPoint(x: endX, y: rowY(row) + radius),
                    radius: radius,
                    startAngle: -.pi / 2,
                    endAngle: .pi / 2,
                    clockwise: !isLeftToRight(row)
                )
            }
            return path
        }

        func point(atDistance distance: CGFloat) -> CGPoint {
            var remaining = min(max(distance, 0), totalLength)
            for row in 0..<rows {
                let ltr = isLeftToRight(row)
                let straight = straightLength(row)
                if remaining <= straight || row == rows - 1 {
                    let x = rowStartX(row) + (ltr ? 1 : -1) * min(remaining, straight)
                    return CGPoint(x: x, y: rowY(row))
                }
                remaining -= straight
                if remaining <= arcLength {
                    let sweep = remaining / radius
                    let angle = -CGFloat.pi / 2 + (ltr ? sweep : -sweep)
                    let center = CGPoint(x: rowEndX(row), y: rowY(row) + radius)
                    return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                }
                remaining -= arcLength
            }
            return CGPoint(x: rowEndX(rows - 1), y: rowY(rows - 1))
        }

        func distance(for progress: Progress) -> CGFloat {
            let reached = min(max(progress.stationsReached, 0), stationCount)
            let from = reached == 0 ? 0 : stationDistance(reached - 1)
            let to = reached >= stationCount ? totalLength : stationDistance(reached)
            return from + (to - from) * min(max(progress.fractionToNext, 0), 1)
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        let geo = Geometry(width: bounds.width, stationCount: stations.count, style: style)
        let path = geo.path()
        let progressDistance = progress.map { geo.distance(for: $0) }

        ctx.setLineCap(.butt)
        ctx.setLineWidth(style.trackWidth)
        ctx.addPath(path)
        ctx.setStrokeColor(DesignTokens.Color.track.cgColor)
        ctx.strokePath()

        if let progressDistance, progressDistance > 0.5 {
            ctx.addPath(path.copy(dashingWithPhase: 0, lengths: [progressDistance, geo.totalLength + 10]))
            ctx.setStrokeColor(DesignTokens.Color.accent.cgColor)
            ctx.strokePath()
        }

        ctx.setLineWidth(1)
        ctx.addPath(path.copy(dashingWithPhase: 0, lengths: [5, 6]))
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        ctx.strokePath()

        let filledCount = progress?.stationsReached ?? stations.count
        for (index, station) in stations.enumerated() {
            drawMarker(index: index, station: station, isFilled: index < filledCount, geo: geo, in: ctx)
        }

        if style.showsLabels {
            drawEndpointLabels(geo: geo)
        }

        if let progressDistance {
            var point = geo.point(atDistance: progressDistance)
            let radius = max(style.trackWidth * 0.62, 7)
            // Keep the dot fully visible at the start and finish edges.
            point.x = min(max(point.x, radius + 1.5), bounds.width - radius - 1.5)
            let dot = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.setStrokeColor(DesignTokens.Color.background.cgColor)
            ctx.setLineWidth(3)
            ctx.fillEllipse(in: dot)
            ctx.strokeEllipse(in: dot)
        }
    }

    private func drawMarker(index: Int, station: Station, isFilled: Bool, geo: Geometry, in ctx: CGContext) {
        let center = geo.stationPoint(index)
        let size = style.markerSize
        let box = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)

        ctx.setFillColor((isFilled ? station.color : DesignTokens.Color.background).cgColor)
        ctx.fill(box)
        if !isFilled {
            ctx.setStrokeColor(UIColor(white: 0.4, alpha: 1).cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(box.insetBy(dx: 0.75, dy: 0.75))
        }

        let number = NSAttributedString(string: "\(index + 1)", attributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: size * 0.56, weight: .heavy),
            .foregroundColor: isFilled ? UIColor.black : UIColor(white: 0.55, alpha: 1)
        ])
        let numberSize = number.size()
        number.draw(at: CGPoint(x: center.x - numberSize.width / 2, y: center.y - numberSize.height / 2))

        guard style.showsLabels, let label = station.label, !label.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let width = geo.stationSpacing - 6
        NSAttributedString(string: label, attributes: Self.captionAttributes(color: station.labelColor, paragraph: paragraph))
            .draw(in: CGRect(x: center.x - width / 2, y: box.minY - 16, width: width, height: 12))
    }

    private func drawEndpointLabels(geo: Geometry) {
        let attributes = Self.captionAttributes(color: DesignTokens.Color.textPrimary, paragraph: nil)
        let start = NSAttributedString(string: "START", attributes: attributes)
        start.draw(at: CGPoint(x: 0, y: geo.rowY(0) - style.markerSize / 2 - 16))

        let finish = NSAttributedString(string: "FINISH", attributes: attributes)
        let lastRow = geo.rows - 1
        let x = geo.isLeftToRight(lastRow) ? bounds.width - finish.size().width : 0
        finish.draw(at: CGPoint(x: x, y: geo.rowY(lastRow) + max(style.markerSize, style.trackWidth) / 2 + 4))
    }

    private static func captionAttributes(color: UIColor, paragraph: NSParagraphStyle?) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: color,
            .kern: 0.6
        ]
        if let paragraph { attributes[.paragraphStyle] = paragraph }
        return attributes
    }
}

// MARK: - Template helpers

extension StationKind {
    /// Short uppercase name that fits above a course marker.
    var courseLabel: String {
        switch self {
        case .skiErg: return "SKIERG"
        case .sledPush: return "SLED PUSH"
        case .sledPull: return "SLED PULL"
        case .burpeeBroadJumps: return "BURPEE BJ"
        case .rowing: return "ROWING"
        case .farmersCarry: return "FARMERS"
        case .sandbagLunges: return "LUNGES"
        case .wallBalls: return "WALL BALLS"
        case .custom(let name): return name.uppercased()
        }
    }
}

extension WorkoutTemplate {
    var courseStations: [CourseMapView.Station] {
        segments
            .filter { $0.type == .station }
            .map { CourseMapView.Station(label: $0.stationKind?.courseLabel) }
    }
}

extension UILabel {
    /// Uppercase caption with letter spacing.
    func setTracked(_ text: String, kern: CGFloat) {
        attributedText = NSAttributedString(string: text, attributes: [.kern: kern])
    }
}
