import Foundation

public enum Format {
    /// "0:07", "12:34", "1:02:03".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "3 minutes 5 seconds", for VoiceOver.
    public static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append(count(h, "hour")) }
        if m > 0 { parts.append(count(m, "minute")) }
        if s > 0 || parts.isEmpty { parts.append(count(s, "second")) }
        return parts.joined(separator: " ")
    }

    /// "1 shot", "3 shots".
    public static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(plural(number, noun))"
    }

    /// "shot" for one, "shots" otherwise.
    public static func plural(_ number: Int, _ noun: String) -> String {
        number == 1 ? noun : noun + "s"
    }

    /// "43%".
    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
