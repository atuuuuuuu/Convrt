import Foundation

/// "90", "1:30", "01:02:03" and "0:01.5" to seconds, and back.
enum TimeParser {
    static func seconds(from text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        var total = 0.0
        for (i, part) in parts.enumerated() {
            let isLast = i == parts.count - 1
            let value: Double
            if isLast {
                guard let v = Double(part), v.isFinite else { return nil }
                value = v
            } else {
                guard let v = Int(part) else { return nil }
                value = Double(v)
            }
            guard value >= 0 else { return nil }
            if parts.count > 1, i > 0, value >= 60 { return nil }      // minutes and seconds stop at 59
            total = total * 60 + value
        }
        return total
    }

    /// "m:ss.s", or "h:mm:ss.s" past an hour.
    static func format(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        let h = tenths / 36000, m = (tenths / 600) % 60, s = Double(tenths % 600) / 10
        return h > 0 ? String(format: "%d:%02d:%04.1f", h, m, s) : String(format: "%d:%04.1f", m, s)
    }
}
