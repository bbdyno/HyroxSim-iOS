//
//  ShareTemplateTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import HyroxCore
@testable import HyroxSim

@MainActor
final class ShareTemplateTests: XCTestCase {

    func testCanvasSizesMatchInstagramFormats() {
        XCTAssertEqual(ShareTemplate.bigNumber.canvasSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(ShareTemplate.splits.canvasSize, CGSize(width: 1080, height: 1350))
    }

    func testDataFromAFullRace() {
        let data = ShareCardData(workout: ScreenshotFixtures.fullRaceWorkout, topPercent: 51.2)
        XCTAssertEqual(data.totalTime, "1:27:57")
        XCTAssertEqual(data.cells.count, 16)
        XCTAssertEqual(data.splits.count, 9, "running total + 8 stations")
        XCTAssertNotNil(data.delta)
        XCTAssertNotNil(data.topPercentText)
        XCTAssertTrue(data.topPercentText?.contains("51%") ?? false)
    }

    func testTopPercentIsOmittedWhenUnknown() {
        XCTAssertNil(ShareCardData(workout: ScreenshotFixtures.fullRaceWorkout, topPercent: nil).topPercentText)
    }

    /// 이미지가 정해진 픽셀 크기로, 검은 배경에 무언가 그려져서 나온다.
    func testRenderedImagesHaveExactPixelSizeAndContent() throws {
        let renderer = ShareTemplateRenderer(
            data: ShareCardData(workout: ScreenshotFixtures.fullRaceWorkout, topPercent: 51.2)
        )
        for template in [ShareTemplate.bigNumber, .splits] {
            let image = renderer.makeImage(template)
            let cg = try XCTUnwrap(image.cgImage)
            // 눈으로 확인할 때: `TEST_RUNNER_SHARE_OUT_DIR=/path xcodebuild test …`
            if let out = ProcessInfo.processInfo.environment["SHARE_OUT_DIR"] {
                try image.pngData()?.write(to: URL(fileURLWithPath: out).appendingPathComponent("share-\(template.rawValue).png"))
            }
            XCTAssertEqual(CGSize(width: cg.width, height: cg.height), template.canvasSize, "\(template)")

            let width = cg.width, height = cg.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            var lit = 0
            for i in stride(from: 0, to: pixels.count, by: 4 * 97) where pixels[i] > 40 || pixels[i + 1] > 40 {
                lit += 1
            }
            XCTAssertGreaterThan(lit, 200, "\(template) drew visible content")
            // 왼쪽 위 모서리는 배경(검정)이다.
            XCTAssertLessThan(pixels[0], 10)
        }
    }

    /// 첫 레이아웃만 무료.
    func testOnlyFirstTemplateIsFree() {
        let gate = FeatureGate(tier: .free)
        XCTAssertEqual(ShareTemplate.allCases.indices.map { gate.canUseShareTemplate(at: $0) }, [true, false, false])
    }
}
