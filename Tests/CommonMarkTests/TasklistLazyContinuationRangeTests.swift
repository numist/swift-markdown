/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A paragraph continuation line in a task list item has a source range that starts at the line's first
/// content byte, whatever the width of the checkbox on the opening line.
@Suite("Task list item continuation line source ranges")
struct TasklistLazyContinuationRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let options: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition]

    private func ranges(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
    }

    /// The first list item's `checked` state (`.some(nil)` for an item without a checkbox), or `nil` if
    /// there is no list item.
    private func itemChecked(
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Bool?? {
        for entry in ranges {
            if case .item(let checked) = entry.kind {
                return checked
            }
        }
        return nil
    }

    private func texts(
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> [Range<Pos>?] {
        ranges.filter { $0.kind == .text }.map { $0.range }
    }

    @Test("an unchecked task list item's lazy continuation line starts at column 1")
    func uncheckedLazyContinuationColumn() throws {
        let ranges = ranges(in: "- [ ] x\ny", options: Self.options)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x" content after checkbox
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))

        // A ten-byte line starts at the same column.
        let longRanges = self.ranges(in: "- [ ] x\nyyyyyyyyyy", options: Self.options)
        try #require(itemChecked(in: longRanges) == .some(.some(false)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[0]?.lowerBound == Pos(line: 1, column: 7))
        #expect(longTexts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 11))
    }

    @Test("a checked task list item's lazy continuation line starts at column 1")
    func checkedLazyContinuationColumn() throws {
        let ranges = ranges(in: "- [x] x\ny", options: Self.options)
        try #require(itemChecked(in: ranges) == .some(.some(true)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x" content after checkbox
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))

        // A ten-byte line starts at the same column.
        let longRanges = self.ranges(in: "- [x] x\nyyyyyyyyyy", options: Self.options)
        try #require(itemChecked(in: longRanges) == .some(.some(true)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[0]?.lowerBound == Pos(line: 1, column: 7))
        #expect(longTexts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 11))
    }

    @Test("a one-space-indented continuation line starts after the space")
    func oneSpaceContinuationColumn() throws {
        let ranges = ranges(in: "- [ ] x\n y", options: Self.options)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 2))   // "y" after the space
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 3))

        // A ten-byte line starts at the same column.
        let longRanges = self.ranges(in: "- [ ] x\n yyyyyyyyyy", options: Self.options)
        try #require(itemChecked(in: longRanges) == .some(.some(false)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 2))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 12))
    }

    @Test("a four-space-indented continuation line starts after the spaces")
    func fourSpaceContinuationColumn() throws {
        let ranges = ranges(in: "- [ ] x\n    y", options: Self.options)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 5))   // "y" after the spaces
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 6))

        // A ten-byte line starts at the same column.
        let longRanges = self.ranges(in: "- [ ] x\n    yyyyyyyyyy", options: Self.options)
        try #require(itemChecked(in: longRanges) == .some(.some(false)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 5))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 15))
    }

    @Test("a list item without a checkbox has the same continuation line range")
    func plainBulletContinuationColumn() throws {
        let ranges = ranges(in: "- x\ny", options: Self.options)
        try #require(itemChecked(in: ranges) == .some(Bool?.none))   // no checkbox
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y"
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))

        // A ten-byte line starts at the same column.
        let longRanges = self.ranges(in: "- x\nyyyyyyyyyy", options: Self.options)
        try #require(itemChecked(in: longRanges) == .some(Bool?.none))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 11))
    }
}
