/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Lone-pipe table row column count")
struct TableLonePipeHeaderTests {

    @Test("lone-pipe header vs a 1-column delimiter is not a table")
    func lonePipeHeaderTrailingDelim() {
        #expect(TreeDump.dump("|\n-|", options: [.tables]) == """
            document
              paragraph
                text "|"
                softbreak
                text "-|"

            """)
    }

    @Test("lone-pipe header vs a leading-pipe delimiter is not a table")
    func lonePipeHeaderLeadingDelim() {
        #expect(TreeDump.dump("|\n|-", options: [.tables]) == """
            document
              paragraph
                text "|"
                softbreak
                text "|-"

            """)
    }

    @Test("a lone pipe followed by a form feed has no cells")
    func lonePipeFormFeed() {
        #expect(TreeDump.dump("|\u{C}\n-|", options: [.tables]) == """
            document
              paragraph
                text "|\\u{C}"
                softbreak
                text "-|"

            """)
    }

    @Test("a lone pipe followed by a space has no cells")
    func lonePipeSpace() {
        #expect(TreeDump.dump("| \n-|", options: [.tables]) == """
            document
              paragraph
                text "|"
                softbreak
                text "-|"

            """)
    }

    @Test("a 1-column header with a 1-column delimiter forms a table")
    func oneColumnTable() {
        #expect(TreeDump.dump("a\n-|", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("a leading+trailing pipe (one empty cell) vs a 2-column delimiter stays a paragraph")
    func doublePipeMismatch() {
        #expect(TreeDump.dump("||\n-|-", options: [.tables]) == """
            document
              paragraph
                text "||"
                softbreak
                text "-|-"

            """)
    }

    @Test("a leading+trailing pipe (one empty cell) with a 1-column delimiter forms a table")
    func doublePipeOneColumnTable() {
        #expect(TreeDump.dump("||\n-|", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1

            """)
    }

    @Test("a two-column header with a two-column delimiter forms a table")
    func ordinaryTable() {
        #expect(TreeDump.dump("a|b\n-|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }
}
