/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for a paragraph continuation line inside a GFM *task-list* item.
///
/// A task-list item (`- [ ] x` / `- [x] x`) has its checkbox marker (`[ ] ` / `[x] `, four
/// columns) consumed by the tasklist extension *after* the list marker, so the item's paragraph
/// content begins four columns past the plain-bullet content column (at the text after the
/// checkbox). cmark-gfm fixes the paragraph's continuation-line re-indent base (`block_offset`) at
/// that checkbox-adjusted content column, so a lazy continuation line re-bases there - four columns
/// further right than a plain bullet's continuation would.
///
/// The flag-off assertions are the guardrail proving the shipped default keeps TRUE physical columns.
@Suite("Task-list item lazy-continuation source ranges (Quirk E)")
struct TasklistLazyContinuationRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: tasklist + source positions on.
    private static let specOptions: MarkdownDocument.ParseOptions =
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

    /// The task-list item's `checked` state, or `nil` if the item isn't a task item. Fixture-sanity:
    /// a `nil` here means the checkbox was never recognized, so the test would be validating a plain
    /// bullet rather than the task-item re-base it claims to.
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

    @Test("flag-off: task-item continuation keeps its TRUE physical column")
    func flagOffKeepsTrueColumn() throws {
        // The shipped default keeps the continuation at its physical column: `y` at
        // column 1 (@2:1-2:2), spec-correct.
        let ranges = ranges(in: "- [ ] x\ny", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))  // still a task item flag-off
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x" content after checkbox
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y" at its TRUE column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))

        // A ten-byte lazy line keeps its TRUE physical columns too.
        let longRanges = self.ranges(in: "- [ ] x\nyyyyyyyyyy", options: Self.specOptions)
        try #require(itemChecked(in: longRanges) == .some(.some(false)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[0]?.lowerBound == Pos(line: 1, column: 7))
        #expect(longTexts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 11))
    }

    /// The checked task item's continuation keeps its TRUE
    /// physical column @2:1.
    @Test("flag-off: checked task-item continuation keeps its TRUE physical column")
    func flagOffCheckedKeepsTrueColumn() throws {
        let ranges = ranges(in: "- [x] x\ny", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(true)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x" content after checkbox
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y" at its TRUE column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))

        // A ten-byte lazy line keeps its TRUE physical columns too.
        let longRanges = self.ranges(in: "- [x] x\nyyyyyyyyyy", options: Self.specOptions)
        try #require(itemChecked(in: longRanges) == .some(.some(true)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[0]?.lowerBound == Pos(line: 1, column: 7))
        #expect(longTexts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 11))
    }

    /// The one leading space is visible, so `y` keeps its
    /// TRUE physical column @2:2.
    @Test("flag-off: one-space task-item continuation keeps its TRUE physical column")
    func flagOffOneSpaceKeepsTrueColumn() throws {
        let ranges = ranges(in: "- [ ] x\n y", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 2))   // "y" at its TRUE column (leading space visible)
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 3))

        // A ten-byte lazy line keeps its TRUE physical columns too.
        let longRanges = self.ranges(in: "- [ ] x\n yyyyyyyyyy", options: Self.specOptions)
        try #require(itemChecked(in: longRanges) == .some(.some(false)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 2))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 12))
    }

    /// The four leading spaces are visible, so `y` keeps
    /// its TRUE physical column @2:5.
    @Test("flag-off: deeper-indent task-item continuation keeps its TRUE physical column")
    func flagOffDeeperIndentKeepsTrueColumn() throws {
        let ranges = ranges(in: "- [ ] x\n    y", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 5))   // "y" at its TRUE column (four spaces visible)
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 6))

        // A ten-byte lazy line keeps its TRUE physical columns too.
        let longRanges = self.ranges(in: "- [ ] x\n    yyyyyyyyyy", options: Self.specOptions)
        try #require(itemChecked(in: longRanges) == .some(.some(false)))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 5))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 15))
    }

    /// A plain bullet's continuation keeps its
    /// TRUE physical column @2:1.
    @Test("flag-off: plain-bullet continuation keeps its TRUE physical column")
    func flagOffPlainBulletKeepsTrueColumn() throws {
        let ranges = ranges(in: "- x\ny", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(Bool?.none))   // an ordinary (non-task) item
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y" at its TRUE column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))

        // A ten-byte lazy line keeps its TRUE physical columns too.
        let longRanges = self.ranges(in: "- x\nyyyyyyyyyy", options: Self.specOptions)
        try #require(itemChecked(in: longRanges) == .some(Bool?.none))
        let longTexts = self.texts(in: longRanges)
        try #require(longTexts.count == 2)
        #expect(longTexts[1]?.lowerBound == Pos(line: 2, column: 1))
        #expect(longTexts[1]?.upperBound == Pos(line: 2, column: 11))
    }
}
