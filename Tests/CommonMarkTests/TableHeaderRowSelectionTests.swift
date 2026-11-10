/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A table's header row is the line immediately before its delimiter row, and the header and delimiter rows must have
/// the same number of cells (Tables (extension)). The lines before the header remain a paragraph.
@Suite("A table takes the line before its delimiter row as its header row")
struct TableHeaderRowSelectionTests {

    @Test("the lines before the header stay a paragraph: top level")
    func precedingLineSplitsOffTopLevel() {
        let source = "x\na|b\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:4
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "b" @2:3-2:4

            """)
    }

    @Test("the lines before the header stay a paragraph: block quote")
    func precedingLineSplitsOffInBlockQuote() {
        let source = "> x\n> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:6
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "a" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                      text "b" @2:5-2:6

            """)
    }

    @Test("the lines before the header stay a paragraph: list item")
    func precedingLineSplitsOffInListItem() {
        let source = "- x\n  a|b\n  -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:3-3:6
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "a" @2:3-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "b" @2:5-2:6

            """)
    }

    @Test("the lines before the header stay a paragraph: CRLF")
    func precedingLineSplitsOffWithCRLF() {
        let source = "x\r\na|b\r\n-|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:4
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "b" @2:3-2:4

            """)
    }

    @Test("the lines before the header stay a paragraph: tab after the block quote marker")
    func precedingLineSplitsOffAfterQuoteTab() {
        let source = ">\tx\n>\ta|b\n>\t-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:6
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "a" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                      text "b" @2:5-2:6

            """)
    }

    @Test("a header and delimiter that differ in cell count leave a later header and delimiter free to open a table: top level")
    func headerCellCountMismatchThenTableTopLevel() {
        let source = "x\na|b|c\n-|-\nd|e\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
                softbreak
                text "a|b|c"
                softbreak
                text "-|-"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"
                  table_cell align=none colspan=1 rowspan=1
                    text "e"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:1
              paragraph @1:1-3:4
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
              table @4:1-5:4
                table_header @4:1-4:4
                  table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                    text "d" @4:1-4:2
                  table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                    text "e" @4:3-4:4

            """)
    }

    @Test("a header and delimiter that differ in cell count leave a later header and delimiter free to open a table: block quote")
    func headerCellCountMismatchThenTableInBlockQuote() {
        let source = "> x\n> a|b|c\n> -|-\n> d|e\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "a|b|c"
                  softbreak
                  text "-|-"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "d"
                    table_cell align=none colspan=1 rowspan=1
                      text "e"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:1
              block_quote @1:1-5:6
                paragraph @1:3-3:6
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                table @4:3-5:6
                  table_header @4:3-4:6
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "d" @4:3-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                      text "e" @4:5-4:6

            """)
    }

    @Test("a header and delimiter that differ in cell count leave a later header and delimiter free to open a table: list item")
    func headerCellCountMismatchThenTableInListItem() {
        let source = "- x\n  a|b|c\n  -|-\n  d|e\n  -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                    softbreak
                    text "a|b|c"
                    softbreak
                    text "-|-"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "d"
                      table_cell align=none colspan=1 rowspan=1
                        text "e"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:1
              list bullet '-' tight @1:1-5:6
                item @1:1-5:6
                  paragraph @1:3-3:6
                    text "x" @1:3-1:4
                    softbreak @-
                    text "a|b|c" @2:3-2:8
                    softbreak @-
                    text "-|-" @3:3-3:6
                  table @4:3-5:6
                    table_header @4:3-4:6
                      table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                        text "d" @4:3-4:4
                      table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                        text "e" @4:5-4:6

            """)
    }

    @Test("a header and delimiter that differ in cell count leave a later header and delimiter free to open a table: CRLF")
    func headerCellCountMismatchThenTableWithCRLF() {
        let source = "x\r\na|b|c\r\n-|-\r\nd|e\r\n-|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
                softbreak
                text "a|b|c"
                softbreak
                text "-|-"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"
                  table_cell align=none colspan=1 rowspan=1
                    text "e"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:1
              paragraph @1:1-3:4
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
              table @4:1-5:4
                table_header @4:1-4:4
                  table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                    text "d" @4:1-4:2
                  table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                    text "e" @4:3-4:4

            """)
    }

    @Test("a header and delimiter that differ in cell count leave a later header and delimiter free to open a table: tab after the block quote marker")
    func headerCellCountMismatchThenTableAfterQuoteTab() {
        let source = ">\tx\n>\ta|b|c\n>\t-|-\n>\td|e\n>\t-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "a|b|c"
                  softbreak
                  text "-|-"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "d"
                    table_cell align=none colspan=1 rowspan=1
                      text "e"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-6:1
              block_quote @1:1-5:6
                paragraph @1:3-3:6
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                table @4:3-5:6
                  table_header @4:3-4:6
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "d" @4:3-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                      text "e" @4:5-4:6

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: top level")
    func notDelimiterRowThenDelimiterRowTopLevel() {
        let source = "x\n-:-\n|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:3
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:4
                    text "-:-" @2:1-2:4

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: block quote")
    func notDelimiterRowThenDelimiterRowInBlockQuote() {
        let source = "> x\n> -:-\n> |-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              block_quote @1:1-3:5
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:5
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:6
                      text "-:-" @2:3-2:6

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: list item")
    func notDelimiterRowThenDelimiterRowInListItem() {
        let source = "- x\n  -:-\n  |-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:5
                item @1:1-3:5
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:3-3:5
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:6
                        text "-:-" @2:3-2:6

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: CRLF")
    func notDelimiterRowThenDelimiterRowWithCRLF() {
        let source = "x\r\n-:-\r\n|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:3
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:4
                    text "-:-" @2:1-2:4

            """)
    }

    @Test("a line that is not a delimiter row leaves the next line free to open a table: tab after the block quote marker")
    func notDelimiterRowThenDelimiterRowAfterQuoteTab() {
        let source = ">\tx\n>\t-:-\n>\t|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "-:-"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              block_quote @1:1-3:5
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:5
                  table_header @2:3-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:6
                      text "-:-" @2:3-2:6

            """)
    }

    @Test("the paragraph is only the header row: top level")
    func headerOnlyTopLevel() {
        let source = "a|b\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:1
              table @1:1-2:4
                table_header @1:1-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "b" @1:3-1:4

            """)
    }

    @Test("the paragraph is only the header row: block quote")
    func headerOnlyInBlockQuote() {
        let source = "> a|b\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:1
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "a" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "b" @1:5-1:6

            """)
    }

    @Test("the paragraph is only the header row: list item")
    func headerOnlyInListItem() {
        let source = "- a|b\n  -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:6
                item @1:1-2:6
                  table @1:3-2:6
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "a" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "b" @1:5-1:6

            """)
    }

    @Test("the paragraph is only the header row: CRLF")
    func headerOnlyWithCRLF() {
        let source = "a|b\r\n-|-\r\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:1
              table @1:1-2:4
                table_header @1:1-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "b" @1:3-1:4

            """)
    }

    @Test("the paragraph is only the header row: tab after the block quote marker")
    func headerOnlyAfterQuoteTab() {
        let source = ">\ta|b\n>\t-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:1
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "a" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "b" @1:5-1:6

            """)
    }

    @Test("NUL in the header row: top level")
    func nulInHeaderTopLevel() {
        let source = "x\na|b\u{0}\n-|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b\u{FFFD}"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-3:4
                table_header @2:1-2:5
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:5
                    text "b\u{FFFD}" @2:3-2:5

            """)
    }

    @Test("NUL in the header row: block quote")
    func nulInHeaderInBlockQuote() {
        let source = "> x\n> a|b\u{0}\n> -|-\n"
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b\u{FFFD}"

            """)
        #expect(TreeDump.dump(source, options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:3-3:6
                  table_header @2:3-2:7
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "a" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:7
                      text "b\u{FFFD}" @2:5-2:7

            """)
    }

    // MARK: - Earlier lines remain a paragraph

    @Test("block quote: preceding line splits off, header is the last line")
    func blockQuote() {
        #expect(TreeDump.dump("> x\n> a\n> |-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"

            """)
    }

    @Test("list item: preceding line splits off, header is the last line")
    func listItem() {
        #expect(TreeDump.dump("- x\n  a\n  |-", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"

            """)
    }

    @Test("CRLF line endings: preceding line splits off, header is the last line")
    func crlfLineEndings() {
        #expect(TreeDump.dump("x\r\na\r\n|-", options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("block quote: a following body row joins the table")
    func blockQuoteBodyRow() {
        #expect(TreeDump.dump("> x\n> a\n> |-\n> b", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                  table_row
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
    }

    @Test("CRLF: a following body row joins the table")
    func crlfBodyRow() {
        #expect(TreeDump.dump("x\r\na\r\n|-\r\nb", options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump("x\r\na\r\n|-\r\nb", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:2
              paragraph @1:1-1:2
                text "x" @1:1-1:2
              table @2:1-4:2
                table_header @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "a" @2:1-2:2
                table_row @4:1-4:2
                  table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                    text "b" @4:1-4:2

            """)
    }

    @Test("contiguous: multiple preceding lines split off as one paragraph")
    func contiguousMultiPreceding() {
        #expect(TreeDump.dump("x\ny\na\n|-", options: [.tables]) == """
            document
              paragraph
                text "x"
                softbreak
                text "y"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a tab after the block quote marker splits the same with and without source positions")
    func tabAfterBlockQuoteMarkerSplit() {
        #expect(TreeDump.dump(">\tx\n> y\n> |-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "y"

            """)
        #expect(TreeDump.dump(">\tx\n> y\n> |-", options: [.tables, .sourcePosition]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "y"

            """)
    }

    // MARK: - No earlier lines

    @Test("bare block-quote header: no preceding paragraph")
    func bareBlockQuoteTable() {
        #expect(TreeDump.dump("> a\n> |-", options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"

            """)
    }

    @Test("bare list-item header: no preceding paragraph")
    func bareListTable() {
        #expect(TreeDump.dump("- a\n  |-", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"

            """)
    }

    // MARK: - No table

    @Test("lazy block-quote continuation: the delimiter is lazy, so no table and no split")
    func lazyBlockQuoteNoSplit() {
        // A delimiter row on a lazy continuation line is paragraph text (Block quotes).
        #expect(TreeDump.dump("> x\na\n|-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "a"
                  softbreak
                  text "|-"

            """)
    }

    @Test("a block-quoted header row whose cell count differs from the delimiter row's forms no table")
    func blockQuoteHeaderMismatchStaysParagraph() {
        #expect(TreeDump.dump("> x\n> a|b\n> |-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "a|b"
                  softbreak
                  text "|-"

            """)
    }

    @Test("block quote: lines with a colon inside the dashes are no delimiter row")
    func blockQuoteInteriorColonStaysParagraph() {
        #expect(TreeDump.dump("> a\n> -:-\n> -:-\n", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "a"
                  softbreak
                  text "-:-"
                  softbreak
                  text "-:-"

            """)
    }

    // MARK: - Only the delimiter row's own line decides whether a table opens

    /// An indented paragraph continuation line is paragraph text (Paragraphs) and becomes the header row;
    /// only an indented delimiter row would prevent the table.
    @Test("an indented header row line does not prevent the table")
    func indentedEarlierLineFormsTable() {
        #expect(TreeDump.dump("x\n    a\n|-", options: [.tables]) == """
            document
              paragraph
                text "x"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
        #expect(TreeDump.dump("> x\n>     a\n> |-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"

            """)
    }

    @Test("a header row on a lazy continuation line forms a table when the delimiter row is prefixed")
    func lazyEarlierLineFormsTable() {
        #expect(TreeDump.dump("> x\ny\n> |-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "x"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "y"

            """)
    }
}
