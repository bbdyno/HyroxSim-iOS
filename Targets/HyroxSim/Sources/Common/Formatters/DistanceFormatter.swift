import Foundation

public enum DistanceFormatter {

    /// Formats meters as "1.23 km" (>= 1000m) or "240 m" (< 1000m)
    public static func short(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        } else {
            return "\(Int(meters)) m"
        }
    }
}
