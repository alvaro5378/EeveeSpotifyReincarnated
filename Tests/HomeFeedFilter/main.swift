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

func section(_ kind: UInt64, id: String, title: String = "", headingKind: UInt64 = 2, extra: Data = Data()) -> Data {
    let feature = kind == 3 ? field(1, field(headingKind, text(1, title))) + extra : text(1, title) + extra
    return field(1, text(1, id)) + field(kind, feature)
}

func sections(_ values: [Data]) -> Data { values.reduce(Data()) { $0 + field(1, $1) } }
func wrapped(_ values: [Data], metadata: Data = Data()) -> Data { field(1, sections(values)) + metadata }

let home = URL(string: "https://spclient.wg.spotify.com/casita/v1/home/all")!
let slot = URL(string: "https://gew1-spclient.spotify.com/casita/v1-beta/slot-content")!
let shortcuts = section(2, id: "user-shortcuts", title: "Recently played")
let friday = section(3, id: "friday-world", title: "It's New Music Friday!")
let radio = section(3, id: "popular-radio", title: "Popular radios")
let charts = section(3, id: "charts", title: "Today's biggest hits")
let personal = section(3, id: "personal-mixes", title: "Your Top Mixes")
let releaseRadar = section(3, id: "release-radar", title: "Release Radar")
let metadata = text(3, "response-id") + varint(8 * 2) + varint(7)
    + varint(8 * 90 + 1) + Data(repeating: 0x61, count: 8)
    + varint(8 * 91 + 5) + Data(repeating: 0x62, count: 4)

let original = wrapped([friday, personal, shortcuts, radio, charts, releaseRadar], metadata: metadata)
let result = HomeFeedFilter.filter(original, url: home)
let diagnostics = HomeFeedFilter.schemaSummary(original)
require(diagnostics.hasPrefix("root=[1/2,3/2,2/0,90/1,91/5]"), "diagnostic field numbers")
require(!diagnostics.contains("Friday") && !diagnostics.contains("user-shortcuts") && !diagnostics.contains("response-id"),
        "diagnostics do not expose field contents")
require(result?.data == wrapped([personal, shortcuts, releaseRadar], metadata: metadata), "keep exact personal/shortcut bytes and all response metadata")
require(result?.removed == 3 && result?.kept == 3, "correct section counts")

// Direct Section lists used by slot-content and newer Home response layouts.
let direct = sections([friday, personal, shortcuts, charts]) + metadata
require(HomeFeedFilter.filter(direct, url: slot)?.data == sections([personal, shortcuts]) + metadata,
        "direct slot-content layout")
require(HomeFeedFilter.filter(direct, url: home)?.data == sections([personal, shortcuts]) + metadata,
        "direct Home structure")
require(HomeFeedFilter.filter(wrapped([friday, radio]), url: home)?.data == wrapped([]),
        "recommendation-only page becomes an empty structure")
require(HomeFeedFilter.filter(sections([friday, radio]) + metadata, url: slot)?.data == metadata,
        "recommendation-only slot preserves metadata without needing shortcuts on every page")

for kind in UInt64(2)...45 {
    let input = wrapped([shortcuts, section(kind, id: "feature-\(kind)", title: "An unlisted music shelf")])
    require(HomeFeedFilter.filter(input, url: home) == nil, "never bulk-delete unlisted feature \(kind)")
}
let anchors = section(7, id: "user-anchors", title: "Pinned music")
require(HomeFeedFilter.filter(wrapped([friday, anchors, shortcuts, radio]), url: home)?.data == wrapped([anchors, shortcuts]),
        "retain both anchored and regular shortcut formats")
require(HomeFeedFilter.filter(wrapped([anchors, friday]), url: home)?.data == wrapped([anchors]),
        "an anchors-only account keeps its top grid")
let misleading = section(3, id: "popular-radio", title: "Daily Mix 1", extra: field(2, text(1, "Popular Radio")))
require(HomeFeedFilter.filter(wrapped([misleading]), url: home) == nil,
        "only match the typed heading, never section IDs or card/metadata strings")
let localized = section(2, id: "not-an-english-id", title: "Freitag")
require(HomeFeedFilter.filter(wrapped([localized, friday]), url: home)?.data == wrapped([localized]),
        "retain by feature type, independent of language and section name")
require(HomeFeedFilter.filter(wrapped([shortcuts]), url: home) == nil, "no rewrite when already clean")

let policy = HomeShelfPolicy(hiddenTitles: HomeShelfPolicy.defaultHiddenTitles)
for title in ["Daily Mix 1", "Discover Weekly", "Release Radar", "On Repeat", "Repeat Rewind",
              "Your Top Mixes", "Your Happy Mix", "Happy Mix", "Instrumental Mix", "Your mood mixes",
              "Because you listened to New Music Friday", "More like Popular Radio", "Made for you",
              "Soundtrack your Sunday afternoon", "It's Friday!", "Fresh new music", "Recommended for today",
              "Radio based on your favorite artist", "Popular Radiohead"] {
    require(!policy.hides(title), "preserve \(title)")
    require(HomeFeedFilter.filter(wrapped([section(3, id: "personal", title: title)]), url: home) == nil,
            "personal and unknown shelves remain byte-identical")
}
for title in ["Popular radio", "Popular radios near you", "NEW MUSIC FRIDAY", "It's New Music Friday!",
              "Today’s biggest hits", "Today's top hits", "Recommended stations", "Happy", "Instrumental",
              "Iconic VMA performances"] {
    require(policy.hides(title), "hide requested generic shelf \(title)")
}
for variant in UInt64(2)...6 {
    let blocked = section(3, id: "generic", title: "Popular radio", headingKind: variant)
    require(HomeFeedFilter.filter(wrapped([personal, blocked]), url: home)?.data == wrapped([personal]),
            "typed heading variant \(variant)")
}
let mixedFresh = section(3, id: "fresh", title: "Fresh new music", extra: field(2, text(1, "Release Radar")))
require(HomeFeedFilter.filter(wrapped([radio, mixedFresh, personal]), url: home)?.data == wrapped([mixedFresh, personal]),
        "keep mixed new-release shelf so Release Radar cannot disappear")
let unknownHeading = section(3, id: "new-heading-format", title: "Popular radio", headingKind: 7)
require(HomeFeedFilter.filter(wrapped([unknownHeading]), url: home) == nil, "unknown heading variants are preserved")
let sponsored = section(3, id: "sponsored", title: "An artist campaign", headingKind: 4)
require(HomeFeedFilter.filter(wrapped([personal, sponsored]), url: home)?.data == wrapped([personal]),
        "remove explicit sponsored heading")
let custom = section(3, id: "custom", title: "State of music today")
require(HomeFeedFilter.filter(wrapped([custom]), url: home) == nil, "unlisted title stays")
require(HomeFeedFilter.filter(wrapped([personal, custom]), url: home,
                              hiddenTitles: ["State of music today"])?.data == wrapped([personal]), "editable custom title")
require(HomeFeedFilter.filter(wrapped([radio]), url: home, hiddenTitles: []) == nil, "deleting a rule restores that shelf")
require(HomeShelfPolicy.sanitizedTitles([" Popular radio ", "POPULAR RADIOS", "", "Radio"]) == ["Popular radio", "Radio"],
        "normalize and deduplicate editable rules")
print("Selective Home shelf policy tests passed")

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
    require(HomeFeedFilter.filter(wrapped([shortcuts, value]), url: home) == nil, "unknown sections alone are unchanged")
    require(HomeFeedFilter.filter(wrapped([shortcuts, radio, value]), url: home)?.data == wrapped([shortcuts, value]),
            "preserve unknown/ambiguous section bytes while removing only a known unwanted shelf")
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
