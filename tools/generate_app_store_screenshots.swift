import AppKit
import Foundation

struct LocalizedCopy {
    let tag: String
    let title: String
    let subtitle: String
}

struct MarketingShot {
    let slug: String
    let sourceName: String
    let accentHex: UInt32
    let en: LocalizedCopy
    let ko: LocalizedCopy
}

enum WatchStyle {
    case ultra
    case seriesModern
    case seriesClassic
}

enum DeviceFamily {
    case iPhone65
    case iPad13
    case watch(WatchStyle)
}

struct RenderTarget {
    let folder: String
    let family: DeviceFamily
    let width: Int
    let height: Int
}

let phoneShots: [MarketingShot] = [
    .init(
        slug: "plan-the-full-hyrox-rehearsal",
        sourceName: "iphone-home.png",
        accentHex: 0xFFD84C,
        en: .init(
            tag: "RACE PREP",
            title: "Plan The Full HYROX Rehearsal",
            subtitle: "Choose official divisions or jump into a custom training session in seconds."
        ),
        ko: .init(
            tag: "레이스 준비",
            title: "HYROX 리허설을 바로 설계하세요",
            subtitle: "공식 디비전을 고르거나 커스텀 세션을 빠르게 시작할 수 있습니다."
        )
    ),
    .init(
        slug: "edit-every-run-rox-zone-and-station",
        sourceName: "iphone-builder.png",
        accentHex: 0xFFB800,
        en: .init(
            tag: "CUSTOM BUILDER",
            title: "Edit Every Run, Rox Zone, and Station",
            subtitle: "Tune segment order, distance, and reusable templates for your next race rehearsal."
        ),
        ko: .init(
            tag: "커스텀 빌더",
            title: "런, Rox Zone, 스테이션을 세밀하게 편집",
            subtitle: "구간 순서와 거리, 저장 템플릿까지 한 번에 조정할 수 있습니다."
        )
    ),
    .init(
        slug: "plan-goal-time-with-data-backed-splits",
        sourceName: "iphone-pace-planner.png",
        accentHex: 0xFFD84C,
        en: .init(
            tag: "PACE PLANNER",
            title: "Plan Goal Time With Data-Backed Splits",
            subtitle: "Preview percentile, run pacing, and station targets before the workout begins."
        ),
        ko: .init(
            tag: "페이스 플래너",
            title: "목표 기록과 구간별 페이스를 미리 설계",
            subtitle: "완주 목표 시간에 맞춰 퍼센타일과 런, 스테이션 목표를 바로 확인할 수 있습니다."
        )
    ),
    .init(
        slug: "follow-the-workout-live-from-apple-watch",
        sourceName: "iphone-mirror.png",
        accentHex: 0x1EA0FF,
        en: .init(
            tag: "LIVE SYNC",
            title: "Follow The Workout Live From Apple Watch",
            subtitle: "See segment progress, pace, GPS, and heart rate on a larger iPhone view."
        ),
        ko: .init(
            tag: "실시간 연동",
            title: "Apple Watch 진행 상황을 iPhone에서 실시간 확인",
            subtitle: "현재 구간, 페이스, GPS, 심박을 큰 화면으로 바로 볼 수 있습니다."
        )
    ),
    .init(
        slug: "review-total-time-splits-and-place",
        sourceName: "iphone-summary.png",
        accentHex: 0xFFFFFF,
        en: .init(
            tag: "POST-WORKOUT",
            title: "Review Total Time, Splits, and Place",
            subtitle: "Break down every finish with a clear summary of segments, pace, and results."
        ),
        ko: .init(
            tag: "운동 요약",
            title: "완주 후 스플릿과 기록을 한눈에 분석",
            subtitle: "총 시간과 구간별 흐름을 요약 화면에서 바로 확인할 수 있습니다."
        )
    ),
    .init(
        slug: "keep-recent-sessions-ready-to-revisit",
        sourceName: "iphone-history.png",
        accentHex: 0xE0C36B,
        en: .init(
            tag: "PROGRESS LOG",
            title: "Keep Recent Sessions Ready To Revisit",
            subtitle: "Open past results fast and stay close to the workouts you want to repeat."
        ),
        ko: .init(
            tag: "기록 관리",
            title: "최근 세션을 빠르게 다시 열고 비교",
            subtitle: "지난 결과를 보관하고 다음 리허설에 바로 이어서 사용할 수 있습니다."
        )
    )
]

let watchShots: [MarketingShot] = [
    .init(
        slug: "start-hyrox-from-your-wrist",
        sourceName: "watch-home.png",
        accentHex: 0xFFD84C,
        en: .init(
            tag: "WRIST START",
            title: "Start HYROX From Your Wrist",
            subtitle: "Launch presets or custom workouts without touching your phone."
        ),
        ko: .init(
            tag: "워치 시작",
            title: "손목에서 바로 HYROX 시작",
            subtitle: "프리셋과 내 운동을 워치에서 즉시 실행할 수 있습니다."
        )
    ),
    .init(
        slug: "see-pace-segment-and-heart-rate-live",
        sourceName: "watch-active.png",
        accentHex: 0x1EA0FF,
        en: .init(
            tag: "LIVE METRICS",
            title: "See Pace, Segment, and Heart Rate Live",
            subtitle: "Track the current block, total time, and effort while you move."
        ),
        ko: .init(
            tag: "실시간 지표",
            title: "페이스와 심박을 실시간으로 확인",
            subtitle: "현재 구간과 총 시간까지 운동 중 바로 체크할 수 있습니다."
        )
    ),
    .init(
        slug: "review-every-split-right-after-the-finish",
        sourceName: "watch-summary.png",
        accentHex: 0xFFFFFF,
        en: .init(
            tag: "QUICK REVIEW",
            title: "Review Every Split Right After The Finish",
            subtitle: "Open your total time and segment results the moment the session ends."
        ),
        ko: .init(
            tag: "즉시 리뷰",
            title: "완주 후 스플릿을 즉시 요약",
            subtitle: "구간별 기록과 전체 시간을 손목에서 바로 확인할 수 있습니다."
        )
    ),
    .init(
        slug: "reopen-your-recent-rehearsals-anytime",
        sourceName: "watch-history.png",
        accentHex: 0xE0C36B,
        en: .init(
            tag: "RECENT SESSIONS",
            title: "Reopen Your Recent Rehearsals Anytime",
            subtitle: "Keep your latest HYROX efforts close and ready for the next training day."
        ),
        ko: .init(
            tag: "최근 세션",
            title: "최근 리허설을 다시 불러오기",
            subtitle: "지난 운동 기록을 빠르게 찾아 다시 확인할 수 있습니다."
        )
    )
]

let targets: [RenderTarget] = [
    .init(folder: "iphone-6_5", family: .iPhone65, width: 1284, height: 2778),
    .init(folder: "ipad-13", family: .iPad13, width: 2064, height: 2752),
    .init(folder: "watch-ultra-3", family: .watch(.ultra), width: 422, height: 514),
    .init(folder: "watch-series-11", family: .watch(.seriesModern), width: 416, height: 496),
    .init(folder: "watch-series-9", family: .watch(.seriesModern), width: 396, height: 484),
    .init(folder: "watch-series-6", family: .watch(.seriesModern), width: 368, height: 448),
    .init(folder: "watch-series-3", family: .watch(.seriesClassic), width: 312, height: 390)
]

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let sourcesDir = root.appendingPathComponent("docs/assets/screenshots")
let outputDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/HyroxSim-AppStore-Screenshots")

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255.0
    let g = CGFloat((hex >> 8) & 0xff) / 255.0
    let b = CGFloat(hex & 0xff) / 255.0
    return NSColor(red: r, green: g, blue: b, alpha: alpha)
}

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, canvasHeight: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasHeight - y - height, width: width, height: height)
}

func aspectFitRect(source: CGSize, in target: CGRect) -> CGRect {
    guard source.width > 0, source.height > 0 else { return target }
    let scale = min(target.width / source.width, target.height / source.height)
    let width = source.width * scale
    let height = source.height * scale
    return CGRect(
        x: target.midX - width / 2,
        y: target.midY - height / 2,
        width: width,
        height: height
    )
}

func aspectFillRect(source: CGSize, in target: CGRect) -> CGRect {
    guard source.width > 0, source.height > 0 else { return target }
    let scale = max(target.width / source.width, target.height / source.height)
    let width = source.width * scale
    let height = source.height * scale
    return CGRect(
        x: target.midX - width / 2,
        y: target.midY - height / 2,
        width: width,
        height: height
    )
}

func ensureDirectory(_ url: URL) throws {
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
}

func sluggedFileName(index: Int, slug: String) -> String {
    String(format: "%02d-%@.png", index + 1, slug)
}

func attributedStyle(font: NSFont, color: NSColor, alignment: NSTextAlignment, lineSpacing: CGFloat = 0) -> [NSAttributedString.Key: Any] {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping
    style.lineSpacing = lineSpacing
    return [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]
}

@discardableResult
func drawText(_ string: String, rect: CGRect, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
    let nsString = NSString(string: string)
    let drawOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    let bounds = nsString.boundingRect(with: rect.size, options: drawOptions, attributes: attributes)
    let drawRect = CGRect(x: rect.minX, y: rect.maxY - ceil(bounds.height), width: rect.width, height: ceil(bounds.height))
    nsString.draw(with: drawRect, options: drawOptions, attributes: attributes)
    return ceil(bounds.height)
}

func drawPosterBackground(in canvas: CGRect, accent: NSColor, family: DeviceFamily, variant: Int) {
    color(0x060606).setFill()
    canvas.fill()

    let diagonalPath = NSBezierPath()
    diagonalPath.move(to: CGPoint(x: canvas.minX, y: canvas.height * 0.18))
    diagonalPath.line(to: CGPoint(x: canvas.maxX, y: canvas.height * 0.36))
    diagonalPath.line(to: CGPoint(x: canvas.maxX, y: canvas.height * 0.26))
    diagonalPath.line(to: CGPoint(x: canvas.minX, y: canvas.height * 0.08))
    diagonalPath.close()
    color(0xFFFFFF, alpha: 0.035).setFill()
    diagonalPath.fill()

    let glowCenter: CGPoint
    let glowRadius: CGFloat
    switch family {
    case .iPhone65:
        glowCenter = CGPoint(x: canvas.width * (variant == 2 ? 0.68 : 0.76), y: canvas.height * 0.83)
        glowRadius = canvas.width * 0.82
    case .iPad13:
        glowCenter = CGPoint(x: canvas.width * 0.78, y: canvas.height * 0.81)
        glowRadius = canvas.width * 0.64
    case .watch:
        glowCenter = CGPoint(x: canvas.width * 0.52, y: canvas.height * 0.84)
        glowRadius = canvas.width * 0.58
    }

    let glow = NSGradient(colors: [accent.withAlphaComponent(0.28), accent.withAlphaComponent(0.0)])!
    glow.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: glowRadius, options: [])

    let haze = NSBezierPath(ovalIn: CGRect(
        x: canvas.width * 0.18,
        y: canvas.height * 0.54,
        width: canvas.width * 0.76,
        height: canvas.width * 0.76
    ))
    color(0xFFFFFF, alpha: 0.015).setFill()
    haze.fill()

    let leftRail = NSBezierPath(roundedRect: CGRect(x: canvas.width * 0.055, y: canvas.height * 0.16, width: max(2, canvas.width * 0.008), height: canvas.height * 0.62), xRadius: 10, yRadius: 10)
    accent.withAlphaComponent(0.78).setFill()
    leftRail.fill()

    let rightRail = NSBezierPath(roundedRect: CGRect(x: canvas.width * 0.937, y: canvas.height * 0.24, width: max(2, canvas.width * 0.008), height: canvas.height * 0.46), xRadius: 10, yRadius: 10)
    accent.withAlphaComponent(0.54).setFill()
    rightRail.fill()

    let border = NSBezierPath(roundedRect: canvas.insetBy(dx: 1, dy: 1), xRadius: canvas.width * 0.025, yRadius: canvas.width * 0.025)
    color(0xFFFFFF, alpha: 0.04).setStroke()
    border.lineWidth = 2
    border.stroke()
}

func drawHeader(copy: LocalizedCopy, accent: NSColor, canvas: CGRect, family: DeviceFamily) {
    let isWatch: Bool
    switch family {
    case .watch:
        isWatch = true
    default:
        isWatch = false
    }

    let width = canvas.width
    let height = canvas.height

    let safeX: CGFloat
    let textWidth: CGFloat
    let alignment: NSTextAlignment
    switch family {
    case .watch:
        safeX = width * 0.08
        textWidth = width * 0.84
        alignment = .center
    case .iPad13:
        safeX = width * 0.08
        textWidth = width * 0.36
        alignment = .left
    case .iPhone65:
        safeX = width * 0.09
        textWidth = width * 0.74
        alignment = .left
    }

    let eyebrowFontSize = min(width, height) * (isWatch ? 0.042 : 0.031)
    let titleMultiplier: CGFloat
    let subtitleMultiplier: CGFloat
    switch family {
    case .watch:
        titleMultiplier = 0.075
        subtitleMultiplier = 0.027
    case .iPad13:
        titleMultiplier = 0.062
        subtitleMultiplier = 0.024
    case .iPhone65:
        titleMultiplier = 0.052
        subtitleMultiplier = 0.022
    }
    let titleFontSize = min(width, height) * titleMultiplier
    let subtitleFontSize = min(width, height) * subtitleMultiplier

    let brandRect = rectFromTop(
        x: safeX,
        y: height * (isWatch ? 0.028 : 0.03),
        width: textWidth,
        height: eyebrowFontSize * 1.25,
        canvasHeight: height
    )

    _ = drawText(
        "HYROX SIM",
        rect: brandRect,
        attributes: attributedStyle(
            font: NSFont.systemFont(ofSize: eyebrowFontSize * 0.96, weight: .semibold),
            color: color(0xFFFFFF, alpha: 0.58),
            alignment: alignment
        )
    )

    let eyebrowRect = rectFromTop(
        x: safeX,
        y: height * (isWatch ? 0.068 : 0.072),
        width: textWidth,
        height: eyebrowFontSize * 1.6,
        canvasHeight: height
    )

    let pillHeight = eyebrowRect.height
    let pillWidth = min(textWidth, max(eyebrowRect.width * 0.24, CGFloat(copy.tag.count) * eyebrowFontSize * 0.78))
    let pillRect = alignment == .center
        ? CGRect(x: canvas.midX - pillWidth / 2, y: eyebrowRect.minY, width: pillWidth, height: pillHeight)
        : CGRect(x: eyebrowRect.minX, y: eyebrowRect.minY, width: pillWidth, height: pillHeight)

    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
    accent.withAlphaComponent(0.18).setFill()
    pillPath.fill()
    accent.withAlphaComponent(0.85).setStroke()
    pillPath.lineWidth = max(1.5, pillHeight * 0.06)
    pillPath.stroke()

    _ = drawText(
        copy.tag,
        rect: pillRect.insetBy(dx: pillHeight * 0.38, dy: pillHeight * 0.18),
        attributes: attributedStyle(
            font: NSFont.systemFont(ofSize: eyebrowFontSize, weight: .heavy),
            color: accent,
            alignment: .center
        )
    )

    let titleTop: CGFloat
    switch family {
    case .watch:
        titleTop = height * 0.13
    case .iPad13:
        titleTop = height * 0.13
    case .iPhone65:
        titleTop = height * 0.14
    }
    let titleHeight: CGFloat
    switch family {
    case .watch:
        titleHeight = height * 0.16
    case .iPad13:
        titleHeight = height * 0.16
    case .iPhone65:
        titleHeight = height * 0.14
    }

    let titleRect = rectFromTop(
        x: safeX,
        y: titleTop,
        width: textWidth,
        height: titleHeight,
        canvasHeight: height
    )

    let subtitleGap: CGFloat
    switch family {
    case .watch:
        subtitleGap = height * 0.008
    case .iPad13:
        subtitleGap = height * 0.004
    case .iPhone65:
        subtitleGap = height * 0.008
    }
    let subtitleTop = titleTop + titleRect.height + subtitleGap
    let subtitleHeight: CGFloat
    switch family {
    case .watch:
        subtitleHeight = height * 0.075
    case .iPad13:
        subtitleHeight = height * 0.072
    case .iPhone65:
        subtitleHeight = height * 0.06
    }
    let subtitleRect = rectFromTop(
        x: safeX,
        y: subtitleTop,
        width: textWidth,
        height: subtitleHeight,
        canvasHeight: height
    )

    _ = drawText(
        copy.title,
        rect: titleRect,
        attributes: attributedStyle(
            font: NSFont.systemFont(ofSize: titleFontSize, weight: .black),
            color: .white,
            alignment: alignment,
            lineSpacing: titleFontSize * 0.1
        )
    )

    _ = drawText(
        copy.subtitle,
        rect: subtitleRect,
        attributes: attributedStyle(
            font: NSFont.systemFont(ofSize: subtitleFontSize, weight: .medium),
            color: color(0xD0D2D6, alpha: 0.92),
            alignment: alignment,
            lineSpacing: subtitleFontSize * 0.22
        )
    )
}

func drawImage(_ image: NSImage, in rect: CGRect, clippingPath: NSBezierPath, fitMode: (CGSize, CGRect) -> CGRect, screenBackground: NSColor = color(0x020202)) {
    screenBackground.setFill()
    clippingPath.fill()

    NSGraphicsContext.saveGraphicsState()
    clippingPath.addClip()
    let drawRect = fitMode(image.size, rect)
    image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
}

func drawPhoneFrame(in rect: CGRect, screenshot: NSImage) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let outer = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.12, yRadius: rect.width * 0.12)
    let outerCg = outer.cgPath
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.02), blur: rect.width * 0.08, color: color(0x000000, alpha: 0.42).cgColor)
    ctx.addPath(outerCg)
    ctx.setFillColor(color(0x121315).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()
    let frameGradient = NSGradient(colors: [color(0x2A2D31), color(0x0A0B0C)])!
    frameGradient.draw(in: rect, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    color(0xFFFFFF, alpha: 0.08).setStroke()
    outer.lineWidth = max(2, rect.width * 0.004)
    outer.stroke()

    let screenRect = rect.insetBy(dx: rect.width * 0.04, dy: rect.width * 0.04)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: rect.width * 0.085, yRadius: rect.width * 0.085)
    drawImage(screenshot, in: screenRect, clippingPath: screen, fitMode: aspectFitRect)

    let speakerRect = CGRect(
        x: rect.midX - rect.width * 0.11,
        y: rect.maxY - rect.width * 0.055,
        width: rect.width * 0.22,
        height: rect.width * 0.018
    )
    let speaker = NSBezierPath(roundedRect: speakerRect, xRadius: speakerRect.height / 2, yRadius: speakerRect.height / 2)
    color(0x1F2124).setFill()
    speaker.fill()
}

func drawIPadFrame(in rect: CGRect, screenshot: NSImage) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let outer = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.06, yRadius: rect.width * 0.06)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.018), blur: rect.width * 0.05, color: color(0x000000, alpha: 0.34).cgColor)
    ctx.addPath(outer.cgPath)
    ctx.setFillColor(color(0x16181B).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()
    let frameGradient = NSGradient(colors: [color(0x23262A), color(0x090A0B)])!
    frameGradient.draw(in: rect, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    color(0xFFFFFF, alpha: 0.08).setStroke()
    outer.lineWidth = max(2, rect.width * 0.003)
    outer.stroke()

    let screenRect = rect.insetBy(dx: rect.width * 0.028, dy: rect.width * 0.028)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: rect.width * 0.035, yRadius: rect.width * 0.035)
    drawImage(screenshot, in: screenRect, clippingPath: screen, fitMode: aspectFitRect, screenBackground: color(0x030303))

    let cameraRect = CGRect(x: rect.midX - rect.width * 0.012, y: rect.maxY - rect.width * 0.03, width: rect.width * 0.024, height: rect.width * 0.024)
    let camera = NSBezierPath(ovalIn: cameraRect)
    color(0x202327).setFill()
    camera.fill()
    color(0x0A0C0F).setStroke()
    camera.lineWidth = max(1.5, rect.width * 0.002)
    camera.stroke()
}

func drawWatchFrame(in rect: CGRect, screenshot: NSImage, style: WatchStyle) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let outerRadius: CGFloat
    let inset: CGFloat
    switch style {
    case .ultra:
        outerRadius = rect.width * 0.2
        inset = rect.width * 0.105
    case .seriesModern:
        outerRadius = rect.width * 0.28
        inset = rect.width * 0.11
    case .seriesClassic:
        outerRadius = rect.width * 0.30
        inset = rect.width * 0.12
    }

    let outer = NSBezierPath(roundedRect: rect, xRadius: outerRadius, yRadius: outerRadius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.03), blur: rect.width * 0.11, color: color(0x000000, alpha: 0.36).cgColor)
    ctx.addPath(outer.cgPath)
    ctx.setFillColor(color(0x121417).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    if style == .ultra {
        let leftAction = NSBezierPath(roundedRect: CGRect(x: rect.minX - rect.width * 0.038, y: rect.midY - rect.height * 0.11, width: rect.width * 0.05, height: rect.height * 0.22), xRadius: rect.width * 0.02, yRadius: rect.width * 0.02)
        color(0xF78B1F).setFill()
        leftAction.fill()
    }

    let buttonRect = CGRect(x: rect.maxX - rect.width * 0.008, y: rect.midY + rect.height * 0.08, width: rect.width * 0.04, height: rect.height * 0.16)
    let button = NSBezierPath(roundedRect: buttonRect, xRadius: buttonRect.width / 2, yRadius: buttonRect.width / 2)
    color(0x202327).setFill()
    button.fill()

    let crownRect = CGRect(x: rect.maxX - rect.width * 0.028, y: rect.midY - rect.width * 0.08, width: rect.width * 0.085, height: rect.width * 0.085)
    let crown = NSBezierPath(ovalIn: crownRect)
    color(0x383C40).setFill()
    crown.fill()

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()
    let frameGradient = NSGradient(colors: [color(0x282B30), color(0x0A0B0D)])!
    frameGradient.draw(in: rect, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    color(0xFFFFFF, alpha: 0.08).setStroke()
    outer.lineWidth = max(1.5, rect.width * 0.006)
    outer.stroke()

    let screenRect = rect.insetBy(dx: inset, dy: inset * (style == .ultra ? 0.95 : 1.0))
    let screenRadius = screenRect.width * (style == .ultra ? 0.18 : 0.24)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: screenRadius, yRadius: screenRadius)
    drawImage(screenshot, in: screenRect, clippingPath: screen, fitMode: aspectFillRect)
}

func renderShot(target: RenderTarget, shot: MarketingShot, copy: LocalizedCopy, screenshot: NSImage, index: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: target.width,
        pixelsHigh: target.height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: target.width, height: target.height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = CGRect(x: 0, y: 0, width: CGFloat(target.width), height: CGFloat(target.height))
    let accent = color(shot.accentHex)
    drawPosterBackground(in: canvas, accent: accent, family: target.family, variant: index)
    drawHeader(copy: copy, accent: accent, canvas: canvas, family: target.family)

    switch target.family {
    case .iPhone65:
        let bodyWidth = canvas.width * 0.53
        let bodyHeight = bodyWidth * 2.06
        let bodyRect = rectFromTop(
            x: canvas.midX - bodyWidth / 2,
            y: canvas.height * 0.41,
            width: bodyWidth,
            height: bodyHeight,
            canvasHeight: canvas.height
        )
        drawPhoneFrame(in: bodyRect, screenshot: screenshot)
    case .iPad13:
        let bodyWidth = canvas.width * 0.42
        let bodyHeight = bodyWidth * 1.34
        let bodyRect = rectFromTop(
            x: canvas.width - bodyWidth - canvas.width * 0.08,
            y: canvas.height * 0.23,
            width: bodyWidth,
            height: bodyHeight,
            canvasHeight: canvas.height
        )
        drawIPadFrame(in: bodyRect, screenshot: screenshot)
    case .watch(let style):
        let bodyWidth: CGFloat
        let topOffset: CGFloat
        switch style {
        case .ultra:
            bodyWidth = canvas.width * 0.55
            topOffset = canvas.height * 0.465
        case .seriesModern:
            bodyWidth = canvas.width * 0.52
            topOffset = canvas.height * 0.49
        case .seriesClassic:
            bodyWidth = canvas.width * 0.50
            topOffset = canvas.height * 0.50
        }
        let bodyHeight = bodyWidth * (style == .ultra ? 1.11 : 1.16)
        let bodyRect = rectFromTop(
            x: canvas.midX - bodyWidth / 2,
            y: topOffset,
            width: bodyWidth,
            height: bodyHeight,
            canvasHeight: canvas.height
        )
        drawWatchFrame(in: bodyRect, screenshot: screenshot, style: style)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func contactSheet(imageURLs: [URL], outputURL: URL, columns: Int, tileSize: CGSize, background: NSColor) throws {
    let rows = Int(ceil(Double(imageURLs.count) / Double(columns)))
    let width = Int(CGFloat(columns) * tileSize.width)
    let height = Int(CGFloat(rows) * tileSize.height)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    background.setFill()
    CGRect(x: 0, y: 0, width: width, height: height).fill()

    for (index, url) in imageURLs.enumerated() {
        guard let image = NSImage(contentsOf: url) else { continue }
        let row = index / columns
        let column = index % columns
        let frame = CGRect(
            x: CGFloat(column) * tileSize.width,
            y: CGFloat(height) - CGFloat(row + 1) * tileSize.height,
            width: tileSize.width,
            height: tileSize.height
        ).insetBy(dx: tileSize.width * 0.04, dy: tileSize.height * 0.04)
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: outputURL)
}

var sourceCache: [String: NSImage] = [:]

func sourceImage(named name: String) -> NSImage {
    if let image = sourceCache[name] { return image }
    let url = sourcesDir.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: url) else {
        fatalError("Missing source screenshot: \(url.path)")
    }
    sourceCache[name] = image
    return image
}

try ensureDirectory(outputDir)

for locale in ["en", "ko"] {
    let localeDir = outputDir.appendingPathComponent(locale)
    try ensureDirectory(localeDir)

    for target in targets {
        let targetDir = localeDir.appendingPathComponent(target.folder)
        try ensureDirectory(targetDir)

        let shots: [MarketingShot]
        switch target.family {
        case .iPhone65, .iPad13:
            shots = phoneShots
        case .watch:
            shots = watchShots
        }

        for (index, shot) in shots.enumerated() {
            let copy = locale == "ko" ? shot.ko : shot.en
            let screenshot = sourceImage(named: shot.sourceName)
            let data = renderShot(target: target, shot: shot, copy: copy, screenshot: screenshot, index: index)
            let fileURL = targetDir.appendingPathComponent(sluggedFileName(index: index, slug: shot.slug))
            try data.write(to: fileURL)
            print("Wrote \(fileURL.path)")
        }
    }
}

let previewDir = outputDir.appendingPathComponent("previews")
try ensureDirectory(previewDir)

let previewTargets = [
    ("en", "iphone-6_5", 3, CGSize(width: 380, height: 822)),
    ("ko", "iphone-6_5", 3, CGSize(width: 380, height: 822)),
    ("en", "ipad-13", 3, CGSize(width: 420, height: 560)),
    ("ko", "ipad-13", 3, CGSize(width: 420, height: 560)),
    ("en", "watch-series-11", 2, CGSize(width: 300, height: 358)),
    ("ko", "watch-series-11", 2, CGSize(width: 300, height: 358))
]

for (locale, folder, columns, tileSize) in previewTargets {
    let sourceFolder = outputDir.appendingPathComponent(locale).appendingPathComponent(folder)
    let imageURLs = try fm.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let previewURL = previewDir.appendingPathComponent("\(locale)-\(folder)-contact-sheet.png")
    try contactSheet(imageURLs: imageURLs, outputURL: previewURL, columns: columns, tileSize: tileSize, background: color(0x080808))
    print("Wrote \(previewURL.path)")
}
