import Foundation

extension UserDefaults {
    @UserDefault(key: "eeveeHomeRecommendationsHidden", defaultValue: false)
    static var homeRecommendationsHidden
}

enum HomeFeedResponses {
    static let enabled = UserDefaults.homeRecommendationsHidden
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
            if let result = HomeFeedFilter.filter(data, url: url) {
                writeDebugLog("[HomeFeed] removed=\(result.removed) kept=\(result.kept) bytes=\(data.count)->\(result.data.count)")
                return result.data
            }
            // No content, URLs, tokens or playlist titles are logged.
            writeDebugLog("[HomeFeed] Unrecognized/unchanged response, bytes=\(data.count) \(HomeFeedFilter.schemaSummary(data))")
            return originalHooksEnabled ? BrowsitaSectionStripper.strip(data, url: url) : nil
        }
        return Completion(body: body)
    }
}
