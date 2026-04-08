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

struct WatchScreenshotActiveWorkoutView: View {
    private let accent = Color.blue
    private let heart = Color.orange

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
                Text("RUN 3 / 8")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
            }

            Text("Strong pace")
                .font(.system(size: 10))
                .foregroundStyle(.gray)

            Text("04:28")
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("0:27:41")
                .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.gray)

            VStack(spacing: 0) {
                Text("4'13\" /km")
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text("PACE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .padding(.vertical, 2)

            HStack(spacing: 3) {
                Text("172")
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(heart)
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(heart)
            }

            Spacer(minLength: 2)

            HStack(spacing: 8) {
                Button {} label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.gray)

                Button {} label: {
                    Text("NEXT")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)

                Button {} label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 4)
        .background(Color.black)
    }
}
