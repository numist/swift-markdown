/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A delimiter row on a lazy continuation line (Block quotes, List items) is paragraph text, just as a
/// lazy `--` is not a setext heading underline, so no table forms.
@Suite("Table delimiter row on a lazy continuation line")
struct TableLazyDelimiterTests {

    // MARK: - Lazy continuation lines

    @Test("lazy `--` continuation in a block quote is paragraph text")
    func lazyDashDash() {
        #expect(TreeDump.dump(">o\n--", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "o"
                  softbreak
                  text "--"

            """)
    }

    @Test("lazy pipe delimiter continuation in a block quote is paragraph text")
    func lazyPipeDelim() {
        #expect(TreeDump.dump(">o\n|-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "o"
                  softbreak
                  text "|-"

            """)
    }

    @Test("lazy colon delimiter continuation in a block quote is paragraph text")
    func lazyColonDelim() {
        #expect(TreeDump.dump(">o\n:-", options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "o"
                  softbreak
                  text ":-"

            """)
    }

    @Test("lazy pipe delimiter continuation in a list item is paragraph text")
    func lazyPipeDelimInList() {
        #expect(TreeDump.dump("- o\n|-", options: [.tables]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "o"
                    softbreak
                    text "|-"

            """)
    }

    // MARK: - Prefixed and top-level lines

    @Test("a prefixed pipe delimiter in a block quote forms a table")
    func prefixedPipeFormsTable() {
        #expect(TreeDump.dump(">o\n>|-", options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "o"

            """)
    }

    @Test("a prefixed `--` in a block quote is a setext heading underline")
    func prefixedDashDashIsHeading() {
        #expect(TreeDump.dump(">o\n>--", options: [.tables]) == """
            document
              block_quote
                heading 2
                  text "o"

            """)
    }

    @Test("a top-level pipe delimiter forms a table")
    func plainPipeFormsTable() {
        #expect(TreeDump.dump("o\n|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "o"

            """)
    }

    @Test("a top-level `--` is a setext heading underline")
    func plainDashDashIsHeading() {
        #expect(TreeDump.dump("o\n--", options: [.tables]) == """
            document
              heading 2
                text "o"

            """)
    }
}
