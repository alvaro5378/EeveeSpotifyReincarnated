import Foundation

typealias Metadata = HomeRecommendationMatcher.Metadata

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("FAIL: \(message)") }
}

final class Node {
    var info: Metadata
    var children: [Node]
    init(_ className: String = "UIView", id: String? = nil, text: String? = nil, children: [Node] = []) {
        info = Metadata(className: className, identifier: id, text: text)
        self.children = children
    }
}

func blocked(_ root: Node) -> Bool {
    HomeRecommendationMatcher.containsBlockedCard(in: root, children: { $0.children }, metadata: { $0.info })
}

// Actual class/identifier spellings from the user's Spotify 9.2.0 IPA.
let cards = [
    "_TtC16Home_CarouselKit27ActionCardCarouselElementUI",
    "_TtC28Discovery_PreviewElementImpl35EpisodeStatusOverMediaPillElementUI",
    "_TtC28Discovery_PreviewElementImplP33_6D7940C57C6655EC9C8A4411906D406B26VerticalVideoCardElementUI",
    "_TtC33VideoRecommendations_ElementsImpl29VideoPreviewCarouselElementUI",
    "_TtC18MusicVideos_ECMKit24VideoPreviewCarouselCell",
    "_TtC36EntitySegments_EntitySegmentPageImpl20FullEpisodeElementUI",
    "_TtC39ListUXPlatformConsumers_ShowsFormatImpl17VideoRowElementUI",
    "MusicVideos_ECMKit.CarouselCardCollectionView",
]
for name in cards {
    require(blocked(Node(name)), "recognize \(name) without an English label")
    require(blocked(Node(children: [Node(children: [Node(children: [Node(name)])])])),
            "recognize wrapped/nested card \(name)")
}
for id in ["ActionCardCarouselElement", "Music-Videos.Video-Card-Carousel"] {
    require(blocked(Node("UICollectionView", id: id)), "recognize carousel identifier")
}
require(blocked(Node("UILabel", text: " Preview episode\n")), "episode preview fallback")
require(blocked(Node("UILabel", text: "VIDEOS YOU MIGHT LIKE")), "video shelf fallback")

for title in ["Podcast", "Video Games", "Episodes", "My videos", "Preview playlist", "Fresh new music"] {
    require(!blocked(Node("UILabel", text: title)), "preserve ordinary title \(title)")
}
require(!blocked(Node("Spotify.VideoPlayer")), "do not use a generic video-class substring")
require(!blocked(Node("UIView", id: "my-ActionCardCarouselElement-playlist")), "identifier must match exactly")
require(!blocked(Node(children: [Node("UILabel", text: "Dark Moody Mix"), Node("UILabel", text: "Energy Mix")])),
        "music shelves stay intact")

// A podcast shortcut must never cause the user's whole shortcut grid to disappear.
let shortcut = Node("Home_AnchorsAndShortcutsKit.ShortcutsGrid", children: [Node(cards[1])])
require(!blocked(Node(children: [shortcut])), "do not inspect shortcut tiles")
require(blocked(Node(children: [shortcut, Node(cards[3])])), "still inspect adjacent video cards")

// The same objects are reused by Spotify. Neither a negative nor a positive
// decision may stick after content changes or arrives asynchronously.
let reused = Node()
require(!blocked(reused), "empty initial cell")
reused.children = [Node(cards[3])]
require(blocked(reused), "late-arriving video child")
reused.children = [Node("UILabel", text: "A music playlist")]
require(!blocked(reused), "cell recycled for music")

// Malformed/deep/wide trees must have a strict work bound and never recurse.
let wide = Node(children: (0..<5000).map { _ in Node() })
var visits = 0
require(!HomeRecommendationMatcher.containsBlockedCard(in: wide, children: { $0.children }, metadata: {
    visits += 1
    return $0.info
}), "wide tree without blocked cards")
require(visits == 512, "visit at most 512 views per cell")
let cycle = Node()
cycle.children = [cycle]
visits = 0
require(!HomeRecommendationMatcher.containsBlockedCard(in: cycle, children: { $0.children }, metadata: {
    visits += 1
    return $0.info
}), "depth bound handles a cyclic fixture")
require(visits == 25, "stop below depth 24")
cycle.children = []
print("Home recommendation matcher tests passed")
