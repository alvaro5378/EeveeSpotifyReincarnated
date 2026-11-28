import Foundation

struct HomeShelfPolicy {
    static let defaultHiddenTitles = [
        "Popular radio", "Recommended stations", "Today's biggest hits",
        "Today's top hits", "New Music Friday", "Iconic VMA performances",
        "Happy", "Instrumental",
    ]

    private let hidden: [String]

    init(hiddenTitles: [String]) {
        hidden = Self.sanitizedTitles(hiddenTitles).map(Self.normalize)
    }

    func hides(_ heading: String, sponsored: Bool = false) -> Bool {
        if sponsored { return true }
        let title = Self.normalize(heading)
        // Protect explicitly personal shelves even if a generic phrase occurs
        // later in the heading. Unlisted shelves are always kept by default.
        let personalPrefixes = [
            "daily mix", "discover weekly", "release radar", "on repeat", "repeat rewind",
            "your top mixes", "your personalized mixes", "made for you",
            "because you listened to", "more like",
        ]
        if personalPrefixes.contains(where: { title == $0 || title.hasPrefix($0 + " ") }) { return false }
        return hidden.contains { blocked in
            // Single mood/genre words must not hide Happy Mix, Instrumental
            // Mix, or other playlists that happen to use the same adjective.
            title == blocked || (blocked.contains(" ") && (" " + title + " ").contains(" " + blocked + " "))
        }
    }

    static func sanitizedTitles(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        return titles.compactMap { value -> String? in
            let text = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            let key = normalize(text)
            return !key.isEmpty && seen.insert(key).inserted ? text : nil
        }.prefix(64).map { $0 }
    }

    static func normalize(_ text: String) -> String {
        let plain = String(text.prefix(512))
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = plain.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        let value = words.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if value == "popular radios" { return "popular radio" }
        if value.hasPrefix("popular radios ") { return "popular radio " + value.dropFirst("popular radios ".count) }
        return value
    }
}
