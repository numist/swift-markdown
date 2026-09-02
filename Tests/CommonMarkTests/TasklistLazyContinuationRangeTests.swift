/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
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
/// This is the Quirk E continuation re-indent (`.cmarkBugCompatibility`, adopted only by the
/// differential fuzzer). The basic/1-space cases mirror the `tasklazy-*` fuzzer oracle pairs; the
/// deeper-indent case is reasoned from cmark's single re-indent rule (every continuation line lands
/// at the fixed content column), validated by the oracle-backed cases here.
/// The flag-off assertions are the guardrail proving the shipped default keeps TRUE physical columns.
@Suite("Task-list item lazy-continuation source ranges (Quirk E)")
struct TasklistLazyContinuationRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// cmark bug-compatibility ON, tasklist enabled - the differential-fuzzer configuration.
    private static let quirkOptions: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition, .cmarkBugCompatibility]

    /// The shipped configuration: tasklist + source positions on, bug-compatibility OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition]

    private func ranges(
        in src: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
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

    @Test("unchecked task item: lazy continuation re-bases to the checkbox-adjusted content column")
    func uncheckedContinuation() throws {
        // "- [ ] x" then "y" (no indent, lazy). The checkbox `[ ] ` (cols 3-6) shifts the paragraph
        // content to column 7, so cmark re-bases the lazy continuation `y` there: @2:7-2:8 (four
        // columns right of a plain bullet's @2:3). Oracle: `tasklazy-unchecked`.
        let ranges = try ranges(in: "- [ ] x\ny", options: Self.quirkOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))  // a task item, unchecked
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 7))   // "y" re-based to content col 7
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 8))
    }

    @Test("checked task item: lazy continuation re-bases to the checkbox-adjusted content column")
    func checkedContinuation() throws {
        // "- [x] x" then "y". `[x] ` is the same four columns as `[ ] `, so `y` re-bases to @2:7-2:8.
        // Oracle: `tasklazy-checked`.
        let ranges = try ranges(in: "- [x] x\ny", options: Self.quirkOptions)
        try #require(itemChecked(in: ranges) == .some(.some(true)))   // a task item, checked
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 7))   // "y" re-based to content col 7
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 8))
    }

    @Test("task item lazy continuation preserves one leading space on top of the checkbox base")
    func oneSpaceContinuation() throws {
        // "- [ ] x" then " y" (one leading space, lazy). cmark keeps a lazy line's residual whitespace,
        // so `y` lands at residual(1) + content col 7 = @2:8-2:9. Oracle: `tasklazy-1sp`.
        let ranges = try ranges(in: "- [ ] x\n y", options: Self.quirkOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 8))   // "y" at residual + col 7
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 9))
    }

    @Test("deeper-indent matched task-item continuation re-bases to the checkbox-adjusted column")
    func deeperIndentContinuation() throws {
        // "- [ ] x" then "    y" (four leading spaces). Indent 4 matches the item, so cmark discards the
        // line's leading whitespace and re-bases `y` to the fixed content column 7: @2:7-2:8. No minted
        // oracle for this shape; reasoned from cmark's re-indent rule (matched continuation → content col).
        let ranges = try ranges(in: "- [ ] x\n    y", options: Self.quirkOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 7))   // "y" re-based to content col 7
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 8))
    }

    @Test("plain bullet continuation re-bases to the plain content column (no checkbox width added)")
    func plainBulletUsesPlainContentColumn() throws {
        // "- x" then "y": a plain bullet, no checkbox. The continuation re-bases to the plain content
        // column 3, NOT 7 - the fix must not add a checkbox width where there is no checkbox.
        // Oracle: `tasklazy-plain-ctl`.
        let ranges = try ranges(in: "- x\ny", options: Self.quirkOptions)
        try #require(itemChecked(in: ranges) == .some(Bool?.none))   // an ordinary (non-task) item
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 3))   // "y" at plain content col 3
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("flag-off: task-item continuation keeps its TRUE physical column")
    func flagOffKeepsTrueColumn() throws {
        // The shipped default (bug-compat OFF) keeps the continuation at its physical column: `y` at
        // column 1 (@2:1-2:2), spec-correct - the re-base is quarantined behind `.cmarkBugCompatibility`.
        let ranges = try ranges(in: "- [ ] x\ny", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))  // still a task item flag-off
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x" content after checkbox
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y" at its TRUE column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
    }

    /// The flag-OFF twin of `checkedContinuation`: the checked task item's continuation keeps its TRUE
    /// physical column @2:1 rather than the flag-ON re-base to the checkbox-adjusted content column.
    @Test("flag-off: checked task-item continuation keeps its TRUE physical column")
    func flagOffCheckedKeepsTrueColumn() throws {
        let ranges = try ranges(in: "- [x] x\ny", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(true)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 7))   // "x" content after checkbox
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y" at its TRUE column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
    }

    /// The flag-OFF twin of `oneSpaceContinuation`: the one leading space is visible, so `y` keeps its
    /// TRUE physical column @2:2 rather than the flag-ON residual-plus-content-column re-base.
    @Test("flag-off: one-space task-item continuation keeps its TRUE physical column")
    func flagOffOneSpaceKeepsTrueColumn() throws {
        let ranges = try ranges(in: "- [ ] x\n y", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 2))   // "y" at its TRUE column (leading space visible)
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 3))
    }

    /// The flag-OFF twin of `deeperIndentContinuation`: the four leading spaces are visible, so `y` keeps
    /// its TRUE physical column @2:5 rather than the flag-ON re-base to the content column.
    @Test("flag-off: deeper-indent task-item continuation keeps its TRUE physical column")
    func flagOffDeeperIndentKeepsTrueColumn() throws {
        let ranges = try ranges(in: "- [ ] x\n    y", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(.some(false)))
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 5))   // "y" at its TRUE column (four spaces visible)
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 6))
    }

    /// The flag-OFF twin of `plainBulletUsesPlainContentColumn`: a plain bullet's continuation keeps its
    /// TRUE physical column @2:1 rather than the flag-ON re-base to the plain content column.
    @Test("flag-off: plain-bullet continuation keeps its TRUE physical column")
    func flagOffPlainBulletKeepsTrueColumn() throws {
        let ranges = try ranges(in: "- x\ny", options: Self.specOptions)
        try #require(itemChecked(in: ranges) == .some(Bool?.none))   // an ordinary (non-task) item
        let texts = texts(in: ranges)
        try #require(texts.count == 2)

        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 1))   // "y" at its TRUE column
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 2))
    }
}
