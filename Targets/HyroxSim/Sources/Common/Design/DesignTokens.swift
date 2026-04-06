import UIKit

public enum DesignTokens {

    public enum Color {
        public static let runAccent = UIColor.systemBlue
        public static let roxZoneAccent = UIColor.systemOrange
        public static let stationAccent = UIColor.systemPurple

        public static let cardBackground = UIColor.secondarySystemBackground
        public static let proTint = UIColor.systemRed
        public static let openTint = UIColor.systemTeal
        public static let mixedTint = UIColor.systemIndigo
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
    }

    public enum Radius {
        public static let card: CGFloat = 16
    }

    public enum Font {
        public static let largeNumber = UIFont.monospacedDigitSystemFont(ofSize: 48, weight: .semibold)
        public static let mediumNumber = UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        public static let smallNumber = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        public static let label = UIFont.preferredFont(forTextStyle: .caption1)
    }
}
