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

    /// A trailing `[label]` following an `^[](attrs)` attribute is consumed by cmark's `link_label`,
    /// which scans a flat buffer and does not rewind on a match — so the bracket pair produces no output.
    /// When the content is multi-segment (here a block-quote body, whose stripped `>` prefixes leave the
    /// lines non-contiguous) the trailing label can straddle a soft-break join, landing the closing `]` in
    /// a later segment that a contiguous-only scan never reaches — the scan must still cross the join and
    /// consume the pair. Consumption is unconditional, so both flag modes must agree.
    @Test(arguments: [ParseOptions(), ParseOptions.cmarkBugCompatibility])
    func trailingBracketAfterAttributeConsumed(_ options: ParseOptions) {
        // Single-line control: contiguous content, the trailing `[y]` is consumed.
        #expect(Document(parsing: "^[](x)[y]", options: options).debugDescription() == """
            Document
            └─ Paragraph
               └─ InlineAttributes attributes: `x`
            """)
        // Multi-segment: the trailing `[\nc]` straddles the block-quote line join, so the closing `]` sits
        // in a later segment; the pair must still be consumed, leaving no literal `[` / `]` text.
        #expect(Document(parsing: ">a^[](x)[\n>c]", options: options).debugDescription() == """
            Document
            └─ BlockQuote
               └─ Paragraph
                  ├─ Text "a"
                  └─ InlineAttributes attributes: `x`
            """)
        // Multi-segment reference form: the join-straddling label `[a\nb]` normalizes to `a b`, resolves
        // against the `^[a b]:` attribute reference, and overwrites the inline `(ignore)` attributes —
        // cmark's `link_label` crosses the join to match the definition (`handle_close_bracket_attribute`).
        #expect(Document(parsing: "^[a b]: color: red\n\n>x^[](ignore)[a\n>b]", options: options).debugDescription() == """
            Document
            └─ BlockQuote
               └─ Paragraph
                  ├─ Text "x"
                  └─ InlineAttributes attributes: `color: red`
            """)
    }
}
