/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Tests for `.tableSpans` and `.tableRowspanDitto`, which let GFM table cells span columns and rows.
@Suite("Parse options - table spans")
struct TableSpanTests {

    // MARK: - colspan

    @Test("an empty `||` cell becomes a colspan filler and grows the cell to its left")
    func colspan() {
        let source = """
        | a | b | c |
        |---|---|---|
        | x || y |
        """
        let rows = firstTableCells(source, options: [.tables, .tableSpans])
        // Header: three ordinary 1×1 cells.
        #expect(rows[0].map(\.columns) == [1, 1, 1])
        // Body: `x` spans two columns, the `||` cell is a 0-column filler, `y` is ordinary.
        #expect(rows[1].map(\.columns) == [2, 0, 1])
        #expect(rows[1].map(\.text) == ["x", "", "y"])
    }

    @Test("a whitespace-only cell does NOT trigger a colspan")
    func whitespaceCellIsNotColspan() {
        let source = """
        | a | b | c |
        |---|---|---|
        | x |  | y |
        """
        let rows = firstTableCells(source, options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [1, 1, 1])
    }

    // MARK: - colspan beyond the column count

    // Excess cells are ignored (Tables (extension)), but a `||` filler adds to the colspan of the nearest
    // non-empty cell to its left, and when that cell is kept its colspan is not capped at the column count.

    @Test("one `||` filler grows a single-column cell's colspan past the column count")
    func colspanExceedsColumnCountByOne() {
        let rows = firstTableCells("o\n|-\no||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [2])
    }

    @Test("two `||` fillers grow a single-column cell's colspan to three")
    func colspanExceedsColumnCountByTwo() {
        let rows = firstTableCells("o\n|-\no|||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [3])
    }

    @Test("three `||` fillers grow a single-column cell's colspan to four")
    func colspanExceedsColumnCountByThree() {
        let rows = firstTableCells("o\n|-\no||||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [4])
    }

    @Test("a leading pipe does not change the uncapped colspan")
    func colspanExceedsColumnCountWithLeadingPipe() {
        let rows = firstTableCells("o\n|-\n|o||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [2])
    }

    @Test("a two-column row grows its first cell's colspan past the column count")
    func colspanExceedsColumnCountTwoColumns() {
        let rows = firstTableCells("a|b\n-|-\no|||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [3, 0])
    }

    @Test("a two-column row grows its first cell's colspan to four")
    func colspanExceedsColumnCountTwoColumnsByTwo() {
        let rows = firstTableCells("a|b\n-|-\no||||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [4, 0])
    }

    // MARK: - colspan within the column count

    @Test("a single-column cell with a trailing pipe has no colspan")
    func singleColumnNoColspan() {
        let rows = firstTableCells("o\n|-\no|", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [1])
    }

    @Test("a two-column row with one `||` filler spans both columns")
    func twoColumnSingleFiller() {
        let rows = firstTableCells("a|b\n-|-\no||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [2, 0])
    }

    @Test("a three-column row with two `||` fillers fills the row exactly")
    func threeColumnTwoFillers() {
        let rows = firstTableCells("a|b|c\n-|-|-\no|||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [3, 0, 0])
    }

    @Test("a lone `||` body row is a single colspan-0 filler")
    func lonePipePairFiller() {
        let rows = firstTableCells("o\n|-\n||", options: [.tables, .tableSpans])
        #expect(rows[1].map(\.columns) == [0])
    }

    // MARK: - rowspan

    @Test("a `^` cell becomes a rowspan filler and grows the cell above")
    func rowspan() {
        let source = """
        | a | b |
        |---|---|
        | x | y |
        | ^ | z |
        """
        let rows = firstTableCells(source, options: [.tables, .tableSpans])
        // First body row: `x` spans two rows.
        #expect(rows[1].map(\.rows) == [2, 1])
        #expect(rows[1].map(\.text) == ["x", "y"])
        // Second body row: the `^` cell is a 0-row filler with its marker text suppressed.
        #expect(rows[2].map(\.rows) == [0, 1])
        #expect(rows[2].map(\.text) == ["", "z"])
    }

    @Test("without .tableRowspanDitto, a `\"` cell is not a rowspan marker")
    func dittoRequiresOption() {
        let source = """
        | a | b |
        |---|---|
        | x | y |
        | " | z |
        """
        let rows = firstTableCells(source, options: [.tables, .tableSpans])
        #expect(rows[1].map(\.rows) == [1, 1])
        #expect(rows[2].map(\.rows) == [1, 1])
        #expect(rows[2][0].text == "\"")
    }

    @Test("with .tableRowspanDitto, a `\"` cell acts as the rowspan marker")
    func dittoMarker() {
        let source = """
        | a | b |
        |---|---|
        | x | y |
        | " | z |
        """
        let rows = firstTableCells(source, options: [.tables, .tableSpans, .tableRowspanDitto])
        #expect(rows[1].map(\.rows) == [2, 1])
        #expect(rows[2].map(\.rows) == [0, 1])
        #expect(rows[2][0].text == "")
    }

    // MARK: - option gating

    @Test("without .tableSpans every cell is an ordinary 1x1 cell")
    func spansDisabled() {
        let source = """
        | a | b | c |
        |---|---|---|
        | x || y |
        """
        let rows = firstTableCells(source, options: .tables)
        for row in rows {
            #expect(row.allSatisfy { $0.columns == 1 && $0.rows == 1 })
        }
    }
}
