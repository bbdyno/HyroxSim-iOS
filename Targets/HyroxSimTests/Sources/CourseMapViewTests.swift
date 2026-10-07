//
//  CourseMapViewTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/7/26.
//

import XCTest
import UIKit
@testable import HyroxSim

@MainActor
final class CourseMapViewTests: XCTestCase {

    /// Renders the course for unusual station counts (custom templates) and keeps
    /// the images as attachments so layout regressions can be eyeballed.
    func testRendersForAnyStationCount() throws {
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("CourseMapViewTests", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        print("COURSE_MAP_RENDER_DIR=\(outputDirectory.path)")

        let styles: [(name: String, style: CourseMapView.Style)] = [("regular", .regular), ("compact", .compact)]
        for (name, style) in styles {
            for count in [0, 1, 2, 3, 5, 8, 9, 12, 16, 20] {
                let view = CourseMapView(style: style)
                view.stations = (0..<count).map { CourseMapView.Station(label: "STATION \($0 + 1)") }
                if style.showsLabels == false, count > 0 {
                    view.progress = CourseMapView.Progress(stationsReached: count / 2, fractionToNext: 0.5)
                }

                let height = view.intrinsicContentSize.height
                XCTAssertGreaterThan(height, 0, "\(name) count \(count)")
                XCTAssertLessThan(height, 420, "\(name) count \(count) should stay compact enough to fit a screen")

                view.frame = CGRect(x: 0, y: 0, width: 327, height: height)
                view.backgroundColor = .black
                let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
                    view.layer.render(in: context.cgContext)
                }
                XCTAssertEqual(image.size.width, 327)

                let attachment = XCTAttachment(image: image)
                attachment.name = "\(name)-\(count)"
                attachment.lifetime = .keepAlways
                add(attachment)
                try image.pngData()?.write(to: outputDirectory.appendingPathComponent("\(name)-\(count).png"))
            }
        }
    }
}
