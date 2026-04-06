import UIKit

/// App-wide design tokens.
/// Color scheme: Black background + Yellow/Gold accent + White/Gray text.
/// Inspired by official HYROX results aesthetic.
public enum DesignTokens {

    public enum Color {
        // MARK: - Base
        public static let background = UIColor.black
        public static let surface = UIColor(white: 0.08, alpha: 1)       // slightly lighter than black
        public static let surfaceElevated = UIColor(white: 0.12, alpha: 1)

        // MARK: - Accent
        public static let accent = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1) // #FFD700 Gold
        public static let accentDim = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 0.3)

        // MARK: - Text
        public static let textPrimary = UIColor.white
        public static let textSecondary = UIColor(white: 0.55, alpha: 1)
        public static let textTertiary = UIColor(white: 0.35, alpha: 1)

        // MARK: - Segment type indicators (subtle, for breakdown dots)
        public static let runAccent = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        public static let roxZoneAccent = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        public static let stationAccent = accent // yellow for stations like the reference

        // MARK: - Active workout backgrounds (darker versions for full-screen)
        public static let runBackground = UIColor(red: 0.05, green: 0.15, blue: 0.3, alpha: 1)
        public static let roxZoneBackground = UIColor(red: 0.25, green: 0.15, blue: 0.0, alpha: 1)
        public static let stationBackground = UIColor(red: 0.15, green: 0.12, blue: 0.0, alpha: 1)

        // MARK: - Functional
        public static let destructive = UIColor.systemRed
        public static let success = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)

        // MARK: - Card
        public static let cardBackground = surface
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
        public static let badge: CGFloat = 4
    }

    public enum Font {
        public static let largeNumber = UIFont.monospacedDigitSystemFont(ofSize: 48, weight: .bold)
        public static let mediumNumber = UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        public static let smallNumber = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        public static let label = UIFont.systemFont(ofSize: 11, weight: .bold)
        public static let headline = UIFont.systemFont(ofSize: 18, weight: .bold)
        public static let title = UIFont.systemFont(ofSize: 34, weight: .black)
    }
}
