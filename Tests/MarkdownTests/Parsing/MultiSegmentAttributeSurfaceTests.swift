/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) import Markdown
import Testing

/// Coverage for the `^[…](attrs)` extended-attribute inline form scanned over multi-segment content,
/// exercised through the exact comparison surface the differential fuzzer uses
/// (`Document.debugDescription(options: .printSourceLocations)` with `.cmarkBugCompatibility`).
///
/// A block-quote / list body whose `(attrs)` spans lines is parsed as multi-segment content: the
/// interior straddles the interned-newline segment joining the two source lines. cmark reads its
/// flattened paragraph buffer, so the interior newline is ordinary attribute content and the form
/// resolves to an `InlineAttributes` node whose attribute string carries that newline
/// (`manual_scan_attribute_attributes`, swift-cmark `src/inlines.c`). The scanner materializes the
/// straddling interior into the arena (the code-span / tab-expansion pattern) to reproduce it - the
/// attribute forms, matching the reference, without indexing the wrong buffer or running past a segment.
@Suite("Multi-segment attribute surface")
struct MultiSegmentAttributeSurfaceTests {

    private static func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.cmarkBugCompatibility])
            .debugDescription(options: .printSourceLocations)
    }

    @Test(arguments: [
        ("> ^[a](\n> b)", "\nb"),
        ("> ^[hi](\n> x)", "\nx"),
        ("- ^[a](\n  b)", "\nb"),
        (">^[a](b\n>c)", "b\nc"),
    ])
    func crossLineAttributeForms(_ markdown: String, _ expectedAttributes: String) {
        let rendered = Self.surface(markdown)
        #expect(!rendered.isEmpty)
        // The `(attrs)` interior spans the line join; the form still resolves to an attribute whose
        // string carries the interior newline (reading it forces the arena materialization).
        #expect(rendered.contains("InlineAttributes"))
        #expect(rendered.contains("attributes: `\(expectedAttributes)`"))
    }
}
