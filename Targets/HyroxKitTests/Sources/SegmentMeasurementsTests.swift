import XCTest
@testable import HyroxKit

final class SegmentMeasurementsTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    // MARK: - Distance

    func testEmptySamplesDistanceIsZero() {
        let m = SegmentMeasurements()
        XCTAssertEqual(m.distanceMeters, 0)
    }

    func testSingleSampleDistanceIsZero() {
        let m = SegmentMeasurements(locationSamples: [
            LocationSample(timestamp: t0, latitude: 37.5665, longitude: 126.9780, horizontalAccuracy: 5)
        ])
        XCTAssertEqual(m.distanceMeters, 0)
    }

    func testTwoPointsDistanceReasonable() {
        // Seoul City Hall (37.5665, 126.9780) → ~100m north (roughly +0.0009 lat)
        let a = LocationSample(timestamp: t0, latitude: 37.5665, longitude: 126.9780, horizontalAccuracy: 5)
        let b = LocationSample(timestamp: t0.addingTimeInterval(30), latitude: 37.5674, longitude: 126.9780, horizontalAccuracy: 5)
        let m = SegmentMeasurements(locationSamples: [a, b])

        // ~100m, allow ±5% tolerance
        XCTAssertEqual(m.distanceMeters, 100, accuracy: 5)
    }

    func testHighAccuracySamplesExcluded() {
        let a = LocationSample(timestamp: t0, latitude: 37.5665, longitude: 126.9780, horizontalAccuracy: 5)
        let bad = LocationSample(timestamp: t0.addingTimeInterval(10), latitude: 37.5700, longitude: 126.9780, horizontalAccuracy: 50) // excluded
        let b = LocationSample(timestamp: t0.addingTimeInterval(20), latitude: 37.5674, longitude: 126.9780, horizontalAccuracy: 5)
        let m = SegmentMeasurements(locationSamples: [a, bad, b])

        // bad sample skipped, distance is a→b only (~100m)
        XCTAssertEqual(m.distanceMeters, 100, accuracy: 5)
    }

    // MARK: - Pace

    func testAveragePace1km5min() {
        // 1km in 5 min = 300 sec/km
        let a = LocationSample(timestamp: t0, latitude: 37.5665, longitude: 126.9780, horizontalAccuracy: 5)
        // ~1000m north: +0.009 lat ≈ 1km
        let b = LocationSample(timestamp: t0.addingTimeInterval(300), latitude: 37.5755, longitude: 126.9780, horizontalAccuracy: 5)
        let m = SegmentMeasurements(locationSamples: [a, b])

        let pace = m.averagePaceSecondsPerKm(activeDuration: 300)
        XCTAssertNotNil(pace)
        // Should be ~300 sec/km, allow ±5% since Haversine distance won't be exactly 1000m
        XCTAssertEqual(pace!, 300, accuracy: 15)
    }

    func testAveragePaceNilForZeroDistance() {
        let m = SegmentMeasurements()
        XCTAssertNil(m.averagePaceSecondsPerKm(activeDuration: 300))
    }

    // MARK: - Heart Rate

    func testAverageHeartRate() {
        let m = SegmentMeasurements(heartRateSamples: [
            HeartRateSample(timestamp: t0, bpm: 140),
            HeartRateSample(timestamp: t0.addingTimeInterval(5), bpm: 160),
            HeartRateSample(timestamp: t0.addingTimeInterval(10), bpm: 150)
        ])
        XCTAssertEqual(m.averageHeartRate, 150)
    }

    func testMaxHeartRate() {
        let m = SegmentMeasurements(heartRateSamples: [
            HeartRateSample(timestamp: t0, bpm: 140),
            HeartRateSample(timestamp: t0.addingTimeInterval(5), bpm: 175),
            HeartRateSample(timestamp: t0.addingTimeInterval(10), bpm: 160)
        ])
        XCTAssertEqual(m.maxHeartRate, 175)
    }

    func testMinHeartRate() {
        let m = SegmentMeasurements(heartRateSamples: [
            HeartRateSample(timestamp: t0, bpm: 140),
            HeartRateSample(timestamp: t0.addingTimeInterval(5), bpm: 120),
            HeartRateSample(timestamp: t0.addingTimeInterval(10), bpm: 160)
        ])
        XCTAssertEqual(m.minHeartRate, 120)
    }

    func testEmptyHeartRateReturnsNil() {
        let m = SegmentMeasurements()
        XCTAssertNil(m.averageHeartRate)
        XCTAssertNil(m.maxHeartRate)
        XCTAssertNil(m.minHeartRate)
    }
}
