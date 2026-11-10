/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A delimiter row cell may be padded with any whitespace character other than a line ending (Characters
/// and lines), including form feed (U+000C) and line tabulation (U+000B) (Tables (extension)).
///
/// Alignment comes from colons at the ends of the cell after trimming that padding.
@Suite("Form feed and line tabulation in a table delimiter row")
struct TableDelimiterWhitespaceTests {

    // MARK: - Form feed and line tabulation pad a delimiter cell

    @Test("a trailing form feed in the delimiter cell forms a table")
    func trailingFormFeed() {
        #expect(TreeDump.dump("d\n-\u{0C}", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a trailing line tabulation in the delimiter cell forms a table")
    func trailingLineTabulation() {
        #expect(TreeDump.dump("d\n-\u{0B}", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a leading-pipe delimiter cell with a trailing form feed forms a table")
    func leadingPipeTrailingFormFeed() {
        #expect(TreeDump.dump("d\n|-\u{0C}", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a leading form feed in the delimiter cell forms a table")
    func leadingFormFeed() {
        #expect(TreeDump.dump("d\n\u{0C}-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a form feed delimiter cell forms a table when the delimiter row is indented")
    func indentedDelimiterRowFormFeed() {
        #expect(TreeDump.dump("d\n -\u{0C}", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a form feed delimiter cell forms a table nested in a block quote")
    func nestedBlockQuoteFormFeed() {
        #expect(TreeDump.dump("> d\n> -\u{0C}", options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "d"

            """)
    }

    // MARK: - Alignment

    @Test("a colon before a trailing form feed sets right alignment")
    func trailingFormFeedRightColon() {
        #expect(TreeDump.dump("d\n-:\u{0C}", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=right colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("colons between line tabulations set center alignment")
    func lineTabulationsAroundColons() {
        #expect(TreeDump.dump("a\n|\u{0B}:--:\u{0B}|\n", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=center colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a leading colon sets left alignment despite a trailing form feed")
    func leadingColonSetsLeftAlignment() {
        #expect(TreeDump.dump("d\n:-\u{0C}", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=left colspan=1 rowspan=1
                    text "d"

            """)
    }

    // MARK: - Not tables

    @Test("a carriage return after the dash is a line ending, so the line is a setext heading underline")
    func trailingCarriageReturnStaysHeading() {
        #expect(TreeDump.dump("d\n-\r", options: [.tables]) == """
            document
              heading 2
                text "d"

            """)
    }

    @Test("an interior form feed invalidates the delimiter cell")
    func interiorFormFeedStaysParagraph() {
        #expect(TreeDump.dump("d\n-\u{0C}-", options: [.tables]) == """
            document
              paragraph
                text "d"
                softbreak
                text "-\\u{C}-"

            """)
    }

    @Test("a column-count mismatch with a form feed delimiter stays a paragraph")
    func columnMismatchStaysParagraph() {
        #expect(TreeDump.dump("a|b\n-\u{0C}", options: [.tables]) == """
            document
              paragraph
                text "a|b"
                softbreak
                text "-"

            """)
    }

    @Test("a plain dash second line stays a setext heading")
    func plainDashStaysHeading() {
        #expect(TreeDump.dump("d\n-", options: [.tables]) == """
            document
              heading 2
                text "d"

            """)
    }
}
