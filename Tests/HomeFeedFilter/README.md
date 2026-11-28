# Home response schema evidence

The field relationships were checked against the user's Spotify 9.2.0
(920002054) arm64 executable, UUID B49E7578-1D86-35D3-8BB5-7DAF68FED8A8.
They are not inferred from recommendation titles or raw substring searches.

| Message | Relevant fields |
| --- | --- |
| `ResolvedHome` | `structure` = 1; other response fields retained verbatim |
| `HomeStructure` | repeated `Section` = 1 |
| `Section` | `sectionInfo` = 1; `shortcuts` feature = 2; other known feature fields through 45 |
| `SectionInfo` | `sectionID` string |
| `GetSlotContentResponse` | repeated `Section`, plus slot type/response metadata |

Swift field reflection and `SwiftProtobuf.Message` conformance witnesses identify
the message and oneof types. The HomeStructure decoder at 0x102D95414 accepts
field 1 as repeated Section. ResolvedHome's traversal helper at 0x1075F866C
visits HomeStructure as field 1. Section's decoder at 0x103607654 dispatches
field 1 to SectionInfo. Its traversal table at 0x10ACB0C9C dispatches the
shortcuts enum case to 0x108365A00, which visits Shortcuts as field 2.

The new option transforms these messages before they enter the UI. It does
not activate the old broad cell-collapse, frame-maintenance or layout hooks.
It accepts both wrapped Home and direct Section-list responses, including
recommendation-only pages. Shortcut entries and non-section metadata retain
their exact bytes. Invalid lengths, ambiguous feature oneofs, unrecognized
schemas and future feature fields cause an unchanged response.

These fixtures are generated examples based on the client's schema, **not
captured live Home responses**. CI checks the parser, routing, buffering,
error/304/no-body behavior and existing regression suites. Actual iPhone
testing is still needed to establish endpoint coverage and runtime behavior.

Reference formats: [Swift reflection records](https://github.com/swiftlang/swift/blob/main/include/swift/RemoteInspection/Records.h),
[SwiftProtobuf Message requirements](https://github.com/apple/swift-protobuf/blob/1.29.0/Sources/SwiftProtobuf/Message.swift).
