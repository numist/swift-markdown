/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Adversarial Unicode-encoding source-position coverage for the DELIVERABLE (flag-OFF).
//
// Source columns are 1-based UTF-8 BYTE offsets into the original source, and a node's
// `sourceRange.upperBound` is the offset just PAST the node's last byte (half-open). Every
// asserted position was taken from the deliverable oracle
//   dump --new-off <bytes + 0x00 options byte>
// which parses with exactly this suite's option set (see `opts`) and no `.cmarkBugCompatibility`.
// Every case here also equals `dump --ref` (cmark-gfm): the byte accounting for multi-codepoint
// graphemes, combining marks, and U+FFFD repair matches the reference on all of them, so there are
// no `// cmark differs:` sites in this suite.
//
// `dfsRanges` (file-scope, defined in SourcePositionTests.swift) is reused for the DFS collection.

@Suite("Adversarial Unicode encoding source positions")
struct AdversarialEncodingPositionTests {

    private typealias Pos = MarkdownNode.SourcePosition
    private typealias Entry = (kind: MarkdownNode.Kind, range: Range<Pos>?)

    /// The deliverable option set. Identical to what `dump --new-off` applies for a `0x00` options
    /// byte (`MarkupParser` always enables tables/strikethrough/tasklist/tableSpans + source
    /// positions, and smart punctuation unless disabled) and deliberately WITHOUT
    /// `.cmarkBugCompatibility`, so these positions are the shipped, spec-correct behavior.
    private static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    // MARK: - Helpers

    /// Parse `src` with the deliverable options and DFS-collect every node's kind and source range.
    private func collect(_ src: String) throws -> [Entry] {
        try MarkdownDocument.withParsedDocument(src, options: Self.opts) { doc in
            var out: [Entry] = []
            dfsRanges(doc.root, into: &out)
            return out
        }
    }

    /// The range of the first node (DFS order) whose kind satisfies `predicate`.
    private func firstRange(_ ranges: [Entry], _ predicate: (MarkdownNode.Kind) -> Bool) -> Range<Pos>? {
        for entry in ranges where predicate(entry.kind) { return entry.range }
        return nil
    }

    /// Whether any node's kind satisfies `predicate`.
    private func hasKind(_ ranges: [Entry], _ predicate: (MarkdownNode.Kind) -> Bool) -> Bool {
        ranges.contains { predicate($0.kind) }
    }

    /// Every `.text` node's range, in DFS order.
    private func textRanges(_ ranges: [Entry]) -> [Range<Pos>?] {
        ranges.filter { $0.kind == .text }.map { $0.range }
    }

    /// The UTF-8 repair the harness (`splitInput`) and `dump` apply to raw bytes: invalid sequences
    /// become U+FFFD. Parsing the result exercises the same repair -> position path as the fuzzer.
    private func repaired(_ raw: [UInt8]) -> String {
        String(decoding: raw, as: UTF8.self)
    }

    private func isHeading(_ k: MarkdownNode.Kind) -> Bool { if case .heading = k { return true } else { return false } }
    private func isList(_ k: MarkdownNode.Kind) -> Bool { if case .list = k { return true } else { return false } }
    private func isItem(_ k: MarkdownNode.Kind) -> Bool { if case .item = k { return true } else { return false } }

    // MARK: - A. Grapheme clusters (multi-codepoint glyphs)
    //
    // A grapheme cluster is one user-perceived glyph built from several code points; each code point
    // is 1..4 UTF-8 bytes. The column must advance by the TOTAL byte count, not 1 per glyph or 1 per
    // code point.
    //   ZWJ family "👨‍👩‍👧" = U+1F468(4) U+200D(3) U+1F469(4) U+200D(3) U+1F467(4) = 18 bytes
    //   flag       "🇺🇸"   = U+1F1FA(4) U+1F1F8(4)                                     = 8 bytes
    //   skin tone  "👍🏽"   = U+1F44D(4) U+1F3FD(4)                                     = 8 bytes

    @Test("ZWJ-family grapheme in text advances the column by its 18 bytes")
    func zwjFamilyInText() throws {
        // "x" + family(18) + "y" = 20 bytes -> text spans 1:1..1:21.
        let ranges = try collect("x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}y")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 21))
    }

    @Test("regional-indicator flag grapheme in text advances by its 8 bytes")
    func flagInText() throws {
        // "x" + flag(8) + "y" = 10 bytes.
        let ranges = try collect("x\u{1F1FA}\u{1F1F8}y")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 11))
    }

    @Test("skin-tone-modified grapheme in text advances by its 8 bytes")
    func skinToneInText() throws {
        // "x" + 👍🏽(8) + "y" = 10 bytes.
        let ranges = try collect("x\u{1F44D}\u{1F3FD}y")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 11))
    }

    @Test("ZWJ-family grapheme immediately before an emphasis run")
    func zwjFamilyBeforeEmphasis() throws {
        // family(18) then "*x*". Leading text ends at col 19; the emphasis opener '*' is byte 19.
        let ranges = try collect("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}*x*")
        let texts = textRanges(ranges)
        try #require(texts.count == 2, "expected the leading text and the emphasized text")
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 19))   // family
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 19)..<Pos(line: 1, column: 22))
        #expect(texts[1] == Pos(line: 1, column: 20)..<Pos(line: 1, column: 21))  // "x"
    }

    @Test("ZWJ-family grapheme in an ATX heading")
    func zwjFamilyInHeading() throws {
        // "# " (content starts at byte 3) + family(18) + " z" -> text 3..23, heading 1..23.
        let ranges = try collect("# \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} z")
        let heading = try #require(firstRange(ranges, isHeading))
        #expect(heading == Pos(line: 1, column: 1)..<Pos(line: 1, column: 23))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 23))
    }

    @Test("regional-indicator flag grapheme in a list item")
    func flagInListItem() throws {
        // "- " (content starts at byte 3) + flag(8) + " z".
        let ranges = try collect("- \u{1F1FA}\u{1F1F8} z")
        let list = try #require(firstRange(ranges, isList))
        #expect(list == Pos(line: 1, column: 1)..<Pos(line: 1, column: 13))
        let item = try #require(firstRange(ranges, isItem))
        #expect(item == Pos(line: 1, column: 1)..<Pos(line: 1, column: 13))
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 3)..<Pos(line: 1, column: 13))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 13))
    }

    @Test("skin-tone grapheme in a GFM table cell")
    func skinToneInTableCell() throws {
        // Header line "| 👍🏽 | b |": '|'(1) ' '(2) 👍🏽(3..10, 8 bytes) ' '(11) '|'(12) ...
        // The first cell's text spans 1:3..1:11.
        let ranges = try collect("| \u{1F44D}\u{1F3FD} | b |\n| - | - |\n| c | d |")
        let table = try #require(firstRange(ranges) { $0 == .table })
        #expect(table == Pos(line: 1, column: 1)..<Pos(line: 3, column: 10))
        let texts = textRanges(ranges)
        try #require(texts.count == 4, "expected the four cell texts 👍🏽, b, c, d")
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 11))   // 👍🏽
    }

    // MARK: - B. Multibyte characters at line boundaries
    //
    // A newline resets the column to 1 on the next line; the byte count of a trailing multibyte
    // character must not leak across the boundary. "€" = U+20AC = 3 bytes.

    @Test("a multibyte char just before a newline does not shift the next line's column 1")
    func multibyteBeforeNewlineResetsColumn() throws {
        // "a€" -> 'a'(1) '€'(2..4), 4 bytes, text 1:1..1:5. Next line "bb" resets to col 1.
        let ranges = try collect("a\u{20AC}\nbb")
        let texts = textRanges(ranges)
        try #require(texts.count == 2, "expected a text on each line, split by a soft break")
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 5))
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 3))
    }

    @Test("CRLF after a multibyte char resets the next line's column and drops the CR")
    func crlfWithMultibyte() throws {
        // "a€\r\nbb": the CR is consumed with the LF; line 2 starts at col 1, identical to the LF case.
        let ranges = try collect("a\u{20AC}\r\nbb")
        let texts = textRanges(ranges)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 5))
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 3))
    }

    @Test("a multibyte char as the last char of a paragraph ends at the past-the-bytes column")
    func multibyteAsLastCharOfParagraph() throws {
        // "ab€" -> 'a'(1) 'b'(2) '€'(3..5), 5 bytes -> 1:1..1:6.
        let ranges = try collect("ab\u{20AC}")
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
    }

    // MARK: - C. Multibyte characters adjacent to markers / delimiters

    @Test("multibyte char immediately before an emphasis opener")
    func multibyteBeforeEmphasisDelimiter() throws {
        // "€*x*": '€'(1..3) text 1:1..1:4; opener '*' is byte 4.
        let ranges = try collect("\u{20AC}*x*")
        let texts = textRanges(ranges)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 4)..<Pos(line: 1, column: 7))
        #expect(texts[1] == Pos(line: 1, column: 5)..<Pos(line: 1, column: 6))
    }

    @Test("emphasis wrapping a single multibyte char")
    func emphasisWrappingMultibyte() throws {
        // "*€*": '*'(1) '€'(2..4) '*'(5), 5 bytes. Emphasis 1:1..1:6, inner text 1:2..1:5.
        let ranges = try collect("*\u{20AC}*")
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 2)..<Pos(line: 1, column: 5))
    }

    @Test("'#' followed by a multibyte char (no space) is NOT a heading")
    func atxHashFollowedByMultibyteIsNotHeading() throws {
        // An ATX opener requires a space/tab/EOL after the '#'. "#é" has 'é' after '#', so it stays a
        // paragraph. 'é' = U+00E9 = 2 bytes; "#é" is 3 bytes -> text 1:1..1:4.
        let ranges = try collect("#\u{E9}")
        #expect(!hasKind(ranges, isHeading), "‘#’ + non-space must not open a heading")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
    }

    @Test("block-quote marker immediately followed by a multibyte char")
    func blockQuoteMarkerFollowedByMultibyte() throws {
        // ">é": '>' opens the quote at col 1 (no space required); 'é'(2..3). BlockQuote 1:1..1:4,
        // inner paragraph/text 1:2..1:4.
        let ranges = try collect(">\u{E9}")
        let bq = try #require(firstRange(ranges) { $0 == .blockQuote })
        #expect(bq == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 2)..<Pos(line: 1, column: 4))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 2)..<Pos(line: 1, column: 4))
    }

    @Test("'-' followed by a multibyte char (no space) is NOT a list")
    func bulletMarkerFollowedByMultibyteIsNotList() throws {
        // A bullet marker must be followed by a space/tab/EOL. "-é" has 'é' after '-', so it stays a
        // paragraph. "-é" is 3 bytes -> text 1:1..1:4.
        let ranges = try collect("-\u{E9}")
        #expect(!hasKind(ranges, isList), "‘-’ + non-space must not open a list")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
    }

    @Test("emoji inside a link label")
    func linkLabelEmoji() throws {
        // "[😀](/u)": '['(1) 😀(2..5, 4 bytes) ']'(6) '('(7) '/'(8) 'u'(9) ')'(10), 10 bytes.
        // Link 1:1..1:11, inner text 1:2..1:6.
        let ranges = try collect("[\u{1F600}](/u)")
        let link = try #require(firstRange(ranges) { $0 == .link })
        #expect(link == Pos(line: 1, column: 1)..<Pos(line: 1, column: 11))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 2)..<Pos(line: 1, column: 6))
    }

    // MARK: - D. Consecutive / dense multibyte

    @Test("a run of three 3-byte chars before an emphasis run")
    func denseMultibyteRunBeforeEmphasis() throws {
        // "€€€*x*": 3×€ = 9 bytes, text 1:1..1:10; opener '*' is byte 10.
        let ranges = try collect("\u{20AC}\u{20AC}\u{20AC}*x*")
        let texts = textRanges(ranges)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 10))
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 10)..<Pos(line: 1, column: 13))
        #expect(texts[1] == Pos(line: 1, column: 11)..<Pos(line: 1, column: 12))
    }

    @Test("mixed 2-, 3-, and 4-byte chars on one line")
    func mixedTwoThreeFourByteChars() throws {
        // "é€👍" = 2 + 3 + 4 = 9 bytes -> text/paragraph 1:1..1:10.
        let ranges = try collect("\u{E9}\u{20AC}\u{1F44D}")
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 1)..<Pos(line: 1, column: 10))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 10))
    }

    @Test("stacked combining marks count each mark's bytes")
    func stackedCombiningMarks() throws {
        // "e" + U+0301(2) + U+0302(2) = 5 bytes (one grapheme, three code points) -> text 1:1..1:6.
        let ranges = try collect("e\u{301}\u{302}")
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
    }

    // MARK: - E. Invalid-UTF-8 repair
    //
    // The harness (`splitInput`) and `dump` both decode with `String(decoding:as:UTF8.self)`, which
    // repairs each invalid subsequence to U+FFFD (3 bytes). These tests parse the REPAIRED string —
    // exactly what the parser sees — and pin the 3-byte accounting of U+FFFD. Each `#expect(repaired
    // == …)` confirms the raw bytes normalize to the asserted form; `dump --new-off` on the raw bytes
    // was verified to produce the identical surface to this normalized form (and both equal `--ref`).

    @Test("lone continuation byte 0x80 in text becomes one 3-byte U+FFFD")
    func loneContinuationByteInText() throws {
        // raw "a" 0x80 "b" -> "a\u{FFFD}b": 'a'(1) U+FFFD(2..4) 'b'(5), 5 bytes -> text 1:1..1:6.
        let src = repaired([0x61, 0x80, 0x62])
        #expect(src == "a\u{FFFD}b")
        let ranges = try collect(src)
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
    }

    @Test("truncated 3-byte sequence 0xE2 0x82 in text becomes ONE U+FFFD")
    func truncatedThreeByteSequenceInText() throws {
        // raw "a" 0xE2 0x82 "b": the maximal ill-formed subpart 0xE2 0x82 -> a SINGLE U+FFFD (not two),
        // then 'b'. "a\u{FFFD}b" = 5 bytes -> text 1:1..1:6.
        let src = repaired([0x61, 0xE2, 0x82, 0x62])
        #expect(src == "a\u{FFFD}b")
        let ranges = try collect(src)
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
    }

    @Test("invalid byte 0xFF in text becomes one 3-byte U+FFFD")
    func invalidByteFFInText() throws {
        // raw "a" 0xFF "b" -> "a\u{FFFD}b", 5 bytes -> text 1:1..1:6. (0xFF is never valid in UTF-8.)
        let src = repaired([0x61, 0xFF, 0x62])
        #expect(src == "a\u{FFFD}b")
        let ranges = try collect(src)
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
    }

    @Test("a repaired U+FFFD immediately before an emphasis opener")
    func loneContinuationByteBeforeEmphasis() throws {
        // raw 0x80 "*x*" -> "\u{FFFD}*x*": U+FFFD(1..3) text 1:1..1:4; opener '*' is byte 4.
        let src = repaired([0x80, 0x2A, 0x78, 0x2A])
        #expect(src == "\u{FFFD}*x*")
        let ranges = try collect(src)
        let texts = textRanges(ranges)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 4)..<Pos(line: 1, column: 7))
        #expect(texts[1] == Pos(line: 1, column: 5)..<Pos(line: 1, column: 6))
    }

    @Test("a repaired U+FFFD inside an ATX heading")
    func truncatedSequenceInHeading() throws {
        // raw "# a" 0xE2 0x82 "b" -> "# a\u{FFFD}b": content starts at byte 3; 'a'(3) U+FFFD(4..6) 'b'(7)
        // -> text 1:3..1:8, heading 1:1..1:8.
        let src = repaired([0x23, 0x20, 0x61, 0xE2, 0x82, 0x62])
        #expect(src == "# a\u{FFFD}b")
        let ranges = try collect(src)
        let heading = try #require(firstRange(ranges, isHeading))
        #expect(heading == Pos(line: 1, column: 1)..<Pos(line: 1, column: 8))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 8))
    }

    @Test("a repaired U+FFFD inside a list item")
    func invalidByteFFInListItem() throws {
        // raw "- a" 0xFF "b" -> "- a\u{FFFD}b": content starts at byte 3; text 1:3..1:8.
        let src = repaired([0x2D, 0x20, 0x61, 0xFF, 0x62])
        #expect(src == "- a\u{FFFD}b")
        let ranges = try collect(src)
        let list = try #require(firstRange(ranges, isList))
        #expect(list == Pos(line: 1, column: 1)..<Pos(line: 1, column: 8))
        let item = try #require(firstRange(ranges, isItem))
        #expect(item == Pos(line: 1, column: 1)..<Pos(line: 1, column: 8))
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 3)..<Pos(line: 1, column: 8))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 8))
    }
}
