/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// cmark-gfm scans an inline CDATA section with the grammar in `scanners.re`
/// (`cdata = "CDATA[" ([^\]\x00]+ | "]" [^\]\x00] | "]]" [^>\x00])*`, via `_scan_html_cdata`), then in
/// `inlines.c` `handle_pointy_brace` ASSUMES a `]]>` closer follows the matched content without verifying
/// it, rejecting only when that assumed closer overruns the buffer. This is narrower than CommonMark 0.31
/// "`<![CDATA[`, then a string not containing `]]>`, then `]]>`". They disagree when the content ends in a
/// lone `]` right before the closer (`<![CDATA[]]]>`, `<![CDATA[x]]]>`): 0.31 reads the content up to the
/// first `]]>`, so the deliverable recognizes inline HTML; cmark's `"]]" [^>\x00]` token absorbs the `]]` +
/// the extra `]` (and then the `>`) as content, pushing the assumed closer past end-of-input, so it rejects
/// the section and the `<` stays literal text.
///
/// The shipped deliverable (flag OFF) stays spec-correct (0.31). These tests parse without
/// `.sourcePosition`.
@Suite("Inline CDATA cmark trailing-bracket quirk")
struct HTMLCDATATrailingBracketQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []

    /// Parse `src` and return the first `.htmlInline` literal (or nil if none) plus the concatenated
    /// `.text` literals of the first paragraph. The leading `o` in every fixture must survive as text, so a
    /// degenerate (empty) tree fails the sanity `#require` instead of passing vacuously.
    private func parse(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> (html: String?, text: String) {
        let inlines: [(kind: MarkdownNode.Kind, literal: String?)] =
            MarkdownDocument.withParsedDocument(src, options: options) { doc in
                paragraphInlines(doc)
            }
        let text = inlines.filter { $0.kind == .text }.compactMap(\.literal).joined()
        try #require(text.contains("o"), "fixture vacuous: leading text 'o' not parsed")
        let html = inlines.first { $0.kind == .htmlInline }.flatMap(\.literal)
        return (html, text)
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (CommonMark 0.31)

    @Test("flag OFF: `<![CDATA[]]]>` (empty content + trailing `]`) IS inline HTML")
    func flagOffEmptyTrailingBracketRecognized() throws {
        #expect(try parse("o<![CDATA[]]]>", options: Self.flagOff).html == "<![CDATA[]]]>")
    }

    @Test("flag OFF: `<![CDATA[x]]]>` (content ending in `]`) IS inline HTML")
    func flagOffContentTrailingBracketRecognized() throws {
        #expect(try parse("o<![CDATA[x]]]>", options: Self.flagOff).html == "<![CDATA[x]]]>")
    }

    // MARK: Agreeing controls

    @Test("both flags: `<![CDATA[xx]]>` (normal) is inline HTML")
    func normalCDATARecognized() throws {
        #expect(try parse("o<![CDATA[xx]]>", options: Self.flagOff).html == "<![CDATA[xx]]>")
    }

    @Test("both flags: `<![CDATA[]]>` (empty content) is inline HTML")
    func emptyCDATARecognized() throws {
        #expect(try parse("o<![CDATA[]]>", options: Self.flagOff).html == "<![CDATA[]]>")
    }
}
