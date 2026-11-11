/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The spaces between pipes and cell content are not part of the cell (Tables (extension)), so a cell's source range
/// covers just its content, and a cell with no content, empty or holding only whitespace, has an empty range just past
/// its opening pipe, or at the row's start in a row of only whitespace, which has no opening pipe. Under `.tableSpans`,
/// a zero-width `||` cell and the first cell of a row of only whitespace have colspan 0. A row runs from its first byte
/// to its closing pipe, or to its last cell's content when it has none, so trailing whitespace is outside it.
@Suite("Table cell and row source ranges")
struct TableEmptyCellSourceRangeTests {

    private static let options: MarkdownDocument.ParseOptions = [.tables, .tableSpans, .sourcePosition]

    @Test("an indented row's cells start after its leading whitespace")
    func indentedRowCellColumns() throws {
        let body = firstTableRows("a|b\n-|-\n x|y", options: Self.options)
        let bodyRow = try #require(body.last, "expected a body row")
        try #require(bodyRow.cells.count == 2, "fixture: expected two body cells, got \(bodyRow.cells.count)")
        #expect((bodyRow.cells[0].range.lowerBound.column, bodyRow.cells[0].range.upperBound.column, bodyRow.cells[0].text) == (2, 3, "x"))
        #expect((bodyRow.cells[1].range.lowerBound.column, bodyRow.cells[1].range.upperBound.column, bodyRow.cells[1].text) == (4, 5, "y"))

        let plain = firstTableRows("a|b\n-|-\nx|y", options: Self.options)
        let plainRow = try #require(plain.last, "expected a body row")
        try #require(plainRow.cells.count == 2, "fixture: expected two body cells, got \(plainRow.cells.count)")
        #expect((plainRow.cells[0].range.lowerBound.column, plainRow.cells[0].range.upperBound.column, plainRow.cells[0].text) == (1, 2, "x"))
        #expect((plainRow.cells[1].range.lowerBound.column, plainRow.cells[1].range.upperBound.column, plainRow.cells[1].text) == (3, 4, "y"))

        // Indenting the header row shifts only the header row's cells.
        let hdr = firstTableRows(" a|b\n-|-\nx|y", options: Self.options)
        try #require(hdr.count == 2, "fixture: expected a header row and a body row")
        try #require(hdr[0].cells.count == 2 && hdr[1].cells.count == 2, "fixture: two cells per row")
        #expect((hdr[0].cells[0].range.lowerBound.column, hdr[0].cells[0].range.upperBound.column, hdr[0].cells[0].text) == (2, 3, "a"))
        #expect((hdr[0].cells[1].range.lowerBound.column, hdr[0].cells[1].range.upperBound.column, hdr[0].cells[1].text) == (4, 5, "b"))
        #expect((hdr[1].cells[0].range.lowerBound.column, hdr[1].cells[0].range.upperBound.column, hdr[1].cells[0].text) == (1, 2, "x"))
        #expect((hdr[1].cells[1].range.lowerBound.column, hdr[1].cells[1].range.upperBound.column, hdr[1].cells[1].text) == (3, 4, "y"))
    }

    @Test("a whitespace-only cell has an empty range just past its opening pipe")
    func whitespaceCellEndColumn() throws {
        // `|x| |y`: x at col 2, the whitespace-only cell's opening pipe at col 3.
        let rows = firstTableRows("a|b|c\n-|-|-\n|x| |y", options: Self.options)
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 3, "expected three body cells, got \(body.cells.count)")
        #expect((body.cells[0].range.lowerBound.column, body.cells[0].range.upperBound.column) == (2, 3))
        #expect(body.cells[0].text == "x")
        #expect(body.cells[1].text == "")
        #expect(body.cells[1].colspan == 1)
        #expect((body.cells[1].range.lowerBound.column, body.cells[1].range.upperBound.column) == (4, 4))
        #expect((body.cells[2].range.lowerBound.column, body.cells[2].range.upperBound.column) == (6, 7))
        #expect(body.cells[2].text == "y")
    }

    @Test("a cell of several spaces has an empty range just past its opening pipe")
    func multiSpaceEmptyCellEndColumn() throws {
        let rows = firstTableRows("a|b\n-|-\n|   |c", options: Self.options)
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].text == "")
        #expect((body.cells[0].range.lowerBound.column, body.cells[0].range.upperBound.column) == (2, 2))
        #expect((body.cells[1].range.lowerBound.column, body.cells[1].range.upperBound.column) == (6, 7))
    }

    @Test("a zero-width first cell is a colspan filler (colspan 0)")
    func zeroWidthFirstCellColspan() throws {
        let bodyRows = firstTableRows("a|b\n-|-\n||c", options: Self.options)
        let body = try #require(bodyRows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].colspan == 0)
        #expect(body.cells[0].text == "")
        #expect((body.cells[0].range.lowerBound.column, body.cells[0].range.upperBound.column) == (2, 2))

        let headerRows = firstTableRows("||b\n-|-\nx|y", options: Self.options)
        let header = try #require(headerRows.first, "expected a header row")
        try #require(header.cells.count == 2, "expected two header cells, got \(header.cells.count)")
        #expect(header.cells[0].colspan == 0)
        #expect((header.cells[0].range.lowerBound.column, header.cells[0].range.upperBound.column) == (2, 2))
    }

    @Test("the last row ends at its closing pipe, before trailing whitespace")
    func lastRowEndExcludesTrailingWhitespace() throws {
        let rows = firstTableRows("a|b\n-|-\n|c| ", options: Self.options)
        let body = try #require(rows.last, "expected a body row")
        #expect(body.range.lowerBound.line == 3)
        #expect(body.range.lowerBound.column == 1)
        #expect(body.range.upperBound.column == 4)
    }

    @Test("a content cell with surrounding whitespace covers just its content")
    func contentCellWithSpacesCoversContent() throws {
        let rows = firstTableRows("a|b\n-|-\n| x |c", options: Self.options)
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].text == "x")
        #expect((body.cells[0].range.lowerBound.column, body.cells[0].range.upperBound.column) == (3, 4))
    }

    @Test("a rightmost body cell with trailing whitespace and no closing pipe ends with its content")
    func rightmostBodyCellTrailingWhitespace() throws {
        let rows = firstTableRows("a|b\n-|-\nx|y ", options: Self.options)
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[1].text == "y")
        #expect((body.cells[1].range.lowerBound.column, body.cells[1].range.upperBound.column) == (3, 4))
        #expect(body.range.upperBound.column == 4)
    }

    @Test("a rightmost header cell with trailing whitespace and no closing pipe ends with its content")
    func rightmostHeaderCellTrailingWhitespace() throws {
        let rows = firstTableRows("a|b  \n-|-\nx|y", options: Self.options)
        let header = try #require(rows.first, "expected a header row")
        try #require(header.cells.count == 2, "expected two header cells, got \(header.cells.count)")
        #expect(header.cells[1].text == "b")
        #expect((header.cells[1].range.lowerBound.column, header.cells[1].range.upperBound.column) == (3, 4))
        #expect(header.range.upperBound.column == 4)
    }

    @Test("a rightmost cell with a closing pipe ends with its content, and the row at the pipe")
    func rightmostCellClosingPipe() throws {
        let rows = firstTableRows("a|b\n-|-\nx|y |", options: Self.options)
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[1].text == "y")
        #expect((body.cells[1].range.lowerBound.column, body.cells[1].range.upperBound.column) == (3, 4))
        #expect(body.range.upperBound.column == 6)
    }

    @Test("a rightmost cell with no trailing whitespace ends with its content")
    func rightmostCellNoTrailingWhitespace() throws {
        let rows = firstTableRows("a|b\n-|-\nx|y", options: Self.options)
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect((body.cells[1].range.lowerBound.column, body.cells[1].range.upperBound.column) == (3, 4))
        #expect(body.range.upperBound.column == 4)
    }
}
