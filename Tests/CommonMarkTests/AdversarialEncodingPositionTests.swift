/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Adversarial Unicode encoding source positions")
struct AdversarialEncodingPositionTests {

    private typealias Pos = MarkdownNode.SourcePosition
    private typealias Entry = (kind: MarkdownNode.Kind, range: Range<Pos>?)

    private static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func collect(_ src: String) -> [Entry] {
        MarkdownDocument.withParsedDocument(src, options: Self.opts) { doc in
            var out: [Entry] = []
            dfsRanges(doc.root, into: &out)
            return out
        }
    }

    private func firstRange(_ ranges: [Entry], _ predicate: (MarkdownNode.Kind) -> Bool) -> Range<Pos>? {
        for entry in ranges where predicate(entry.kind) { return entry.range }
        return nil
    }

    private func hasKind(_ ranges: [Entry], _ predicate: (MarkdownNode.Kind) -> Bool) -> Bool {
        ranges.contains { predicate($0.kind) }
    }

    private func textRanges(_ ranges: [Entry]) -> [Range<Pos>?] {
        ranges.filter { $0.kind == .text }.map { $0.range }
    }

    private func isHeading(_ k: MarkdownNode.Kind) -> Bool { if case .heading = k { return true } else { return false } }
    private func isList(_ k: MarkdownNode.Kind) -> Bool { if case .list = k { return true } else { return false } }
    private func isItem(_ k: MarkdownNode.Kind) -> Bool { if case .item = k { return true } else { return false } }

    @Test("ZWJ-family grapheme in text advances the column by its 18 bytes")
    func zwjFamilyInText() throws {
        let ranges = collect("x\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}y")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 21))
    }

    @Test("regional-indicator flag grapheme in text advances by its 8 bytes")
    func flagInText() throws {
        let ranges = collect("x\u{1F1FA}\u{1F1F8}y")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 11))
    }

    @Test("skin-tone-modified grapheme in text advances by its 8 bytes")
    func skinToneInText() throws {
        let ranges = collect("x\u{1F44D}\u{1F3FD}y")
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 11))
    }

    @Test("ZWJ-family grapheme immediately before an emphasis run")
    func zwjFamilyBeforeEmphasis() throws {
        let ranges = collect("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}*x*")
        let texts = textRanges(ranges)
        try #require(texts.count == 2, "expected the leading text and the emphasized text")
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 19))
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 19)..<Pos(line: 1, column: 22))
        #expect(texts[1] == Pos(line: 1, column: 20)..<Pos(line: 1, column: 21))
    }

    @Test("ZWJ-family grapheme in an ATX heading")
    func zwjFamilyInHeading() throws {
        let ranges = collect("# \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} z")
        let heading = try #require(firstRange(ranges, isHeading))
        #expect(heading == Pos(line: 1, column: 1)..<Pos(line: 1, column: 23))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 23))
    }

    @Test("regional-indicator flag grapheme in a list item")
    func flagInListItem() throws {
        let ranges = collect("- \u{1F1FA}\u{1F1F8} z")
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
        let ranges = collect("| \u{1F44D}\u{1F3FD} | b |\n| - | - |\n| c | d |")
        let table = try #require(firstRange(ranges) { $0 == .table })
        #expect(table == Pos(line: 1, column: 1)..<Pos(line: 3, column: 10))
        let texts = textRanges(ranges)
        try #require(texts.count == 4, "expected the four cell texts 👍🏽, b, c, d")
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 11))
    }

    @Test("a multibyte char just before a line ending does not shift the next line's column 1")
    func multibyteBeforeLineEndingResetsColumn() throws {
        let ranges = collect("a\u{20AC}\nbb")
        let texts = textRanges(ranges)
        try #require(texts.count == 2, "expected a text on each line, split by a soft line break")
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 5))
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 3))
    }

    @Test("a CRLF line ending after a multibyte char resets the next line's column")
    func crlfWithMultibyte() throws {
        let ranges = collect("a\u{20AC}\r\nbb")
        let texts = textRanges(ranges)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 5))
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 3))
    }

    @Test("a paragraph ending in a multibyte char ends just past its last byte")
    func multibyteAsLastCharOfParagraph() throws {
        let ranges = collect("ab\u{20AC}")
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
    }

    @Test("multibyte char immediately before an emphasis opener")
    func multibyteBeforeEmphasisDelimiter() throws {
        let ranges = collect("\u{20AC}*x*")
        let texts = textRanges(ranges)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 4)..<Pos(line: 1, column: 7))
        #expect(texts[1] == Pos(line: 1, column: 5)..<Pos(line: 1, column: 6))
    }

    @Test("emphasis wrapping a single multibyte char")
    func emphasisWrappingMultibyte() throws {
        let ranges = collect("*\u{20AC}*")
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 2)..<Pos(line: 1, column: 5))
    }

    @Test("'#' followed by a multibyte char (no space) is NOT a heading")
    func atxHashFollowedByMultibyteIsNotHeading() throws {
        let ranges = collect("#\u{E9}")
        #expect(!hasKind(ranges, isHeading))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
    }

    @Test("block-quote marker immediately followed by a multibyte char")
    func blockQuoteMarkerFollowedByMultibyte() throws {
        // A block-quote marker's following space is optional (Block quotes), unlike an ATX heading's or a list marker's.
        let ranges = collect(">\u{E9}")
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
        let ranges = collect("-\u{E9}")
        #expect(!hasKind(ranges, isList))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 4))
    }

    @Test("emoji inside link text")
    func linkTextEmoji() throws {
        let ranges = collect("[\u{1F600}](/u)")
        let link = try #require(firstRange(ranges) { $0 == .link })
        #expect(link == Pos(line: 1, column: 1)..<Pos(line: 1, column: 11))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 2)..<Pos(line: 1, column: 6))
    }

    @Test("a run of three 3-byte chars before an emphasis run")
    func denseMultibyteRunBeforeEmphasis() throws {
        let ranges = collect("\u{20AC}\u{20AC}\u{20AC}*x*")
        let texts = textRanges(ranges)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 10))
        let emphasis = try #require(firstRange(ranges) { $0 == .emphasis })
        #expect(emphasis == Pos(line: 1, column: 10)..<Pos(line: 1, column: 13))
        #expect(texts[1] == Pos(line: 1, column: 11)..<Pos(line: 1, column: 12))
    }

    @Test("mixed 2-, 3-, and 4-byte chars on one line")
    func mixedTwoThreeFourByteChars() throws {
        let ranges = collect("\u{E9}\u{20AC}\u{1F44D}")
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 1)..<Pos(line: 1, column: 10))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 10))
    }

    @Test("stacked combining marks count each mark's bytes")
    func stackedCombiningMarks() throws {
        let ranges = collect("e\u{301}\u{302}")
        let para = try #require(firstRange(ranges) { $0 == .paragraph })
        #expect(para == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
        let texts = textRanges(ranges)
        try #require(texts.count == 1)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 6))
    }
}
