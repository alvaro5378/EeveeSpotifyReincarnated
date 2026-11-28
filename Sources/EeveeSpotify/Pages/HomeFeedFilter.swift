import Foundation

// Spotify 9.2.0: ResolvedHome.structure (1) -> HomeStructure.sections (1).
// Section contains sectionInfo (1) and a feature oneof: shortcuts is field 2.
// Slot-content responses carry repeated Section directly in field 1.
// See Tests/HomeFeedFilter/README.md for the client-side schema evidence.
enum HomeFeedFilter {
    struct Result {
        let data: Data
        let kept: Int
        let removed: Int
    }

    static func handles(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased().hasSuffix(".spotify.com") == true else { return false }
        let path = url.path.lowercased()
        return path == "/casita/v1/home" || path.hasPrefix("/casita/v1/home/")
            || path == "/casita/v1-beta/slot-content" || path.hasPrefix("/casita/v1-beta/slot-content/")
    }

    static func filter(_ data: Data, url: URL) -> Result? {
        guard handles(url), !data.isEmpty, data.count <= 4 * 1024 * 1024,
              let fields = parse(data) else { return nil }
        // Try the direct Section list before the wrapped ResolvedHome form.
        if let result = filterSections(data, fields: fields) { return result.removed > 0 ? result : nil }
        let structures = fields.filter { $0.number == 1 }
        guard structures.count == 1, let structure = structures.first,
              let range = structure.payload else { return nil }
        let original = data.subdata(in: range)
        guard let innerFields = parse(original),
              let result = filterSections(original, fields: innerFields), result.removed > 0 else { return nil }
        var rebuilt = Data()
        for field in fields {
            if field.range == structure.range {
                rebuilt.append(data.subdata(in: field.range.lowerBound..<range.lowerBound - field.lengthBytes))
                rebuilt.append(varint(UInt64(result.data.count)))
                rebuilt.append(result.data)
            } else {
                rebuilt.append(data.subdata(in: field.range))
            }
        }
        return Result(data: rebuilt, kept: result.kept, removed: result.removed)
    }

    // Numeric wire structure only, for diagnosing a new response layout.
    // Never includes field values, IDs, titles, URLs or raw response bytes.
    static func schemaSummary(_ data: Data) -> String {
        guard data.count <= 4 * 1024 * 1024, let root = parse(data) else { return "unparsed" }
        func summary(_ fields: [Field]) -> String {
            fields.prefix(12).map { "\($0.number)/\($0.wire)" }.joined(separator: ",")
        }
        var output = "root=[\(summary(root))]"
        var bytes = data
        var fields = root
        for level in 1...2 {
            guard let range = fields.first(where: { $0.number == 1 })?.payload else { break }
            bytes = bytes.subdata(in: range)
            guard let child = parse(bytes) else { break }
            output += " child\(level)=[\(summary(child))]"
            fields = child
        }
        return output
    }

    private static func filterSections(_ data: Data, fields: [Field]) -> Result? {
        let sections = fields.filter { $0.number == 1 }
        guard !sections.isEmpty else { return nil }
        var remove = Set<Int>()
        var kept = 0
        for section in sections {
            guard let payload = section.payload,
                  let kind = sectionKind(data.subdata(in: payload)) else { return nil }
            if kind == 2 { kept += 1 } else { remove.insert(section.range.lowerBound) }
        }
        var result = Data()
        for field in fields where !remove.contains(field.range.lowerBound) {
            result.append(data.subdata(in: field.range))
        }
        return Result(data: result, kept: kept, removed: remove.count)
    }

    private static func sectionKind(_ data: Data) -> UInt64? {
        guard let fields = parse(data), fields.allSatisfy({ $0.payload != nil }) else { return nil }
        let info = fields.filter { $0.number == 1 }
        let features = fields.filter { (2...45).contains($0.number) }
        // Future/ambiguous feature layouts stay intact rather than deleting data.
        guard info.count == 1, features.count == 1,
              fields.allSatisfy({ $0.number <= 45 }),
              let infoRange = info.first?.payload,
              let metadata = parse(data.subdata(in: infoRange)),
              let id = metadata.first(where: { $0.number == 1 }), let idRange = id.payload else { return nil }
        let infoData = data.subdata(in: infoRange)
        guard let name = String(data: infoData.subdata(in: idRange), encoding: .utf8),
              !name.isEmpty, name.utf8.count <= 1024,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              let featureRange = features[0].payload,
              parse(data.subdata(in: featureRange)) != nil else { return nil }
        return features[0].number
    }

    private struct Field {
        let number: UInt64
        let wire: UInt64
        let range: Range<Int>
        let payload: Range<Int>?
        let lengthBytes: Int
    }

    private static func parse(_ data: Data) -> [Field]? {
        var cursor = 0
        var fields = [Field]()
        while cursor < data.count {
            guard fields.count < 4096 else { return nil }
            let start = cursor
            guard let tag = readVarint(data, cursor: &cursor), tag >> 3 > 0,
                  tag >> 3 <= 0x1fffffff else { return nil }
            var payload: Range<Int>?
            var lengthBytes = 0
            switch tag & 7 {
            case 0:
                guard readVarint(data, cursor: &cursor) != nil else { return nil }
            case 1:
                guard data.count - cursor >= 8 else { return nil }
                cursor += 8
            case 2:
                let lengthStart = cursor
                guard let length = readVarint(data, cursor: &cursor), length <= UInt64(data.count - cursor) else { return nil }
                lengthBytes = cursor - lengthStart
                payload = cursor..<cursor + Int(length)
                cursor += Int(length)
            case 5:
                guard data.count - cursor >= 4 else { return nil }
                cursor += 4
            default: return nil
            }
            fields.append(Field(number: tag >> 3, wire: tag & 7, range: start..<cursor, payload: payload, lengthBytes: lengthBytes))
        }
        return fields
    }

    private static func readVarint(_ data: Data, cursor: inout Int) -> UInt64? {
        var value: UInt64 = 0
        for byte in 0..<10 {
            guard cursor < data.count else { return nil }
            let next = data[cursor]
            cursor += 1
            if byte == 9, next > 1 { return nil }
            value |= UInt64(next & 0x7f) << (7 * byte)
            if next & 0x80 == 0 { return value }
        }
        return nil
    }

    private static func varint(_ input: UInt64) -> Data {
        var number = input
        var bytes = Data()
        while number >= 0x80 {
            bytes.append(UInt8(number & 0x7f) | 0x80)
            number >>= 7
        }
        bytes.append(UInt8(number))
        return bytes
    }
}
