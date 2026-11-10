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
/// its opening pipe; a zero-width `||` cell has colspan 0. A row runs from its first byte to its closing pipe, or to its
/// last cell's content when it has none, so trailing whitespace is outside it.
@Suite("Table cell and row source ranges")
struct TableEmptyCellSourceRangeTests {

    private struct Cell {
        let colspan: Int
        let startColumn: Int
        let endColumn: Int
        let text: String
    }

    private struct Row {
        let startColumn: Int
        let endColumn: Int
        let line: Int
        let cells: [Cell]
    }

    /// Rows (with per-cell columns, colspan, and text) of the first table in `source`, parsed with
    /// spans and source positions. Rows and cells with no source range are omitted.
    private func tableRows(_ source: String) -> [Row] {
        MarkdownDocument.withParsedDocument(
            source, options: [.tables, .tableSpans, .sourcePosition]
        ) { doc -> [Row] in
            var rows: [Row] = []
            var found = false
            doc.root.children.forEach { block in
                if found || block.kind != .table { return }
                found = true
                block.children.forEach { row in
                    guard case .tableRow = row.kind, let rowRange = row.sourceRange else { return }
                    var cells: [Cell] = []
                    row.children.forEach { cell in
                        guard case .tableCell(_, let columns, _) = cell.kind,
                              let range = cell.sourceRange else { return }
                        var text = ""
                        cell.children.forEach { inline in
                            if let lit = inline.literal() { text += lit }
                        }
                        cells.append(Cell(
                            colspan: columns,
                            startColumn: range.lowerBound.column,
                            endColumn: range.upperBound.column,
                            text: text
                        ))
                    }
                    rows.append(Row(
                        startColumn: rowRange.lowerBound.column,
                        endColumn: rowRange.upperBound.column,
                        line: rowRange.lowerBound.line,
                        cells: cells
                    ))
                }
            }
            return rows
        }
    }

    @Test("an indented row's cells start after its leading whitespace")
    func indentedRowCellColumns() throws {
        let body = tableRows("a|b\n-|-\n x|y")
        let bodyRow = try #require(body.last, "expected a body row")
        try #require(bodyRow.cells.count == 2, "fixture: expected two body cells, got \(bodyRow.cells.count)")
        #expect((bodyRow.cells[0].startColumn, bodyRow.cells[0].endColumn, bodyRow.cells[0].text) == (2, 3, "x"))
        #expect((bodyRow.cells[1].startColumn, bodyRow.cells[1].endColumn, bodyRow.cells[1].text) == (4, 5, "y"))

        let plain = tableRows("a|b\n-|-\nx|y")
        let plainRow = try #require(plain.last, "expected a body row")
        try #require(plainRow.cells.count == 2, "fixture: expected two body cells, got \(plainRow.cells.count)")
        #expect((plainRow.cells[0].startColumn, plainRow.cells[0].endColumn, plainRow.cells[0].text) == (1, 2, "x"))
        #expect((plainRow.cells[1].startColumn, plainRow.cells[1].endColumn, plainRow.cells[1].text) == (3, 4, "y"))

        // Indenting the header row shifts only the header row's cells.
        let hdr = tableRows(" a|b\n-|-\nx|y")
        try #require(hdr.count == 2, "fixture: expected a header row and a body row")
        try #require(hdr[0].cells.count == 2 && hdr[1].cells.count == 2, "fixture: two cells per row")
        #expect((hdr[0].cells[0].startColumn, hdr[0].cells[0].endColumn, hdr[0].cells[0].text) == (2, 3, "a"))
        #expect((hdr[0].cells[1].startColumn, hdr[0].cells[1].endColumn, hdr[0].cells[1].text) == (4, 5, "b"))
        #expect((hdr[1].cells[0].startColumn, hdr[1].cells[0].endColumn, hdr[1].cells[0].text) == (1, 2, "x"))
        #expect((hdr[1].cells[1].startColumn, hdr[1].cells[1].endColumn, hdr[1].cells[1].text) == (3, 4, "y"))
    }

    @Test("a whitespace-only cell has an empty range just past its opening pipe")
    func whitespaceCellEndColumn() throws {
        // `|x| |y`: x at col 2, the whitespace-only cell's opening pipe at col 3.
        let rows = tableRows("a|b|c\n-|-|-\n|x| |y")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 3, "expected three body cells, got \(body.cells.count)")
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (2, 3))
        #expect(body.cells[0].text == "x")
        #expect(body.cells[1].text == "")
        #expect(body.cells[1].colspan == 1)
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (4, 4))
        #expect((body.cells[2].startColumn, body.cells[2].endColumn) == (6, 7))
        #expect(body.cells[2].text == "y")
    }

    @Test("a cell of several spaces has an empty range just past its opening pipe")
    func multiSpaceEmptyCellEndColumn() throws {
        let rows = tableRows("a|b\n-|-\n|   |c")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].text == "")
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (2, 2))
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (6, 7))
    }

    @Test("a zero-width first cell is a colspan filler (colspan 0)")
    func zeroWidthFirstCellColspan() throws {
        let bodyRows = tableRows("a|b\n-|-\n||c")
        let body = try #require(bodyRows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].colspan == 0)
        #expect(body.cells[0].text == "")
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (2, 2))

        let headerRows = tableRows("||b\n-|-\nx|y")
        let header = try #require(headerRows.first, "expected a header row")
        try #require(header.cells.count == 2, "expected two header cells, got \(header.cells.count)")
        #expect(header.cells[0].colspan == 0)
        #expect((header.cells[0].startColumn, header.cells[0].endColumn) == (2, 2))
    }

    @Test("the last row ends at its closing pipe, before trailing whitespace")
    func lastRowEndExcludesTrailingWhitespace() throws {
        let rows = tableRows("a|b\n-|-\n|c| ")
        let body = try #require(rows.last, "expected a body row")
        #expect(body.line == 3)
        #expect(body.startColumn == 1)
        #expect(body.endColumn == 4)
    }

    @Test("a content cell with surrounding whitespace covers just its content")
    func contentCellWithSpacesCoversContent() throws {
        let rows = tableRows("a|b\n-|-\n| x |c")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[0].text == "x")
        #expect((body.cells[0].startColumn, body.cells[0].endColumn) == (3, 4))
    }

    @Test("a rightmost body cell with trailing whitespace and no closing pipe ends with its content")
    func rightmostBodyCellTrailingWhitespace() throws {
        let rows = tableRows("a|b\n-|-\nx|y ")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[1].text == "y")
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (3, 4))
        #expect(body.endColumn == 4)
    }

    @Test("a rightmost header cell with trailing whitespace and no closing pipe ends with its content")
    func rightmostHeaderCellTrailingWhitespace() throws {
        let rows = tableRows("a|b  \n-|-\nx|y")
        let header = try #require(rows.first, "expected a header row")
        try #require(header.cells.count == 2, "expected two header cells, got \(header.cells.count)")
        #expect(header.cells[1].text == "b")
        #expect((header.cells[1].startColumn, header.cells[1].endColumn) == (3, 4))
        #expect(header.endColumn == 4)
    }

    @Test("a rightmost cell with a closing pipe ends with its content, and the row at the pipe")
    func rightmostCellClosingPipe() throws {
        let rows = tableRows("a|b\n-|-\nx|y |")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect(body.cells[1].text == "y")
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (3, 4))
        #expect(body.endColumn == 6)
    }

    @Test("a rightmost cell with no trailing whitespace ends with its content")
    func rightmostCellNoTrailingWhitespace() throws {
        let rows = tableRows("a|b\n-|-\nx|y")
        let body = try #require(rows.last, "expected a body row")
        try #require(body.cells.count == 2, "expected two body cells, got \(body.cells.count)")
        #expect((body.cells[1].startColumn, body.cells[1].endColumn) == (3, 4))
        #expect(body.endColumn == 4)
    }
}
