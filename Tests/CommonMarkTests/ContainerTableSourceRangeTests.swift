/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of a GFM table nested in a container: a block quote, a list item, both, a container whose prefix is
/// a tab, and a table whose header is a lazy continuation line.
///
/// A nested table's lines aren't contiguous in the source (each carries its container's prefix), yet every row, cell
/// and cell inline has the source range of its own bytes. A short row's filler cell has no source text, so it has no
/// source range.
@Suite("Source ranges of tables nested in containers")
struct ContainerTableSourceRangeTests {

    static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: Self.opts, sourceRanges: true)
    }

    @Test("a table in a list item")
    func listItem() {
        #expect(tree("- b|c\n  -|-\n  d|e") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  table @1:3-3:6
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "b" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "c" @1:5-1:6
                    table_row @3:3-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                        text "d" @3:3-3:4
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "e" @3:5-3:6

            """)
    }

    @Test("a table in a block quote")
    func blockQuote() {
        #expect(tree("> b|c\n> -|-\n> d|e") == """
            document @1:1-3:6
              block_quote @1:1-3:6
                table @1:3-3:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "b" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "c" @1:5-1:6
                  table_row @3:3-3:6
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "d" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "e" @3:5-3:6

            """)
    }

    @Test("a table in a list item in a block quote")
    func nestedContainers() {
        #expect(tree("> - b|c\n>   -|-\n>   d|e") == """
            document @1:1-3:8
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    table @1:5-3:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "b" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "c" @1:7-1:8
                      table_row @3:5-3:8
                        table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                          text "d" @3:5-3:6
                        table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                          text "e" @3:7-3:8

            """)
    }

    /// The `>` prefix and the tab after it are each one byte, so every row's content starts at byte column 3.
    @Test("a table in a block quote whose prefix ends in a tab")
    func tabAfterBlockQuoteMarker() {
        #expect(tree(">\tb|c\n>\t-|-\n>\td|e") == """
            document @1:1-3:6
              block_quote @1:1-3:6
                table @1:3-3:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "b" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "c" @1:5-1:6
                  table_row @3:3-3:6
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "d" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "e" @3:5-3:6

            """)
    }

    /// The body row `\td|e` is indented by one tab byte, so `d` is at byte column 2.
    @Test("a table in a list item whose continuation lines are indented by a tab")
    func tabIndentedListItem() {
        #expect(tree("-\tb|c\n\t-|-\n\td|e") == """
            document @1:1-3:5
              list bullet '-' tight @1:1-3:5
                item @1:1-3:5
                  table @1:3-3:5
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "b" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "c" @1:5-1:6
                    table_row @3:2-3:5
                      table_cell align=none colspan=1 rowspan=1 @3:2-3:3
                        text "d" @3:2-3:3
                      table_cell align=none colspan=1 rowspan=1 @3:4-3:5
                        text "e" @3:4-3:5

            """)
    }

    /// The header `b|c` is a lazy continuation line of the block quote's paragraph, so it starts at column 1 of line 2.
    @Test("a table in a block quote whose header is a lazy continuation line")
    func lazyHeader() {
        #expect(tree("> a\nb|c\n> -|-") == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
                table @2:1-3:6
                  table_header @2:1-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                      text "b" @2:1-2:2
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "c" @2:3-2:4

            """)
    }

    /// The paragraph line before the header row stays a paragraph, and the table starts on the header row's line.
    @Test("a table in a list item after a paragraph line")
    func listItemWithPrecedingParagraph() {
        #expect(tree("- a\n  b|c\n  -|-") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  table @2:3-3:6
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "c" @2:5-2:6

            """)
    }

    /// The cell spans its source bytes `b\|x`. Its text `b|x` drops the backslash, but the text's source range still
    /// runs from `b` to `x`, so it matches the cell's.
    @Test("a table in a block quote with an escaped pipe in a cell")
    func escapedPipe() {
        #expect(tree("> b\\|x|c\n> -|-") == """
            document @1:1-2:6
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:9
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:7
                      text "b|x" @1:3-1:7
                    table_cell align=none colspan=1 rowspan=1 @1:8-1:9
                      text "c" @1:8-1:9

            """)
    }

    /// The NUL is one source byte, so the U+FFFD that replaces it in the text maps back onto that byte.
    @Test("a table in a block quote with a NUL in a cell")
    func nulInCell() {
        #expect(tree("> b\u{0}|c\n> -|-") == """
            document @1:1-2:6
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:7
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:5
                      text "b\u{FFFD}" @1:3-1:5
                    table_cell align=none colspan=1 rowspan=1 @1:6-1:7
                      text "c" @1:6-1:7

            """)
    }

    @Test("a short row in a block-quoted table pads a filler cell with no range")
    func shortRow() {
        #expect(tree("> b|c\n> -|-\n> d|") == """
            document @1:1-3:5
              block_quote @1:1-3:5
                table @1:3-3:5
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "b" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "c" @1:5-1:6
                  table_row @3:3-3:5
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "d" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @-

            """)
    }

    /// A lazy continuation line's leading whitespace, including a partially consumed tab's remaining columns, is not
    /// paragraph content, so the header row is a lone `|` with no cells and no table forms.
    @Test("a lazy lone-pipe header after a split tab is paragraph text")
    func splitTabLonePipeHeaderIsParagraph() {
        #expect(tree("- >x\n \t|\n  >-|\n") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  block_quote @1:3-3:6
                    paragraph @1:4-3:6
                      text "x" @1:4-1:5
                      softbreak @-
                      text "|" @2:3-2:4
                      softbreak @-
                      text "-|" @3:4-3:6

            """)
    }

    /// A lazy continuation line's leading whitespace is not paragraph content, so the header row is a lone `|` with no
    /// cells and no table forms.
    @Test("a lazy lone-pipe header is paragraph text")
    func lazyLonePipeHeaderIsParagraph() {
        #expect(tree(">x\n  |\n>-|\n") == """
            document @1:1-3:4
              block_quote @1:1-3:4
                paragraph @1:2-3:4
                  text "x" @1:2-1:3
                  softbreak @-
                  text "|" @2:3-2:4
                  softbreak @-
                  text "-|" @3:2-3:4

            """)
    }
}
