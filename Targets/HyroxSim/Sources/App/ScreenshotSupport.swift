import Foundation
import HyroxCore
import HyroxPersistenceApple

enum PhoneScreenshotScenario: String {
    case home = "ScreenshotPhoneHome"
    case builder = "ScreenshotPhoneBuilder"
    case history = "ScreenshotPhoneHistory"
    case summary = "ScreenshotPhoneSummary"
    case mirror = "ScreenshotPhoneMirror"

    static var current: PhoneScreenshotScenario? {
        let arguments = ProcessInfo.processInfo.arguments
        return allCases.first(where: { arguments.contains($0.rawValue) })
    }

    static var allCases: [PhoneScreenshotScenario] {
        [.home, .builder, .history, .summary, .mirror]
    }
}

enum PhoneScreenshotSeeder {
    static var isEnabled: Bool {
        PhoneScreenshotScenario.current != nil
    }

    @MainActor
    static func seed(into persistence: PersistenceController) {
        try? persistence.saveTemplate(ScreenshotFixtures.customTemplate)
        try? persistence.saveCompletedWorkout(ScreenshotFixtures.summaryWorkout)
    }
}
