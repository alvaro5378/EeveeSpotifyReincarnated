# Home response schema evidence

The field relationships were checked against the user's Spotify 9.2.0
(920002054) arm64 executable, UUID B49E7578-1D86-35D3-8BB5-7DAF68FED8A8.
They are not inferred from recommendation titles or raw substring searches.

| Message | Relevant fields |
| --- | --- |
| `ResolvedHome` | `structure` = 1; other response fields retained verbatim |
| `HomeStructure` | repeated `Section` = 1 |
| `Section` | `sectionInfo` = 1; `shortcuts` = 2; `anchors` = 7; feature fields through 45 |
| `SectionInfo` | `sectionID` string |
| `ImageLink` | `heading` = 1; `itemSource` = 2 |
| `Heading` | empty = 1; text = 2; enriched = 3; sponsored = 4; description = 5; static enriched = 6 |
| `GetSlotContentResponse` | repeated `Section`, plus slot type/response metadata |

Swift field reflection and `SwiftProtobuf.Message` conformance witnesses identify
the message and oneof types. The HomeStructure decoder at 0x102D95414 accepts
field 1 as repeated Section. ResolvedHome's traversal helper at 0x1075F866C
visits HomeStructure as field 1. Section's decoder at 0x103607654 dispatches
field 1 to SectionInfo. Its traversal table at 0x10ACB0C9C dispatches the
shortcuts enum case to 0x108365A00, which visits Shortcuts as field 2. The
anchors enum case dispatches to 0x10997AC44, which visits Anchors as field 7.
Both belong to the Home_AnchorsAndShortcutsKit quick-access surface.

ImageLink is Section feature 3 (visitor helper 0x108319B78). ImageLink's
heading helper at 0x107000A30 visits Heading as field 1, while 0x109892310
visits ItemSource as field 2. The Heading traversal at 0x109498188 switches
between the six variants above. TextHeading's traversal uses string field 1
for its text (0x1080862B4 / outlined visitor helper 0x10A0F088C).

## Selective policy (revision 5)

Revision 4 was stable on-device but removed too much: the user wants personal
mixes and related recommendations. The current policy retains **every section
by default**, removing only recognized ImageLink headings that match the user's
editable list, or an explicit sponsored heading. It does not infer unwanted
content from weekdays, genre words inside mix names, section IDs, card titles,
or arbitrary strings in the response. Personal and unlisted shelves remain
byte-identical. Unknown sections are preserved individually.

The initial list comes from the earlier desktop cleanup and the user's
clarification: Popular radio, Recommended stations, Today's biggest/top hits,
New Music Friday, Iconic VMA performances, and exact generic Happy/Instrumental
headings. Happy Mix and Instrumental Mix remain visible. Fresh new music is
not blocked by default because it may include Release Radar; filtering that
mixed shelf's individual cards is not implemented.

The existing stored enable flag now enables only this selective policy. There
is no blanket-delete mode in revision 5. New list preferences are separate.
The existing ad pass remains composed after a targeted rewrite when it was
already enabled; removing one generic shelf cannot bypass that pass.

The new option transforms these messages before they enter the UI. It does
not activate the old broad cell-collapse, frame-maintenance or layout hooks.
It accepts both wrapped Home and direct Section-list responses. Quick-access
entries, other music shelves and non-section metadata retain their exact bytes.
Invalid root lengths leave the response unchanged; ambiguous sections, unknown
headings and future feature fields are individually preserved.

These fixtures are generated examples based on the client's schema, **not
captured live Home responses**. CI checks the parser, routing, buffering,
error/304/no-body behavior and existing regression suites. Actual iPhone
testing is still needed to establish endpoint coverage and runtime behavior.

Reference formats: [Swift reflection records](https://github.com/swiftlang/swift/blob/main/include/swift/RemoteInspection/Records.h),
[SwiftProtobuf Message requirements](https://github.com/apple/swift-protobuf/blob/1.29.0/Sources/SwiftProtobuf/Message.swift).
