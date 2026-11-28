import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("FAIL: \(message)") }
}

func varint(_ input: UInt64) -> Data {
    var value = input
    var result = Data()
    while value >= 128 { result.append(UInt8(value & 127) | 128); value >>= 7 }
    result.append(UInt8(value))
    return result
}

func field(_ number: UInt64, _ body: Data) -> Data {
    varint(number << 3 | 2) + varint(UInt64(body.count)) + body
}

func text(_ number: UInt64, _ value: String) -> Data { field(number, Data(value.utf8)) }

func section(_ kind: UInt64, id: String, title: String = "") -> Data {
    field(1, text(1, id)) + field(kind, text(1, title))
}

func sections(_ values: [Data]) -> Data { values.reduce(Data()) { $0 + field(1, $1) } }
func wrapped(_ values: [Data], metadata: Data = Data()) -> Data { field(1, sections(values)) + metadata }

let home = URL(string: "https://spclient.wg.spotify.com/casita/v1/home/all")!
let slot = URL(string: "https://gew1-spclient.spotify.com/casita/v1-beta/slot-content")!
let shortcuts = section(2, id: "user-shortcuts", title: "Recently played")
let friday = section(3, id: "friday-world", title: "It's Friday!")
let radio = section(3, id: "popular-radio", title: "Popular radios")
let charts = section(3, id: "charts", title: "Today's biggest hits")
let metadata = text(3, "response-id") + varint(8 * 2) + varint(7)
    + varint(8 * 90 + 1) + Data(repeating: 0x61, count: 8)
    + varint(8 * 91 + 5) + Data(repeating: 0x62, count: 4)

let original = wrapped([friday, shortcuts, radio, charts], metadata: metadata)
let result = HomeFeedFilter.filter(original, url: home)
let diagnostics = HomeFeedFilter.schemaSummary(original)
require(diagnostics.hasPrefix("root=[1/2,3/2,2/0,90/1,91/5]"), "diagnostic field numbers")
require(!diagnostics.contains("Friday") && !diagnostics.contains("user-shortcuts") && !diagnostics.contains("response-id"),
        "diagnostics do not expose field contents")
require(result?.data == wrapped([shortcuts], metadata: metadata), "keep exact shortcut bytes and all response metadata")
require(result?.removed == 3 && result?.kept == 1, "correct section counts")

// Direct Section lists used by slot-content and newer Home response layouts.
let direct = sections([friday, shortcuts, charts]) + metadata
require(HomeFeedFilter.filter(direct, url: slot)?.data == sections([shortcuts]) + metadata,
        "direct slot-content layout")
require(HomeFeedFilter.filter(direct, url: home)?.data == sections([shortcuts]) + metadata,
        "direct Home structure")
require(HomeFeedFilter.filter(wrapped([friday, radio]), url: home)?.data == wrapped([]),
        "recommendation-only page becomes an empty structure")
require(HomeFeedFilter.filter(sections([friday, radio]) + metadata, url: slot)?.data == metadata,
        "recommendation-only slot preserves metadata without needing shortcuts on every page")

for kind in UInt64(3)...45 {
    require(HomeFeedFilter.filter(wrapped([shortcuts, section(kind, id: "feature-\(kind)")]), url: home)?.data == wrapped([shortcuts]),
            "remove recognized feature field \(kind)")
}
let misleading = section(3, id: "mobile-shortcuts-section", title: "spotify.casita.v1.resolved.Shortcuts")
require(HomeFeedFilter.filter(wrapped([shortcuts, misleading]), url: home)?.data == wrapped([shortcuts]),
        "titles and ID strings cannot turn a recommendation into shortcuts")
let localized = section(2, id: "not-an-english-id", title: "Freitag")
require(HomeFeedFilter.filter(wrapped([localized, friday]), url: home)?.data == wrapped([localized]),
        "retain by feature type, independent of language and section name")
require(HomeFeedFilter.filter(wrapped([shortcuts]), url: home) == nil, "no rewrite when already clean")

for url in [
    "https://spclient.wg.spotify.com/casita/v1/feeds",
    "https://spclient.wg.spotify.com/casita/v1/home-other",
    "https://spclient.wg.spotify.com/browsita/v1/home",
    "https://spclient.wg.spotify.com/scrollsita/v1/home",
    "https://api.spotify.com/v1/me/playlists",
    "https://spclient.wg.spotify.com/search/v1/home",
    "https://spotify.com.evil.example/casita/v1/home/all",
    "http://spclient.wg.spotify.com/casita/v1/home/all",
] {
    let parsed = URL(string: url)!
    require(!HomeFeedFilter.handles(parsed), "do not intercept \(url)")
    require(HomeFeedFilter.filter(original, url: parsed) == nil, "do not rewrite unrelated endpoints")
}

let duplicateFeature = field(1, text(1, "id")) + field(2, Data()) + field(3, Data())
let duplicateInfo = field(1, text(1, "id")) + field(1, text(1, "id-2")) + field(3, Data())
let invalidInfo = field(1, field(1, Data([0xff]))) + field(3, Data())
let noID = field(1, Data()) + field(3, Data())
let unknown = section(46, id: "future-kind")
for value in [duplicateFeature, duplicateInfo, invalidInfo, noID, unknown] {
    require(HomeFeedFilter.filter(wrapped([shortcuts, value]), url: home) == nil,
            "leave entire unrecognized/ambiguous response unchanged")
}
for malformed in [Data([0]), Data([0x0a, 0x7f, 0]), Data([0x0a] + Array(repeating: UInt8(0xff), count: 10)),
                  Data(original.dropLast()), Data("{\"sections\":[]}".utf8)] {
    require(HomeFeedFilter.filter(malformed, url: home) == nil, "malformed/unknown wire data passes through")
}
require(HomeFeedFilter.filter(Data(repeating: 0, count: 4 * 1024 * 1024 + 1), url: home) == nil,
        "response size limit")
require(HomeFeedFilter.filter(sections(Array(repeating: shortcuts, count: 4097)), url: home) == nil,
        "field count limit")

// Routing must leave every existing response hook active when the new option
// is off, and cannot activate unrelated account behavior for Home-only use.
for enabled in [false, true] {
    for existing in [false, true] {
        require(HomeFeedRoute.select(url: home, enabled: enabled, originalHooks: existing)
                    == (enabled ? .home : existing ? .originalHooks : .passthrough), "Home routing")
        require(HomeFeedRoute.select(url: URL(string: "https://api.spotify.com/v1/me"), enabled: enabled, originalHooks: existing)
                    == (existing ? .originalHooks : .passthrough), "unrelated routing")
        require(HomeFeedRoute.select(url: nil, enabled: enabled, originalHooks: existing)
                    == (existing ? .originalHooks : .passthrough), "nil-URL routing")
    }
}

let captures = HomeFeedCaptureStore<Int>()
captures.begin(1)
let noBody = captures.finish(1)!
require(noBody.body(url: home, status: 304, failed: false, transform: { _, _ in fatalError("304 must not transform") }) == nil,
        "no-body 304 remains no-body")
require(captures.finish(1) == nil, "consume a capture exactly once")
captures.append(Data(), for: 2)
require(captures.finish(2)!.body(url: home, status: 200, failed: false,
                              transform: { _, _ in fatalError("empty chunk must not transform") }) == Data(),
        "distinguish an actual empty chunk from no data event")

captures.begin(3)
captures.append(Data(original.prefix(17)), for: 3)
captures.append(Data(original.dropFirst(17)), for: 3)
captures.append(Data([1, 2, 3]), for: 4)
let complete = captures.finish(3)!
require(complete.body(url: home, status: 200, failed: false,
                      transform: { HomeFeedFilter.filter($0, url: $1)?.data }) == result?.data, "reassemble and transform chunks once")
require(captures.finish(4)!.data == Data([1, 2, 3]), "parallel tasks have separate buffers")
for (url, status, failed) in [(home, 200, true), (home, 500, false), (home, 304, false),
                              (home, 0, false), (URL(string: "https://example.com/redirect")!, 200, false)] {
    require(complete.body(url: url, status: status, failed: failed,
                          transform: { _, _ in fatalError("must replay unchanged") }) == original,
            "errors, partial bodies and redirects preserve bytes")
}
require(complete.body(url: nil, status: 200, failed: false, transform: { _, _ in fatalError() }) == original,
        "missing URL preserves bytes")
require(complete.body(url: home, status: nil, failed: false, transform: { _, _ in fatalError() }) == original,
        "missing HTTP status preserves bytes")
require(complete.body(url: home, status: 200, failed: false, transform: { _, _ in nil }) == original,
        "unknown schema is replayed unchanged")

DispatchQueue.concurrentPerform(iterations: 128) { i in
    captures.begin(i)
    captures.append(Data([UInt8(i)]), for: i)
    captures.append(Data([UInt8(i)]), for: i)
    require(captures.finish(i)!.data == Data([UInt8(i), UInt8(i)]), "thread-safe task isolation")
}
print("Home feed filter and response lifecycle tests passed")
