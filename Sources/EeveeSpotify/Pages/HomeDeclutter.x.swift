import Orion
import UIKit

struct HomeSectionsGroup: HookGroup {}
struct HomeSectionHeadingsGroup: HookGroup {}
struct HomePillsGroup: HookGroup {}

enum HomePart: String, CaseIterable, Codable {
    case shortcuts, promos, previews, dj, pills
    case episodeCarousels = "episode_carousels"

    var marker: String? {
        switch self {
        case .shortcuts: return "Home_AnchorsAndShortcutsKit"
        case .promos: return "Discovery_PromoElement"
        case .previews: return "Discovery_PreviewElement"
        case .dj: return "Discovery_DJElement"
        case .episodeCarousels, .pills: return nil
        }
    }
}

extension UserDefaults {
    @UserDefault(key: "eeveeHomeHidden", defaultValue: [HomePart]())
    private static var homeHiddenSections

    @UserDefault(key: "eeveeHomeEpisodeCarouselsHidden", defaultValue: false)
    private static var homeEpisodeCarouselsHidden

    static var homeHidden: [HomePart] {
        get {
            var parts = homeHiddenSections
            if homeEpisodeCarouselsHidden { parts.append(.episodeCarousels) }
            return parts
        }
        set {
            homeEpisodeCarouselsHidden = newValue.contains(.episodeCarousels)
            homeHiddenSections = newValue.filter { $0 != .episodeCarousels }
        }
    }
}

enum HomeDeclutter {
    static let launchHidden = Set(UserDefaults.homeHidden)
    // The old eeveeHomeFeedHidden preference is deliberately ignored. The
    // unstable shortcuts-only experiment is not enabled in this build.
    static let hidden = launchHidden
    static let meter = PerfMeter("Home][Declutter")
    private static let hidesMarkedSections = hidden.contains { $0.marker != nil }
    private static let checksFeedContent = hidden.contains(.episodeCarousels)
    private static var verdictKey: UInt8 = 0
    private static var logged = Set<HomePart>()

    private final class Verdict {
        weak var content: UIView?
        let part: HomePart?
        let final: Bool
        let time = CACurrentMediaTime()
        init(content: UIView?, part: HomePart?, final: Bool) { self.content = content; self.part = part; self.final = final }
    }

    static func hiddenSection(for cell: UICollectionViewCell) -> HomePart? {
        // Nested carousel items must retain Spotify's own sizing; collapse
        // only their containing Home section.
        var ancestor = cell.superview
        while let view = ancestor {
            if view is UICollectionViewCell { return nil }
            ancestor = view.superview
        }
        let content = cell.contentView.subviews.first
        if checksFeedContent, let part = classifyFeedContent(content) { return part }
        guard hidesMarkedSections else { return nil }
        if let verdict = objc_getAssociatedObject(cell, &verdictKey) as? Verdict, verdict.content === content, content != nil,
           verdict.final || CACurrentMediaTime() - verdict.time < 1 {
            return verdict.part
        }
        let result = classify(cell)
        objc_setAssociatedObject(cell, &verdictKey, Verdict(content: content, part: result.part, final: result.final), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return result.part
    }

    private static func classifyFeedContent(_ content: UIView?) -> HomePart? {
        guard let content else { return nil }
        let contentType = NSStringFromClass(type(of: content))
        guard contentType.contains("Home_EvoPageImpl"), contentType.contains("HomeStructure") else { return nil }

        // Keep the plain shortcut grid. Other Home cards can have additional
        // wrappers or a nested carousel, so do not assume a two-view path.
        if let collection = content.subviews.first?.subviews.first as? UICollectionView,
           collection.accessibilityIdentifier?.isEmpty != false,
           !NSStringFromClass(type(of: collection)).contains("Home_CarouselKit"),
           !HomeRecommendationMatcher.isBlockedCard(metadata(collection)) {
            return nil
        }
        return HomeRecommendationMatcher.containsBlockedCard(in: content,
            children: { $0.subviews }, metadata: metadata) ? .episodeCarousels : nil
    }

    static func hidesHeading(in view: UIView) -> Bool {
        guard let heading = PageLookup.find("Components.UI.SectionHeadingHome", in: view) else { return false }
        return HomeRecommendationMatcher.containsBlockedCard(in: heading,
            children: { $0.subviews }, metadata: metadata)
    }

    private static func metadata(_ view: UIView) -> HomeRecommendationMatcher.Metadata {
        .init(className: NSStringFromClass(type(of: view)), identifier: view.accessibilityIdentifier,
              text: (view as? UILabel)?.text ?? view.accessibilityLabel)
    }

    private static func classify(_ cell: UICollectionViewCell) -> (part: HomePart?, final: Bool) {
        var ancestor = cell.superview
        while let view = ancestor {
            if view is UICollectionViewCell { return (nil, true) }
            ancestor = view.superview
        }
        var names = [String]()
        var queue: [UIView] = [cell]
        var index = 0
        while index < queue.count {
            let view = queue[index]
            index += 1
            names.append(NSStringFromClass(type(of: view)))
            if queue.count < 512 { queue += view.subviews.prefix(512 - queue.count) }
        }
        let all = names.joined()
        guard all.contains("Home_EvoPageImpl") else { return (nil, true) }
        let part = HomePart.allCases.first { hidden.contains($0) && $0.marker.map(all.contains) == true }
        if let part, logged.insert(part).inserted { eeveeLog("[EeveeSpotify][Home] Collapsed %@", part.rawValue) }
        // Sections fill in after their first pass, so a visible verdict is only final once content has settled.
        return (part, part != nil || queue.count > 40)
    }
}

class HomeSectionCellHook: ClassHook<UICollectionViewCell> {
    typealias Group = HomeSectionsGroup
    static let targetName = "_TtC12Element_List18CollectionViewCell"

    func preferredLayoutAttributesFittingAttributes(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let result = orig.preferredLayoutAttributesFittingAttributes(attributes)
        let part = HomeDeclutter.meter.measure { HomeDeclutter.hiddenSection(for: target) }
        let hidden = part != nil
        if target.clipsToBounds != hidden { target.clipsToBounds = hidden }
        if hidden { result.size.height = 0 }
        if part == .episodeCarousels { result.isHidden = true }
        return result
    }

}

class HomeSectionHeadingHook: ClassHook<UICollectionReusableView> {
    typealias Group = HomeSectionHeadingsGroup
    static let targetName = "_TtC12Element_List21SupplementaryItemView"

    func preferredLayoutAttributesFittingAttributes(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let result = orig.preferredLayoutAttributesFittingAttributes(attributes)
        if HomeDeclutter.hidesHeading(in: target) {
            result.size.height = 0
            result.isHidden = true
        }
        return result
    }
}

class HomePillsHook: ClassHook<UIView> {
    typealias Group = HomePillsGroup
    static let targetName = "_TtC14Home_PillUIKit14PillScrollView"

    func didMoveToWindow() {
        orig.didMoveToWindow()
        target.isHidden = true
    }
}

func activateHomeDeclutter() {
    let hidden = HomeDeclutter.hidden
    guard !hidden.isEmpty else { return }
    let start = CFAbsoluteTimeGetCurrent()
    var active = [String]()
    if hidden.contains(.pills), NSClassFromString(HomePillsHook.targetName) != nil {
        HomePillsGroup().activate()
        active.append("pills")
    }
    if !hidden.subtracting([.pills]).isEmpty, NSClassFromString(HomeSectionCellHook.targetName) != nil {
        HomeSectionsGroup().activate()
        active.append("sections")
        if hidden.contains(.episodeCarousels),
           NSClassFromString(HomeSectionHeadingHook.targetName) != nil {
            HomeSectionHeadingsGroup().activate()
            active.append("headings")
        }
    }
    eeveeLog("[EeveeSpotify][Home] Declutter: hiding %@, hooks %@ (%.2f ms)", hidden.map(\.rawValue).sorted().joined(separator: ", "),
             active.isEmpty ? "MISSING" : active.joined(separator: "+"), (CFAbsoluteTimeGetCurrent() - start) * 1000)
}
