/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Under Tables (extension), a `|` directly after a backslash is part of the cell's content rather than a cell
/// delimiter, however many backslashes precede it. The backslash directly before the `|` is removed, and inline
/// parsing resolves the remaining backslash escapes.
@Suite("Table backslash-before-pipe cell splitting")
struct TableBackslashPipeCellSplitTests {

    /// With the backslash before the `|` removed, the cell's content is `\|`, an escaped `|`.
    @Test("two backslashes before a pipe keep it in a single cell")
    func twoBackslashesEscapePipe() throws {
        let rows = firstTableCells("o\n|-\n\\\\|", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 1, "fixture: body row must be a single cell, got \(rows[1].count)")
        #expect(rows[1][0].columns == 1)
        #expect(rows[1][0].text == "|")
    }

    @Test("one backslash before a pipe keeps it in a single cell")
    func oneBackslashEscapesPipe() throws {
        let rows = firstTableCells("o\n|-\n\\|", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 1, "fixture: body row must be a single cell, got \(rows[1].count)")
        #expect(rows[1][0].columns == 1)
        #expect(rows[1][0].text == "|")
    }

    /// With the backslash before the `|` removed, the cell's content is `\\\|`: an escaped `\` and an escaped `|`.
    @Test("four backslashes before a pipe keep it in a single cell")
    func fourBackslashesEscapePipe() throws {
        let rows = firstTableCells("o\n|-\n\\\\\\\\|", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 1, "fixture: body row must be a single cell, got \(rows[1].count)")
        #expect(rows[1][0].columns == 1)
        #expect(rows[1][0].text == "\\|")
    }

    @Test("an unescaped pipe splits a body row into two cells")
    func unescapedPipeSplits() throws {
        let rows = firstTableCells("x|y\n-|-\na|b", options: [.tables, .tableSpans])
        try #require(rows.count == 2, "fixture: expected a header row and a body row, got \(rows.count)")
        try #require(rows[1].count == 2, "fixture: body row must split into two cells, got \(rows[1].count)")
        #expect(rows[1].map(\.columns) == [1, 1])
        #expect(rows[1].map(\.text) == ["a", "b"])
    }
}
