import SwiftUI
import HyroxCore
import HyroxPersistenceApple

enum WatchScreenshotScenario: String {
    case home = "ScreenshotWatchHome"
    case active = "ScreenshotWatchActive"
    case history = "ScreenshotWatchHistory"
    case summary = "ScreenshotWatchSummary"

    static var current: WatchScreenshotScenario? {
        let arguments = ProcessInfo.processInfo.arguments
        return allCases.first(where: { arguments.contains($0.rawValue) })
    }

    static var allCases: [WatchScreenshotScenario] {
        [.home, .active, .history, .summary]
    }
}

enum WatchScreenshotSeeder {
    static var isEnabled: Bool {
        WatchScreenshotScenario.current != nil
    }

    @MainActor
    static func seed(into persistence: PersistenceController) {
        try? persistence.saveTemplate(ScreenshotFixtures.customTemplate)
        try? persistence.saveCompletedWorkout(ScreenshotFixtures.watchSummaryWorkout)
    }
}

/// 스크린샷용 운동 화면. 가짜 그림이 아니라 실제 `WorkoutDisplayView` 를 고정된 값으로 띄운다 —
/// 그래야 스토어 이미지가 실제 화면과 어긋나지 않는다.
struct WatchScreenshotActiveWorkoutView: View {
    @State private var model = WatchScreenshotWorkoutModel()

    var body: some View {
        WorkoutDisplayView(model: model)
    }
}

@MainActor
final class WatchScreenshotWorkoutModel: WorkoutDisplaying {
    /// `ScreenshotWatchStation` 인자를 주면 스테이션 화면.
    private let isStation = ProcessInfo.processInfo.arguments.contains("ScreenshotWatchStation")

    var segmentElapsedText: String { isStation ? "03:47" : "04:12" }
    var totalElapsedText: String { isStation ? "0:31:20" : "0:24:31" }
    var currentDisplayTitle: String { isStation ? "Burpee Broad Jumps" : "Run 4 / 8" }
    var nextDisplayTitle: String? { isStation ? "Run 5" : "Burpee Broad Jumps" }
    var paceText: String { "4'12\"" }
    var stationTargetText: String? { isStation ? "80 m" : nil }
    var heartRateText: String { isStation ? "171" : "162" }
    var heartRateZone: HeartRateZone? { .z4 }
    var goalText: String { isStation ? "03:26" : "04:24" }
    var goalDeltaText: String { isStation ? "+0:21" : "-0:12" }
    var isOverGoal: Bool { isStation }
    var totalGoalText: String { "1:15:00" }
    var totalDeltaText: String { "-0:35" }
    var isOverTotalGoal: Bool { false }
    var accent: WorkoutDisplayAccent { isStation ? .station : .run }
    var isPaused: Bool { false }
    var isLastSegment: Bool { false }
    var isConnected: Bool { true }
    var stripCells: [SegmentStripState] {
        let done: [SegmentStripState] = [.ahead, .ahead, .ahead, .behind, .ahead, .ahead]
        let finished = isStation ? done + [.ahead] : done
        return finished + [.current] + Array(repeating: .upcoming, count: 16 - finished.count - 1)
    }

    func advance() {}
    func togglePause() {}
    func endWorkout() {}
}
