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
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                    Text("RUN 3 / 8")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text("0:27:41")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }

            Text("04:28")
                .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("GOAL")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("06:00")
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("-1:32")
                    .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.green)
            }

            Text("4'13\" /km  •  680 m")
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.86))

            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(heart)
                Text("172")
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(heart)
            }

            Spacer(minLength: 14)

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
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .background(Color.black)
    }
}
