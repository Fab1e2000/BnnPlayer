import Foundation

struct LyricLine: Equatable, Identifiable {
    let timestampMs: Int
    let primaryText: String
    let secondaryText: String?

    var id: String {
        "\(timestampMs)-\(primaryText)-\(secondaryText ?? "")"
    }

    var timestamp: TimeInterval {
        TimeInterval(timestampMs) / 1000
    }
}
