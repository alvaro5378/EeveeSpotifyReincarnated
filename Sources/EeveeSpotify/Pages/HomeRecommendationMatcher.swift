import Foundation

// Used only inside a Home section, never to filter songs by their titles.
enum HomeRecommendationMatcher {
    struct Metadata {
        let className: String
        let identifier: String?
        let text: String?
    }

    // View class names and identifiers present in Spotify 9.2.0's executable.
    // Prefer these to translated labels or broad words such as "video".
    private static let cardClasses = [
        "ActionCardCarouselElementUI",
        "EpisodeStatusOverMediaPillElementUI",
        "FullEpisodeElementUI",
        "VerticalVideoCardElementUI",
        "VideoPreviewCarouselElementUI",
        "VideoPreviewCarouselCell",
        "VideoRowElementUI",
    ]
    private static let cardIdentifiers: Set<String> = [
        "ActionCardCarouselElement", "Music-Videos.Video-Card-Carousel",
    ]

    static func isShortcut(_ metadata: Metadata) -> Bool {
        metadata.className.contains("Home_AnchorsAndShortcutsKit")
    }

    static func isBlockedCard(_ metadata: Metadata) -> Bool {
        if isShortcut(metadata) { return false }
        if let identifier = metadata.identifier, cardIdentifiers.contains(identifier) { return true }
        if cardClasses.contains(where: metadata.className.hasSuffix) { return true }
        if metadata.className.contains("MusicVideos_ECMKit"),
           metadata.className.hasSuffix("CarouselCardCollectionView") { return true }
        return normalized(metadata.text) == "preview episode"
    }

    static func isBlockedHeading(_ text: String?) -> Bool {
        normalized(text) == "videos you might like"
    }

    // Read only, bounded, and reevaluated on every fitting pass: reused cells
    // and cards populated after the first pass must not keep stale verdicts.
    // In particular, never call layoutIfNeeded while UIKit is fitting a cell.
    static func containsBlockedCard<Node>(in root: Node,
                                         children: (Node) -> [Node],
                                         metadata: (Node) -> Metadata) -> Bool {
        let limit = 512
        var queue: [(Node, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count {
            let (node, depth) = queue[index]
            index += 1
            let info = metadata(node)
            if isShortcut(info) { continue }
            if isBlockedCard(info) || isBlockedHeading(info.text) { return true }
            if depth < 24, queue.count < limit {
                queue.append(contentsOf: children(node).prefix(limit - queue.count).map { ($0, depth + 1) })
            }
        }
        return false
    }

    private static func normalized(_ text: String?) -> String? {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
