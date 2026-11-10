/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Under Tables (extension), spaces between pipes and cell content are trimmed. Every whitespace character (Characters
/// and lines) except a line ending, including line tabulation (U+000B) and form feed (U+000C), is such padding: it is
/// trimmed from both edges of a cell, and may precede a row's leading pipe or follow its closing pipe.
@Suite("Table cell pipe-boundary whitespace")
struct TableCellPipeWhitespaceTests {

    private static let ff = "\u{0C}"  // form feed
    private static let vt = "\u{0B}"  // line tabulation

    // MARK: - Whitespace after a pipe

    @Test("a form feed after an interior header pipe is not part of the next cell")
    func interiorHeaderFormFeed() {
        #expect(TreeDump.dump("a|\(Self.ff)b\n-|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a form feed after an interior body pipe is not part of the next cell")
    func interiorBodyFormFeed() {
        #expect(TreeDump.dump("a|b\n-|-\nc|\(Self.ff)d", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a trailing pipe then a form feed is a closing pipe on the delimiter row")
    func delimiterTrailingPipeFormFeed() {
        #expect(TreeDump.dump("d\n-|\(Self.ff)", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a trailing pipe then a line tabulation is a closing pipe on the delimiter row")
    func delimiterTrailingPipeLineTabulation() {
        #expect(TreeDump.dump("d\n-|\(Self.vt)", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a trailing pipe then a form feed closes the header row, so a three-cell delimiter row forms no table")
    func trailingHeaderPipeFormFeedMismatch() {
        // The header row and delimiter row must have the same number of cells.
        #expect(TreeDump.dump("a|b|\(Self.ff)\n-|-|-", options: [.tables]) == """
            document
              paragraph
                text "a|b|\\u{C}"
                softbreak
                text "-|-|-"

            """)
    }

    // MARK: - Other cell edges

    @Test("a form feed before a pipe is padding")
    func formFeedBeforePipe() {
        #expect(TreeDump.dump("a\(Self.ff)|b\n-|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a form feed starting a first cell with no leading pipe is padding")
    func leadingFormFeedFirstCellNoPipe() {
        #expect(TreeDump.dump("\(Self.ff)a|b\n-|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a line tabulation starting a first cell with no leading pipe is padding")
    func leadingLineTabulationFirstCellNoPipe() {
        #expect(TreeDump.dump("\(Self.vt)a|b\n-|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a line tabulation before a row's leading pipe is padding")
    func lineTabulationBeforeLeadingPipe() {
        #expect(TreeDump.dump("| a | b |\n|-|-|\n\(Self.vt)| x | y |\n", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              table @1:1-3:11
                table_header @1:1-1:10
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "a" @1:3-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                    text "b" @1:7-1:8
                table_row @3:2-3:11
                  table_cell align=none colspan=1 rowspan=1 @3:4-3:5
                    text "x" @3:4-3:5
                  table_cell align=none colspan=1 rowspan=1 @3:8-3:9
                    text "y" @3:8-3:9

            """)
    }

    @Test("a line tabulation before a header row's leading pipe is padding")
    func lineTabulationBeforeHeaderLeadingPipe() {
        #expect(TreeDump.dump("\(Self.vt)| a | b |\n|-|-|", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a line tabulation before a closing pipe is padding")
    func lineTabulationBeforeClosingPipe() {
        #expect(TreeDump.dump("a|b\n-|-\n| x\(Self.vt)| y\(Self.ff)|", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
                  table_cell align=none colspan=1 rowspan=1
                    text "y"

            """)
    }

    @Test("a lone pipe after a line tabulation is a row with no cells, which ends the table")
    func lineTabulationBeforeLonePipe() {
        #expect(TreeDump.dump("a\n|-\n\(Self.vt)|\n", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
              paragraph
                text "|"

            """)
    }

    @Test("a form feed after a leading pipe is padding")
    func leadingFormFeedFirstCellWithPipe() {
        #expect(TreeDump.dump("|\(Self.ff)a|b\n-|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a trailing pipe then a form feed closes a body row")
    func trailingBodyPipeFormFeed() {
        #expect(TreeDump.dump("a|b\n-|-\nc|d|\(Self.ff)", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a delimiter row with a trailing pipe forms a one-column table")
    func bareTrailingPipe() {
        #expect(TreeDump.dump("d\n-|", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("an escaped pipe is not a cell separator")
    func escapedPipeNotSeparator() {
        // A one-cell header row doesn't match a two-cell delimiter row.
        #expect(TreeDump.dump("a\\|b\n-|-", options: [.tables]) == """
            document
              paragraph
                text "a|b"
                softbreak
                text "-|-"

            """)
    }
}
