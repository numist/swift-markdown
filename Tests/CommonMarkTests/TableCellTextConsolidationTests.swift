/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Table cell text consolidation")
struct TableCellTextConsolidationTests {

    @Test("a bracket literal merges with adjacent text in a cell")
    func bracketMergesWithText() {
        #expect(TreeDump.dump("[t\n|-", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              table @1:1-2:3
                table_header @1:1-1:3
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:3
                    text "[t" @1:1-1:3

            """)
    }

    @Test("a decoded entity merges with the text before it in a cell")
    func entityMergesWithText() {
        #expect(TreeDump.dump("a&amp;\n|-", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              table @1:1-2:3
                table_header @1:1-1:7
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:7
                    text "a&" @1:1-1:7

            """)
    }

    @Test("entity + bracket + smart quote form one text node in a cell")
    func entityBracketSmartQuoteMerge() {
        #expect(TreeDump.dump("[\"&amp;\n|-", options: [.tables, .sourcePosition, .smart], sourceRanges: true) == """
            document @1:1-2:3
              table @1:1-2:3
                table_header @1:1-1:8
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:8
                    text "[”&" @1:1-1:8

            """)
    }

    @Test("plain cell text is a single node")
    func plainCellTextSingleNode() {
        #expect(TreeDump.dump("ab\n|-", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              table @1:1-2:3
                table_header @1:1-1:3
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:3
                    text "ab" @1:1-1:3

            """)
    }

    @Test("emphasis is not merged into adjacent cell text")
    func emphasisBoundaryNotMerged() {
        #expect(TreeDump.dump("a*b*c\n|-", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              table @1:1-2:3
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:6
                    text "a" @1:1-1:2
                    emph @1:2-1:5
                      text "b" @1:3-1:4
                    text "c" @1:5-1:6

            """)
    }

    @Test("each row's cells consolidate independently")
    func multiRowConsolidation() {
        #expect(TreeDump.dump("a|b\n-|-\n[x|]y\nm[|n]", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:6
              table @1:1-4:6
                table_header @1:1-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "b" @1:3-1:4
                table_row @3:1-3:6
                  table_cell align=none colspan=1 rowspan=1 @3:1-3:3
                    text "[x" @3:1-3:3
                  table_cell align=none colspan=1 rowspan=1 @3:4-3:6
                    text "]y" @3:4-3:6
                table_row @4:1-4:6
                  table_cell align=none colspan=1 rowspan=1 @4:1-4:3
                    text "m[" @4:1-4:3
                  table_cell align=none colspan=1 rowspan=1 @4:4-4:6
                    text "n]" @4:4-4:6

            """)
    }

    @Test("a cell with an escaped pipe merges the pipe with its neighbouring text")
    func escapedPipeCellConsolidates() {
        #expect(TreeDump.dump("x\\|[y\n|-", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              table @1:1-2:3
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:6
                    text "x|[y" @1:1-1:6

            """)
    }

    @Test("a cell with leading whitespace merges its text runs")
    func leadingWhitespaceCellConsolidates() {
        #expect(TreeDump.dump("a|b\n-|-\n [x|y", options: [.tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:6
              table @1:1-3:6
                table_header @1:1-1:4
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                    text "b" @1:3-1:4
                table_row @3:2-3:6
                  table_cell align=none colspan=1 rowspan=1 @3:2-3:4
                    text "[x" @3:2-3:4
                  table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                    text "y" @3:5-3:6

            """)
    }
}
