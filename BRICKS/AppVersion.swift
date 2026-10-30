import Foundation

/// Dotted version numbers ("1.6", "1.10.2"), compared part by part as numbers so 1.10 is
/// newer than 1.9 and 1.6 equals 1.6.0.
enum AppVersion {
    static func isOlder(_ version: String, than other: String) -> Bool {
        let a = parts(version), b = parts(other)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
}
