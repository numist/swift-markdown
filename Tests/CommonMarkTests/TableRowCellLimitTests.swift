/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// `maxTableRowCells` bounds the cells a table row can have, every cell a line splits into counted, empty cells and
/// span fillers included, before a body row is cut to the header's width (Tables (extension)). A delimiter row past it
/// opens no table, and neither does one below a paragraph line past it. A body row past it ends the table and starts a
/// paragraph.
@Suite("Table row cell limit")
struct TableRowCellLimitTests {

    private func limits(_ cells: Int) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxTableRowCells = cells
        return limits
    }

    // MARK: - Header and delimiter rows

    @Test("a header and delimiter row of as many cells as the limit open a table")
    func headerAtLimit() {
        #expect(TreeDump.dump("a|b|c\n-|-|-", options: .tables, limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                  table_cell align=none colspan=1 rowspan=1
                    text "c"

            """)
    }

    @Test("a header and delimiter row of one cell more than the limit are a paragraph")
    func headerPastLimit() {
        #expect(TreeDump.dump("a|b|c|d\n-|-|-|-", options: .tables, limits: limits(3)) == """
            document
              paragraph
                text "a|b|c|d"
                softbreak
                text "-|-|-|-"

            """)
    }

    @Test("an escaped pipe does not split a header cell")
    func escapedPipeInHeader() {
        #expect(TreeDump.dump("a\\|b|c|d\n-|-|-", options: .tables, limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a|b"
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }

    @Test("a limit of zero or less opens no table", arguments: [0, -1])
    func nonPositiveLimit(_ cells: Int) {
        #expect(TreeDump.dump("a\n|-", options: .tables, limits: limits(cells)) == """
            document
              paragraph
                text "a"
                softbreak
                text "|-"

            """)
    }

    // MARK: - Paragraph lines above the delimiter row

    @Test("a paragraph line above the header with as many cells as the limit leaves the table")
    func precedingLineAtLimit() {
        #expect(TreeDump.dump("w|w|w\na|b\n-|-", options: .tables, limits: limits(3)) == """
            document
              paragraph
                text "w|w|w"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a paragraph line above the header with more cells than the limit leaves a paragraph")
    func precedingLinePastLimit() {
        #expect(TreeDump.dump("w|w|w|w\na|b\n-|-", options: .tables, limits: limits(3)) == """
            document
              paragraph
                text "w|w|w|w"
                softbreak
                text "a|b"
                softbreak
                text "-|-"

            """)
    }

    @Test("a paragraph line past the limit keeps every later delimiter row of the paragraph from opening a table")
    func precedingLinePastLimitFarAbove() {
        #expect(TreeDump.dump("w|w|w|w\nx\na|b\n-|-\nc\n-|-", options: .tables, limits: limits(3)) == """
            document
              paragraph
                text "w|w|w|w"
                softbreak
                text "x"
                softbreak
                text "a|b"
                softbreak
                text "-|-"
                softbreak
                text "c"
                softbreak
                text "-|-"

            """)
    }

    @Test("a delimiter-shaped paragraph line past the limit keeps a later delimiter row from opening a table")
    func delimiterShapedLinePastLimit() {
        let source = "a|b\n-|-|-|-\nc|d\n-|-"
        #expect(TreeDump.dump(source, options: .tables, limits: limits(4)) == """
            document
              paragraph
                text "a|b"
                softbreak
                text "-|-|-|-"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
        #expect(TreeDump.dump(source, options: .tables, limits: limits(3)) == """
            document
              paragraph
                text "a|b"
                softbreak
                text "-|-|-|-"
                softbreak
                text "c|d"
                softbreak
                text "-|-"

            """)
    }

    @Test("a line past the limit in a definition an underline removes leaves a later table")
    func lineInRemovedDefinition() {
        #expect(TreeDump.dump("[d]: /u \"\nw|w|w|w\na|b\n-|-\n\"\n===\ne|f\n-|-", options: .tables, limits: limits(3)) == """
            document
              paragraph
                text "==="
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "e"
                  table_cell align=none colspan=1 rowspan=1
                    text "f"

            """)
    }

    @Test("a line past the limit in an earlier paragraph leaves the table")
    func lineInEarlierParagraph() {
        #expect(TreeDump.dump("w|w|w|w\n\na|b\n-|-", options: .tables, limits: limits(3)) == """
            document
              paragraph
                text "w|w|w|w"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
    }

    @Test("a paragraph line past the limit in a block quote leaves a paragraph")
    func precedingLineInBlockQuote() {
        #expect(TreeDump.dump("> w|w|w\n> a|b\n> -|-", options: .tables, limits: limits(3)) == """
            document
              block_quote
                paragraph
                  text "w|w|w"
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
        #expect(TreeDump.dump("> w|w|w|w\n> a|b\n> -|-", options: .tables, limits: limits(3)) == """
            document
              block_quote
                paragraph
                  text "w|w|w|w"
                  softbreak
                  text "a|b"
                  softbreak
                  text "-|-"

            """)
    }

    @Test("a lazy paragraph line past the limit leaves a paragraph")
    func lazyPrecedingLine() {
        #expect(TreeDump.dump("> x\nw|w|w|w\n> a|b\n> -|-", options: .tables, limits: limits(3)) == """
            document
              block_quote
                paragraph
                  text "x"
                  softbreak
                  text "w|w|w|w"
                  softbreak
                  text "a|b"
                  softbreak
                  text "-|-"

            """)
    }

    // MARK: - Body rows

    @Test("a body row of as many cells as the limit is a row, cut to the header's width")
    func bodyRowAtLimit() {
        #expect(TreeDump.dump("a\n|-\nb|b|b\nc", options: .tables, limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "c"

            """)
    }

    @Test("a body row of one cell more than the limit ends the table and starts a paragraph")
    func bodyRowPastLimit() {
        #expect(TreeDump.dump("a\n|-\nb|b|b|b\nc", options: [.tables, .sourcePosition], limits: limits(3), sourceRanges: true) == """
            document @1:1-4:2
              table @1:1-2:3
                table_header @1:1-1:2
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:2
                    text "a" @1:1-1:2
              paragraph @3:1-4:2
                text "b|b|b|b" @3:1-3:8
                softbreak @-
                text "c" @4:1-4:2

            """)
    }

    @Test("empty cells count toward a body row's cells", arguments: [MarkdownDocument.ParseOptions.tables, [.tables, .tableSpans]])
    func emptyBodyCellsCount(_ options: MarkdownDocument.ParseOptions) {
        let colspan = options.contains(.tableSpans) ? 0 : 1
        #expect(TreeDump.dump("a\n|-\n||||\nc", options: options, limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=\(colspan) rowspan=1
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "c"

            """)
        #expect(TreeDump.dump("a\n|-\n|||||\nc", options: options, limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
              paragraph
                text "|||||"
                softbreak
                text "c"

            """)
    }

    @Test("colspan and rowspan fillers count toward a body row's cells")
    func spanFillersCount() {
        #expect(TreeDump.dump("a|b\n-|-\nc||^\nd", options: [.tables, .tableSpans], limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=2 rowspan=1
                    text "c"
                  table_cell align=none colspan=0 rowspan=1
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "d"
                  table_cell align=none colspan=1 rowspan=1

            """)
        #expect(TreeDump.dump("a|b\n-|-\nc||^|^\nd", options: [.tables, .tableSpans], limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
              paragraph
                text "c||^|^"
                softbreak
                text "d"

            """)
    }

    @Test("a paragraph a body row past the limit starts opens no table at a later delimiter row")
    func paragraphAfterBodyRowPastLimit() {
        #expect(TreeDump.dump("a\n|-\nb|b|b|b\nc\n|-", options: .tables, limits: limits(3)) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
              paragraph
                text "b|b|b|b"
                softbreak
                text "c"
                softbreak
                text "|-"

            """)
    }

    // MARK: - Default limits

    @Test("the default limits keep a header row, a paragraph line above it and a body row of 100,000 cells")
    func defaultLimitsAtScale() {
        let wide = "|" + String(repeating: "a|", count: 100_000)
        let header = TreeDump.dump(wide + "\n|" + String(repeating: "-|", count: 100_000), options: .tables)
        #expect(header.hasPrefix("document\n  table\n    table_header\n"))
        #expect(header.components(separatedBy: "table_cell").count - 1 == 100_000)
        let preceding = TreeDump.dump(wide + "\nb\n|-", options: .tables)
        #expect(preceding.hasPrefix("document\n  paragraph\n"))
        #expect(preceding.hasSuffix("""
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """))
        #expect(TreeDump.dump("b\n|-\n" + wide, options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "a"

            """)
    }

    @Test("the default limits open a table of any width, below any paragraph line, with body rows of any width")
    func defaultLimits() {
        #expect(TreeDump.dump("w|w|w|w\na|b|c|d\n-|-|-|-\nb|b|b|b|b", options: .tables) == """
            document
              paragraph
                text "w|w|w|w"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                  table_cell align=none colspan=1 rowspan=1
                    text "d"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"

            """)
        #expect(TreeDump.dump("a\n|-\n|||||\nc", options: [.tables, .tableSpans]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                table_row
                  table_cell align=none colspan=0 rowspan=1
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "c"

            """)
    }
}
