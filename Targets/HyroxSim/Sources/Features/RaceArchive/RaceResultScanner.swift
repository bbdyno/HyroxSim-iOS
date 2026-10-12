//
//  RaceResultScanner.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit
import Vision

/// 결과 화면 사진에서 글자를 읽는다. 전부 기기 안에서 처리하고 사진은 어디에도 보내지 않는다.
enum RaceResultScanner {

    enum ScanError: Error { case unreadableImage }

    /// 사진 → 구간 기록. 해석은 `RaceResultTextParser` 가 한다.
    static func scan(_ image: UIImage) async throws -> ParsedRaceResult {
        RaceResultTextParser.parse(try await recognize(image))
    }

    static func recognize(_ image: UIImage) async throws -> [RecognizedTextLine] {
        guard let cgImage = image.cgImage else { throw ScanError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // 구간 이름과 시간뿐이라 단어 교정은 오히려 "SkiErg" 같은 말을 망가뜨린다.
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                // Vision 은 원점이 왼쪽 아래다. 파서는 위에서 아래로 읽는다.
                return RecognizedTextLine(
                    text: text,
                    x: Double(box.minX), y: Double(1 - box.maxY),
                    w: Double(box.width), h: Double(box.height)
                )
            }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
