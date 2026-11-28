import Foundation

extension UserDefaults {
    @UserDefault(key: "eeveeHomeRecommendationsHidden", defaultValue: false)
    static var homeUnwantedShelvesHidden

    @UserDefault(key: "eeveeHomeHiddenShelfTitles", defaultValue: HomeShelfPolicy.defaultHiddenTitles)
    static var homeHiddenShelfTitles
}

enum HomeFeedResponses {
    static let enabled = UserDefaults.homeUnwantedShelvesHidden
    static let hiddenTitles = HomeShelfPolicy.sanitizedTitles(UserDefaults.homeHiddenShelfTitles)
    static let originalHooksEnabled = UserDefaults.patchType.isPatching
    private static let captures = HomeFeedCaptureStore<ObjectIdentifier>()

    struct Completion {
        let body: Data?
    }

    static func route(_ url: URL?) -> HomeFeedRoute {
        HomeFeedRoute.select(url: url, enabled: enabled, originalHooks: originalHooksEnabled)
    }

    static func begin(_ task: URLSessionTask) {
        captures.begin(ObjectIdentifier(task))
    }

    static func append(_ data: Data, for task: URLSessionTask) {
        captures.append(data, for: ObjectIdentifier(task))
    }

    static func finish(_ task: URLSessionTask, error: Error?) -> Completion? {
        guard enabled, let capture = captures.finish(ObjectIdentifier(task)) else { return nil }
        let body = capture.body(url: task.currentRequest?.url, status: (task.response as? HTTPURLResponse)?.statusCode,
                                failed: error != nil) { data, url in
            let result = HomeFeedFilter.filter(data, url: url, hiddenTitles: hiddenTitles)
            if let result {
                writeDebugLog("[HomeFeed] removed=\(result.removed) kept=\(result.kept) bytes=\(data.count)->\(result.data.count)")
            } else {
                // No content, URLs, tokens or playlist titles are logged.
                writeDebugLog("[HomeFeed] No matching shelf removed, bytes=\(data.count) \(HomeFeedFilter.schemaSummary(data))")
            }
            // Preserve the existing ad pass even when a targeted shelf was removed.
            let filtered = result?.data ?? data
            if originalHooksEnabled, let stripped = BrowsitaSectionStripper.strip(filtered, url: url) { return stripped }
            return result?.data
        }
        return Completion(body: body)
    }
}
