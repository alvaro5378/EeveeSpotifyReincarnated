import Foundation

enum HomeFeedRoute {
    case originalHooks, home, passthrough

    static func select(url: URL?, enabled: Bool, originalHooks: Bool) -> HomeFeedRoute {
        if enabled, let url, HomeFeedFilter.handles(url) { return .home }
        return originalHooks ? .originalHooks : .passthrough
    }
}

// Separate from the existing response buffers. No-body 304s and cancelled or
// failed tasks must retain the original delegate semantics, including nil body.
final class HomeFeedCaptureStore<Key: Hashable> {
    struct Capture {
        private(set) var data: Data?

        mutating func append(_ chunk: Data) {
            if data == nil { data = chunk } else { data?.append(chunk) }
        }

        func body(url: URL?, status: Int?, failed: Bool,
                  transform: (Data, URL) -> Data?) -> Data? {
            guard let data, !data.isEmpty, !failed, let status, (200..<300).contains(status),
                  let url, HomeFeedFilter.handles(url) else { return data }
            return transform(data, url) ?? data
        }
    }

    private let lock = NSLock()
    private var captures: [Key: Capture] = [:]

    func begin(_ key: Key) {
        lock.lock(); defer { lock.unlock() }
        if captures[key] == nil { captures[key] = Capture() }
    }

    func append(_ data: Data, for key: Key) {
        lock.lock(); defer { lock.unlock() }
        var capture = captures[key] ?? Capture()
        capture.append(data)
        captures[key] = capture
    }

    func finish(_ key: Key) -> Capture? {
        lock.lock(); defer { lock.unlock() }
        return captures.removeValue(forKey: key)
    }
}
